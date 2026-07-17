//
//  PortForwarding.swift
//  SwiftTermApp
//
//  Local SSH port forwarding (the "ssh -L" flow): the app listens on a port
//  on the device's loopback interface, and pipes each accepted connection
//  through the SSH session as a direct-tcpip channel.  This lets Safari or any
//  app on the iPad reach a service on - or reachable from - the SSH server,
//  e.g. a web UI bound to localhost on a tailnet box.
//

import SwiftUI
import Network

// MARK: - Persisted definition

/// The saved description of a forward, remembered per host across launches.
struct PortForwardDef: Codable, Identifiable, Equatable {
    var id = UUID()
    var hostId: UUID
    var localPort: Int
    var remoteHost: String
    var remotePort: Int
}

// MARK: - A single accepted connection

/// Owns one accepted local NWConnection and its paired direct-tcpip channel,
/// pumping bytes in both directions until either side closes.
private final class TunnelConnection {
    private let nw: NWConnection
    private weak var session: Session?
    private let remoteHost: String
    private let remotePort: Int
    private let localPort: Int
    private let onClose: (TunnelConnection) -> ()
    private var channel: Channel?
    private var closed = false
    private let lock = NSLock ()

    init (nw: NWConnection, session: Session, remoteHost: String, remotePort: Int, localPort: Int,
          onClose: @escaping (TunnelConnection) -> ()) {
        self.nw = nw
        self.session = session
        self.remoteHost = remoteHost
        self.remotePort = remotePort
        self.localPort = localPort
        self.onClose = onClose
    }

    func start () {
        nw.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                Task { await self?.openChannel () }
            case .failed, .cancelled:
                self?.close ()
            default:
                break
            }
        }
        nw.start (queue: PortForward.queue)
    }

    private func openChannel () async {
        guard let session else { close (); return }
        // The channel's read callback delivers remote -> local bytes; the pump
        // invokes it serially, so writes to the socket stay in order.
        let ch = await session.tunnelTcp (host: remoteHost, port: Int32 (remotePort),
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
        receiveLocal ()
    }

    private func receiveLocal () {
        nw.receive (minimumIncompleteLength: 1, maximumLength: 32 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            // Await the send before issuing the next receive so chunks reach the
            // channel in order (each send hops through the serialized session actor).
            Task {
                if let data, !data.isEmpty, let ch = self.channel {
                    await ch.send (data) { _ in }
                }
                if isComplete || error != nil {
                    self.close ()
                } else {
                    self.receiveLocal ()
                }
            }
        }
    }

    func close () {
        lock.lock ()
        if closed {
            lock.unlock ()
            return
        }
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

// MARK: - A running forward

/// A local listener bound to loopback that forwards every accepted connection
/// to `remoteHost:remotePort` through the SSH session.
final class PortForward: ObservableObject, Identifiable {
    static let queue = DispatchQueue (label: "port-forward", qos: .userInitiated)

    let id: UUID
    let hostId: UUID
    let localPort: Int
    let remoteHost: String
    let remotePort: Int

    weak var session: Session?
    private var listener: NWListener?
    private var connections: [ObjectIdentifier: TunnelConnection] = [:]
    private let lock = NSLock ()

    @Published var active = false
    @Published var status = ""
    @Published var openConnections = 0

    init (def: PortForwardDef, session: Session?) {
        self.id = def.id
        self.hostId = def.hostId
        self.localPort = def.localPort
        self.remoteHost = def.remoteHost
        self.remotePort = def.remotePort
        self.session = session
    }

    var def: PortForwardDef {
        PortForwardDef (id: id, hostId: hostId, localPort: localPort, remoteHost: remoteHost, remotePort: remotePort)
    }

    func start () {
        guard listener == nil else { return }
        guard session != nil else {
            setStatus ("No active session — open a terminal to this host first", active: false)
            return
        }
        guard let port = NWEndpoint.Port (rawValue: UInt16 (localPort)) else {
            setStatus ("Invalid local port", active: false)
            return
        }
        // Bind to loopback only, so the forward is not exposed to the local network.
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = NWEndpoint.hostPort (host: .ipv4 (.loopback), port: port)
        params.allowLocalEndpointReuse = true

        do {
            let listener = try NWListener (using: params)
            listener.newConnectionHandler = { [weak self] connection in
                self?.accept (connection)
            }
            listener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    self.setStatus ("Listening on 127.0.0.1:\(self.localPort)", active: true)
                case .failed (let error):
                    self.setStatus ("Failed: \(error.localizedDescription)", active: false)
                    self.stop ()
                case .cancelled:
                    self.setStatus ("Stopped", active: false)
                default:
                    break
                }
            }
            self.listener = listener
            listener.start (queue: PortForward.queue)
        } catch {
            setStatus ("Could not listen on port \(localPort): \(error.localizedDescription)", active: false)
        }
    }

    func stop () {
        listener?.cancel ()
        listener = nil
        lock.lock ()
        let conns = connections
        connections = [:]
        lock.unlock ()
        for (_, c) in conns {
            c.close ()
        }
        DispatchQueue.main.async {
            self.active = false
            self.openConnections = 0
            if self.status.hasPrefix ("Listening") {
                self.status = "Stopped"
            }
        }
    }

    private func accept (_ nw: NWConnection) {
        guard let session else {
            nw.cancel ()
            return
        }
        let tunnel = TunnelConnection (nw: nw, session: session, remoteHost: remoteHost, remotePort: remotePort, localPort: localPort) { [weak self] closed in
            guard let self else { return }
            self.lock.lock ()
            self.connections [ObjectIdentifier (closed)] = nil
            let n = self.connections.count
            self.lock.unlock ()
            DispatchQueue.main.async { self.openConnections = n }
        }
        lock.lock ()
        connections [ObjectIdentifier (tunnel)] = tunnel
        let n = connections.count
        lock.unlock ()
        DispatchQueue.main.async { self.openConnections = n }
        tunnel.start ()
    }

    private func setStatus (_ text: String, active: Bool) {
        DispatchQueue.main.async {
            self.status = text
            self.active = active
        }
    }
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
                Section (footer: Text ("Each forward listens on 127.0.0.1 on this device and tunnels connections to the address as seen from the SSH server. Open http://localhost:<local port> to use it.")) {
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
                Section (header: Text ("Listen on this device")) {
                    TextField ("Local port (e.g. 8080)", text: $newLocalPort)
                        .keyboardType (.numberPad)
                }
                Section (header: Text ("Forward to (as seen from the server)")) {
                    TextField ("Host (e.g. localhost)", text: $newRemoteHost)
                        .autocapitalization (.none)
                        .disableAutocorrection (true)
                    TextField ("Remote port (e.g. 80)", text: $newRemotePort)
                        .keyboardType (.numberPad)
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
        guard let local = Int (newLocalPort), local > 0, local < 65536,
              let remote = Int (newRemotePort), remote > 0, remote < 65536,
              !newRemoteHost.trimmingCharacters (in: .whitespaces).isEmpty else {
            return false
        }
        return true
    }

    func addForward () {
        guard let local = Int (newLocalPort), let remote = Int (newRemotePort) else { return }
        let def = PortForwardDef (hostId: host.id, localPort: local,
                                  remoteHost: newRemoteHost.trimmingCharacters (in: .whitespaces), remotePort: remote)
        store.add (def: def, session: session)
        newLocalPort = ""
        newRemoteHost = "localhost"
        newRemotePort = ""
        showingAdd = false
    }
}

struct PortForwardRow: View {
    @ObservedObject var forward: PortForward

    var body: some View {
        HStack {
            VStack (alignment: .leading, spacing: 2) {
                Text ("127.0.0.1:\(String (forward.localPort))  →  \(forward.remoteHost):\(String (forward.remotePort))")
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
            Toggle ("", isOn: Binding (
                get: { forward.active },
                set: { on in
                    if on { forward.start () } else { forward.stop () }
                }))
            .labelsHidden ()
        }
    }
}
