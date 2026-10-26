import XCTest

/// Opt in through the test-run configuration on a device with Mario preloaded.
final class HardwareSmokeTests: XCTestCase {
    /// Read-only delivery check for a newly provisioned iPad. Uses the installed
    /// library and real runtime; never resets data, links Chat, or chooses a save.
    @MainActor
    func testIPadInstallationAndMarioBoot() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Requires the owner's physical iPad with Mario installed.")
        #else
        guard ProcessInfo.processInfo.environment["ISWITCH_IPAD_SMOKE"] == "1" else {
            throw XCTSkip("Explicit iPad delivery validation only.")
        }
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = []
        app.launch()
        XCUIDevice.shared.orientation = .portrait
        let ready = NSPredicate { _, _ in
            app.frame.height > app.frame.width && app.buttons["dock-settings"].isHittable
        }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: ready, object: nil)], timeout: 15), .completed)
        XCTAssertTrue(app.buttons["game-010015100B514000"].waitForExistence(timeout: 10))
        captureIPad("Switch iPad portrait")
        app.buttons["dock-settings"].tap()
        XCTAssertTrue(app.switches["performanceHUD"].waitForExistence(timeout: 10))
        captureIPad("Switch iPad Settings")
        let cloud = app.buttons["cloudSavesSettings"]
        let list = app.collectionViews.firstMatch
        for _ in 0..<8 {
            if cloud.isHittable && cloud.frame.maxY < list.frame.maxY - 8 { break }
            list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.65))
                .press(forDuration: 0.05, thenDragTo: list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35)))
        }
        XCTAssertTrue(cloud.isHittable)
        cloud.tap()
        XCTAssertTrue(app.staticTexts["cloudSaveStatus"].waitForExistence(timeout: 15))
        captureIPad("Switch iPad iCloud availability")
        app.buttons["closePanel"].tap()
        app.buttons["dock-chat"].tap()
        let chatReady = NSPredicate { _, _ in app.buttons["continueGuest"].exists || app.buttons["createChat"].exists }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: chatReady, object: nil)], timeout: 15), .completed)
        if app.buttons["continueGuest"].exists { XCTAssertTrue(app.buttons["connectDiscord"].exists) }
        captureIPad("Switch iPad Chat options")
        app.buttons["closePanel"].tap()
        XCUIDevice.shared.orientation = .landscapeLeft
        var previous = CGRect.null
        let settled = NSPredicate { _, _ in
            let frame = app.buttons["startGame"].frame
            defer { previous = frame }
            return app.frame.width > app.frame.height && app.buttons["startGame"].isHittable && frame == previous
        }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: settled, object: nil)], timeout: 10), .completed)
        captureIPad("Switch iPad landscape")
        app.buttons["startGame"].tap()
        let game = XCUIApplication(bundleIdentifier: "com.odestins.iswitch.game.010015100b514000")
        XCTAssertTrue(game.wait(for: .runningForeground, timeout: 20))
        XCTAssertTrue(game.buttons["Play"].waitForExistence(timeout: 30))
        captureIPad("Mario iPad native launcher")
        game.buttons["Play"].tap()
        for _ in 0..<6 {
            Thread.sleep(forTimeInterval: 5)
            XCTAssertEqual(game.state, .runningForeground)
        }
        captureIPad("Mario iPad after 30 seconds")
        app.activate()
        #endif
    }

    @MainActor private func captureIPad(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Only run after comparing this checkpoint with a fresh device save backup.
    /// This exercises a real restore without selecting different player progress.
    @MainActor
    func testRestoreVerifiedMarioCheckpointOnDevice() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Requires an explicitly verified checkpoint on the owner's iPhone.")
        #else
        guard let snapshot = ProcessInfo.processInfo.environment["ISWITCH_CLOUD_RESTORE_SNAPSHOT"],
              UUID(uuidString: snapshot) != nil else { throw XCTSkip("Explicit, backed-up restore validation only.") }
        continueAfterFailure = false
        let game = XCUIApplication(bundleIdentifier: "com.odestins.iswitch.game.010015100b514000")
        if game.state != .notRunning { game.terminate() }
        game.open(URL(string: "nxnative-010015100b514000://launch?restore=\(snapshot)")!)
        let confirmation = game.alerts["Restore saved progress?"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 30))
        let checkpoint = confirmation.buttons.matching(NSPredicate(format: "label CONTAINS %@", " · v1.0.1")).firstMatch
        XCTAssertTrue(checkpoint.exists)
        checkpoint.tap()
        let dismissed = NSPredicate { _, _ in !confirmation.exists && game.state == .runningForeground }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: dismissed, object: nil)], timeout: 15), .completed)
        Thread.sleep(forTimeInterval: 10)
        XCTAssertEqual(game.state, .runningForeground)
        let restored = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); restored.name = "Mario after verified cloud restore"; restored.lifetime = .keepAlways; add(restored)
        XCUIApplication().activate()
        // The delivery script separately verifies all save bytes, the retained
        // recovery copy, and the new cloud revision after this interaction.
        #endif
    }

    @MainActor
    func testCloudSavesAndChatOnDevice() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Requires the owner's physical iPhone and iCloud-enabled signing.")
        #else
        guard ProcessInfo.processInfo.environment["ISWITCH_CLOUD_SMOKE"] == "1" else { throw XCTSkip("Explicit device validation only.") }
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = []; app.launch()
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(app.buttons["dock-chat"].waitForExistence(timeout: 15))
        app.buttons["dock-chat"].tap()
        XCTAssertTrue(app.buttons["createChat"].waitForExistence(timeout: 40), "Existing Discord consent should restore without signing in again")
        let chat = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); chat.name = "Chat on iPhone"; chat.lifetime = .keepAlways; add(chat)
        app.buttons["Chat settings"].tap()
        XCTAssertTrue(app.navigationBars["Chat Settings"].waitForExistence(timeout: 5))
        let chatSettings = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); chatSettings.name = "Chat settings on iPhone"; chatSettings.lifetime = .keepAlways; add(chatSettings)
        app.buttons["closePanel"].tap(); app.buttons["dock-settings"].tap()
        let settings = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); settings.name = "Settings on iPhone"; settings.lifetime = .keepAlways; add(settings)
        let cloud = app.buttons["cloudSavesSettings"]
        for _ in 0..<3 { if cloud.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(cloud.waitForExistence(timeout: 5)); cloud.tap()
        let status = app.staticTexts["cloudSaveStatus"]
        let available = NSPredicate { _, _ in status.exists && status.value as? String == "Available" }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: available, object: nil)], timeout: 40), .completed)
        if ProcessInfo.processInfo.environment["ISWITCH_EXPECT_CLOUD_UPLOAD"] == "1" {
            let uploaded = NSPredicate { _, _ in status.label == "Saves are in iCloud" }
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: uploaded, object: nil)], timeout: 60), .completed)
        }
        let saved = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); saved.name = "iCloud saves on iPhone"; saved.lifetime = .keepAlways; add(saved)
        app.buttons["closePanel"].tap()
        #endif
    }

    @MainActor
    func testGameChatRestoresUserAuthorizedAccount() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Requires the owner's explicit Discord authorization on the physical iPhone.")
        #else
        guard ProcessInfo.processInfo.environment["ISWITCH_DISCORD_LINKED"] == "1" else {
            throw XCTSkip("Run only after the owner has authorized Discord on this iPhone.")
        }
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = []; app.launch()
        XCUIDevice.shared.orientation = .portrait
        let ready = NSPredicate { _, _ in app.frame.height > app.frame.width && app.buttons["dock-chat"].isHittable }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: ready, object: nil)], timeout: 10), .completed)
        app.buttons["dock-chat"].tap()
        XCTAssertTrue(app.buttons["createChat"].waitForExistence(timeout: 40), "The real SDK must restore authorization and become Ready")
        XCTAssertFalse(app.buttons["connectDiscord"].exists)
        let screen = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); screen.name = "Restored Discord account on iPhone"; screen.lifetime = .keepAlways; add(screen)
        // Do not send messages/invitations or join a call during this read-only check.
        #endif
    }

    @MainActor
    func testPreloadedMarioBoots() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Requires a physical iPhone with Mario installed.")
        #else
        guard ProcessInfo.processInfo.environment["ISWITCH_HARDWARE_SMOKE"] == "1" else {
            throw XCTSkip("Set ISWITCH_HARDWARE_SMOKE=1 in the test-run environment to exercise the installed game.")
        }
        continueAfterFailure = false
        let game = XCUIApplication(bundleIdentifier: "com.odestins.iswitch.game.010015100b514000")
        if game.state != .notRunning { game.terminate() }
        let launcher = XCUIApplication()
        launcher.launchArguments = []
        launcher.launch()
        XCUIDevice.shared.orientation = .portrait
        let portraitReady = NSPredicate { _, _ in launcher.frame.height > launcher.frame.width }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: portraitReady, object: nil)], timeout: 10), .completed)
        XCTAssertTrue(launcher.buttons["game-010015100B514000"].waitForExistence(timeout: 15))
        launcher.buttons["dock-sources"].tap()
        let keyStatus = launcher.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "entries stored")).firstMatch
        for _ in 0..<4 { if keyStatus.exists { break }; launcher.collectionViews.firstMatch.swipeUp() }
        let files = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); files.name = "Stored keys on iPhone"; files.lifetime = .keepAlways; add(files)
        XCTAssertTrue(keyStatus.waitForExistence(timeout: 5))
        let firmware = launcher.staticTexts["Firmware.22.1.0.zip"]
        for _ in 0..<4 { if firmware.exists { break }; launcher.collectionViews.firstMatch.swipeUp() }
        XCTAssertTrue(firmware.waitForExistence(timeout: 5))
        launcher.buttons["closePanel"].tap()
        launcher.buttons["Your profile"].tap()
        XCTAssertTrue(launcher.buttons["chooseProfilePhoto"].waitForExistence(timeout: 5))
        launcher.buttons["closePanel"].tap()
        setHUD(false, in: launcher)
        XCUIDevice.shared.orientation = .landscapeLeft
        let landscapeReady = NSPredicate { _, _ in launcher.frame.width > launcher.frame.height && launcher.buttons["startGame"].isHittable }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: landscapeReady, object: nil)], timeout: 10), .completed)
        let home = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); home.name = "iSwitch Mario on iPhone"; home.lifetime = .keepAlways; add(home)
        launcher.buttons["startGame"].tap()
        XCTAssertTrue(game.wait(for: .runningForeground, timeout: 20))
        let play = game.buttons["Play"]
        XCTAssertTrue(play.waitForExistence(timeout: 30)); play.tap()
        // Give first-launch graphics initialization time, checking for a process exit.
        for _ in 0..<6 {
            Thread.sleep(forTimeInterval: 5)
            XCTAssertEqual(game.state, .runningForeground)
        }
        XCTAssertFalse(game.staticTexts["performanceFPS"].exists)
        let boot = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); boot.name = "Mario with performance HUD off"; boot.lifetime = .keepAlways; add(boot)
        for enabled in [true, false] {
            launcher.activate()
            setHUD(enabled, in: launcher)
            // Match the game's orientation before tapping. Physical device
            // rotation can otherwise move Start while XCTest synthesizes a tap.
            XCUIDevice.shared.orientation = .landscapeLeft
            var previous = CGRect.null
            let settled = NSPredicate { _, _ in
                let frame = launcher.buttons["startGame"].frame
                defer { previous = frame }
                return launcher.frame.width > launcher.frame.height &&
                    launcher.buttons["startGame"].isHittable && frame == previous
            }
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: settled, object: nil)], timeout: 10), .completed)
            launcher.buttons["startGame"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            XCTAssertTrue(game.wait(for: .runningForeground, timeout: 15))
            let changed = NSPredicate { _, _ in game.staticTexts["performanceFPS"].exists == enabled }
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: changed, object: nil)], timeout: 10), .completed)
            XCTAssertFalse(game.buttons["Play"].exists, "Changing the HUD should resume the running game")
            let state = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); state.name = enabled ? "Mario HUD enabled while resuming" : "Mario HUD hidden while resuming"; state.lifetime = .keepAlways; add(state)
        }
        launcher.activate()
        XCUIDevice.shared.orientation = .portrait
        let chatReady = NSPredicate { _, _ in launcher.frame.height > launcher.frame.width && launcher.buttons["dock-chat"].isHittable }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: chatReady, object: nil)], timeout: 10), .completed)
        launcher.buttons["dock-chat"].tap()
        let accountScreen = NSPredicate { _, _ in launcher.buttons["connectDiscord"].exists || launcher.buttons["createChat"].exists }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: accountScreen, object: nil)], timeout: 15), .completed)
        let chatScreen = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); chatScreen.name = "GameChat on physical iPhone"; chatScreen.lifetime = .keepAlways; add(chatScreen)
        // Account consent, real messages and calls remain explicit user actions.
        #endif
    }

    @MainActor
    private func setHUD(_ enabled: Bool, in app: XCUIApplication) {
        XCUIDevice.shared.orientation = .portrait
        let ready = NSPredicate { _, _ in app.frame.height > app.frame.width && app.buttons["dock-settings"].isHittable }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: ready, object: nil)], timeout: 10), .completed)
        app.buttons["dock-settings"].tap()
        let toggle = app.switches["performanceHUD"]
        for _ in 0..<3 { if toggle.isHittable { break }; app.collectionViews.firstMatch.swipeUp() }
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        if ((toggle.value as? String) == "1") != enabled {
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        }
        let changed = NSPredicate(format: "value == %@", enabled ? "1" : "0")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: changed, object: toggle)], timeout: 5), .completed)
        app.buttons["closePanel"].tap()
    }
}
