import Foundation
import Security
import iSwitchCore

struct GameChatConfiguration: Decodable {
    let applicationID: String
    let redirectURI: String
    var guestEndpoint: String? = nil
    var guestEndpointURL: URL? {
        guard let guestEndpoint, let url = URL(string: guestEndpoint), url.scheme == "https",
              url.host != nil, url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              url.path == "/v1/guest-token" else { return nil }
        return url
    }
    static func load() -> Self? {
        guard let url = Bundle.main.url(forResource: "discord", withExtension: "json"),
              let data = try? Data(contentsOf: url), let value = try? JSONDecoder().decode(Self.self, from: data),
              GameChatRules.validID(value.applicationID), value.redirectURI == "discord-\(value.applicationID):/authorize/callback" else { return nil }
        return value
    }
}

struct GameChatTokens: Codable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
    var mergedGuestID: String? = nil
}

struct GameChatCredentialStore {
    var read: () throws -> GameChatTokens?
    var save: (GameChatTokens) throws -> Void
    var delete: () throws -> Void

    static func keychain(service: String = "com.odestins.iswitch.discord") -> Self {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                  kSecAttrService as String: service, kSecAttrAccount as String: "authorization"]
        func check(_ status: OSStatus) throws {
            if status != errSecSuccess {
                throw LibraryError.invalid(status == errSecInteractionNotAllowed ? "Unlock this device to reconnect Discord." : "Discord sign-in could not be saved securely (\(status)).")
            }
        }
        return Self(read: {
            var query = base; query[kSecReturnData as String] = true; query[kSecMatchLimit as String] = kSecMatchLimitOne
            var value: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &value)
            if status == errSecItemNotFound { return nil }
            try check(status)
            guard let data = value as? Data, data.count < 64 * 1024 else { throw LibraryError.invalid("Link Discord again to restore your account.") }
            return try JSONDecoder().decode(GameChatTokens.self, from: data)
        }, save: { tokens in
            let fields: [String: Any] = [kSecValueData as String: try JSONEncoder().encode(tokens),
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
            let status = SecItemUpdate(base as CFDictionary, fields as CFDictionary)
            if status == errSecItemNotFound {
                var item = base; fields.forEach { item[$0] = $1 }; item[kSecAttrSynchronizable as String] = false
                try check(SecItemAdd(item as CFDictionary, nil))
            } else { try check(status) }
        }, delete: {
            let status = SecItemDelete(base as CFDictionary)
            if status != errSecItemNotFound { try check(status) }
        })
    }
}
