import XCTest
#if os(macOS)
@testable import SwitchMacApp
#else
@testable import iSwitch
#endif

/// Opt-in network acceptance. Creates one isolated guest and checks the real
/// broker/SDK gateway. Never joins a lobby, activates a microphone, sends a
/// message or invite, or reads the owner's stored Discord credentials.
final class LiveGuestChatTests: XCTestCase {
    @MainActor func testGuestConnectsAndRenewsWithoutDiscordLogin() async throws {
        guard ProcessInfo.processInfo.environment["SWITCH_CHAT_LIVE_TEST"] == "1" else {
            throw XCTSkip("Live guest acceptance requires explicit SWITCH_CHAT_LIVE_TEST=1.")
        }
        var identity: GuestChatIdentity?
        let guests = GuestChatIdentityStore(read: { identity }, save: { identity = $0 })
        let credentials = GameChatCredentialStore(read: { nil }, save: { _ in XCTFail("Guest must not save OAuth credentials") }, delete: {})
        let chat = GameChatService(credentials: credentials, guestStore: guests, managesAudio: false)
        defer { chat.shutdown() }
        await chat.continueAsGuest(name: "Switch validation")
        XCTAssertTrue(chat.linked, chat.notice ?? chat.status)
        XCTAssertTrue(chat.isGuest); XCTAssertNotNil(chat.account)
        let accountID = chat.account?.id
        let original = identity?.fingerprint
        await chat.reconnect(forceRefresh: true)
        XCTAssertTrue(chat.linked, chat.notice ?? chat.status)
        XCTAssertEqual(identity?.fingerprint, original)
        XCTAssertFalse(chat.inParty); XCTAssertFalse(chat.hasCall)
        chat.shutdown()
        let restored = GameChatService(credentials: credentials, guestStore: guests, managesAudio: false)
        defer { restored.shutdown() }
        await restored.restore()
        XCTAssertTrue(restored.linked, restored.notice ?? restored.status)
        XCTAssertEqual(restored.account?.id, accountID)
        await restored.unlink()
        XCTAssertFalse(restored.linked); XCTAssertEqual(identity?.active, false)
    }
}
