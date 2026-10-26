import Foundation
import Security
import iSwitchCore

enum SourceKind: String, Codable, Sendable { case game, firmware }
struct SourceReference: Codable, Identifiable, Sendable {
    var id = UUID()
    var kind: SourceKind
    var filename: String
    var bytes: Int64
    var addedAt = Date.now
    var localFilename: String
    var archiveCount: Int?
    var titleID: String?
}
struct VaultSnapshot: Sendable {
    var files: [SourceReference]
    var keyCount: Int?
    var keyError: String?
    var missingFileIDs: Set<UUID> = []
}

/// Owns local copies, so a provider moving or evicting the original cannot break imports.
/// File coordination and copying run on this actor, away from the UI actor.
actor SourceVault {
    private let directory: URL
    private let keyQuery: [String: String]
    private var index: URL { directory.appendingPathComponent("references.json") }

    init(directory: URL, testing: Bool = false) {
        self.directory = directory
        keyQuery = [kSecClass as String: kSecClassGenericPassword as String,
                    kSecAttrService as String: testing ? "com.odestins.iswitch.test-sources" : "com.odestins.iswitch.sources",
                    kSecAttrAccount as String: "prod.keys"]
    }

    func snapshot() throws -> VaultSnapshot {
        let files = try references()
        // Interrupted imports are never indexed. Remove only our unfinished copies.
        for url in (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [] where url.pathExtension == "partial" {
            try? FileManager.default.removeItem(at: url)
        }
        var keys: Int?, result: CFTypeRef?, keyError: String?
        var query = keyQuery as [String: Any]; query[kSecReturnData as String] = true
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data {
            do { keys = try SourceValidation.keyCount(data) }
            catch { keyError = "Stored keys could not be read. Add prod.keys again to replace them; your imported games are safe." }
        }
        else if status != errSecItemNotFound { keyError = keychainError(status).localizedDescription }
        let missing = Set(files.filter { !copyIsAvailable($0) }.map(\.id))
        return VaultSnapshot(files: files, keyCount: keys, keyError: keyError, missingFileIDs: missing)
    }

    func importKeys(_ url: URL) throws -> Int {
        let data = try coordinated(url) { try boundedRead($0, maximum: 256 * 1024) }
        let count = try SourceValidation.keyCount(data)
        let updates: [String: Any] = [kSecValueData as String: data, kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        var status = SecItemUpdate(keyQuery as CFDictionary, updates as CFDictionary)
        if status == errSecItemNotFound {
            var attributes = keyQuery as [String: Any]
            updates.forEach { attributes[$0] = $1 }
            attributes[kSecAttrSynchronizable as String] = false
            status = SecItemAdd(attributes as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw keychainError(status) }
        return count
    }

    func removeKeys() throws {
        let result = SecItemDelete(keyQuery as CFDictionary)
        guard result == errSecSuccess || result == errSecItemNotFound else { throw LibraryError.invalid("The stored keys could not be removed.") }
    }

    func add(_ url: URL, kind: SourceKind) throws -> SourceReference {
        try Task.checkCancellation()
        var files = try references()
        guard files.count < 500 else { throw LibraryError.invalid("Remove an imported file before adding more (500 maximum).") }
        try createDirectory()
        return try coordinated(url) { source in
            let values = try source.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard values.isRegularFile == true, let bytes = values.fileSize, bytes > 0 else { throw LibraryError.invalid("Choose a nonempty file from Files.") }
            var archiveCount: Int?
            if kind == .game {
                let handle = try FileHandle(forReadingFrom: source); defer { try? handle.close() }
                try SourceValidation.gameHeader(try handle.read(upToCount: 4096) ?? Data(), extension: source.pathExtension)
            } else { archiveCount = try FirmwareArchive.inspect(source).archiveCount }
            let capacity = try directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage
            if let capacity, capacity < Int64(bytes) + 256 * 1024 * 1024 { throw LibraryError.invalid("Free at least \(ByteCountFormatter.string(fromByteCount: Int64(bytes) + 256 * 1024 * 1024, countStyle: .file)) on this device, then try again.") }
            let filename = UUID().uuidString + "." + source.pathExtension.lowercased()
            let destination = directory.appendingPathComponent(filename)
            let staging = directory.appendingPathComponent(filename + ".partial")
            defer { try? FileManager.default.removeItem(at: staging) }
            try FileManager.default.copyItem(at: source, to: staging)
            try Task.checkCancellation()
            guard try staging.resourceValues(forKeys: [.fileSizeKey]).fileSize == bytes else {
                throw LibraryError.invalid("The selected file changed while copying. Wait for its download to finish and try again.")
            }
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: staging.path)
            let reference = SourceReference(kind: kind, filename: url.lastPathComponent, bytes: Int64(bytes), localFilename: filename,
                                            archiveCount: archiveCount, titleID: SourceValidation.titleID(in: url.lastPathComponent))
            // If the app is terminated between the file rename and index commit,
            // retain enough metadata to recover this complete offline copy.
            let journal = destination.appendingPathExtension("importing")
            try JSONEncoder().encode(reference).write(to: journal, options: [.atomic, .completeFileProtection])
            var committed = false
            defer {
                if committed || !FileManager.default.fileExists(atPath: destination.path) {
                    try? FileManager.default.removeItem(at: journal)
                } else {
                    // If cleanup itself fails, keep the journal with the copy
                    // so the next launch can recover it instead of orphaning it.
                    do {
                        try FileManager.default.removeItem(at: destination)
                        try? FileManager.default.removeItem(at: journal)
                    } catch {}
                }
            }
            try FileManager.default.moveItem(at: staging, to: destination)
            files.append(reference)
            try save(files)
            committed = true
            return reference
        }
    }

    func assign(_ reference: SourceReference, titleID: String) throws {
        var files = try references()
        guard let i = files.firstIndex(where: { $0.id == reference.id }) else { return }
        files[i].titleID = titleID; try save(files)
    }

    func remove(id: UUID) throws {
        let files = try references()
        guard let item = files.first(where: { $0.id == id }) else { return }
        let original = directory.appendingPathComponent(item.localFilename)
        let deleting = original.appendingPathExtension("deleting")
        guard !itemExists(deleting) else {
            throw LibraryError.invalid("A previous removal has conflicting files. Both copies have been kept for recovery.")
        }
        let present = FileManager.default.fileExists(atPath: original.path)
        if present { try FileManager.default.moveItem(at: original, to: deleting) }
        do { try save(files.filter { $0.id != id }) }
        catch { if present { try? FileManager.default.moveItem(at: deleting, to: original) }; throw error }
        if present { try FileManager.default.removeItem(at: deleting) }
    }

    private func references() throws -> [SourceReference] {
        var files: [SourceReference] = []
        let hasIndex = FileManager.default.fileExists(atPath: index.path)
        do {
            if hasIndex {
                files = try JSONDecoder().decode([SourceReference].self, from: boundedRead(index, maximum: 4 * 1024 * 1024))
                try validate(files)
            }
        } catch { throw LibraryError.invalid("The imported-file index could not be read. Existing files and keys have been preserved.") }
        guard FileManager.default.fileExists(atPath: directory.path) else { return files }
        let contents = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        try recoverDeletions(contents, files: files, hasIndex: hasIndex)
        let journals = contents.filter { $0.pathExtension == "importing" }
        for journal in journals {
            let reference: SourceReference
            do {
                reference = try JSONDecoder().decode(SourceReference.self, from: boundedRead(journal, maximum: 16 * 1024))
                try validate([reference])
                guard journal.lastPathComponent == reference.localFilename + ".importing" else { throw LibraryError.unreadableLibrary }
            } catch { throw LibraryError.invalid("An interrupted import's recovery information could not be read. Existing files and keys have been kept.") }
            if !files.contains(where: { $0.id == reference.id && $0.localFilename == reference.localFilename }) {
                let destination = directory.appendingPathComponent(reference.localFilename)
                if FileManager.default.fileExists(atPath: destination.path) {
                    guard copyIsAvailable(reference) else { throw LibraryError.invalid("An interrupted import is incomplete. Its files have been kept for recovery.") }
                    files.append(reference)
                    try validate(files)
                    try save(files)
                }
            }
            try? FileManager.default.removeItem(at: journal)
        }
        return files
    }

    /// Recovery runs before every read or mutation, including a deletion retried
    /// immediately after launch. Only our rename markers and a valid index give
    /// enough evidence to complete a removal; ambiguous files remain untouched.
    private func recoverDeletions(_ contents: [URL], files: [SourceReference], hasIndex: Bool) throws {
        for deleting in contents where deleting.pathExtension == "deleting" {
            let original = deleting.deletingPathExtension()
            guard isOwnedFilename(original.lastPathComponent),
                  let values = try? deleting.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
                  values.isRegularFile == true, values.isSymbolicLink != true else { continue }
            guard hasIndex else {
                throw LibraryError.invalid("The imported-file index is missing. Interrupted removals have been kept for recovery.")
            }
            guard !itemExists(original) else { continue }
            if let reference = files.first(where: { $0.localFilename == original.lastPathComponent }) {
                guard values.fileSize.map(Int64.init) == reference.bytes else { continue }
                try FileManager.default.moveItem(at: deleting, to: original)
            } else {
                try FileManager.default.removeItem(at: deleting)
            }
        }
    }

    private func itemExists(_ url: URL) -> Bool {
        // Unlike fileExists alone, attributes also detect a dangling symlink.
        FileManager.default.fileExists(atPath: url.path) || (try? FileManager.default.attributesOfItem(atPath: url.path)) != nil
    }

    private func isOwnedFilename(_ name: String) -> Bool {
        name.range(of: "^[A-Fa-f0-9-]{36}\\.(nsp|xci|zip)$", options: .regularExpression) != nil &&
            UUID(uuidString: String(name.prefix(36))) != nil
    }

    private func validate(_ files: [SourceReference]) throws {
        guard files.count <= 500, Set(files.map(\.id)).count == files.count,
              Set(files.map(\.localFilename)).count == files.count,
              files.allSatisfy({ file in
                  let name = file.localFilename
                  return isOwnedFilename(name) && file.bytes > 0 && !file.filename.isEmpty &&
                      (file.kind == .firmware ? name.hasSuffix(".zip") : !name.hasSuffix(".zip"))
              }) else { throw LibraryError.unreadableLibrary }
    }

    private func copyIsAvailable(_ reference: SourceReference) -> Bool {
        let file = directory.appendingPathComponent(reference.localFilename)
        guard let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]) else { return false }
        return values.isRegularFile == true && values.isSymbolicLink != true && values.fileSize.map(Int64.init) == reference.bytes
    }

    private func createDirectory() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var folder = directory
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try folder.setResourceValues(values)
    }

    private func keychainError(_ status: OSStatus) -> LibraryError {
        if status == errSecInteractionNotAllowed { return .invalid("Unlock this device to access stored keys.") }
        return .invalid("Keychain is unavailable (error \(status)). Reinstall a correctly signed copy of reSwitch; existing keys have been preserved.")
    }

    private func save(_ files: [SourceReference]) throws {
        try createDirectory()
        try JSONEncoder().encode(files).write(to: index, options: [.atomic, .completeFileProtection])
    }

    private func coordinated<T>(_ url: URL, read: (URL) throws -> T) throws -> T {
        guard url.isFileURL else { throw LibraryError.invalid("Choose a file on this device or iCloud Drive.") }
        let grant = url.startAccessingSecurityScopedResource(); defer { if grant { url.stopAccessingSecurityScopedResource() } }
        var result: Result<T, Error>?, error: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: .withoutChanges, error: &error) { source in result = Result { try read(source) } }
        if let error { throw error }
        guard let result else { throw LibraryError.invalid("The selected file could not be opened. Download it in Files and try again.") }
        return try result.get()
    }
}
