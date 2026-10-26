import XCTest

final class GameChatUITests: XCTestCase {
    @MainActor func testChatSettingsBeforeAndDuringVoice() {
        // Preview transport never opens a real microphone or contacts other people.
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--reset-test-library", "--gamechat-preview"]
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        app.buttons["dock-chat"].tap()
        app.buttons["chatSettings"].tap()
        XCTAssertTrue(app.buttons["chatReconnect"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.switches["chatSettingsMicrophone"].exists)
        attach("Chat settings before voice")
        app.buttons["closePanel"].tap()
        app.buttons["dock-chat"].tap()
        app.buttons["createChat"].tap()
        XCTAssertTrue(app.buttons["chatMute"].waitForExistence(timeout: 5))
        app.buttons["closePanel"].tap()
        app.buttons["dock-chat"].tap()
        app.buttons["chatSettings"].tap()
        let microphone = app.switches["chatSettingsMicrophone"]
        for _ in 0..<4 { if microphone.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(microphone.isHittable)
        let previous = microphone.value as? String
        microphone.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        let changed = NSPredicate { _, _ in microphone.value as? String != previous }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: changed, object: nil)], timeout: 5), .completed)
        XCTAssertTrue(app.switches["chatSettingsListening"].exists)
        attach("Chat settings during voice")
        app.buttons["closePanel"].tap()
        XCTAssertTrue(app.buttons["Unmute microphone"].waitForExistence(timeout: 5))
    }

    @MainActor func testAccountScreenHasNoDeveloperConfigurationFields() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing", "--reset-test-library"]
        app.launch(); XCUIDevice.shared.orientation = .portrait
        app.buttons["dock-chat"].tap()
        XCTAssertTrue(app.buttons["connectDiscord"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["continueGuest"].exists)
        XCTAssertFalse(app.buttons["continueGuest"].isEnabled)
        XCTAssertEqual(app.secureTextFields.count, 0)
        XCTAssertEqual(app.textFields.count, 0)
        attach("GameChat account connection")
    }

    @MainActor func testGuestCanJoinTextAndVoiceWithoutDiscordSignIn() {
        // All account/network/audio behavior is the explicit Debug fixture.
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing", "--reset-test-library"]
        app.launch(); XCUIDevice.shared.orientation = .portrait
        app.buttons["dock-chat"].tap()
        XCTAssertTrue(app.buttons["continueGuest"].waitForExistence(timeout: 10))
        let age = app.switches["gameChatAge"]
        if age.value as? String != "1" { age.tap() }
        app.buttons["continueGuest"].tap()
        XCTAssertTrue(app.staticTexts["Connected as Guest"].waitForExistence(timeout: 10))
        app.buttons["joinChat"].tap()
        let invitation = app.alerts["Join Chat"].textFields["Invitation code"]
        invitation.tap(); invitation.typeText("12345678-abcd-1234-abcd-123456789012")
        // Wait for the iPad keyboard transition before using the alert's final position.
        // Tapping outside the alert invokes XCTest's default Cancel interruption handler.
        if UIDevice.current.userInterfaceIdiom == .pad {
            XCTAssertTrue(app.buttons["Hide keyboard"].waitForExistence(timeout: 5))
        }
        app.alerts["Join Chat"].buttons["Join"].tap()
        XCTAssertTrue(app.buttons["chatMute"].waitForExistence(timeout: 10))
        let draft = app.textFields["chatMessageDraft"].exists ? app.textFields["chatMessageDraft"] : app.textViews["chatMessageDraft"]
        draft.tap(); draft.typeText("Hello from a guest")
        app.buttons["sendChatMessage"].tap()
        XCTAssertTrue(app.staticTexts["Hello from a guest"].waitForExistence(timeout: 5))
        attach("Guest Chat text and voice")
        app.buttons["closePanel"].tap()
    }

    @MainActor func testFixtureMessagesPartyAndBothOrientations() {
        // Explicit in-process fixture; this test cannot send a real DM or invite.
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing", "--reset-test-library", "--gamechat-preview"]
        app.launch(); XCUIDevice.shared.orientation = .portrait
        app.buttons["dock-chat"].tap()
        XCTAssertTrue(app.buttons["gameChatList"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons["joinChat"].label, "Join")
        app.buttons["joinChat"].tap()
        XCTAssertTrue(app.alerts["Join Chat"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.alerts["Join Chat"].textFields["Invitation code"].exists)
        app.alerts["Join Chat"].buttons["Cancel"].tap()
        attach("GameChat portrait menu")
        app.buttons["gameChatList"].tap()
        app.buttons["chatFriend-1002"].tap()
        let draft = app.textFields["chatMessageDraft"].exists ? app.textFields["chatMessageDraft"] : app.textViews["chatMessageDraft"]
        XCTAssertTrue(draft.waitForExistence(timeout: 5)); draft.tap(); draft.typeText("See you in GameChat")
        app.buttons["sendChatMessage"].tap()
        XCTAssertTrue(app.staticTexts["See you in GameChat"].waitForExistence(timeout: 5))
        attach("GameChat text conversation")
        // Settle the iPad keyboard before dismissing its containing sheet.
        if UIDevice.current.userInterfaceIdiom == .pad && app.buttons["Hide keyboard"].exists {
            app.buttons["Hide keyboard"].tap()
        }
        app.buttons["closePanel"].tap(); app.buttons["dock-chat"].tap()
        app.buttons["createChat"].tap()
        XCTAssertTrue(app.buttons["chatMute"].waitForExistence(timeout: 10))
        attach("GameChat portrait party")
        XCUIDevice.shared.orientation = .landscapeLeft
        let ready = NSPredicate { _, _ in app.frame.width > app.frame.height && app.buttons["chatMute"].isHittable }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: ready, object: nil)], timeout: 10), .completed)
        app.buttons["chatMute"].tap()
        attach("GameChat landscape party")
        app.buttons["closePanel"].tap()
        XCTAssertTrue(app.buttons["Unmute microphone"].waitForExistence(timeout: 5))
        attach("HOME active Chat landscape")
        XCUIDevice.shared.orientation = .portrait
        let portrait = NSPredicate { _, _ in app.frame.height > app.frame.width && app.buttons["Unmute microphone"].isHittable }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: portrait, object: nil)], timeout: 10), .completed)
        attach("HOME active Chat portrait")
    }

    @MainActor private func attach(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }

    @MainActor func testFailedSendShowsAlertInsideConversationAndPreservesDraft() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing", "--reset-test-library", "--gamechat-preview", "--gamechat-send-failure"]
        app.launch(); XCUIDevice.shared.orientation = .portrait
        app.buttons["dock-chat"].tap(); app.buttons["gameChatList"].tap(); app.buttons["chatFriend-1002"].tap()
        let draft = app.textFields["chatMessageDraft"].exists ? app.textFields["chatMessageDraft"] : app.textViews["chatMessageDraft"]
        draft.tap(); draft.typeText("Keep my message")
        app.buttons["sendChatMessage"].tap()
        XCTAssertTrue(app.staticTexts["chatSendError"].waitForExistence(timeout: 5))
        XCTAssertEqual(draft.value as? String, "Keep my message")
        app.buttons["closePanel"].tap()
    }
}
