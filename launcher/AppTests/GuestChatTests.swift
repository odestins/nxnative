import XCTest
import iSwitchCore
#if os(macOS)
@testable import SwitchMacApp
#else
@testable import iSwitch
#endif

@MainActor private final class GuestTestState {
    var identity: GuestChatIdentity?
    var discord: GameChatTokens?
    var savedDiscord = 0
    var failIdentitySave = false, failDiscordSave = false
    var identities: GuestChatIdentityStore { .init(read: { self.identity }, save: {
        if self.failIdentitySave { throw LibraryError.invalid("Fixture Keychain unavailable") }; self.identity = $0
    }) }
    var credentials: GameChatCredentialStore {
        .init(read: { self.discord }, save: {
            if self.failDiscordSave { throw LibraryError.invalid("Fixture Keychain unavailable") }
            self.discord = $0; self.savedDiscord += 1
        }, delete: { self.discord = nil })
    }
}

@MainActor private final class GuestTestAuthorizer: GuestChatAuthorizing {
    let available = true
    var identities: [GuestChatIdentity] = []
    var fail = false
    var hold = false
    var gate: CheckedContinuation<Void, Never>?
    func authorize(_ identity: GuestChatIdentity) async throws -> GameChatTokens {
        identities.append(identity)
        if hold { await withCheckedContinuation { gate = $0 } }
        if fail { throw LibraryError.invalid("Guest Chat unavailable") }
        return .init(accessToken: "guest-token", refreshToken: "", expiresAt: .now.addingTimeInterval(3600))
    }
}

@MainActor private final class GuestTestTransport: GameChatTransport {
    let available = true
    var onEvent: ((String, String) -> Void)?
    var ready = false, party = false, voice = false
    var actions: [String] = []
    var lastAuthorization: [String: Any] = [:]
    var holdAuthorization = false, allowCancellation = true
    var gate: CheckedContinuation<Void, Never>?
    var snapshot: [String: Any] {
        ["status": ready ? "Ready" : "Disconnected", "account": ["id": "1001", "name": "Player"],
         "friends": [], "members": party ? [["id": "1001", "name": "Player"]] : [],
         "lobbyID": party ? "2001" : "0", "hasCall": voice, "voiceStatus": voice ? "Connected" : "Disconnected"]
    }
    func tick() {}
    func cancel() { ready = false; party = false; voice = false; actions.append("cancel") }
    func cancelAuthorization() -> Bool { allowCancellation }
    func request(_ action: String, _ parameters: [String: Any], timeout: Double) async throws -> [String: Any] {
        actions.append(action)
        switch action {
        case "connect": ready = true
        case "join": party = true
        case "leave": party = false; voice = false
        case "voiceStart": voice = true
        case "voiceStop": voice = false
        case "refresh": return ["accessToken": "renewed-discord", "refreshToken": "renewed-refresh", "expiresIn": 3600]
        case "authorize":
            lastAuthorization = parameters
            if holdAuthorization { await withCheckedContinuation { gate = $0 } }
            return ["accessToken": "discord-access", "refreshToken": "discord-refresh", "expiresIn": 3600]
        case "partyMessages": return ["messages": []]
        default: break
        }
        return [:]
    }
}

final class GuestChatTests: XCTestCase {
    @MainActor func testGuestCanJoinSendAndUseVoiceWithoutOAuthOrStoredAccessTokens() async {
        let state = GuestTestState(), transport = GuestTestTransport(), auth = GuestTestAuthorizer()
        let chat = GameChatService(transport: transport, credentials: state.credentials, guestAuthorizer: auth, guestStore: state.identities, managesAudio: false, microphonePermission: { true })
        defer { chat.shutdown() }
        await chat.continueAsGuest(name: "Player")
        XCTAssertTrue(chat.linked); XCTAssertTrue(chat.isGuest); XCTAssertEqual(chat.connectionLabel, "Connected as Guest")
        XCTAssertEqual(state.savedDiscord, 0); XCTAssertNil(state.discord)
        XCTAssertFalse(transport.actions.contains("authorize")); XCTAssertFalse(transport.actions.contains("refresh"))
        await chat.joinParty("12345678-abcd-1234-abcd-123456789012")
        XCTAssertTrue(chat.inParty); XCTAssertTrue(chat.hasCall)
        chat.draft = "Guest message"; await chat.send()
        XCTAssertTrue(transport.actions.contains("partySend")); XCTAssertEqual(chat.draft, "")
    }

    @MainActor func testRestoresTheSameGuestAndRenewsInPlaceDuringVoice() async throws {
        let state = GuestTestState(), transport = GuestTestTransport(), auth = GuestTestAuthorizer()
        state.identity = try .create(name: "My guest")
        let chat = GameChatService(transport: transport, credentials: state.credentials, guestAuthorizer: auth, guestStore: state.identities, managesAudio: false, microphonePermission: { true })
        defer { chat.shutdown() }
        await chat.restore(); await chat.createParty()
        let joins = transport.actions.filter { $0 == "connect" }.count
        await chat.reconnect(forceRefresh: true)
        XCTAssertTrue(chat.hasCall); XCTAssertTrue(chat.inParty)
        XCTAssertEqual(transport.actions.filter { $0 == "connect" }.count, joins)
        XCTAssertTrue(transport.actions.contains("updateToken")); XCTAssertFalse(transport.actions.contains("refresh"))
        XCTAssertEqual(auth.identities.count, 2)
        XCTAssertEqual(auth.identities[0].credential, auth.identities[1].credential)
        XCTAssertEqual(state.savedDiscord, 0)
    }

    @MainActor func testRenewalFailureKeepsTheExistingCallAndIdentity() async throws {
        let state = GuestTestState(), transport = GuestTestTransport(), auth = GuestTestAuthorizer()
        let chat = GameChatService(transport: transport, credentials: state.credentials, guestAuthorizer: auth, guestStore: state.identities, managesAudio: false, microphonePermission: { true })
        defer { chat.shutdown() }
        await chat.continueAsGuest(name: "Player"); await chat.createParty()
        auth.fail = true; await chat.reconnect(forceRefresh: true)
        XCTAssertTrue(chat.hasCall); XCTAssertTrue(chat.linked); XCTAssertTrue(chat.inParty)
        XCTAssertFalse(transport.actions.contains("cancel")); XCTAssertNotNil(chat.notice)
    }

    @MainActor func testDisconnectDoesNotLoseGuestIdentityOrAnotherSavedDiscordSession() async {
        let state = GuestTestState(), transport = GuestTestTransport(), auth = GuestTestAuthorizer()
        state.discord = .init(accessToken: "saved-discord", refreshToken: "saved-refresh", expiresAt: .distantFuture)
        let chat = GameChatService(transport: transport, credentials: state.credentials, guestAuthorizer: auth, guestStore: state.identities, managesAudio: false)
        defer { chat.shutdown() }
        await chat.continueAsGuest(name: "Player")
        let credential = state.identity?.credential
        await chat.unlink(); XCTAssertFalse(state.identity!.active)
        XCTAssertEqual(state.discord?.accessToken, "saved-discord")
        let restored = GameChatService(transport: GuestTestTransport(), credentials: state.credentials, guestAuthorizer: auth, guestStore: state.identities, managesAudio: false)
        await restored.restore(); XCTAssertFalse(restored.linked, "Guest disconnect must not sign into an older Discord account")
        restored.shutdown()
        await chat.continueAsGuest(name: "Renamed")
        XCTAssertEqual(state.identity?.credential, credential); XCTAssertTrue(chat.linked)
    }

    @MainActor func testOptionalDiscordLinkUsesTheSDKMergeFlow() async {
        let state = GuestTestState(), transport = GuestTestTransport(), auth = GuestTestAuthorizer()
        let chat = GameChatService(transport: transport, credentials: state.credentials, guestAuthorizer: auth, guestStore: state.identities, managesAudio: false)
        defer { chat.shutdown() }
        await chat.continueAsGuest(name: "Player"); await chat.link()
        XCTAssertEqual(transport.lastAuthorization["guestAccessToken"] as? String, "guest-token")
        XCTAssertFalse(chat.isGuest); XCTAssertTrue(chat.linked)
        XCTAssertTrue(state.identity!.merged); XCTAssertFalse(state.identity!.active)
        XCTAssertEqual(state.discord?.refreshToken, "discord-refresh")
    }

    @MainActor func testCancelledDiscordLinkPreservesGuestAndIgnoresLateResponse() async {
        let state = GuestTestState(), transport = GuestTestTransport(), auth = GuestTestAuthorizer()
        let chat = GameChatService(transport: transport, credentials: state.credentials, guestAuthorizer: auth, guestStore: state.identities, managesAudio: false)
        defer { chat.shutdown() }
        await chat.continueAsGuest(name: "Player"); transport.holdAuthorization = true
        let linking = Task { await chat.link() }
        for _ in 0..<100 { if transport.gate != nil { break }; await Task.yield() }
        XCTAssertNotNil(transport.gate)
        chat.cancelLink(); transport.gate?.resume(); transport.gate = nil; await linking.value
        XCTAssertTrue(chat.isGuest); XCTAssertTrue(chat.linked); XCTAssertTrue(state.identity!.active)
        XCTAssertEqual(state.savedDiscord, 0); XCTAssertFalse(transport.actions.contains("cancel"))
    }

    @MainActor func testCompletedMergeRestoresDiscordWhenGuestMarkerWriteWasInterrupted() async {
        let state = GuestTestState(), transport = GuestTestTransport(), auth = GuestTestAuthorizer()
        let chat = GameChatService(transport: transport, credentials: state.credentials, guestAuthorizer: auth, guestStore: state.identities, managesAudio: false)
        await chat.continueAsGuest(name: "Player"); state.failIdentitySave = true; await chat.link()
        XCTAssertTrue(chat.linked); XCTAssertFalse(chat.isGuest)
        XCTAssertTrue(state.identity!.active); XCTAssertFalse(state.identity!.merged)
        XCTAssertEqual(state.discord?.mergedGuestID, state.identity?.fingerprint)
        chat.shutdown()
        let restored = GameChatService(transport: GuestTestTransport(), credentials: state.credentials, guestAuthorizer: auth, guestStore: state.identities, managesAudio: false)
        defer { restored.shutdown() }
        await restored.restore()
        XCTAssertTrue(restored.linked); XCTAssertFalse(restored.isGuest)
        XCTAssertEqual(auth.identities.count, 1)
    }

    @MainActor func testFailedOAuthPersistenceKeepsConnectionAndRetriesLatestCredentials() async {
        let state = GuestTestState(), transport = GuestTestTransport(), auth = GuestTestAuthorizer()
        let chat = GameChatService(transport: transport, credentials: state.credentials, guestAuthorizer: auth, guestStore: state.identities, managesAudio: false)
        defer { chat.shutdown() }
        await chat.continueAsGuest(name: "Player"); state.failDiscordSave = true; await chat.link()
        XCTAssertTrue(chat.linked); XCTAssertFalse(chat.isGuest); XCTAssertNotNil(chat.notice)
        XCTAssertNil(state.discord)
        state.failDiscordSave = false; await chat.reconnect()
        XCTAssertTrue(chat.linked); XCTAssertEqual(state.discord?.refreshToken, "discord-refresh")
        XCTAssertEqual(state.discord?.mergedGuestID, state.identity?.fingerprint)
    }

    @MainActor func testUnavailableGuestStoreDoesNotBlockExistingDiscordSignIn() async {
        let state = GuestTestState()
        state.discord = .init(accessToken: "existing", refreshToken: "existing-refresh", expiresAt: .distantFuture)
        let guests = GuestChatIdentityStore(read: { throw LibraryError.invalid("Fixture guest record unavailable") }, save: { _ in })
        let chat = GameChatService(transport: GuestTestTransport(), credentials: state.credentials, guestAuthorizer: GuestTestAuthorizer(), guestStore: guests, managesAudio: false)
        defer { chat.shutdown() }
        await chat.restore(); XCTAssertTrue(chat.linked); XCTAssertFalse(chat.isGuest)
    }

    @MainActor func testUnreadableOldDiscordRecordDoesNotBlockGuestRestoration() async throws {
        let state = GuestTestState(); state.identity = try .create(name: "Player")
        let credentials = GameChatCredentialStore(read: { throw LibraryError.invalid("Fixture old OAuth record unavailable") }, save: { _ in }, delete: {})
        let chat = GameChatService(transport: GuestTestTransport(), credentials: credentials, guestAuthorizer: GuestTestAuthorizer(), guestStore: state.identities, managesAudio: false)
        defer { chat.shutdown() }
        await chat.restore(); XCTAssertTrue(chat.linked); XCTAssertTrue(chat.isGuest)
    }

    @MainActor func testStartedMergeFinishesBeforeDisconnectCanDiscardItsCredentials() async {
        let state = GuestTestState(), transport = GuestTestTransport(), auth = GuestTestAuthorizer()
        let chat = GameChatService(transport: transport, credentials: state.credentials, guestAuthorizer: auth, guestStore: state.identities, managesAudio: false)
        defer { chat.shutdown() }
        await chat.continueAsGuest(name: "Player"); transport.holdAuthorization = true; transport.allowCancellation = false
        let linking = Task { await chat.link() }
        for _ in 0..<100 { if transport.gate != nil { break }; await Task.yield() }
        chat.cancelLink(); await chat.unlink(); XCTAssertTrue(chat.linking)
        transport.gate?.resume(); transport.gate = nil; await linking.value
        XCTAssertTrue(chat.linked); XCTAssertFalse(chat.isGuest); XCTAssertEqual(state.savedDiscord, 1)
    }

    @MainActor func testLateGuestTokenCannotUndoDisconnect() async {
        let state = GuestTestState(), transport = GuestTestTransport(), auth = GuestTestAuthorizer()
        let chat = GameChatService(transport: transport, credentials: state.credentials, guestAuthorizer: auth, guestStore: state.identities, managesAudio: false)
        defer { chat.shutdown() }
        auth.hold = true
        let connecting = Task { await chat.continueAsGuest(name: "Player") }
        for _ in 0..<100 { if auth.gate != nil { break }; await Task.yield() }
        XCTAssertNotNil(auth.gate); await chat.unlink()
        auth.gate?.resume(); auth.gate = nil; await connecting.value
        XCTAssertFalse(chat.linked); XCTAssertFalse(state.identity!.active); XCTAssertFalse(transport.actions.contains("connect"))
    }

    func testNamesAndCredentialGeneration() throws {
        let first = try GuestChatIdentity.create(name: "  Player  "), second = try GuestChatIdentity.create(name: "Player")
        XCTAssertEqual(first.displayName, "Player"); XCTAssertEqual(first.credential.count, 43)
        XCTAssertNotEqual(first.credential, second.credential)
        for name in ["", "  ", String(repeating: "a", count: 33), "bad\u{0}name", "a\u{202e}b"] {
            XCTAssertThrowsError(try GuestChatIdentity.validName(name))
        }
    }

    func testExistingDiscordCredentialsDecodeUnchangedAndEndpointRequiresHTTPS() throws {
        let original = GameChatTokens(accessToken: "old-access", refreshToken: "old-refresh", expiresAt: .distantFuture)
        XCTAssertEqual(try JSONDecoder().decode(GameChatTokens.self, from: JSONEncoder().encode(original)).refreshToken, "old-refresh")
        for endpoint in ["http://example.com/v1/guest-token", "https://u:p@example.com/v1/guest-token", "https://example.com/v1/guest-token?secret=x", "https://example.com/redirect"] {
            XCTAssertNil(GameChatConfiguration(applicationID: "123", redirectURI: "discord-123:/authorize/callback", guestEndpoint: endpoint).guestEndpointURL)
        }
    }
}
