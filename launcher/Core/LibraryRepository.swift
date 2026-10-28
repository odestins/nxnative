import Foundation
import CryptoKit

public struct LibrarySnapshot: Sendable {
    public var games: [LibraryGame]
    public var recoveryMessage: String?
}

private struct LibraryDocument: Codable {
    var schemaVersion = 1
    var games: [LibraryGame]
}

/// Serializes mutations and writes metadata atomically. Large game data never enters this store.
public actor LibraryRepository {
    public let directory: URL
    private var games: [LibraryGame] = []
    private var loaded = false
    private var writable = false
    private let fileManager = FileManager.default
    private var primary: URL { directory.appendingPathComponent("library.json") }
    private var backup: URL { directory.appendingPathComponent("library.backup.json") }

    public init(directory: URL) { self.directory = directory }

    public func load() throws -> LibrarySnapshot {
        if loaded { return LibrarySnapshot(games: games) }
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        if !fileManager.fileExists(atPath: primary.path) && !fileManager.fileExists(atPath: backup.path) {
            loaded = true; writable = true
            return LibrarySnapshot(games: [])
        }
        if let good = try? read(primary) {
            games = good; loaded = true; writable = true
            return LibrarySnapshot(games: games)
        }
        if let bytes = try? boundedRead(backup, maximum: GameTransfer.maximumBytes), let good = try? decode(bytes) {
            // Preserve the unreadable original before restoring a valid copy.
            if fileManager.fileExists(atPath: primary.path) {
                try fileManager.copyItem(at: primary, to: directory.appendingPathComponent("library.recovery-\(UUID().uuidString).json"))
            }
            try bytes.write(to: primary, options: .atomic)
            games = good; loaded = true; writable = true
            return LibrarySnapshot(games: games, recoveryMessage: "Your library was restored from its previous backup. The unreadable file was kept for recovery. The most recent change may need to be repeated.")
        }
        throw LibraryError.unreadableLibrary
    }

    private func read(_ url: URL) throws -> [LibraryGame] {
        try decode(boundedRead(url, maximum: GameTransfer.maximumBytes))
    }

    private func decode(_ data: Data) throws -> [LibraryGame] {
        let document = try JSONDecoder().decode(LibraryDocument.self, from: data)
        guard document.schemaVersion == 1, document.games.count <= GameTransfer.maximumGames else { throw LibraryError.unreadableLibrary }
        var ids = Set<String>()
        for game in document.games {
            _ = try game.manifest.validated()
            guard game.id == game.id.uppercased(), ids.insert(game.id).inserted,
                  game.manifest.artworkBase64 == nil else { throw LibraryError.unreadableLibrary }
            if let name = game.artworkFilename {
                guard name.range(of: "^[a-f0-9]{64}\\.jpg$", options: .regularExpression) != nil else { throw LibraryError.unreadableLibrary }
            }
        }
        return document.games
    }

    public func importGames(_ manifests: [GameManifest], artwork: [String: Data] = [:]) throws -> [LibraryGame] {
        try requireWritable()
        let validated = try manifests.map { try $0.validated() }
        guard !validated.isEmpty, validated.count <= GameTransfer.maximumGames,
              Set(validated.map(\.id)).count == validated.count else { throw LibraryError.invalid("Choose distinct game cards to import.") }
        var next = games
        for var manifest in validated {
            let index = next.firstIndex { $0.id == manifest.id }
            var record = index.map { next[$0] } ?? LibraryGame(manifest: manifest)
            // Reimporting a planning card must not downgrade an already prepared game.
            if manifest.buildState == .planned && record.manifest.buildState != .planned { continue }
            if let image = artwork[manifest.id] {
                guard image.count <= 512 * 1024 else { throw LibraryError.invalid("The normalized cover image is too large.") }
                let digest = SHA256.hash(data: image).map { String(format: "%02x", $0) }.joined()
                let filename = "\(digest).jpg"
                let folder = directory.appendingPathComponent("Artwork", isDirectory: true)
                try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
                let destination = folder.appendingPathComponent(filename)
                if !fileManager.fileExists(atPath: destination.path) { try image.write(to: destination, options: .atomic) }
                record.artworkFilename = filename
            }
            if manifest.bundleID != record.manifest.bundleID || manifest.version != record.manifest.version {
                record.lastLaunchResult = .unknown
            }
            manifest.artworkBase64 = nil
            record.manifest = manifest
            if let index { next[index] = record } else { next.append(record) }
        }
        guard next.count <= GameTransfer.maximumGames else { throw LibraryError.invalid("This library is full (500 games). Remove a card before adding another.") }
        try persist(next)
        return games
    }

    public func toggleFavorite(id: String) throws -> [LibraryGame] {
        try requireWritable()
        var next = games
        if let index = next.firstIndex(where: { $0.id == id }) { next[index].isFavorite.toggle() }
        try persist(next); return games
    }

    public func recordLaunch(id: String, opened: Bool, now: Date = .now) throws -> [LibraryGame] {
        try requireWritable()
        var next = games
        if let index = next.firstIndex(where: { $0.id == id }) {
            next[index].lastLaunchResult = opened ? .opened : .unavailable
            if opened { next[index].lastOpenedAt = now }
        }
        try persist(next); return games
    }

    public func remove(id: String) throws -> [LibraryGame] {
        try requireWritable()
        try persist(games.filter { $0.id != id })
        // Covers remain available to the previous metadata backup. No game saves are touched.
        return games
    }

    public func exportLibrary() throws -> Data {
        try requireWritable()
        guard !games.isEmpty else { throw LibraryError.invalid("Add a game before exporting your library.") }
        // Encode one card at a time. A large library may contain hundreds of
        // covers, but an export must never allocate all of their base64 copies.
        var data = Data("{\"schemaVersion\":1,\"games\":[".utf8)
        let encoder = JSONEncoder()
        for (index, game) in games.enumerated() {
            try Task.checkCancellation()
            var manifest = game.manifest
            if let name = game.artworkFilename {
                let url = directory.appendingPathComponent("Artwork").appendingPathComponent(name)
                manifest.artworkBase64 = try boundedRead(url, maximum: 512 * 1024).base64EncodedString()
            }
            let card = try encoder.encode(manifest)
            let separator = index == 0 ? 0 : 1
            guard card.count <= GameTransfer.maximumBytes - data.count - separator - 2 else {
                throw LibraryError.invalid("Your library is too large to export in one file. Keep the individual game cards from your Mac as backups.")
            }
            if index > 0 { data.append(0x2c) }
            data.append(card)
        }
        data.append(contentsOf: "]}".utf8)
        return data
    }

    public func resetPreservingRecoveryFiles() throws -> [LibraryGame] {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        for url in [primary, backup] where fileManager.fileExists(atPath: url.path) {
            try fileManager.moveItem(at: url, to: directory.appendingPathComponent("library.recovery-\(UUID().uuidString).json"))
        }
        loaded = true; writable = true
        try persist([])
        return games
    }

    private func requireWritable() throws {
        if !loaded { _ = try load() }
        guard writable else { throw LibraryError.unreadableLibrary }
    }

    private func persist(_ next: [LibraryGame]) throws {
        // Character-count validation cannot bound UTF-8: one grapheme may
        // contain arbitrarily many combining marks. Reject oversized metadata
        // before encoding, and account for JSON overhead before replacing files.
        let limit = GameTransfer.maximumBytes
        let tooLarge = LibraryError.invalid("The library is too large to save safely (32 MB maximum). Use shorter game-card metadata.")
        var bytes = 0
        for game in next {
            let m = game.manifest
            for value in [m.titleID, m.name, m.version, m.bundleID, m.launchURL, m.minimumOS,
                          m.sourceRevision ?? "", game.artworkFilename ?? ""] {
                guard value.utf8.count <= limit - bytes else { throw tooLarge }
                bytes += value.utf8.count
            }
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(LibraryDocument(games: next))
        guard data.count <= limit else { throw tooLarge }
        // The file may have become unreadable since load(). Never promote
        // corrupt or oversized bytes over the last known-good recovery copy.
        if let previous = try? boundedRead(primary, maximum: limit), (try? decode(previous)) != nil {
            try previous.write(to: backup, options: .atomic)
        }
        try data.write(to: primary, options: .atomic)
        games = next
    }
}

/// Read at most limit + 1 bytes even if a file grows or its reported size is wrong.
public func boundedRead(_ url: URL, maximum: Int) throws -> Data {
    guard url.isFileURL else { throw LibraryError.invalid("Choose a local file or a file from iCloud Drive.") }
    guard maximum >= 0, maximum < Int.max else { throw LibraryError.invalid("The file-size limit is invalid.") }
    try Task.checkCancellation()
    guard try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
        throw LibraryError.invalid("Choose a regular file, not a folder or file link.")
    }
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    var data = Data()
    while data.count <= maximum {
        try Task.checkCancellation()
        let chunk = try handle.read(upToCount: min(64 * 1024, maximum + 1 - data.count)) ?? Data()
        if chunk.isEmpty { return data }
        data.append(chunk)
    }
    throw LibraryError.invalid("This file is too large to import.")
}
