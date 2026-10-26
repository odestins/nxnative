import Foundation

public enum GameChatRules {
    public static func validID(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 20 && value.first != "0" &&
        value.utf8.allSatisfy { (48...57).contains($0) } && UInt64(value) != nil
    }

    public static func invitation(_ value: String) -> String? {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (16...256).contains(value.utf8.count),
              value.utf8.allSatisfy({ (33...126).contains($0) }) else { return nil }
        return value
    }

    public static func message(_ value: String) -> String? {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return !text.isEmpty && text.utf16.count <= 2000 ? text : nil
    }

    public static func avatar(_ value: String) -> URL? {
        guard let url = URL(string: value), url.scheme == "https",
              ["cdn.discordapp.com", "media.discordapp.net"].contains(url.host ?? ""),
              url.user == nil, url.password == nil else { return nil }
        return url
    }

    public static func inviteURL(_ value: String) -> String? {
        guard let url = URLComponents(string: value), url.scheme == "switchchat",
              url.user == nil, url.password == nil, url.port == nil, url.fragment == nil,
              url.queryItems?.count == 1, let item = url.queryItems?.first else { return nil }
        let sharedLink = url.host == "join" && url.path.isEmpty && item.name == "code"
        let discordLink = url.host == "game" && url.path == "/_discord/join" && item.name == "secret"
        guard sharedLink || discordLink else { return nil }
        return item.value.flatMap(invitation)
    }
}
