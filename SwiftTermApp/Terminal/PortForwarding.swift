//
//  PortForwarding.swift
//  SwiftTermApp
//
//  SSH port forwarding over the terminal's session, in three flavours:
//
//  - Local (ssh -L): listen on a loopback port on the device; each connection is
//    tunnelled to a fixed host:port as seen from the SSH server.
//  - Dynamic (ssh -D): listen on a loopback port as a SOCKS5 proxy; each connection
//    names its own destination, tunnelled through the server (a lightweight VPN).
//  - Remote (ssh -R): ask the server to open a listening port; connections there are
//    forwarded back and delivered to a host:port reachable from the device.
//

import SwiftUI
import Network

// MARK: - Persisted definition

enum PortForwardKind: String, Codable {
    case local
    case dynamic
    case remote

    var short: String {
        switch self {
        case .local: return "Local (-L)"
        case .dynamic: return "Dynamic SOCKS (-D)"
        case .remote: return "Remote (-R)"
        }
    }
}

/// The saved description of a forward, remembered per host across launches.
struct PortForwardDef: Codable, Identifiable, Equatable {
    var id = UUID()
    var hostId: UUID
    var kind: PortForwardKind = .local
    var localPort: Int
    var remoteHost: String
    var remotePort: Int

    enum CodingKeys: String, CodingKey {
        case id, hostId, kind, localPort, remoteHost, remotePort
    }

    init (id: UUID = UUID(), hostId: UUID, kind: PortForwardKind = .local, localPort: Int, remoteHost: String, remotePort: Int) {
        self.id = id
        self.hostId = hostId
        self.kind = kind
        self.localPort = localPort
        self.remoteHost = remoteHost
        self.remotePort = remotePort
    }

    init (from decoder: Decoder) throws {
        let c = try decoder.container (keyedBy: CodingKeys.self)
        id = try c.decode (UUID.self, forKey: .id)
        hostId = try c.decode (UUID.self, forKey: .hostId)
        // Older saved forwards predate the kind field; treat them as local
        kind = (try? c.decode (PortForwardKind.self, forKey: .kind)) ?? .local
        localPort = try c.decode (Int.self, forKey: .localPort)
        remoteHost = try c.decode (String.self, forKey: .remoteHost)
        remotePort = try c.decode (Int.self, forKey: .remotePort)
    }
}

// MARK: - Byte pump helpers

/// Copies bytes from an NWConnection into an SSH channel, awaiting each send so the
/// order is preserved through the serialized session actor.
private func pumpLocalToChannel (_ nw: NWConnection, _ channelBox: @escaping () -> Channel?, onClose: @escaping () -> ()) {
    func step () {
        nw.receive (minimumIncompleteLength: 1, maximumLength: 32 * 1024) { data, _, isComplete, error in
            Task {
                if let data, !data.isEmpty, let ch = channelBox () {
                    await ch.send (data) { _ in }
                }
                if isComplete || error != nil {
                    onClose ()
                } else {
                    step ()
                }
            }
        }
    }
    step ()
}

// MARK: - A forward-direction connection (local & dynamic)

/// Owns one accepted local NWConnection and its paired direct-tcpip channel, pumping
/// bytes both ways.  For dynamic forwards it first negotiates SOCKS5 to learn the
/// destination; for local forwards the destination is fixed.
private final class TunnelConnection {
    private let nw: NWConnection
    private weak var session: Session?
    private let fixedHost: String?
    private let fixedPort: Int?
    private let localPort: Int
    private let onClose: (TunnelConnection) -> ()
    private var channel: Channel?
    private var closed = false
    private let lock = NSLock ()

    /// - Parameters:
    ///   - fixedHost/fixedPort: the destination for a local forward; nil means SOCKS
    ///     negotiation determines the destination (dynamic forward).
    init (nw: NWConnection, session: Session, fixedHost: String?, fixedPort: Int?, localPort: Int,
          onClose: @escaping (TunnelConnection) -> ()) {
        self.nw = nw
        self.session = session
        self.fixedHost = fixedHost
        self.fixedPort = fixedPort
        self.localPort = localPort
        self.onClose = onClose
    }

    func start () {
        nw.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                if let self, self.fixedHost == nil {
                    self.negotiateSocks ()
                } else if let self {
                    Task { await self.openChannel (host: self.fixedHost!, port: self.fixedPort!) }
                }
            case .failed, .cancelled:
                self?.close ()
            default:
                break
            }
        }
        nw.start (queue: PortForward.queue)
    }

    private func openChannel (host: String, port: Int) async {
        guard let session else { close (); return }
        let ch = await session.tunnelTcp (host: host, port: Int32 (port),
                                          originatingHost: "127.0.0.1", originatingPort: Int32 (localPort)) { [weak self] _, out, _, eof in
            if let out, !out.isEmpty {
                self?.nw.send (content: out, completion: .contentProcessed { _ in })
            }
            if eof {
                self?.close ()
            }
        }
        guard let ch else {
            close ()
            return
        }
        channel = ch
        session.activate (channel: ch)
        pumpLocalToChannel (nw, { [weak self] in self?.channel }, onClose: { [weak self] in self?.close () })
    }

    // MARK: SOCKS5 (RFC 1928), enough for the CONNECT command with no auth

    private var socksBuffer = Data ()

    private func negotiateSocks () {
        readMore { [weak self] in self?.parseGreeting () }
    }

    private func readMore (_ then: @escaping () -> ()) {
        nw.receive (minimumIncompleteLength: 1, maximumLength: 512) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                self.socksBuffer.append (data)
                then ()
            } else if isComplete || error != nil {
                self.close ()
            } else {
                self.readMore (then)
            }
        }
    }

    private func parseGreeting () {
        // [VER=5, NMETHODS, METHODS...]
        guard socksBuffer.count >= 2 else { return readMore { [weak self] in self?.parseGreeting () } }
        let b = [UInt8] (socksBuffer)
        guard b [0] == 0x05 else { return close () }
        let nmethods = Int (b [1])
        guard b.count >= 2 + nmethods else { return readMore { [weak self] in self?.parseGreeting () } }
        socksBuffer.removeFirst (2 + nmethods)
        // Reply: version 5, method 0 (no authentication)
        nw.send (content: Data ([0x05, 0x00]), completion: .contentProcessed { [weak self] _ in
            self?.readMore { self?.parseRequest () }
        })
    }

    private func parseRequest () {
        // [VER=5, CMD, RSV, ATYP, ADDR..., PORT(2)]
        let b = [UInt8] (socksBuffer)
        guard b.count >= 4 else { return readMore { [weak self] in self?.parseRequest () } }
        guard b [0] == 0x05 else { return close () }
        guard b [1] == 0x01 else { return replySocks (error: 0x07) }   // only CONNECT supported
        let atyp = b [3]
        var host: String
        var offset: Int
        switch atyp {
        case 0x01: // IPv4
            guard b.count >= 4 + 4 + 2 else { return readMore { [weak self] in self?.parseRequest () } }
            host = "\(b[4]).\(b[5]).\(b[6]).\(b[7])"
            offset = 4 + 4
        case 0x03: // domain name
            guard b.count >= 5 else { return readMore { [weak self] in self?.parseRequest () } }
            let len = Int (b [4])
            guard b.count >= 5 + len + 2 else { return readMore { [weak self] in self?.parseRequest () } }
            host = String (bytes: b [5 ..< 5 + len], encoding: .utf8) ?? ""
            offset = 5 + len
        case 0x04: // IPv6
            guard b.count >= 4 + 16 + 2 else { return readMore { [weak self] in self?.parseRequest () } }
            let parts = (0 ..< 8).map { i in String (format: "%02x%02x", b [4 + i*2], b [4 + i*2 + 1]) }
            host = parts.joined (separator: ":")
            offset = 4 + 16
        default:
            return replySocks (error: 0x08)   // address type not supported
        }
        let port = Int (b [offset]) << 8 | Int (b [offset + 1])
        guard !host.isEmpty else { return replySocks (error: 0x04) }

        // Reply success (bind addr 0.0.0.0:0) then open the tunnel and start piping
        nw.send (content: Data ([0x05, 0x00, 0x00, 0x01, 0, 0, 0, 0, 0, 0]), completion: .contentProcessed { [weak self] _ in
            guard let self else { return }
            Task { await self.openChannel (host: host, port: port) }
        })
    }

    private func replySocks (error code: UInt8) {
        nw.send (content: Data ([0x05, code, 0x00, 0x01, 0, 0, 0, 0, 0, 0]), completion: .contentProcessed { [weak self] _ in
            self?.close ()
        })
    }

    func close () {
        lock.lock ()
        if closed { lock.unlock (); return }
        closed = true
        lock.unlock ()

        nw.cancel ()
        if let ch = channel {
            let session = self.session
            Task {
                await ch.close ()
                session?.unregister (channel: ch)
            }
        }
        onClose (self)
    }
}

// MARK: - A reverse-direction connection (remote)

/// Owns one server-forwarded channel and an outbound NWConnection to the local target,
/// pumping bytes both ways.
private final class ReverseTunnelConnection {
    private weak var session: Session?
    private let channel: Channel
    private let nw: NWConnection
    private let onClose: (ReverseTunnelConnection) -> ()
    private var closed = false
    private let lock = NSLock ()

    init (session: Session, channel: Channel, targetHost: String, targetPort: Int,
          onClose: @escaping (ReverseTunnelConnection) -> ()) {
        self.session = session
        self.channel = channel
        self.onClose = onClose
        let host = NWEndpoint.Host (targetHost)
        let port = NWEndpoint.Port (rawValue: UInt16 (targetPort & 0xffff)) ?? 80
        self.nw = NWConnection (host: host, port: port, using: .tcp)
    }

    func start () {
        nw.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.pumpLocalToChannel ()
            case .failed, .cancelled:
                self?.close ()
            default:
                break
            }
        }
        nw.start (queue: PortForward.queue)
    }

    private func pumpLocalToChannel () {
        func step () {
            nw.receive (minimumIncompleteLength: 1, maximumLength: 32 * 1024) { [weak self] data, _, isComplete, error in
                guard let self else { return }
                Task {
                    if let data, !data.isEmpty {
                        await self.channel.send (data) { _ in }
                    }
                    if isComplete || error != nil {
                        self.close ()
                    } else {
                        step ()
                    }
                }
            }
        }
        step ()
    }

    /// Called by the accept loop with each chunk the server forwards
    func deliverFromChannel (_ data: Data?, eof: Bool) {
        if let data, !data.isEmpty {
            nw.send (content: data, completion: .contentProcessed { _ in })
        }
        if eof {
            close ()
        }
    }

    func close () {
        lock.lock ()
        if closed { lock.unlock (); return }
        closed = true
        lock.unlock ()

        nw.cancel ()
        let ch = channel
        let session = self.session
        Task {
            await ch.close ()
            session?.unregister (channel: ch)
        }
        onClose (self)
    }
}

// MARK: - SOCKS self-test

/// Connects to a running SOCKS5 forward as a client, performs the handshake and an
/// HTTP request to a well-known host, and reports whether the response came back.
/// This exercises the whole chain: listener → SOCKS negotiation → direct-tcpip
/// channel → SSH server → destination → back, so a success proves the proxy works.
private final class SocksProbe {
    private let nw: NWConnection
    private let targetHost: String
    private let targetPort: Int
    private let completion: (Bool, String) -> ()
    private var done = false
    private let queue = DispatchQueue (label: "socks-probe")

    init (localPort: Int, targetHost: String, targetPort: Int, completion: @escaping (Bool, String) -> ()) {
        self.targetHost = targetHost
        self.targetPort = targetPort
        self.completion = completion
        let port = NWEndpoint.Port (rawValue: UInt16 (localPort)) ?? 8080
        self.nw = NWConnection (host: .ipv4 (.loopback), port: port, using: .tcp)
    }

    func run () {
        queue.asyncAfter (deadline: .now () + 12) { [weak self] in
            self?.finish (false, "Timed out — no response came back through the proxy.")
        }
        nw.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.sendGreeting ()
            case .failed (let e):
                self?.finish (false, "Could not connect to the proxy: \(e.localizedDescription)")
            default:
                break
            }
        }
        nw.start (queue: queue)
    }

    private func sendGreeting () {
        // SOCKS5, one method: no authentication
        nw.send (content: Data ([0x05, 0x01, 0x00]), completion: .contentProcessed { [weak self] _ in
            self?.readGreetingReply ()
        })
    }

    private func readGreetingReply () {
        nw.receive (minimumIncompleteLength: 2, maximumLength: 2) { [weak self] data, _, _, _ in
            guard let self else { return }
            let b = data.map { [UInt8] ($0) } ?? []
            guard b.count >= 2, b [0] == 0x05, b [1] == 0x00 else {
                return self.finish (false, "The proxy did not accept the SOCKS5 handshake.")
            }
            self.sendConnect ()
        }
    }

    private func sendConnect () {
        // CONNECT to targetHost:targetPort using a domain-name address
        var req: [UInt8] = [0x05, 0x01, 0x00, 0x03]
        let host = Array (targetHost.utf8)
        req.append (UInt8 (host.count))
        req.append (contentsOf: host)
        req.append (UInt8 (targetPort >> 8))
        req.append (UInt8 (targetPort & 0xff))
        nw.send (content: Data (req), completion: .contentProcessed { [weak self] _ in
            self?.readConnectReply ()
        })
    }

    private func readConnectReply () {
        nw.receive (minimumIncompleteLength: 10, maximumLength: 512) { [weak self] data, _, _, _ in
            guard let self else { return }
            let b = data.map { [UInt8] ($0) } ?? []
            guard b.count >= 2, b [0] == 0x05 else {
                return self.finish (false, "No reply to the SOCKS5 connect request.")
            }
            guard b [1] == 0x00 else {
                return self.finish (false, "The proxy could not reach \(self.targetHost):\(self.targetPort) (SOCKS error \(b [1])). The SSH server may lack internet access.")
            }
            self.sendHttp ()
        }
    }

    private func sendHttp () {
        let req = "GET / HTTP/1.0\r\nHost: \(targetHost)\r\nConnection: close\r\n\r\n"
        nw.send (content: Data (req.utf8), completion: .contentProcessed { [weak self] _ in
            self?.readHttp ()
        })
    }

    private func readHttp () {
        nw.receive (minimumIncompleteLength: 1, maximumLength: 1024) { [weak self] data, _, _, _ in
            guard let self else { return }
            guard let data, !data.isEmpty else {
                return self.finish (false, "Connected through the proxy, but \(self.targetHost) sent nothing back.")
            }
            let text = String (decoding: data, as: UTF8.self)
            if text.hasPrefix ("HTTP/") {
                let statusLine = text.split (whereSeparator: { $0 == "\r" || $0 == "\n" }).first.map (String.init) ?? "HTTP response"
                self.finish (true, "✓ Reached \(self.targetHost) through the proxy.\n\(statusLine)")
            } else {
                self.finish (true, "✓ The tunnel carried data back from \(self.targetHost).")
            }
        }
    }

    private func finish (_ ok: Bool, _ msg: String) {
        queue.async {
            if self.done { return }
            self.done = true
            self.nw.cancel ()
            DispatchQueue.main.async { self.completion (ok, msg) }
        }
    }
}

// MARK: - A running forward

final class PortForward: ObservableObject, Identifiable {
    static let queue = DispatchQueue (label: "port-forward", qos: .userInitiated)

    let id: UUID
    let hostId: UUID
    let kind: PortForwardKind
    let localPort: Int
    let remoteHost: String
    let remotePort: Int

    weak var session: Session?
    private var listener: NWListener?
    private var remoteListener: OpaquePointer?
    private var remoteAcceptRunning = false
    private var tunnels: [ObjectIdentifier: TunnelConnection] = [:]
    private var reverseTunnels: [ObjectIdentifier: ReverseTunnelConnection] = [:]
    private let lock = NSLock ()

    @Published var active = false
    @Published var status = ""
    @Published var openConnections = 0
    @Published var testing = false

    private var probe: SocksProbe?

    /// Verifies a running SOCKS forward by driving a real request through it.
    func testSocks (completion: @escaping (Bool, String) -> ()) {
        guard kind == .dynamic else { completion (false, "Test is only available for SOCKS forwards."); return }
        guard active else { completion (false, "Turn the forward on first."); return }
        DispatchQueue.main.async { self.testing = true }
        let probe = SocksProbe (localPort: localPort, targetHost: "www.google.com", targetPort: 80) { [weak self] ok, msg in
            self?.probe = nil
            DispatchQueue.main.async { self?.testing = false }
            completion (ok, msg)
        }
        self.probe = probe
        probe.run ()
    }

    init (def: PortForwardDef, session: Session?) {
        self.id = def.id
        self.hostId = def.hostId
        self.kind = def.kind
        self.localPort = def.localPort
        self.remoteHost = def.remoteHost
        self.remotePort = def.remotePort
        self.session = session
    }

    var def: PortForwardDef {
        PortForwardDef (id: id, hostId: hostId, kind: kind, localPort: localPort, remoteHost: remoteHost, remotePort: remotePort)
    }

    /// A one-line description of what this forward routes, for the UI.
    var routeDescription: String {
        switch kind {
        case .local:   return "127.0.0.1:\(localPort)  →  \(remoteHost):\(remotePort)"
        case .dynamic: return "SOCKS5 on 127.0.0.1:\(localPort)"
        case .remote:  return "server:\(localPort)  →  \(remoteHost):\(remotePort)"
        }
    }

    func start () {
        guard session != nil else {
            setStatus ("No active session — open a terminal to this host first", active: false)
            return
        }
        switch kind {
        case .local, .dynamic:
            startLocalListener ()
        case .remote:
            startRemoteListener ()
        }
    }

    // MARK: Local & dynamic (NWListener on loopback)

    private func startLocalListener () {
        // If a previous attempt left a listener that never became ready, tear it down
        // rather than silently doing nothing on the next toggle.
        if let existing = listener {
            existing.cancel ()
            listener = nil
        }
        guard localPort > 0, localPort < 65536, let port = NWEndpoint.Port (rawValue: UInt16 (localPort)) else {
            setStatus ("Invalid local port \(localPort)", active: false)
            return
        }
        // Loopback only, so the forward is not exposed to the local network.
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = NWEndpoint.hostPort (host: .ipv4 (.loopback), port: port)
        params.allowLocalEndpointReuse = true

        let newListener: NWListener
        do {
            newListener = try NWListener (using: params)
        } catch {
            setStatus ("Could not open port \(localPort): \(error.localizedDescription)", active: false)
            return
        }
        newListener.newConnectionHandler = { [weak self] connection in
            self?.acceptLocal (connection)
        }
        newListener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.setStatus (self.kind == .dynamic
                    ? "SOCKS5 on 127.0.0.1:\(self.localPort)"
                    : "Listening on 127.0.0.1:\(self.localPort)", active: true)
            case .waiting (let error):
                // Usually the port is already in use; surface it instead of hanging
                self.setStatus ("Waiting — \(error.localizedDescription) (is port \(self.localPort) already in use?)", active: false)
            case .failed (let error):
                self.setStatus ("Failed: \(error.localizedDescription)", active: false)
                self.stop ()
            case .cancelled:
                self.setStatus ("Stopped", active: false)
            default:
                break
            }
        }
        self.listener = newListener
        setStatus ("Starting on 127.0.0.1:\(localPort)…", active: false)
        newListener.start (queue: PortForward.queue)
    }

    private func acceptLocal (_ nw: NWConnection) {
        guard let session else { nw.cancel (); return }
        let tunnel = TunnelConnection (nw: nw, session: session,
                                       fixedHost: kind == .dynamic ? nil : remoteHost,
                                       fixedPort: kind == .dynamic ? nil : remotePort,
                                       localPort: localPort) { [weak self] closed in
            self?.removeTunnel (ObjectIdentifier (closed))
        }
        lock.lock ()
        tunnels [ObjectIdentifier (tunnel)] = tunnel
        lock.unlock ()
        publishConnectionCount ()
        tunnel.start ()
    }

    private func removeTunnel (_ key: ObjectIdentifier) {
        lock.lock ()
        tunnels [key] = nil
        lock.unlock ()
        publishConnectionCount ()
    }

    // MARK: Remote (server-side listener + accept loop)

    private func startRemoteListener () {
        guard !remoteAcceptRunning, let session else { return }
        remoteAcceptRunning = true
        Task {
            guard let listener = await session.forwardListen (host: nil, port: Int32 (localPort)) else {
                self.remoteAcceptRunning = false
                self.setStatus ("Server refused to listen on port \(localPort)", active: false)
                return
            }
            self.remoteListener = listener
            self.setStatus ("Server listening on :\(localPort)", active: true)

            // Accept forwarded connections until stopped or the session drops
            while self.remoteAcceptRunning {
                let holder = ReverseChannelHolder ()
                let channel = await session.forwardAccept (listener: listener) { _, out, _, eof in
                    holder.connection?.deliverFromChannel (out, eof: eof)
                }
                guard self.remoteAcceptRunning, let channel, let session = self.session else {
                    if let channel { await channel.close () }
                    break
                }
                let reverse = ReverseTunnelConnection (session: session, channel: channel,
                                                       targetHost: self.remoteHost, targetPort: self.remotePort) { [weak self] closed in
                    self?.removeReverseTunnel (ObjectIdentifier (closed))
                }
                holder.connection = reverse
                session.activate (channel: channel)
                self.lock.lock ()
                self.reverseTunnels [ObjectIdentifier (reverse)] = reverse
                self.lock.unlock ()
                self.publishConnectionCount ()
                reverse.start ()
            }
        }
    }

    private func removeReverseTunnel (_ key: ObjectIdentifier) {
        lock.lock ()
        reverseTunnels [key] = nil
        lock.unlock ()
        publishConnectionCount ()
    }

    // MARK: Stop / status

    func stop () {
        listener?.cancel ()
        listener = nil
        remoteAcceptRunning = false
        if let rl = remoteListener {
            remoteListener = nil
            let session = self.session
            Task { await session?.forwardCancel (listener: rl) }
        }
        lock.lock ()
        let localConns = tunnels
        let reverseConns = reverseTunnels
        tunnels = [:]
        reverseTunnels = [:]
        lock.unlock ()
        for (_, c) in localConns { c.close () }
        for (_, c) in reverseConns { c.close () }
        DispatchQueue.main.async {
            self.active = false
            self.openConnections = 0
            if self.status.hasPrefix ("Listening") || self.status.hasPrefix ("SOCKS") || self.status.hasPrefix ("Server") {
                self.status = "Stopped"
            }
        }
    }

    private func publishConnectionCount () {
        lock.lock ()
        let n = tunnels.count + reverseTunnels.count
        lock.unlock ()
        DispatchQueue.main.async { self.openConnections = n }
    }

    private func setStatus (_ text: String, active: Bool) {
        DispatchQueue.main.async {
            self.status = text
            self.active = active
        }
    }
}

/// Lets the forwardAccept read callback reach the ReverseTunnelConnection that is
/// created just after the channel is accepted.
private final class ReverseChannelHolder {
    weak var connection: ReverseTunnelConnection?
}

// MARK: - Store

/// Holds the running forwards and persists their definitions per host.
final class PortForwardStore: ObservableObject {
    static let shared = PortForwardStore ()
    private static let defaultsKey = "portForwards"

    @Published private(set) var forwards: [PortForward] = []

    init () {
        load ()
    }

    func forwards (for hostId: UUID) -> [PortForward] {
        forwards.filter { $0.hostId == hostId }
    }

    func add (def: PortForwardDef, session: Session?) {
        let forward = PortForward (def: def, session: session)
        forwards.append (forward)
        save ()
    }

    func remove (_ forward: PortForward) {
        forward.stop ()
        forwards.removeAll { $0.id == forward.id }
        save ()
    }

    /// Rebinds a host's forwards to the current live session (they hold a weak
    /// reference, so this is needed whenever a terminal reconnects).
    func bind (hostId: UUID, session: Session?) {
        for forward in forwards where forward.hostId == hostId {
            forward.session = session
        }
    }

    private func load () {
        guard let data = UserDefaults.standard.data (forKey: PortForwardStore.defaultsKey),
              let defs = try? JSONDecoder ().decode ([PortForwardDef].self, from: data) else {
            return
        }
        forwards = defs.map { PortForward (def: $0, session: nil) }
    }

    private func save () {
        let defs = forwards.map { $0.def }
        if let data = try? JSONEncoder ().encode (defs) {
            UserDefaults.standard.set (data, forKey: PortForwardStore.defaultsKey)
        }
    }
}

// MARK: - UI

struct PortForwardsView: View {
    let host: Host
    let terminalGetter: () -> AppTerminalView?

    @Environment(\.dismiss) var dismiss
    @ObservedObject var store = PortForwardStore.shared
    @State var showingAdd = false
    @State var newKind: PortForwardKind = .local
    @State var newLocalPort = ""
    @State var newRemoteHost = "localhost"
    @State var newRemotePort = ""

    var session: Session? {
        (terminalGetter () as? SshTerminalView)?.session
    }

    var hostForwards: [PortForward] {
        store.forwards (for: host.id)
    }

    var body: some View {
        NavigationView {
            List {
                Section (footer: Text ("Local (-L) tunnels a device port to a target reached from the server. Dynamic (-D) is a SOCKS5 proxy on the device. Remote (-R) opens a port on the server that is forwarded back to a target this device can reach.")) {
                    if hostForwards.isEmpty {
                        Text ("No port forwards yet")
                            .foregroundColor (.secondary)
                    }
                    ForEach (hostForwards) { forward in
                        PortForwardRow (forward: forward)
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            store.remove (hostForwards [index])
                        }
                    }
                }
            }
            .navigationTitle ("Port Forwarding")
            .navigationBarTitleDisplayMode (.inline)
            .toolbar {
                ToolbarItem (placement: .navigationBarLeading) {
                    Button ("Done") { dismiss () }
                }
                ToolbarItem (placement: .navigationBarTrailing) {
                    Button (action: { showingAdd = true }) {
                        Image (systemName: "plus")
                    }
                }
            }
            .onAppear {
                store.bind (hostId: host.id, session: session)
            }
            .sheet (isPresented: $showingAdd) {
                addSheet
            }
        }
        .navigationViewStyle (.stack)
    }

    var addSheet: some View {
        NavigationView {
            Form {
                Section {
                    Picker ("Type", selection: $newKind) {
                        Text ("Local (-L)").tag (PortForwardKind.local)
                        Text ("Dynamic SOCKS (-D)").tag (PortForwardKind.dynamic)
                        Text ("Remote (-R)").tag (PortForwardKind.remote)
                    }
                }
                Section (header: Text (newKind == .remote ? "Server listens on port" : "Listen on this device port")) {
                    TextField (newKind == .remote ? "Remote port (e.g. 8080)" : "Local port (e.g. 8080)", text: $newLocalPort)
                        .keyboardType (.numberPad)
                }
                if newKind != .dynamic {
                    Section (header: Text (newKind == .remote ? "Forward to (reachable from this device)" : "Forward to (as seen from the server)")) {
                        TextField ("Host (e.g. localhost)", text: $newRemoteHost)
                            .autocapitalization (.none)
                            .disableAutocorrection (true)
                        TextField ("Port (e.g. 80)", text: $newRemotePort)
                            .keyboardType (.numberPad)
                    }
                }
            }
            .navigationTitle ("New Forward")
            .navigationBarTitleDisplayMode (.inline)
            .toolbar {
                ToolbarItem (placement: .navigationBarLeading) {
                    Button ("Cancel") { showingAdd = false }
                }
                ToolbarItem (placement: .navigationBarTrailing) {
                    Button ("Add") { addForward () }
                        .disabled (!canAdd)
                }
            }
        }
    }

    var canAdd: Bool {
        guard let local = Int (newLocalPort), local > 0, local < 65536 else { return false }
        if newKind == .dynamic { return true }
        guard let remote = Int (newRemotePort), remote > 0, remote < 65536,
              !newRemoteHost.trimmingCharacters (in: .whitespaces).isEmpty else {
            return false
        }
        return true
    }

    func addForward () {
        guard let local = Int (newLocalPort) else { return }
        let remote = Int (newRemotePort) ?? 0
        let def = PortForwardDef (hostId: host.id, kind: newKind, localPort: local,
                                  remoteHost: newRemoteHost.trimmingCharacters (in: .whitespaces), remotePort: remote)
        store.add (def: def, session: session)
        newLocalPort = ""
        newRemoteHost = "localhost"
        newRemotePort = ""
        newKind = .local
        showingAdd = false
    }
}

struct PortForwardRow: View {
    @ObservedObject var forward: PortForward
    @State private var testResult: String = ""
    @State private var showTestResult = false
    @State private var showBrowser = false

    var body: some View {
        HStack {
            VStack (alignment: .leading, spacing: 2) {
                Text (forward.kind.short)
                    .font (.caption2)
                    .foregroundColor (.secondary)
                Text (forward.routeDescription)
                    .font (.system (.body, design: .monospaced))
                    .lineLimit (1)
                    .minimumScaleFactor (0.7)
                if !forward.status.isEmpty {
                    Text (forward.active && forward.openConnections > 0
                          ? "\(forward.status) · \(forward.openConnections) open"
                          : forward.status)
                        .font (.caption)
                        .foregroundColor (forward.active ? .green : .secondary)
                }
            }
            Spacer ()
            // For a running SOCKS proxy: a built-in browser that routes through it (the
            // practical way to use ssh -D on iOS), plus a one-tap end-to-end test.
            if forward.kind == .dynamic && forward.active {
                if #available(iOS 17.0, *) {
                    Button (action: { showBrowser = true }) {
                        Image (systemName: "safari")
                    }
                    .buttonStyle (.bordered)
                    .padding (.trailing, 4)
                }
                if forward.testing {
                    ProgressView ()
                        .padding (.trailing, 6)
                } else {
                    Button ("Test") {
                        forward.testSocks { _, msg in
                            testResult = msg
                            showTestResult = true
                        }
                    }
                    .buttonStyle (.bordered)
                    .font (.caption)
                    .padding (.trailing, 6)
                }
            }
            Toggle ("", isOn: Binding (
                get: { forward.active },
                set: { on in
                    if on { forward.start () } else { forward.stop () }
                }))
            .labelsHidden ()
        }
        .alert ("Proxy Test", isPresented: $showTestResult) {
            Button ("OK") { }
        } message: {
            Text (testResult)
        }
        // Full-screen so the browser uses the whole display rather than a small
        // form-sheet card on iPad
        .fullScreenCover (isPresented: $showBrowser) {
            if #available(iOS 17.0, *) {
                SocksBrowserView (localPort: forward.localPort)
            }
        }
    }
}
