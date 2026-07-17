//
//  SftpBrowserView.swift
//  SwiftTermApp
//
//  A file browser over the SFTP channel of a connected SSH session:
//  navigate remote directories, download files (via the share sheet, so they
//  can be saved to Files, AirDropped, etc), upload files from the Files app,
//  create directories and delete entries.
//

import SwiftUI

struct SftpBrowserView: View {
    let terminalGetter: () -> AppTerminalView?

    @Environment(\.dismiss) var dismiss
    @State var sftp: SFTP?
    @State var path: String = "/"
    @State var entries: [SftpDirEntry] = []
    @State var busy = false
    @State var statusMessage: String? = nil
    @State var uploadPickerShown = false
    @State var mkdirPromptShown = false
    @State var mkdirName = ""

    // Set when a private-key file is tapped, driving the download-or-import prompt
    @State var keyActionEntry: SftpDirEntry? = nil
    @State var importedKeyMessage: String? = nil

    // Transfers are held fully in memory (SessionActor's read/write API); keep a sane cap
    static let transferLimit = 256 * 1024 * 1024

    // Private keys are small; refuse to slurp anything larger as a key
    static let keySizeLimit = 128 * 1024

    var sortedEntries: [SftpDirEntry] {
        entries.sorted {
            if $0.isDirectory != $1.isDirectory {
                return $0.isDirectory
            }
            return $0.name.localizedCaseInsensitiveCompare ($1.name) == .orderedAscending
        }
    }

    func join (_ dir: String, _ name: String) -> String {
        dir == "/" ? "/\(name)" : "\(dir)/\(name)"
    }

    func connect () async {
        guard let terminal = terminalGetter () as? SshTerminalView, let session = terminal.session else {
            statusMessage = "No active SSH session"
            return
        }
        guard let sftp = await session.openSftp () else {
            statusMessage = "The server did not accept an SFTP session"
            return
        }
        self.sftp = sftp
        path = await sftp.realpath (path: ".") ?? "/"
        await load ()
    }

    func load () async {
        guard let sftp else { return }
        busy = true
        defer { busy = false }
        if let listing = await sftp.listDirectory (path: path) {
            entries = listing
            statusMessage = nil
        } else {
            entries = []
            statusMessage = "Could not read \(path)"
        }
    }

    func navigate (into name: String) {
        path = join (path, name)
        Task { await load () }
    }

    func navigateUp () {
        var parts = path.split (separator: "/")
        guard parts.count > 0 else { return }
        parts.removeLast ()
        path = "/" + parts.joined (separator: "/")
        Task { await load () }
    }

    func download (_ entry: SftpDirEntry) async {
        guard let sftp else { return }
        guard entry.size < SftpBrowserView.transferLimit else {
            statusMessage = "\(entry.name) is too large to download here (\(ByteCountFormatter.string (fromByteCount: Int64 (entry.size), countStyle: .file)))"
            return
        }
        busy = true
        defer { busy = false }
        let remote = join (path, entry.name)
        guard let bytes = await sftp.readFile (path: remote, limit: max (Int (entry.size), 1)) else {
            statusMessage = "Could not read \(remote)"
            return
        }
        let local = FileManager.default.temporaryDirectory.appendingPathComponent (entry.name)
        do {
            try bytes.withUnsafeBufferPointer {
                try Data (buffer: $0).write (to: local)
            }
        } catch {
            statusMessage = "Could not save \(entry.name) locally: \(error.localizedDescription)"
            return
        }
        await MainActor.run {
            share (fileUrl: local)
        }
    }

    /// A file worth offering to import as an SSH key: a plausible name, or one
    /// living under a .ssh directory, sized like a key rather than a blob.
    func looksLikePrivateKey (_ entry: SftpDirEntry) -> Bool {
        guard !entry.isDirectory, entry.size > 0, entry.size < SftpBrowserView.keySizeLimit else {
            return false
        }
        let name = entry.name.lowercased ()
        if name.hasSuffix (".pub") { return false }
        if path.lowercased ().hasSuffix ("/.ssh") { return true }
        return name.hasSuffix (".pem") || name.hasSuffix (".key")
            || name.hasPrefix ("id_") || name == "identity"
    }

    /// Reads the file and, if it is a PEM/OpenSSH private key, stores it in the
    /// app's key list — the same destination as pasting a key by hand, but pulled
    /// straight off the host over SFTP instead of copied from another device.
    func importAsKey (_ entry: SftpDirEntry) async {
        guard let sftp else { return }
        busy = true
        defer { busy = false }
        let remote = join (path, entry.name)
        guard let contents = await sftp.readFileAsString (path: remote, limit: SftpBrowserView.keySizeLimit) else {
            statusMessage = "Could not read \(remote)"
            return
        }
        guard contents.contains ("BEGIN") && contents.contains ("PRIVATE KEY") else {
            statusMessage = "\(entry.name) does not look like a private key"
            return
        }
        // Try to attach the matching public key sitting next to it (id_rsa -> id_rsa.pub)
        var publicKey = ""
        if let pub = await sftp.readFileAsString (path: remote + ".pub", limit: SftpBrowserView.keySizeLimit),
           pub.contains ("ssh-") || pub.contains ("ecdsa-") {
            publicKey = pub.trimmingCharacters (in: .whitespacesAndNewlines)
        }

        let keyType: KeyType = contents.contains ("EC PRIVATE KEY") ? .ecdsa (inEnclave: false) : .rsa (2048)
        await MainActor.run {
            let key = CKey (context: globalDataController.container.viewContext)
            key.id = UUID ()
            key.name = "\(entry.name) (from \(host.alias == "" ? host.hostname : host.alias))"
            key.type = keyType
            key.privateKey = contents
            key.publicKey = publicKey
            key.passphrase = ""
            globalDataController.save ()
            importedKeyMessage = SshUtil.openSSHKeyRequiresPassword (key: contents)
                ? "Imported \(entry.name) — it is passphrase-protected, so add the passphrase in Keys before using it."
                : "Imported \(entry.name) into your keys."
        }
    }

    var host: Host {
        (terminalGetter () as? SshTerminalView)?.host ?? MemoryHost ()
    }

    func share (fileUrl: URL) {
        guard var parent = UIApplication.shared.connectedScenes
            .compactMap ({ ($0 as? UIWindowScene)?.keyWindow?.rootViewController }).first else {
            statusMessage = "Cannot present the share sheet"
            return
        }
        while let presented = parent.presentedViewController {
            parent = presented
        }
        let activity = UIActivityViewController (activityItems: [fileUrl], applicationActivities: nil)
        // On iPad the share sheet is a popover and needs an anchor
        activity.popoverPresentationController?.sourceView = parent.view
        activity.popoverPresentationController?.sourceRect = CGRect (
            x: parent.view.bounds.midX, y: parent.view.bounds.midY, width: 0, height: 0)
        activity.popoverPresentationController?.permittedArrowDirections = []
        parent.present (activity, animated: true)
    }

    func upload (result: Result<URL, Error>) {
        guard case .success (let url) = result else { return }
        Task {
            guard let sftp else { return }
            busy = true
            defer { busy = false }
            let scoped = url.startAccessingSecurityScopedResource ()
            defer {
                if scoped { url.stopAccessingSecurityScopedResource () }
            }
            guard let contents = try? Data (contentsOf: url) else {
                statusMessage = "Could not read \(url.lastPathComponent)"
                return
            }
            guard contents.count < SftpBrowserView.transferLimit else {
                statusMessage = "\(url.lastPathComponent) is too large to upload here"
                return
            }
            let remote = join (path, url.lastPathComponent)
            if await sftp.writeFile (path: remote, contents: contents) {
                statusMessage = "Uploaded \(url.lastPathComponent)"
            } else {
                statusMessage = "Upload of \(url.lastPathComponent) failed"
            }
            await load ()
        }
    }

    func delete (_ entry: SftpDirEntry) {
        Task {
            guard let sftp else { return }
            let remote = join (path, entry.name)
            let ok: Bool
            if entry.isDirectory {
                ok = await sftp.rmdir (path: remote)
            } else {
                ok = await sftp.unlink (path: remote)
            }
            if !ok {
                statusMessage = entry.isDirectory
                    ? "Could not delete \(entry.name) — directories must be empty"
                    : "Could not delete \(entry.name)"
            }
            await load ()
        }
    }

    func makeDirectory () {
        let name = mkdirName.trimmingCharacters (in: .whitespaces)
        mkdirName = ""
        guard name != "" else { return }
        Task {
            guard let sftp else { return }
            if await sftp.mkdir (path: join (path, name)) == false {
                statusMessage = "Could not create \(name)"
            }
            await load ()
        }
    }

    var body: some View {
        NavigationView {
            VStack (spacing: 0) {
                if let statusMessage {
                    Text (statusMessage)
                        .font (.footnote)
                        .foregroundColor (.secondary)
                        .padding (.horizontal)
                        .padding (.vertical, 4)
                }
                List {
                    Section (header: Text (path).textCase (nil).font (.footnote.monospaced ())) {
                        if path != "/" {
                            Button (action: navigateUp) {
                                Label ("..", systemImage: "arrow.turn.left.up")
                            }
                        }
                        ForEach (sortedEntries) { entry in
                            row (for: entry)
                        }
                    }
                }
                .listStyle (.insetGrouped)
            }
            .navigationTitle ("Files")
            .navigationBarTitleDisplayMode (.inline)
            .toolbar {
                ToolbarItem (placement: .navigationBarLeading) {
                    Button ("Done") { dismiss () }
                }
                ToolbarItem (placement: .navigationBarTrailing) {
                    HStack {
                        if busy {
                            ProgressView ()
                        }
                        Button (action: { mkdirPromptShown = true }) {
                            Image (systemName: "folder.badge.plus")
                        }
                        Button (action: { uploadPickerShown = true }) {
                            Image (systemName: "square.and.arrow.up.on.square")
                        }
                        Button (action: { Task { await load () } }) {
                            Image (systemName: "arrow.clockwise")
                        }
                    }
                }
            }
            .fileImporter (isPresented: $uploadPickerShown, allowedContentTypes: [.item], onCompletion: upload)
            .confirmationDialog (keyActionEntry?.name ?? "", isPresented: Binding (
                get: { keyActionEntry != nil },
                set: { if !$0 { keyActionEntry = nil } }), titleVisibility: .visible) {
                if let entry = keyActionEntry {
                    Button ("Import as SSH Key") {
                        keyActionEntry = nil
                        Task { await importAsKey (entry) }
                    }
                    Button ("Download") {
                        keyActionEntry = nil
                        Task { await download (entry) }
                    }
                    Button ("Cancel", role: .cancel) { keyActionEntry = nil }
                }
            } message: {
                Text ("This looks like a private key. Import it into your keys, or download the file.")
            }
            .alert ("Key Import", isPresented: Binding (
                get: { importedKeyMessage != nil },
                set: { if !$0 { importedKeyMessage = nil } })) {
                Button ("OK") { importedKeyMessage = nil }
            } message: {
                Text (importedKeyMessage ?? "")
            }
            .sheet (isPresented: $mkdirPromptShown) {
                NavigationView {
                    Form {
                        TextField ("Folder name", text: $mkdirName)
                            .autocapitalization (.none)
                            .disableAutocorrection (true)
                    }
                    .navigationTitle ("New Folder")
                    .navigationBarTitleDisplayMode (.inline)
                    .toolbar {
                        ToolbarItem (placement: .navigationBarLeading) {
                            Button ("Cancel") {
                                mkdirName = ""
                                mkdirPromptShown = false
                            }
                        }
                        ToolbarItem (placement: .navigationBarTrailing) {
                            Button ("Create") {
                                mkdirPromptShown = false
                                makeDirectory ()
                            }
                        }
                    }
                }
            }
        }
        .navigationViewStyle (.stack)
        .task {
            await connect ()
        }
    }

    func row (for entry: SftpDirEntry) -> some View {
        Button (action: {
            if entry.isDirectory {
                navigate (into: entry.name)
            } else if looksLikePrivateKey (entry) {
                keyActionEntry = entry
            } else {
                Task { await download (entry) }
            }
        }) {
            HStack {
                Image (systemName: entry.isDirectory ? "folder.fill" : (looksLikePrivateKey (entry) ? "key" : (entry.isSymlink ? "link" : "doc")))
                    .foregroundColor (entry.isDirectory ? .accentColor : (looksLikePrivateKey (entry) ? .orange : .secondary))
                    .frame (width: 24)
                Text (entry.name)
                    .lineLimit (1)
                Spacer ()
                if !entry.isDirectory {
                    Text (ByteCountFormatter.string (fromByteCount: Int64 (entry.size), countStyle: .file))
                        .font (.footnote)
                        .foregroundColor (.secondary)
                }
            }
        }
        .foregroundColor (.primary)
        .swipeActions (edge: .trailing) {
            Button (role: .destructive) {
                delete (entry)
            } label: {
                Label ("Delete", systemImage: "trash")
            }
        }
    }
}
