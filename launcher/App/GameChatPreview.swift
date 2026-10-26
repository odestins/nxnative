import Foundation
import iSwitchCore

extension GameChatService {
    @MainActor static func forLaunch() -> GameChatService {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
            if ProcessInfo.processInfo.arguments.contains("--reset-test-library") { UserDefaults.standard.removeObject(forKey: "discordAgeRequirementConfirmed") }
            let preview = ProcessInfo.processInfo.arguments.contains("--gamechat-preview")
            let store = GameChatCredentialStore(read: { preview ? GameChatTokens(accessToken: "fixture", refreshToken: "fixture", expiresAt: .distantFuture) : nil }, save: { _ in }, delete: {})
            var identity: GuestChatIdentity?
            let guests = GuestChatIdentityStore(read: { identity }, save: { identity = $0 })
            return GameChatService(transport: PreviewChatTransport(), credentials: store, guestAuthorizer: PreviewGuestAuthorizer(), guestStore: guests, managesAudio: false, microphonePermission: { true })
        }
        #endif
        return GameChatService()
    }
}

#if DEBUG
@MainActor private struct PreviewGuestAuthorizer: GuestChatAuthorizing {
    let available = true
    func authorize(_ identity: GuestChatIdentity) async throws -> GameChatTokens {
        GameChatTokens(accessToken: "guest-fixture", refreshToken: "", expiresAt: .distantFuture)
    }
}
/// Explicit UI-test fixture, excluded from Release. Never uses a real account.
@MainActor final class PreviewChatTransport: GameChatTransport {
    let available = true
    var onEvent: ((String, String) -> Void)?
    var ready = false, party = false, voice = false, muted = false, deafened = false
    var rows: [[String: Any]] = [["id": "1561000000000000001", "authorID": "1002", "author": "Alex", "text": "Ready for a game?"]]
    var snapshot: [String: Any] {
        ["status": ready ? "Ready" : "Disconnected", "account": ["id": "1001", "name": "Player"],
         "friends": [["id": "1002", "name": "Alex", "status": "Online", "activity": "In ArcStation"], ["id": "1003", "name": "Sam", "status": "Online"], ["id": "1004", "name": "Nora", "status": "Offline"]],
         "members": party ? [["id": "1001", "name": "Player", "inVoice": voice], ["id": "1002", "name": "Alex", "speaking": voice, "inVoice": voice]] : [],
         "lobbyID": party ? "2001" : "0", "hasCall": voice, "voiceStatus": voice ? "Connected" : "Disconnected", "muted": muted, "deafened": deafened]
    }
    func tick() {}
    func cancel() { ready = false; party = false; voice = false }
    func request(_ action: String, _ parameters: [String: Any], timeout: Double) async throws -> [String: Any] {
        switch action {
        case "connect": ready = true
        case "authorize": throw LibraryError.invalid("UI tests use a simulated account; live sign-in is disabled.")
        case "join": party = true
        case "leave": party = false; voice = false
        case "voiceStart": voice = true
        case "voiceStop": voice = false
        case "mute": muted = parameters["value"] as? Bool ?? false
        case "deafen": deafened = parameters["value"] as? Bool ?? false
        case "messages", "partyMessages": return ["messages": rows]
        case "send", "partySend":
            if ProcessInfo.processInfo.arguments.contains("--gamechat-send-failure") { throw LibraryError.invalid("Message could not be delivered. Your draft is saved.") }
            rows.append(["id": String(1_561_000_000_000_000_001 + rows.count), "authorID": "1001", "author": "Player", "text": parameters["text"] as? String ?? ""])
        default: break
        }
        return [:]
    }
}
#endif
