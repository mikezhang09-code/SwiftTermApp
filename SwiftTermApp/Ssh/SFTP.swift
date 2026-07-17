//
//  SFTP.swift
//  SwiftTermApp
//
//  Created by Miguel de Icaza on 2/1/22.
//  Copyright © 2022 Miguel de Icaza. All rights reserved.
//

import Foundation
@_implementationOnly import CSSH

public class SftpHandle {
    weak var session: Session!
    weak var sessionActor: SessionActor!
    var handle: OpaquePointer!
    
    init (_ sftpHandle: OpaquePointer, session: Session) {
        self.handle = sftpHandle
        self.session = session
        self.sessionActor = session.sessionActor
    }
    deinit {
        if let h = handle {
            let k = sessionActor
            Task {
                await k?.sftpClose(sftpHandle: h)
            }
        }
    }
    
    func close () async {
        if let h = handle {
            await sessionActor.sftpClose(sftpHandle: h)
            handle = nil
        }
    }
}

public class SftpFileHandle : SftpHandle {
    override init (_ sftpHandle: OpaquePointer, session: Session) {
        super.init (sftpHandle, session: session)
    }
}

public class SftpDirHandle : SftpHandle {
    override init (_ sftpHandle: OpaquePointer, session: Session) {
        super.init (sftpHandle, session: session)
    }
    
    /// Reads the next directory entry
    /// - Returns: nil at the end, or a tuple containing the file attributes, the file string, and an `ls -l` style renderinf of the contents.   The string values can be nil, if there were file contents that could not be represented as utf8.
    func readDir () async -> (attrs: LIBSSH2_SFTP_ATTRIBUTES, name: Data, rendered: Data)? {
        return await sessionActor.sftpReaddir(sftpHandle: handle)
    }
}

public class SFTP {
    var handle: OpaquePointer
    weak var session: Session!
    
    init (session: Session, sftpHandle: OpaquePointer) {
        self.handle = sftpHandle
        self.session = session
    }
    
    deinit {
        let h = handle
        let k = session.sessionActor
        Task {
            await k.sftpShutdown (h)
        }
    }

    func stat (path: String) async -> LIBSSH2_SFTP_ATTRIBUTES? {
        await session.sessionActor.sftpStat (self, path: path)
    }

    func open (path: String, flags: UInt) async -> SftpHandle? {
        guard let h = await session.sessionActor.sftpOpen (self, path: path, flags: flags, file: true) else {
            return nil
        }
        return SftpHandle (h, session: session)
    }
    
    func openDir (path: String, flags: UInt) async -> SftpDirHandle? {
        guard let h = await session.sessionActor.sftpOpen (self, path: path, flags: flags, file: false) else {
            return nil
        }
        return SftpDirHandle (h, session: session)
    }
    
    func readFile (path: String, limit: Int) async -> [Int8]? {
        await session.sessionActor.sftpReadFile (self, path: path, limit: limit)
    }

    func readFileAsString (path: String, limit: Int) async -> String? {
        if let bytes = await readFile (path: path, limit: limit) {
            let d = Data (bytes: bytes, count: bytes.count)
            return String (bytes: d, encoding: .utf8)
        }
        return nil
    }

    /// Resolves a path to its canonical absolute form ("." resolves to the user's home)
    func realpath (path: String) async -> String? {
        await session.sessionActor.sftpRealpath (self, path: path)
    }

    /// Creates the file at path with the given contents, returns true on success
    func writeFile (path: String, contents: Data) async -> Bool {
        await session.sessionActor.sftpWriteFile (self, path: path, contents: contents) == 0
    }

    func mkdir (path: String) async -> Bool {
        await session.sessionActor.sftpMkdir (self, path: path) == 0
    }

    func unlink (path: String) async -> Bool {
        await session.sessionActor.sftpUnlink (self, path: path) == 0
    }

    func rmdir (path: String) async -> Bool {
        await session.sessionActor.sftpRmdir (self, path: path) == 0
    }

    /// Reads the full directory at path into entries the UI can consume ("." and ".." are skipped)
    func listDirectory (path: String) async -> [SftpDirEntry]? {
        guard let dir = await openDir (path: path, flags: 0) else {
            return nil
        }
        var result: [SftpDirEntry] = []
        while let entry = await dir.readDir () {
            guard let name = String (data: entry.name, encoding: .utf8) else {
                continue
            }
            if name == "." || name == ".." {
                continue
            }
            let havePermissions = (entry.attrs.flags & UInt (LIBSSH2_SFTP_ATTR_PERMISSIONS)) != 0
            let haveSize = (entry.attrs.flags & UInt (LIBSSH2_SFTP_ATTR_SIZE)) != 0
            let haveTime = (entry.attrs.flags & UInt (LIBSSH2_SFTP_ATTR_ACMODTIME)) != 0
            let fileType = entry.attrs.permissions & UInt (LIBSSH2_SFTP_S_IFMT)
            result.append (SftpDirEntry (
                name: name,
                isDirectory: havePermissions && fileType == UInt (LIBSSH2_SFTP_S_IFDIR),
                isSymlink: havePermissions && fileType == UInt (LIBSSH2_SFTP_S_IFLNK),
                size: haveSize ? entry.attrs.filesize : 0,
                modified: haveTime ? Date (timeIntervalSince1970: Double (entry.attrs.mtime)) : nil))
        }
        await dir.close ()
        return result
    }
}

/// A directory entry as surfaced to the UI, free of libssh2 types
struct SftpDirEntry: Identifiable {
    var name: String
    var isDirectory: Bool
    var isSymlink: Bool
    var size: UInt64
    var modified: Date?

    var id: String { name }
}
