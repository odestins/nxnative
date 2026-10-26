import Foundation

public enum SourceValidation {
    public static func keyCount(_ data: Data) throws -> Int {
        guard data.count <= 256 * 1024, let text = String(data: data, encoding: .utf8) else {
            throw LibraryError.invalid("Choose a prod.keys text file smaller than 256 KB.")
        }
        var entries: [String: String] = [:]
        for raw in text.replacingOccurrences(of: "\u{feff}", with: "").components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2,
                  parts[0].range(of: "^[A-Za-z0-9_]+$", options: .regularExpression) != nil,
                  parts[1].range(of: "^[a-fA-F0-9]{32,4096}$", options: .regularExpression) != nil,
                  parts[1].count.isMultiple(of: 2) else { throw LibraryError.invalid("This is not a valid prod.keys file. Key values are never displayed or logged.") }
            let name = parts[0].lowercased(), value = parts[1].lowercased()
            if let old = entries[name], old != value { throw LibraryError.invalid("The key file contains conflicting entries.") }
            entries[name] = value
        }
        guard entries["header_key"]?.count == 64 else { throw LibraryError.invalid("This file is missing a valid header_key.") }
        return entries.count
    }

    public static func gameHeader(_ header: Data, extension ext: String) throws {
        switch ext.lowercased() {
        case "nsp":
            guard header.prefix(4) == Data("PFS0".utf8) else { throw LibraryError.invalid("This file is not an NSP container. A renamed ZIP or installer is not a game dump.") }
        case "xci":
            guard header.count >= 260, header.subdata(in: 256..<260) == Data("HEAD".utf8) else { throw LibraryError.invalid("This file is not an XCI cartridge image.") }
        default: throw LibraryError.invalid("Choose an uncompressed .nsp or .xci file. For a ZIP, first tap it in the iPhone Files app to extract it.")
        }
    }

    public static func titleID(in filename: String) -> String? {
        guard let range = filename.range(of: "(?i)(?<![0-9a-f])0100[0-9a-f]{12}(?![0-9a-f])", options: .regularExpression) else { return nil }
        return String(filename[range]).uppercased()
    }
}

public struct FirmwareArchiveSummary: Sendable, Equatable {
    public let archiveCount: Int
    public let expandedBytes: UInt64
}

/// Checks the ZIP directory without expanding hundreds of megabytes into memory.
/// Decryption and NCA integrity checks belong to the runtime's preparation stage.
public enum FirmwareArchive {
    public static func inspect(_ url: URL) throws -> FirmwareArchiveSummary {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let size = try handle.seekToEnd()
        guard size >= 22, size <= 8 * 1024 * 1024 * 1024 else { throw invalid }
        let tailSize = min(size, 65_557)
        try handle.seek(toOffset: size - tailSize)
        let tail = try handle.read(upToCount: Int(tailSize)) ?? Data()
        guard tail.count == Int(tailSize) else { throw invalid }
        var end: Int?
        for i in stride(from: tail.count - 22, through: 0, by: -1) {
            if tail.u32(i) == 0x06054b50, i + 22 + Int(tail.u16(i + 20)) == tail.count { end = i; break }
        }
        guard let end, tail.u16(end + 4) == 0, tail.u16(end + 6) == 0 else { throw invalid }
        let count = Int(tail.u16(end + 10)), length = Int(tail.u32(end + 12))
        let offset = UInt64(tail.u32(end + 16))
        guard count > 0, count <= 4096, count == Int(tail.u16(end + 8)), length <= 4 * 1024 * 1024,
              offset + UInt64(length) <= size - tailSize + UInt64(end) else { throw invalid }
        try handle.seek(toOffset: offset)
        let directory = try handle.read(upToCount: length) ?? Data()
        guard directory.count == length else { throw invalid }
        var cursor = 0, ncas = 0, total: UInt64 = 0, names = Set<String>()
        for _ in 0..<count {
            guard cursor + 46 <= directory.count, directory.u32(cursor) == 0x02014b50 else { throw invalid }
            let flags = directory.u16(cursor + 8), method = directory.u16(cursor + 10)
            let compressed = UInt64(directory.u32(cursor + 20)), expanded = UInt64(directory.u32(cursor + 24))
            let nameLength = Int(directory.u16(cursor + 28))
            let next = cursor + 46 + nameLength + Int(directory.u16(cursor + 30)) + Int(directory.u16(cursor + 32))
            let unixMode = directory.u32(cursor + 38) >> 16
            let local = UInt64(directory.u32(cursor + 42))
            guard nameLength > 0, next <= directory.count, flags & 1 == 0, [0, 8].contains(method),
                  directory.u16(cursor + 34) == 0, unixMode & 0xf000 != 0xa000,
                  expanded <= 2 * 1024 * 1024 * 1024, local + 30 + compressed <= offset,
                  let name = String(data: directory.subdata(in: cursor + 46..<cursor + 46 + nameLength), encoding: .utf8),
                  !name.hasPrefix("/"), !name.contains("\\"), !name.contains(":"),
                  !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
                  !name.split(separator: "/").contains(".."), names.insert(name.lowercased()).inserted else { throw invalid }
            if !name.hasSuffix("/") {
                let basename = String(name.split(separator: "/").last ?? "")
                guard basename.range(of: "^[a-fA-F0-9]{32}(\\.cnmt)?\\.nca$", options: .regularExpression) != nil,
                      expanded > 0 else { throw invalid }
                ncas += 1; total += expanded
                guard total <= 8 * 1024 * 1024 * 1024 else { throw invalid }
            }
            cursor = next
        }
        guard cursor == directory.count, ncas > 0 else { throw invalid }
        return FirmwareArchiveSummary(archiveCount: ncas, expandedBytes: total)
    }

    private static var invalid: LibraryError {
        .invalid("Choose a firmware ZIP containing only NCA files. Split, encrypted, ZIP64, damaged, and installer archives are not supported.")
    }
}

private extension Data {
    func u16(_ offset: Int) -> UInt16 { UInt16(self[offset]) | UInt16(self[offset + 1]) << 8 }
    func u32(_ offset: Int) -> UInt32 { UInt32(u16(offset)) | UInt32(u16(offset + 2)) << 16 }
}
