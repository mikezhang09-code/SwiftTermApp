//
//  LocalTerminal.swift
//  SwiftTermApp
//
//  A terminal that runs commands on the device itself, without any SSH
//  connection, powered by the ios_system framework (the engine behind
//  a-Shell): ls, mkdir, cp, grep, tar, curl and friends run in-process,
//  since iOS does not allow spawning external programs.
//
//  A `ping` command is provided here as well: it is not part of
//  ios_system, and iOS allows unprivileged ICMP via datagram sockets
//  (the SimplePing technique).
//

import Foundation
import SwiftUI
import SwiftTerm
import UIKit
import ios_system

// MARK: - Runtime setup

enum LocalCommandRuntime {
    static var initialized = false

    static func initialize () {
        guard !initialized else { return }
        initialized = true
        initializeEnvironment ()
        replaceCommand ("ping", "swiftterm_local_ping", true)
        // Commands land in the app's Documents directory, which the user can
        // also see in the Files app under "On My iPad/iPhone"
        if let documents = FileManager.default.urls (for: .documentDirectory, in: .userDomainMask).first {
            FileManager.default.changeCurrentDirectoryPath (documents.path)
        }
    }
}

// MARK: - The terminal view

///
/// Provides a minimal line-editing shell over ios_system: it echoes typed
/// characters, runs the entered command with its output wired to the
/// terminal, and prints a prompt again when the command finishes.
///
class LocalTerminalView: AppTerminalView, TerminalViewDelegate {
    var lineBuffer: [UInt8] = []
    var running = false
    var pendingEscape = false
    let executor = DispatchQueue (label: "local-terminal", qos: .userInitiated)
    let readerQueue = DispatchQueue (label: "local-terminal-reader", qos: .userInitiated)

    // Shared between the command thread (which sets them when ios_system returns) and
    // the reader loop (which finishes the command once the pipe is drained)
    private let stateLock = NSLock ()
    private var pendingExit: Int32 = 0
    private var commandDone = false

    init (frame: CGRect) throws {
        let host = MemoryHost (alias: "iPad", hostname: "localhost", hostKind: "apple")
        try super.init (frame: frame, host: host)
        LocalCommandRuntime.initialize ()
        terminalDelegate = self
        applyTheme (theme: settings.getTheme ())
        feed (text: "Local terminal — commands run on this device.\r\n")
        feed (text: "Try: \u{1b}[1mls\u{1b}[0m, \u{1b}[1mmkdir\u{1b}[0m, \u{1b}[1mgrep\u{1b}[0m, \u{1b}[1mping\u{1b}[0m, \u{1b}[1mtar\u{1b}[0m — \u{1b}[1mhelp\u{1b}[0m lists everything.\r\n\r\n")
        prompt ()
    }

    required init? (coder: NSCoder) {
        fatalError ("init(coder:) has not been implemented")
    }

    var promptDirectory: String {
        let dir = FileManager.default.currentDirectoryPath
        let home = NSHomeDirectory ()
        if dir.hasPrefix (home) {
            let relative = String (dir.dropFirst (home.count))
            return relative == "" ? "~" : "~" + relative
        }
        return dir
    }

    func prompt () {
        feed (text: "\u{1b}[1;32mipad\u{1b}[0m:\u{1b}[1;34m\(promptDirectory)\u{1b}[0m$ ")
    }

    // MARK: Keyboard input

    public func send (source: TerminalView, data: ArraySlice<UInt8>) {
        if running {
            // While a command runs the only input we handle is ctrl-c
            if data.contains (3) {
                _ = ios_kill ()
            }
            return
        }
        for byte in data {
            // Swallow escape sequences (arrow keys and friends): ESC, then
            // everything up to the final byte of a CSI sequence
            if pendingEscape {
                if byte >= 0x40 && byte != UInt8 (ascii: "[") {
                    pendingEscape = false
                }
                continue
            }
            switch byte {
            case 0x1b:
                pendingEscape = true
            case 13:
                feed (text: "\r\n")
                let command = String (bytes: lineBuffer, encoding: .utf8) ?? ""
                lineBuffer = []
                run (command: command.trimmingCharacters (in: .whitespaces))
            case 127, 8:
                if lineBuffer.count > 0 {
                    while let last = lineBuffer.last, last & 0xc0 == 0x80 {
                        lineBuffer.removeLast ()
                    }
                    if lineBuffer.count > 0 {
                        lineBuffer.removeLast ()
                    }
                    feed (text: "\u{8} \u{8}")
                }
            case 3:
                feed (text: "^C\r\n")
                lineBuffer = []
                prompt ()
            case 9:
                break
            default:
                if byte >= 32 || byte >= 0x80 {
                    lineBuffer.append (byte)
                    feed (byteArray: [byte][0...])
                }
            }
        }
    }

    // MARK: Command execution

    func run (command: String) {
        guard command != "" else {
            prompt ()
            return
        }
        if command == "help" {
            feed (text: "Commands available on this device:\r\n")
            let all = (commandsAsArray () as? [String])?.sorted () ?? []
            feed (text: all.joined (separator: ", ") + "\r\n")
            feed (text: "\r\nNote: this shell runs commands one at a time; pipes and scripts work,\r\nbut interactive programs that read from stdin do not.\r\n")
            prompt ()
            return
        }
        running = true
        let sessionId = Unmanaged.passUnretained (self).toOpaque ()
        executor.async {
            ios_switchSession (sessionId)
            ios_setContext (sessionId)

            var fds: [Int32] = [0, 0]
            guard pipe (&fds) == 0, let writer = fdopen (fds [1], "w") else {
                DispatchQueue.main.async {
                    self.feed (text: "Could not create the output pipe\r\n")
                    self.finishCommand (exitCode: 1)
                }
                return
            }
            let readFd = fds [0]
            // Non-blocking so the reader never wedges even though ios_system reuses the
            // write descriptor and the pipe may never report EOF
            _ = fcntl (readFd, F_SETFL, fcntl (readFd, F_GETFL) | O_NONBLOCK)

            self.stateLock.lock ()
            self.commandDone = false
            self.stateLock.unlock ()

            // A single reader owns both the command output and the closing prompt, so
            // they can never be reordered (a concurrent reader plus a separate "finish"
            // once raced the prompt ahead of the last output chunk).  It drains the pipe
            // live while the command runs, then — once the command has returned and the
            // pipe is empty — restores the prompt.
            self.readerQueue.async {
                var buffer = [UInt8] (repeating: 0, count: 16384)
                while true {
                    let n = read (readFd, &buffer, buffer.count)
                    if n > 0 {
                        let text = LocalTerminalView.terminalText (Data (buffer [0 ..< n]))
                        DispatchQueue.main.async { self.feed (text: text) }
                        continue
                    }
                    // No data right now: finish if the command is done, else wait for more
                    self.stateLock.lock ()
                    let done = self.commandDone
                    let code = self.pendingExit
                    self.stateLock.unlock ()
                    if done {
                        close (readFd)
                        DispatchQueue.main.async { self.finishCommand (exitCode: code) }
                        return
                    }
                    usleep (4000)
                }
            }

            let input = fopen ("/dev/null", "r")
            ios_setStreams (input, writer, writer)
            // joinMainThread defaults to true, so ios_system blocks until the command
            // finishes; by the time it returns all output has been written to the pipe.
            let exitCode = ios_system (command)
            fflush (writer)
            fclose (writer)
            if input != nil {
                fclose (input)
            }

            self.stateLock.lock ()
            self.pendingExit = exitCode
            self.commandDone = true
            self.stateLock.unlock ()
        }
    }

    /// Renders raw command output for the terminal: lossy UTF-8 (so invalid bytes
    /// do not drop the whole chunk) with bare newlines promoted to CRLF.
    static func terminalText (_ data: Data) -> String {
        String (decoding: data, as: UTF8.self)
            .replacingOccurrences (of: "\r\n", with: "\n")
            .replacingOccurrences (of: "\n", with: "\r\n")
    }

    /// Ends the current command: prints the exit code if it failed, restores the
    /// prompt, and re-enables input.  Idempotent — both the EOF path and the
    /// failsafe may call it.
    func finishCommand (exitCode: Int32) {
        dispatchPrecondition (condition: .onQueue (DispatchQueue.main))
        guard running else { return }
        running = false
        if exitCode != 0 {
            feed (text: "\u{1b}[2m[exit code: \(exitCode)]\u{1b}[0m\r\n")
        }
        prompt ()
    }

    // MARK: TerminalViewDelegate conformance

    public func scrolled (source: TerminalView, position: Double) {}
    public func setTerminalTitle (source: TerminalView, title: String) {}
    public func sizeChanged (source: TerminalView, newCols: Int, newRows: Int) {
        setenv ("COLUMNS", "\(newCols)", 1)
        setenv ("LINES", "\(newRows)", 1)
    }
    public func clipboardCopy (source: TerminalView, content: Data) {}
    public func rangeChanged (source: TerminalView, startY: Int, endY: Int) {}
    public func hostCurrentDirectoryUpdate (source: TerminalView, directory: String?) {}
    public func requestOpenLink (source: TerminalView, link: String, params: [String: String]) {
        if let fixedup = link.addingPercentEncoding (withAllowedCharacters: .urlQueryAllowed),
           let url = NSURLComponents (string: fixedup)?.url {
            UIApplication.shared.open (url)
        }
    }
    public func bell (source: TerminalView) {}
}

// MARK: - Hosting UI

class LocalTerminalViewController: UIViewController {
    var terminalView: LocalTerminalView?
    static weak var visibleTerminal: LocalTerminalView?

    override func viewDidLoad () {
        super.viewDidLoad ()
        guard let terminalView = try? LocalTerminalView (frame: view.frame) else {
            return
        }
        self.terminalView = terminalView
        view.addSubview (terminalView)
        terminalView.translatesAutoresizingMaskIntoConstraints = false
        terminalView.topAnchor.constraint (equalTo: view.safeAreaLayoutGuide.topAnchor).isActive = true
        terminalView.leftAnchor.constraint (equalTo: view.leftAnchor).isActive = true
        terminalView.rightAnchor.constraint (equalTo: view.rightAnchor).isActive = true
        view.keyboardLayoutGuide.topAnchor.constraint (equalTo: terminalView.bottomAnchor).isActive = true
    }

    override func viewDidAppear (_ animated: Bool) {
        super.viewDidAppear (animated)
        LocalTerminalViewController.visibleTerminal = terminalView
        _ = terminalView?.becomeFirstResponder ()
    }
}

struct LocalTerminalHost: UIViewControllerRepresentable {
    typealias UIViewControllerType = LocalTerminalViewController

    func makeUIViewController (context: Context) -> LocalTerminalViewController {
        return LocalTerminalViewController ()
    }

    func updateUIViewController (_ uiViewController: LocalTerminalViewController, context: Context) {}
}

/// Local terminal with the same AI toolbar affordance as SSH terminals
struct LocalTerminalPage: View {
    @State var showAi = false
    @State var showAiCommand = false
    @State var showAiDiagnose = false

    var body: some View {
        LocalTerminalHost ()
            .toolbar {
                ToolbarItem (placement: .navigationBarTrailing) {
                    Menu {
                        Button (action: { showAi = true }) {
                            Label (LocalTerminalViewController.visibleTerminal?.hasAiSelection == true
                                   ? "Explain Selection" : "Explain Output",
                                   systemImage: "text.magnifyingglass")
                        }
                        .accessibilityIdentifier ("ai-explain")
                        Button (action: { showAiDiagnose = true }) {
                            Label ("Diagnose Failure", systemImage: "stethoscope")
                        }
                        .accessibilityIdentifier ("ai-diagnose")
                        Button (action: { showAiCommand = true }) {
                            Label ("Get a Command", systemImage: "wand.and.stars")
                        }
                        .accessibilityIdentifier ("ai-command")
                    } label: {
                        Image (systemName: "sparkles")
                    }
                    .accessibilityIdentifier ("ai-menu")
                }
            }
            .sheet (isPresented: $showAi, onDismiss: {
                _ = LocalTerminalViewController.visibleTerminal?.becomeFirstResponder ()
            }) {
                AiExplainView (terminalGetter: { LocalTerminalViewController.visibleTerminal })
            }
            .sheet (isPresented: $showAiDiagnose, onDismiss: {
                _ = LocalTerminalViewController.visibleTerminal?.becomeFirstResponder ()
            }) {
                AiExplainView (terminalGetter: { LocalTerminalViewController.visibleTerminal }, mode: .diagnose)
            }
            .sheet (isPresented: $showAiCommand, onDismiss: {
                _ = LocalTerminalViewController.visibleTerminal?.becomeFirstResponder ()
            }) {
                AiCommandView (terminalGetter: { LocalTerminalViewController.visibleTerminal })
            }
    }
}

// MARK: - ping

// iOS does not allow raw sockets, but it does allow ICMP over SOCK_DGRAM,
// which is enough for an unprivileged ping (this is what Apple's SimplePing
// sample uses).  ios_system does not ship a ping, so we provide one.
@_cdecl("swiftterm_local_ping")
public func swiftterm_local_ping (argc: Int32, argv: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?) -> Int32 {
    func emit (_ text: String) {
        fputs (text, thread_stdout)
        fflush (thread_stdout)
    }

    var count = 4
    var target: String? = nil
    var i = 1
    while i < Int (argc), let raw = argv? [Int (i)] {
        let arg = String (cString: raw)
        if arg == "-c", i + 1 < Int (argc), let next = argv? [Int (i) + 1] {
            count = max (Int (String (cString: next)) ?? 4, 1)
            i += 2
            continue
        }
        target = arg
        i += 1
    }
    guard let host = target else {
        emit ("usage: ping [-c count] host\n")
        return 1
    }

    // Resolve the host to an IPv4 address
    var hints = addrinfo (ai_flags: 0, ai_family: AF_INET, ai_socktype: SOCK_DGRAM, ai_protocol: 0,
                          ai_addrlen: 0, ai_canonname: nil, ai_addr: nil, ai_next: nil)
    var res: UnsafeMutablePointer<addrinfo>? = nil
    guard getaddrinfo (host, nil, &hints, &res) == 0, let info = res else {
        emit ("ping: cannot resolve \(host)\n")
        return 1
    }
    defer { freeaddrinfo (res) }
    guard let addrPtr = info.pointee.ai_addr, info.pointee.ai_addrlen >= MemoryLayout<sockaddr_in>.size else {
        emit ("ping: cannot resolve \(host): no IPv4 address\n")
        return 1
    }
    var addr = sockaddr_in ()
    memcpy (&addr, addrPtr, MemoryLayout<sockaddr_in>.size)
    let addressString = String (cString: inet_ntoa (addr.sin_addr))

    let fd = socket (AF_INET, SOCK_DGRAM, IPPROTO_ICMP)
    guard fd >= 0 else {
        emit ("ping: this device does not allow ICMP sockets (errno \(errno))\n")
        return 1
    }
    defer { close (fd) }
    var timeout = timeval (tv_sec: 2, tv_usec: 0)
    setsockopt (fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t (MemoryLayout<timeval>.size))

    emit ("PING \(host) (\(addressString)): 56 data bytes\n")

    let identifier = UInt16 (UInt32 (getpid ()) & 0xffff)
    var received = 0
    var rtts: [Double] = []

    for seq in 0..<count {
        if seq > 0 {
            usleep (1_000_000)
        }
        // ICMP echo request: type 8, code 0, checksum, identifier, sequence, 56-byte payload
        var packet = [UInt8] (repeating: 0, count: 64)
        packet [0] = 8
        packet [4] = UInt8 (identifier >> 8)
        packet [5] = UInt8 (identifier & 0xff)
        packet [6] = UInt8 (seq >> 8)
        packet [7] = UInt8 (seq & 0xff)
        for j in 8..<64 {
            packet [j] = UInt8 (j)
        }
        var checksum: UInt32 = 0
        for j in stride (from: 0, to: packet.count, by: 2) {
            checksum += UInt32 (packet [j]) << 8 | UInt32 (packet [j + 1])
        }
        while checksum > 0xffff {
            checksum = (checksum & 0xffff) + (checksum >> 16)
        }
        let sum = ~UInt16 (checksum & 0xffff)
        packet [2] = UInt8 (sum >> 8)
        packet [3] = UInt8 (sum & 0xff)

        let sendTime = Date ()
        let sent = packet.withUnsafeBytes { rawBuffer -> Int in
            withUnsafeBytes (of: &addr) { addrBuffer in
                sendto (fd, rawBuffer.baseAddress, rawBuffer.count, 0,
                        addrBuffer.baseAddress!.assumingMemoryBound (to: sockaddr.self),
                        socklen_t (MemoryLayout<sockaddr_in>.size))
            }
        }
        if sent < 0 {
            emit ("ping: sendto failed (errno \(errno))\n")
            continue
        }

        // Receive until we see our echo reply or the timeout hits.  Darwin
        // delivers the IP header along with the ICMP payload on DGRAM sockets.
        var reply = [UInt8] (repeating: 0, count: 65535)
        var matched = false
        while !matched {
            let n = recv (fd, &reply, reply.count, 0)
            if n < 0 {
                if errno == EINTR {
                    return 2   // interrupted with ctrl-c
                }
                emit ("request timeout for icmp_seq \(seq)\n")
                break
            }
            guard n >= 20 else { continue }
            let ipHeaderLength = Int (reply [0] & 0x0f) * 4
            guard n >= ipHeaderLength + 8 else { continue }
            let icmpType = reply [ipHeaderLength]
            let replySeq = Int (reply [ipHeaderLength + 6]) << 8 | Int (reply [ipHeaderLength + 7])
            let ttl = Int (reply [8])
            if icmpType == 0 && replySeq == seq {
                matched = true
                received += 1
                let rtt = Date ().timeIntervalSince (sendTime) * 1000
                rtts.append (rtt)
                emit ("\(n - ipHeaderLength) bytes from \(addressString): icmp_seq=\(seq) ttl=\(ttl) time=\(String (format: "%.3f", rtt)) ms\n")
            }
        }
    }

    emit ("\n--- \(host) ping statistics ---\n")
    let loss = count > 0 ? Double (count - received) / Double (count) * 100 : 0
    emit ("\(count) packets transmitted, \(received) packets received, \(String (format: "%.1f", loss))% packet loss\n")
    if rtts.count > 0 {
        let minR = rtts.min () ?? 0, maxR = rtts.max () ?? 0
        let avg = rtts.reduce (0, +) / Double (rtts.count)
        emit ("round-trip min/avg/max = \(String (format: "%.3f/%.3f/%.3f", minR, avg, maxR)) ms\n")
    }
    return received > 0 ? 0 : 1
}
