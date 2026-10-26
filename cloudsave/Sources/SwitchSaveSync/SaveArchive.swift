import Foundation
import CryptoKit
import Darwin

public enum SaveError: LocalizedError {
    case invalid(String), unavailable, tooLarge
    public var errorDescription: String? {
        switch self {
        case .invalid(let reason): return reason
        case .unavailable: return "iCloud Drive is unavailable. Your progress is still saved on this device."
        case .tooLarge: return "This save exceeds the 512 MB cloud-save limit. Your local save is safe."
        }
    }
}

public struct SaveClock: Codable, Equatable, Sendable {
    public var values: [String: UInt64]
    public init(_ values: [String: UInt64] = [:]) { self.values = values }
    public func dominates(_ other: SaveClock) -> Bool {
        other.values.allSatisfy { values[$0.key, default: 0] >= $0.value }
    }
    public func merged(_ other: SaveClock) -> SaveClock {
        var result = values
        for (key, value) in other.values { result[key] = max(result[key, default: 0], value) }
        return SaveClock(result)
    }
    public mutating func advance(device: String) throws {
        guard UUID(uuidString: device) != nil, values.count < 64 || values[device] != nil,
              values[device, default: 0] < UInt64.max else { throw SaveError.invalid("The save history could not be advanced safely.") }
        values[device, default: 0] += 1
    }
}

public struct SaveEntry: Codable, Equatable, Sendable {
    public var path: String
    public var bytes: UInt64
    public var digest: String
    public var directory: Bool
    public var guestName: Data?
}

public struct SaveManifest: Codable, Equatable, Identifiable, Sendable {
    public var schema = 1
    public var id: String
    public var titleID: String
    public var game: String
    public var version: String
    public var device: String
    public var deviceName: String
    public var savedAt: Date
    public var clock: SaveClock
    public var contentHash: String
    public var entries: [SaveEntry]
    public var bytes: UInt64 { entries.reduce(0) { $0 + $1.bytes } }

    public init(titleID: String, game: String, version: String, device: String, deviceName: String, clock: SaveClock) {
        self.id = UUID().uuidString.lowercased(); self.titleID = titleID; self.game = game; self.version = version
        self.device = device; self.deviceName = deviceName; self.clock = clock; savedAt = Date(); contentHash = ""; entries = []
    }
    public static func heads(_ manifests: [SaveManifest]) -> [SaveManifest] {
        manifests.filter { candidate in
            !manifests.contains { $0.id != candidate.id && $0.clock != candidate.clock && $0.clock.dominates(candidate.clock) }
        }.sorted { $0.savedAt > $1.savedAt }
    }
}

/// One bounded, checksummed document: header + raw file bytes. No executable,
/// ROM, key or firmware path is accepted by the runtime caller. Stream payloads
/// so a large save never becomes a second large in-memory buffer.
public enum SaveArchive {
    public static let maximumBytes: UInt64 = 512 * 1024 * 1024
    private static let magic = Data("SWITCHSAVE01\n".utf8)
    private static let attribute = "org.d2rmobile.guest-name"
    private static var encoder: JSONEncoder { let e = JSONEncoder(); e.outputFormatting = [.sortedKeys]; return e }

    public static func entries(at root: URL) throws -> [SaveEntry] {
        try Task.checkCancellation()
        let fm = FileManager.default
        guard try root.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey]).isSymbolicLink != true,
              try root.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else { throw SaveError.invalid("The save folder is not a regular directory.") }
        let keys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
        let root = root.resolvingSymlinksInPath().standardizedFileURL
        let prefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        var traversalError: Error?
        guard let iterator = fm.enumerator(at: root, includingPropertiesForKeys: keys, errorHandler: { _, error in
            traversalError = error; return false
        }) else { throw SaveError.invalid("The save folder could not be read.") }
        var result: [SaveEntry] = [], total: UInt64 = 0
        for case let url as URL in iterator {
            try Task.checkCancellation()
            let pathOnDisk = url.standardizedFileURL.path
            guard pathOnDisk.hasPrefix(prefix) else { throw SaveError.invalid("A save path changed during backup.") }
            let path = String(pathOnDisk.dropFirst(prefix.count))
            let v = try url.resourceValues(forKeys: Set(keys))
            guard v.isSymbolicLink != true, v.isDirectory == true || v.isRegularFile == true else { throw SaveError.invalid("A save contains an unsupported file link.") }
            let directory = v.isDirectory == true
            guard directory || (v.fileSize ?? -1) >= 0 else { throw SaveError.invalid("A save file's size could not be read.") }
            let size = UInt64(max(0, v.fileSize ?? 0))
            let count = directory ? 0 : size
            guard count <= maximumBytes, total <= maximumBytes - count, result.count < 10000 else { throw SaveError.tooLarge }
            total += count
            let n = getxattr(url.path, attribute, nil, 0, 0, XATTR_NOFOLLOW)
            if n < 0 && errno != ENOATTR && errno != ENOTSUP { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
            var guest: Data?
            if n > 0 {
                guard n <= 1024 else { throw SaveError.invalid("Invalid save filename metadata.") }
                var bytes = Data(count: n)
                let read = bytes.withUnsafeMutableBytes { getxattr(url.path, attribute, $0.baseAddress, n, 0, XATTR_NOFOLLOW) }
                guard read == n else { throw SaveError.invalid("Save filename metadata changed during backup.") }; guest = bytes
            }
            result.append(SaveEntry(path: path, bytes: count, digest: directory ? "" : try digest(url, bytes: count), directory: directory, guestName: guest))
        }
        if let traversalError { throw traversalError }
        let sorted = result.sorted { $0.path < $1.path }; try validateEntries(sorted); return sorted
    }
    public static func fingerprint(_ entries: [SaveEntry]) throws -> String { hash(try encoder.encode(entries)) }
    public static func fingerprint(at root: URL) throws -> String { try fingerprint(entries(at: root)) }

    @discardableResult public static func write(snapshot: URL, to destination: URL, manifest: SaveManifest) throws -> SaveManifest {
        try write(snapshot: snapshot, to: destination, manifest: manifest, entries: entries(at: snapshot))
    }

    /// Reuse a previously hashed immutable snapshot; verify its bytes again while
    /// writing so a changed source can never enter the outbox.
    @discardableResult static func write(snapshot: URL, to destination: URL, manifest: SaveManifest, entries: [SaveEntry]) throws -> SaveManifest {
        try Task.checkCancellation()
        var manifest = manifest
        manifest.entries = entries; manifest.contentHash = try fingerprint(entries)
        try validate(manifest)
        let header = try encoder.encode(manifest)
        guard header.count <= 4 * 1024 * 1024 else { throw SaveError.tooLarge }
        let temporary = destination.deletingLastPathComponent().appendingPathComponent(".archive-\(UUID().uuidString)")
        FileManager.default.createFile(atPath: temporary.path, contents: nil)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let out = try FileHandle(forWritingTo: temporary); defer { try? out.close() }
        try out.write(contentsOf: magic)
        var length = UInt32(header.count).littleEndian
        try withUnsafeBytes(of: &length) { try out.write(contentsOf: Data($0)) }
        try out.write(contentsOf: header)
        for item in manifest.entries where !item.directory {
            try Task.checkCancellation()
            let input = try FileHandle(forReadingFrom: snapshot.appendingPathComponent(item.path)); defer { try? input.close() }
            var left = item.bytes, digest = SHA256()
            while left > 0 {
                let data = try exact(input, min(left, 64 * 1024)); left -= UInt64(data.count)
                digest.update(data: data); try out.write(contentsOf: data)
            }
            guard hex(digest.finalize()) == item.digest, (try input.read(upToCount: 1) ?? Data()).isEmpty else { throw SaveError.invalid("The save changed while it was being backed up.") }
        }
        try out.synchronize(); try out.close()
        try Task.checkCancellation()
        try FileManager.default.moveItem(at: temporary, to: destination)
        return manifest
    }

    public static func readManifest(_ url: URL) throws -> SaveManifest {
        let input = try FileHandle(forReadingFrom: url); defer { try? input.close() }
        return try readHeader(input)
    }
    public static func extract(_ archive: URL, to destination: URL, expectedTitle: String) throws -> SaveManifest {
        try Task.checkCancellation()
        guard !FileManager.default.fileExists(atPath: destination.path) else { throw SaveError.invalid("The restore destination already exists.") }
        let input = try FileHandle(forReadingFrom: archive); defer { try? input.close() }
        let manifest = try readHeader(input)
        guard manifest.titleID == expectedTitle else { throw SaveError.invalid("This save belongs to another game.") }
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
        var completed = false
        defer { if !completed { try? FileManager.default.removeItem(at: destination) } }
        for item in manifest.entries {
            try Task.checkCancellation()
            let url = destination.appendingPathComponent(item.path)
            try FileManager.default.createDirectory(at: item.directory ? url : url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if !item.directory {
                guard FileManager.default.createFile(atPath: url.path, contents: nil) else { throw SaveError.invalid("Not enough space to restore this save.") }
                let output = try FileHandle(forWritingTo: url); defer { try? output.close() }
                var left = item.bytes, digest = SHA256()
                while left > 0 {
                    let data = try exact(input, min(left, 64 * 1024)); left -= UInt64(data.count)
                    digest.update(data: data); try output.write(contentsOf: data)
                }
                guard hex(digest.finalize()) == item.digest else { throw SaveError.invalid("The cloud save failed its integrity check. Your local save was kept.") }
                try output.synchronize(); try output.close()
            }
            if let guest = item.guestName {
                let rc = guest.withUnsafeBytes { setxattr(url.path, attribute, $0.baseAddress, guest.count, 0, XATTR_NOFOLLOW) }
                guard rc == 0 else { throw SaveError.invalid("The save filename metadata could not be restored.") }
            }
        }
        guard (try input.read(upToCount: 1) ?? Data()).isEmpty else { throw SaveError.invalid("The save document has unexpected trailing data.") }
        completed = true; return manifest
    }

    /// Restore before the game mounts its working copy. The old committed save
    /// survives the atomic swap and is retained in a local recovery folder.
    public static func restore(_ archive: URL, save: URL, backups: URL, titleID: String, expectedManifest: SaveManifest? = nil) throws -> SaveManifest {
        let fm = FileManager.default
        let savePath = save.resolvingSymlinksInPath().standardizedFileURL.path
        let backupPath = backups.resolvingSymlinksInPath().standardizedFileURL.path
        guard backupPath != savePath, !backupPath.hasPrefix(savePath + "/") else {
            throw SaveError.invalid("Recovery backups must be kept outside the active save folder.")
        }
        try fm.createDirectory(at: backups, withIntermediateDirectories: true)
        // Extract at the final recovery location. The atomic exchange then puts
        // the old save there directly; no fallible move remains after activation.
        let staging = backups.appendingPathComponent("before-restore-\(UUID().uuidString)")
        var committed = false
        defer { if !committed { try? fm.removeItem(at: staging) } }
        let manifest = try extract(archive, to: staging, expectedTitle: titleID)
        guard expectedManifest == nil || expectedManifest == manifest else {
            throw SaveError.invalid("The cloud save changed since it was selected. Refresh the backups and try again.")
        }
        try Task.checkCancellation()
        if fm.fileExists(atPath: save.path) {
            let values = try save.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
            guard values.isSymbolicLink != true, values.isDirectory == true,
                  renamex_np(staging.path, save.path, UInt32(RENAME_SWAP)) == 0 else {
                throw SaveError.invalid("The save could not be replaced atomically. Your current progress is unchanged.")
            }
        } else if rename(staging.path, save.path) != 0 {
            throw SaveError.invalid("The cloud save could not be installed safely. Your progress was not changed.")
        }
        committed = true
        return manifest
    }
    private static func readHeader(_ input: FileHandle) throws -> SaveManifest {
        guard try exact(input, UInt64(magic.count)) == magic else { throw SaveError.invalid("Not a Switch save document.") }
        let bytes = try exact(input, 4)
        let length = bytes.enumerated().reduce(UInt32(0)) { $0 | UInt32($1.element) << ($1.offset * 8) }
        guard length > 0, length <= 4 * 1024 * 1024 else { throw SaveError.tooLarge }
        let manifest = try JSONDecoder().decode(SaveManifest.self, from: exact(input, UInt64(length)))
        try validate(manifest); return manifest
    }
    private static func validate(_ m: SaveManifest) throws {
        guard m.schema == 1, UUID(uuidString: m.id) != nil, UUID(uuidString: m.device) != nil,
              m.titleID.range(of: "^[0-9A-F]{16}$", options: .regularExpression) != nil,
              m.game.count <= 256, m.version.count <= 64, m.deviceName.count <= 128, m.clock.values.count <= 64,
              m.clock.values.allSatisfy({ UUID(uuidString: $0.key) != nil && $0.value > 0 }) else { throw SaveError.invalid("Invalid save document metadata.") }
        try validateEntries(m.entries)
        guard try fingerprint(m.entries) == m.contentHash else { throw SaveError.invalid("The save document metadata failed its integrity check.") }
    }
    private static func validateEntries(_ entries: [SaveEntry]) throws {
        guard entries.count <= 10000 else { throw SaveError.tooLarge }
        var paths = Set<String>(), files = Set<String>(), total: UInt64 = 0
        for item in entries {
            if let metadata = item.guestName {
                guard let name = String(data: metadata, encoding: .utf8), !name.isEmpty, !name.contains("/"), !name.contains("\0"), name != ".", name != ".." else { throw SaveError.invalid("Invalid save filename metadata.") }
            }
            let parts = item.path.split(separator: "/", omittingEmptySubsequences: false)
            let normalized = item.path.precomposedStringWithCanonicalMapping.lowercased()
            guard !item.path.hasPrefix("/"), !item.path.contains("\0"), item.path.utf8.count <= 1024,
                  parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }), paths.insert(normalized).inserted,
                  item.guestName?.count ?? 0 <= 1024,
                  item.directory ? item.bytes == 0 && item.digest.isEmpty : item.digest.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil else { throw SaveError.invalid("Unsafe or duplicate path in save document.") }
            guard item.bytes <= maximumBytes, total <= maximumBytes - item.bytes else { throw SaveError.tooLarge }; total += item.bytes
            if !item.directory { files.insert(normalized) }
        }
        for path in paths {
            var parts = path.split(separator: "/"); parts.removeLast()
            while !parts.isEmpty {
                guard !files.contains(parts.joined(separator: "/")) else { throw SaveError.invalid("A save file is also used as a folder.") }; parts.removeLast()
            }
        }
    }
    private static func exact(_ input: FileHandle, _ count: UInt64) throws -> Data {
        var result = Data(); result.reserveCapacity(Int(count))
        while result.count < Int(count) {
            try Task.checkCancellation()
            guard let part = try input.read(upToCount: Int(count) - result.count), !part.isEmpty else { throw SaveError.invalid("The save document is incomplete. Your local save was kept.") }
            result.append(part)
        }
        return result
    }
    private static func digest(_ url: URL, bytes: UInt64) throws -> String {
        let file = try FileHandle(forReadingFrom: url); defer { try? file.close() }
        var digest = SHA256(), remaining = bytes
        while remaining > 0 {
            let data = try exact(file, min(remaining, 64 * 1024))
            remaining -= UInt64(data.count); digest.update(data: data)
        }
        guard (try file.read(upToCount: 1) ?? Data()).isEmpty else { throw SaveError.invalid("A save file changed during backup. Try again after the game has finished saving.") }
        return hex(digest.finalize())
    }
    private static func hash(_ data: Data) -> String { hex(SHA256.hash(data: data)) }
    private static func hex<S: Sequence>(_ value: S) -> String where S.Element == UInt8 { value.map { String(format: "%02x", $0) }.joined() }
}
