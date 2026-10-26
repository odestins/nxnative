import Foundation
import Security
import CryptoKit
import iSwitchCore

struct GuestChatIdentity: Codable, Equatable {
    let credential: String
    var displayName: String
    var active: Bool
    var merged: Bool
    var prefersDiscord: Bool? = nil
    var fingerprint: String { SHA256.hash(data: Data(credential.utf8)).map { String(format: "%02x", $0) }.joined() }

    static func create(name: String) throws -> Self {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw LibraryError.invalid("Couldn’t create your private Chat profile. Try again.")
        }
        let credential = Data(bytes).base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        return Self(credential: credential, displayName: try validName(name), active: true, merged: false)
    }

    static func validName(_ input: String) throws -> String {
        let name = input.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCanonicalMapping
        guard !name.isEmpty, name.unicodeScalars.count <= 32,
              !name.unicodeScalars.contains(where: { $0.properties.generalCategory == .control || $0.properties.generalCategory == .format }) else {
            throw LibraryError.invalid("Choose a Chat name with 1–32 characters.")
        }
        return name
    }
}

struct GuestChatIdentityStore {
    var read: () throws -> GuestChatIdentity?
    var save: (GuestChatIdentity) throws -> Void

    static func keychain() -> Self {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.odestins.iswitch.chat.guest", kSecAttrAccount as String: "identity"]
        func check(_ status: OSStatus) throws {
            guard status == errSecSuccess else {
                throw LibraryError.invalid(status == errSecInteractionNotAllowed ? "Unlock this device to restore Chat." : "Your Chat profile couldn’t be saved securely. Try again.")
            }
        }
        return Self(read: {
            var query = base; query[kSecReturnData as String] = true; query[kSecMatchLimit as String] = kSecMatchLimitOne
            var value: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &value)
            if status == errSecItemNotFound { return nil }
            try check(status)
            guard let data = value as? Data, data.count < 4096 else { throw LibraryError.invalid("Your guest Chat profile couldn’t be read.") }
            let identity = try JSONDecoder().decode(GuestChatIdentity.self, from: data)
            guard identity.credential.range(of: "^[A-Za-z0-9_-]{43}$", options: .regularExpression) != nil else {
                throw LibraryError.invalid("Your guest Chat profile couldn’t be read.")
            }
            return identity
        }, save: { identity in
            let fields: [String: Any] = [kSecValueData as String: try JSONEncoder().encode(identity),
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
            let status = SecItemUpdate(base as CFDictionary, fields as CFDictionary)
            if status == errSecItemNotFound {
                var item = base; fields.forEach { item[$0] = $1 }; item[kSecAttrSynchronizable as String] = false
                try check(SecItemAdd(item as CFDictionary, nil))
            } else { try check(status) }
        })
    }
}

@MainActor protocol GuestChatAuthorizing {
    var available: Bool { get }
    func authorize(_ identity: GuestChatIdentity) async throws -> GameChatTokens
}

// Never forward the installation credential through an HTTP redirect.
private final class GuestChatRedirectPolicy: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

@MainActor final class GuestChatClient: GuestChatAuthorizing {
    private let configuration: GameChatConfiguration?
    private let session: URLSession
    private let redirectPolicy = GuestChatRedirectPolicy()
    var available: Bool { configuration?.guestEndpointURL != nil }

    init(configuration: GameChatConfiguration? = .load(), session: URLSession? = nil) {
        self.configuration = configuration
        let settings = URLSessionConfiguration.ephemeral
        settings.timeoutIntervalForRequest = 20; settings.timeoutIntervalForResource = 25
        settings.httpCookieStorage = nil; settings.urlCache = nil
        self.session = session ?? URLSession(configuration: settings)
    }

    func authorize(_ identity: GuestChatIdentity) async throws -> GameChatTokens {
        guard let configuration, let endpoint = configuration.guestEndpointURL else {
            throw LibraryError.invalid("Guest Chat is not available in this build yet. You can still connect Discord.")
        }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(identity.credential)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(["displayName": GuestChatIdentity.validName(identity.displayName)])
        let (bytes, response) = try await session.bytes(for: request, delegate: redirectPolicy)
        var data = Data()
        for try await byte in bytes {
            guard data.count < 32_768 else { throw LibraryError.invalid("Chat returned an unreadable response. Try again.") }
            data.append(byte)
        }
        guard let http = response as? HTTPURLResponse else { throw LibraryError.invalid("Couldn’t connect to Chat. Try again.") }
        if http.statusCode == 409 { throw LibraryError.invalid("This guest profile is now linked to Discord. Choose Connect Discord to return to it.") }
        if http.statusCode == 429 { throw LibraryError.invalid("Chat is busy. Wait a minute, then try again.") }
        guard http.statusCode == 200 else { throw LibraryError.invalid("Guest Chat is temporarily unavailable. Try again shortly, or connect Discord.") }
        struct Reply: Decodable { let applicationID: String; let accessToken: String; let expiresIn: Double }
        guard let reply = try? JSONDecoder().decode(Reply.self, from: data), reply.applicationID == configuration.applicationID,
              !reply.accessToken.isEmpty, reply.accessToken.utf8.count <= 16_384,
              reply.expiresIn.isFinite, (60...604_800).contains(reply.expiresIn) else {
            throw LibraryError.invalid("Chat returned incomplete access. Try again.")
        }
        // Only the installation identity is persisted. Provisional tokens are
        // renewed from the broker, never sent through Discord's refresh flow.
        return GameChatTokens(accessToken: reply.accessToken, refreshToken: "", expiresAt: .now.addingTimeInterval(reply.expiresIn))
    }
}
