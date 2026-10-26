import XCTest
import iSwitchCore
#if os(macOS)
@testable import SwitchMacApp
#else
@testable import iSwitch
#endif

@MainActor private final class ChatTestTransport: GameChatTransport {
    let available = true
    var onEvent: ((String, String) -> Void)?
    var ready = false, party = false, voice = false, muted = false
    var actions: [String] = []
    var failSend = false
    var delayFirstConversation = false
    var messageRevision = 0
    var refreshGate: CheckedContinuation<Void, Never>?
    var holdRefresh = false
    var holdLeave = false
    var leaveGate: CheckedContinuation<Void, Never>?
    var snapshot: [String: Any] {
        ["status": ready ? "Ready" : "Disconnected", "account": ["id": "101", "name": "Owner"],
         "friends": [["id": "102", "name": "Alex"], ["id": "103", "name": "Sam"]],
         "members": party ? [["id": "101", "name": "Owner"]] : [], "lobbyID": party ? "201" : "0",
         "hasCall": voice, "voiceStatus": voice ? "Connected" : "Disconnected", "muted": muted]
    }
    func tick() {}
    func cancel() { ready = false; party = false; voice = false }
    func request(_ action: String, _ parameters: [String: Any], timeout: Double) async throws -> [String: Any] {
        actions.append(action)
        switch action {
        case "connect": ready = true
        case "join": party = true
        case "acceptInvite": return ["secret": "12345678-abcd-1234-abcd-123456789012"]
        case "leave":
            if holdLeave { await withCheckedContinuation { leaveGate = $0 } }
            party = false; voice = false
        case "voiceStart": voice = true
        case "voiceStop": voice = false
        case "mute": muted = parameters["value"] as? Bool ?? false
        case "send", "partySend": if failSend { throw LibraryError.invalid("Offline") }
        case "messages", "partyMessages":
            let id = parameters["id"] as? String ?? "201"
            if delayFirstConversation && id == "102" { try await Task.sleep(for: .milliseconds(120)) }
            let suffix = messageRevision == 0 ? "" : " (\(messageRevision))"
            return ["messages": [["id": "1561000000000000001", "authorID": id, "author": id, "text": "Message from \(id)\(suffix)"]]]
        case "refresh":
            if holdRefresh { await withCheckedContinuation { refreshGate = $0 } }
            return ["accessToken": "fixture-new-access", "refreshToken": "fixture-new-refresh", "expiresIn": 3600]
        default: break
        }
        return [:]
    }
}

@MainActor private final class ChatTestCredentials {
    var tokens: GameChatTokens? = .init(accessToken: "fixture-access", refreshToken: "fixture-refresh", expiresAt: .distantFuture)
    var saves = 0
    var store: GameChatCredentialStore { .init(read: { self.tokens }, save: { self.tokens = $0; self.saves += 1 }, delete: { self.tokens = nil }) }
}

final class GameChatTests: XCTestCase {
    @MainActor func testRestoresWithoutReauthorizingAndLocalDisconnectPreservesSharedGrant() async throws {
        let transport = ChatTestTransport(), credentials = ChatTestCredentials()
        let chat = GameChatService(transport: transport, credentials: credentials.store, guestStore: .init(read: { nil }, save: { _ in }), managesAudio: false)
        defer { chat.shutdown() }
        await chat.restore()
        XCTAssertTrue(chat.linked)
        XCTAssertFalse(transport.actions.contains("authorize"))
        XCTAssertFalse(transport.actions.contains("refresh"))
        await chat.unlink()
        XCTAssertNil(credentials.tokens)
        XCTAssertFalse(chat.linked)
        XCTAssertTrue(chat.friends.isEmpty)
        XCTAssertFalse(transport.actions.contains("revoke"), "Signing out on iPhone must not revoke ArcStation's shared app grant")
    }

    @MainActor func testMicrophoneDenialPreservesPartyTextAndVoiceCanToggleLater() async throws {
        let transport = ChatTestTransport(), credentials = ChatTestCredentials()
        var permitted = false
        let chat = GameChatService(transport: transport, credentials: credentials.store, guestStore: .init(read: { nil }, save: { _ in }), managesAudio: false, microphonePermission: { permitted })
        defer { chat.shutdown() }
        await chat.restore(); await chat.createParty()
        XCTAssertTrue(chat.inParty); XCTAssertFalse(chat.hasCall)
        XCTAssertFalse(transport.actions.contains("voiceStart"))
        XCTAssertEqual(chat.conversation, .party("201"))
        chat.draft = "Hello party"; await chat.send()
        XCTAssertTrue(transport.actions.contains("partySend"))
        permitted = true; await chat.startVoice()
        XCTAssertTrue(chat.hasCall)
        await chat.toggleMute(); XCTAssertTrue(chat.muted)
        await chat.stopVoice(); XCTAssertFalse(chat.hasCall); XCTAssertTrue(chat.inParty)
        await chat.leaveParty(); XCTAssertFalse(chat.inParty)
    }

    @MainActor func testFailedSendKeepsDraftAndConversationChangesPreserveSeparateDrafts() async throws {
        let transport = ChatTestTransport(), credentials = ChatTestCredentials()
        let chat = GameChatService(transport: transport, credentials: credentials.store, guestStore: .init(read: { nil }, save: { _ in }), managesAudio: false)
        defer { chat.shutdown() }
        await chat.restore(); await chat.select(.friend("102"))
        chat.draft = "Do not lose this message"; transport.failSend = true
        await chat.send()
        XCTAssertEqual(chat.draft, "Do not lose this message"); XCTAssertFalse(chat.isSending)
        XCTAssertEqual(chat.sendError, "Offline"); XCTAssertNil(chat.notice)
        await chat.select(.friend("103")); chat.draft = "Another draft"
        await chat.select(.friend("102")); XCTAssertEqual(chat.draft, "Do not lose this message")
        transport.failSend = false; await chat.send(); XCTAssertEqual(chat.draft, "")
        XCTAssertNil(chat.sendError)
        await chat.select(.friend("103")); XCTAssertEqual(chat.draft, "Another draft")
    }

    @MainActor func testOldConversationResponseCannotReplaceNewSelection() async throws {
        let transport = ChatTestTransport(), credentials = ChatTestCredentials()
        let chat = GameChatService(transport: transport, credentials: credentials.store, guestStore: .init(read: { nil }, save: { _ in }), managesAudio: false)
        defer { chat.shutdown() }
        await chat.restore(); transport.delayFirstConversation = true
        let old = Task { await chat.select(.friend("102")) }
        try await Task.sleep(for: .milliseconds(20))
        await chat.select(.friend("103")); await old.value
        XCTAssertEqual(chat.conversation, .friend("103"))
        XCTAssertEqual(chat.messages.first?.text, "Message from 103")
        XCTAssertFalse(chat.loadingMessages)
    }

    @MainActor func testUnlinkDuringRefreshCannotRestoreCredentials() async throws {
        let transport = ChatTestTransport(), credentials = ChatTestCredentials()
        let chat = GameChatService(transport: transport, credentials: credentials.store, guestStore: .init(read: { nil }, save: { _ in }), managesAudio: false)
        defer { chat.shutdown() }
        await chat.restore(); transport.holdRefresh = true
        let refresh = Task { await chat.reconnect(forceRefresh: true) }
        for _ in 0..<50 { if transport.refreshGate != nil { break }; await Task.yield() }
        XCTAssertNotNil(transport.refreshGate)
        await chat.unlink()
        transport.refreshGate?.resume(); transport.refreshGate = nil; await refresh.value
        XCTAssertFalse(chat.linked); XCTAssertNil(credentials.tokens); XCTAssertEqual(credentials.saves, 0)
    }

    @MainActor func testOfficialBridgeAndBundledAppConfiguration() {
        XCTAssertTrue(ASDiscordBridge.compiledAvailable())
        XCTAssertEqual(GameChatConfiguration.load()?.applicationID, "1560449870496792729")
        XCTAssertNotNil(ASDiscordBridge.parseSnowflake("1560449870496792729"))
        for value in ["-1", "01", "18446744073709551616", "1e10"] { XCTAssertNil(ASDiscordBridge.parseSnowflake(value)) }
    }

    @MainActor func testMuteRemainsAvailableWhileGatewayReconnects() async {
        let transport = ChatTestTransport(), credentials = ChatTestCredentials()
        let chat = GameChatService(transport: transport, credentials: credentials.store, guestStore: .init(read: { nil }, save: { _ in }), managesAudio: false, microphonePermission: { true })
        defer { chat.shutdown() }
        await chat.restore(); await chat.createParty()
        XCTAssertTrue(chat.hasCall)
        transport.ready = false; transport.onEvent?("status", "Reconnecting")
        XCTAssertFalse(chat.linked); XCTAssertTrue(chat.hasCall)
        await chat.toggleMute()
        XCTAssertTrue(chat.muted); XCTAssertTrue(transport.actions.contains("mute"))
    }

    @MainActor func testDuplicateInvitesAreSuppressedAndResetForNewParty() async throws {
        let transport = ChatTestTransport(), credentials = ChatTestCredentials()
        let chat = GameChatService(transport: transport, credentials: credentials.store, guestStore: .init(read: { nil }, save: { _ in }), managesAudio: false)
        defer { chat.shutdown() }
        await chat.restore(); await chat.createParty(voice: false)
        let friend = try XCTUnwrap(chat.friends.first)
        await chat.invite(friend); await chat.invite(friend)
        XCTAssertEqual(transport.actions.filter { $0 == "invite" }.count, 1)
        XCTAssertTrue(chat.invitedIDs.contains(friend.id)); XCTAssertTrue(chat.invitingIDs.isEmpty)
        await chat.leaveParty(); await chat.createParty(voice: false); await chat.invite(friend)
        XCTAssertEqual(transport.actions.filter { $0 == "invite" }.count, 2)
    }

    @MainActor func testInvitationAcceptanceJoinsOnceAndDisconnectLeavesTheParty() async {
        let transport = ChatTestTransport(), credentials = ChatTestCredentials()
        let chat = GameChatService(transport: transport, credentials: credentials.store, guestStore: .init(read: { nil }, save: { _ in }), managesAudio: false, microphonePermission: { true })
        defer { chat.shutdown() }
        await chat.restore()
        let invite = ChatInvitation(id: "301", name: "Alex")
        await chat.accept(invite)
        XCTAssertTrue(chat.inParty); XCTAssertTrue(chat.hasCall); XCTAssertFalse(chat.busy)
        await chat.accept(invite)
        XCTAssertEqual(transport.actions.filter { $0 == "acceptInvite" }.count, 1)
        await chat.unlink()
        XCTAssertTrue(transport.actions.contains("leave")); XCTAssertNil(credentials.tokens)
        XCTAssertFalse(chat.inParty); XCTAssertFalse(chat.hasCall)
    }

    @MainActor func testLeavingPartyWhileMicrophonePromptIsOpenCannotStartVoice() async {
        let transport = ChatTestTransport(), credentials = ChatTestCredentials()
        var permission: CheckedContinuation<Bool, Never>?
        let chat = GameChatService(transport: transport, credentials: credentials.store, guestStore: .init(read: { nil }, save: { _ in }), managesAudio: false, microphonePermission: { await withCheckedContinuation { permission = $0 } })
        defer { chat.shutdown() }
        await chat.restore(); await chat.createParty(voice: false)
        let start = Task { await chat.startVoice() }
        for _ in 0..<50 { if permission != nil { break }; await Task.yield() }
        XCTAssertNotNil(permission)
        await chat.leaveParty(); permission?.resume(returning: true); await start.value
        XCTAssertFalse(transport.actions.contains("voiceStart")); XCTAssertFalse(chat.hasCall); XCTAssertFalse(chat.changingVoice)
    }

    @MainActor func testRejoiningSamePartyDoesNotReuseOldMicrophoneApproval() async {
        let transport = ChatTestTransport(), credentials = ChatTestCredentials()
        var permissions: [CheckedContinuation<Bool, Never>] = []
        let chat = GameChatService(transport: transport, credentials: credentials.store, guestStore: .init(read: { nil }, save: { _ in }), managesAudio: false, microphonePermission: { await withCheckedContinuation { permissions.append($0) } })
        defer { chat.shutdown() }
        await chat.restore(); await chat.createParty(voice: false)
        let oldStart = Task { await chat.startVoice() }
        for _ in 0..<100 { if permissions.count == 1 { break }; await Task.yield() }
        XCTAssertEqual(permissions.count, 1)
        await chat.leaveParty(); await chat.createParty(voice: false)
        XCTAssertEqual(chat.lobbyID, "201", "Rejoining can return the same lobby ID")
        let newStart = Task { await chat.startVoice() }
        for _ in 0..<100 { if permissions.count == 2 { break }; await Task.yield() }
        XCTAssertEqual(permissions.count, 2)
        guard permissions.count == 2 else {
            permissions.first?.resume(returning: false); await oldStart.value; await newStart.value
            return
        }
        permissions.first?.resume(returning: true); await oldStart.value
        XCTAssertFalse(transport.actions.contains("voiceStart"), "The previous chat's approval cannot turn on this chat's microphone")
        XCTAssertTrue(chat.changingVoice, "An old response cannot hide the current microphone request")
        permissions.last?.resume(returning: true); await newStart.value
        XCTAssertTrue(chat.hasCall); XCTAssertFalse(chat.changingVoice)
        XCTAssertEqual(transport.actions.filter { $0 == "voiceStart" }.count, 1)
    }

    @MainActor func testFinishingOldJoinCannotUnlockALeaveInProgress() async {
        let transport = ChatTestTransport(), credentials = ChatTestCredentials()
        var permission: CheckedContinuation<Bool, Never>?
        let chat = GameChatService(transport: transport, credentials: credentials.store, guestStore: .init(read: { nil }, save: { _ in }), managesAudio: false, microphonePermission: { await withCheckedContinuation { permission = $0 } })
        defer { chat.shutdown() }
        await chat.restore()
        let join = Task { await chat.createParty() }
        for _ in 0..<100 { if permission != nil { break }; await Task.yield() }
        XCTAssertNotNil(permission)
        transport.holdLeave = true
        let leave = Task { await chat.leaveParty() }
        for _ in 0..<100 { if transport.leaveGate != nil { break }; await Task.yield() }
        XCTAssertNotNil(transport.leaveGate)
        permission?.resume(returning: true); await join.value
        XCTAssertTrue(chat.busy, "Leaving must stay locked until the SDK finishes leaving")
        XCTAssertFalse(transport.actions.contains("voiceStart"))
        transport.leaveGate?.resume(); await leave.value
        XCTAssertFalse(chat.busy); XCTAssertFalse(chat.inParty)
    }

    @MainActor func testParticipantControlChecksTheCallInsteadOfGatewayReadiness() async {
        // No account, network request or real call is needed: a disconnected
        // SDK must route this local operation to the call check.
        let bridge = ASDiscordBridge(applicationID: 1560449870496792729)
        let error: String? = await withCheckedContinuation { continuation in
            bridge.perform("participant", parameters: ["id": "102", "mute": true]) { _, error in
                continuation.resume(returning: error)
            }
        }
        XCTAssertEqual(error, "Join voice chat first.")
    }

    @MainActor func testGatewayRecoveryRefreshesMissedMessagesInVisibleConversation() async throws {
        let transport = ChatTestTransport(), credentials = ChatTestCredentials()
        let chat = GameChatService(transport: transport, credentials: credentials.store, guestStore: .init(read: { nil }, save: { _ in }), managesAudio: false)
        defer { chat.shutdown() }
        await chat.restore(); chat.setVisible(true); await chat.select(.friend("102"))
        XCTAssertEqual(chat.messages.first?.text, "Message from 102")
        transport.ready = false; transport.onEvent?("status", "Disconnected")
        transport.messageRevision = 1
        transport.ready = true; transport.onEvent?("status", "Ready")
        for _ in 0..<100 {
            if chat.messages.first?.text == "Message from 102 (1)" { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(chat.messages.first?.text, "Message from 102 (1)")
        XCTAssertEqual(transport.actions.filter { $0 == "messages" }.count, 2, "Reconnect catches up once without continuous message polling")
    }
}
