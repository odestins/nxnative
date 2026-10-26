import XCTest
@testable import iSwitchCore

final class GameChatRulesTests: XCTestCase {
    func testRejectsMalformedAndOverflowingDiscordIDs() {
        for value in ["", "0", "01", "+123", "1e4", " 123", "１２３", "18446744073709551616"] { XCTAssertFalse(GameChatRules.validID(value), value) }
        XCTAssertTrue(GameChatRules.validID("1560449870496792729"))
        XCTAssertTrue(GameChatRules.validID("18446744073709551615"))
    }
    func testInvitationLinkIsRestrictedToOneDataParameter() {
        let code = "12345678-abcd-1234-abcd-123456789012"
        XCTAssertEqual(GameChatRules.inviteURL("switchchat://join?code=\(code)"), code)
        XCTAssertEqual(GameChatRules.inviteURL("switchchat://game/_discord/join?secret=\(code)"), code)
        XCTAssertNil(GameChatRules.inviteURL("switchchat://game/_discord/join?secret=\(code)&admin=true"))
        for link in ["https://join?code=\(code)", "switchchat://join/evil?code=\(code)", "switchchat://join?code=\(code)&code=other", "switchchat://user@join?code=\(code)", "switchchat://join?code=\(code)#fragment"] {
            XCTAssertNil(GameChatRules.inviteURL(link))
        }
        XCTAssertNil(GameChatRules.invitation("short"))
        XCTAssertNil(GameChatRules.invitation("invitation with spaces"))
    }
    func testMessageLimitAndAvatarHosts() {
        XCTAssertEqual(GameChatRules.message(" hello \n"), "hello")
        XCTAssertNil(GameChatRules.message(" \n"))
        XCTAssertNotNil(GameChatRules.message(String(repeating: "a", count: 2000)))
        XCTAssertNil(GameChatRules.message(String(repeating: "😀", count: 1001)))
        XCTAssertNotNil(GameChatRules.avatar("https://cdn.discordapp.com/embed/avatars/1.png"))
        XCTAssertNil(GameChatRules.avatar("http://cdn.discordapp.com/a"))
        XCTAssertNil(GameChatRules.avatar("https://cdn.discordapp.com.evil.test/a"))
        XCTAssertNil(GameChatRules.avatar("file:///private/data"))
    }
}
