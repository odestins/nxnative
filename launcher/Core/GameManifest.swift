import Foundation

public enum LibraryError: LocalizedError, Equatable, Sendable {
    case invalid(String)
    case unreadableLibrary
    public var errorDescription: String? {
        switch self {
        case .invalid(let reason): reason
        case .unreadableLibrary: "The library could not be read, and no valid backup was found. Your files have been kept. Export the recovery files from Settings before resetting the library."
        }
    }
}

public struct GameManifest: Codable, Equatable, Identifiable, Sendable {
    public enum BuildState: String, Codable, Sendable { case planned, project, packaged }
    public enum Compatibility: String, Codable, Sendable { case profiled, experimental }
    public var schemaVersion: Int
    public var titleID: String
    public var name: String
    public var version: String
    public var bundleID: String
    public var launchURL: String
    public var buildState: BuildState
    public var compatibility: Compatibility
    public var minimumOS: String
    public var sourceRevision: String?
    public var artworkBase64: String?
    public var id: String { titleID }

    public init(titleID: String, name: String, version: String = "Not prepared", bundleID: String? = nil,
                buildState: BuildState = .planned, compatibility: Compatibility = .profiled,
                artworkBase64: String? = nil) {
        self.schemaVersion = 1
        self.titleID = titleID.uppercased()
        self.name = name
        self.version = version
        self.bundleID = bundleID ?? "org.nxnative.\(titleID.lowercased())"
        self.launchURL = Self.url(for: titleID)
        self.buildState = buildState
        self.compatibility = compatibility
        self.minimumOS = "26.0"
        self.artworkBase64 = artworkBase64
    }

    public static func url(for titleID: String) -> String { "nxnative-\(titleID.lowercased())://launch" }

    public func launchRequestURL(showPerformanceHUD: Bool, restoreSnapshot: String? = nil) throws -> URL {
        let checked = try validated()
        guard var components = URLComponents(string: checked.launchURL) else { throw LibraryError.invalid("The game launch link is invalid.") }
        // App-owned settings are added after card validation; imported cards still
        // cannot provide query parameters or arbitrary runtime options.
        components.queryItems = [URLQueryItem(name: "hud", value: showPerformanceHUD ? "1" : "0")]
        if let restoreSnapshot {
            guard UUID(uuidString: restoreSnapshot) != nil else { throw LibraryError.invalid("The cloud save identifier is invalid.") }
            components.queryItems?.append(URLQueryItem(name: "restore", value: restoreSnapshot))
        }
        guard let url = components.url else { throw LibraryError.invalid("The game launch link is invalid.") }
        return url
    }

    public func validated() throws -> Self {
        guard schemaVersion == 1 else { throw LibraryError.invalid("This game card uses an unsupported format. Update reSwitch and try again.") }
        guard titleID.range(of: "^[0-9A-Fa-f]{16}$", options: .regularExpression) != nil else {
            throw LibraryError.invalid("A game card must contain a 16-character title ID.")
        }
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.count <= 200,
              !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw LibraryError.invalid("The game name is empty or invalid.")
        }
        guard !version.isEmpty, version.count <= 64,
              !version.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              bundleID.range(of: "^[A-Za-z0-9-]+(\\.[A-Za-z0-9-]+)+$", options: .regularExpression) != nil,
              bundleID.count <= 200 else { throw LibraryError.invalid("The game's version or app identifier is invalid.") }
        // A card cannot introduce arbitrary schemes, web links, commands, paths, or query parameters.
        guard launchURL == Self.url(for: titleID) else {
            throw LibraryError.invalid("The launch link does not match this game's title ID. Re-export it with the reSwitch preparation tool.")
        }
        guard minimumOS.range(of: "^[0-9]{1,2}\\.[0-9]{1,2}(\\.[0-9]{1,2})?$", options: .regularExpression) != nil,
              (sourceRevision?.count ?? 0) <= 64 else { throw LibraryError.invalid("The game card's requirements are invalid.") }
        if let artworkBase64 {
            guard artworkBase64.utf8.count <= 2_800_000,
                  let data = Data(base64Encoded: artworkBase64), data.count <= 2_000_000 else {
                throw LibraryError.invalid("The cover image is invalid or too large (2 MB maximum).")
            }
        }
        var result = self
        result.titleID = titleID.uppercased()
        result.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return result
    }
}

public struct GameTransfer: Codable, Sendable {
    public var schemaVersion: Int = 1
    public var games: [GameManifest]
    public init(games: [GameManifest]) { self.games = games }
    public static let maximumBytes = 32 * 1024 * 1024
    public static let maximumGames = 500

    public static func decode(_ data: Data) throws -> [GameManifest] {
        guard data.count <= maximumBytes else { throw LibraryError.invalid("This library file is too large (32 MB maximum). Import individual game cards instead.") }
        let decoder = JSONDecoder()
        let games: [GameManifest]
        do {
            if let object = try JSONSerialization.jsonObject(with: data) as? [String: Any], object["games"] != nil {
                let transfer = try decoder.decode(Self.self, from: data)
                guard transfer.schemaVersion == 1 else { throw LibraryError.invalid("This library uses an unsupported format.") }
                games = transfer.games
            } else { games = [try decoder.decode(GameManifest.self, from: data)] }
        } catch let error as LibraryError { throw error }
        catch { throw LibraryError.invalid("This is not a reSwitch game card or library. Import the .iswitch file created on your Mac; NSP, XCI, IPA, and key files cannot be opened here.") }
        guard !games.isEmpty, games.count <= maximumGames else { throw LibraryError.invalid("A library must contain 1–500 games.") }
        let checked = try games.map { try $0.validated() }
        guard Set(checked.map(\.id)).count == checked.count else { throw LibraryError.invalid("This file contains the same game more than once.") }
        return checked
    }
}

public struct LibraryGame: Codable, Identifiable, Equatable, Sendable {
    public enum LaunchResult: String, Codable, Sendable { case unknown, opened, unavailable }
    public var manifest: GameManifest
    public var artworkFilename: String?
    public var addedAt: Date
    public var lastOpenedAt: Date?
    public var isFavorite: Bool
    public var lastLaunchResult: LaunchResult
    public var id: String { manifest.id }

    public init(manifest: GameManifest, artworkFilename: String? = nil, now: Date = .now) {
        self.manifest = manifest
        self.artworkFilename = artworkFilename
        self.addedAt = now
        self.isFavorite = false
        self.lastLaunchResult = .unknown
    }

    public var status: String {
        if manifest.buildState == .planned { return "Prepare on Mac" }
        switch lastLaunchResult {
        case .opened: return "Opened before"
        case .unavailable: return "Install game app"
        case .unknown: return manifest.buildState == .project ? "Xcode project prepared" : "Ready to install"
        }
    }
}

public enum LibrarySort: String, CaseIterable, Sendable {
    case recent = "Recent", name = "Name", added = "Date added"
    public func sorted(_ games: [LibraryGame], search: String = "", favoritesOnly: Bool = false) -> [LibraryGame] {
        games.filter {
            (!favoritesOnly || $0.isFavorite) && (search.isEmpty || $0.manifest.name.localizedCaseInsensitiveContains(search) || $0.id.localizedCaseInsensitiveContains(search))
        }.sorted { a, b in
            switch self {
            case .recent:
                let left = a.lastOpenedAt ?? .distantPast, right = b.lastOpenedAt ?? .distantPast
                if left != right { return left > right }
            case .added: if a.addedAt != b.addedAt { return a.addedAt > b.addedAt }
            case .name: break
            }
            let order = a.manifest.name.localizedStandardCompare(b.manifest.name)
            return order == .orderedSame ? a.id < b.id : order == .orderedAscending
        }
    }
}
