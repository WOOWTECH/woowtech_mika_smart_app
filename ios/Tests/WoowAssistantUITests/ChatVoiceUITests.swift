import XCTest

/// Simulator-only Debug fixture: no Speech, microphone, network or real account.
final class ChatVoiceUITests: XCTestCase {
    private let app = XCUIApplication()
    override func setUpWithError() throws {
        continueAfterFailure = false
        executionTimeAllowance = 180
        #if !targetEnvironment(simulator)
        throw XCTSkip("The isolated voice fixture runs only on a simulator.")
        #endif
    }
    override func tearDownWithError() throws { app.terminate() }

    func testHoldAndReleaseMergesCurrentDraftWithoutSending() {
        launch()
        compose("Existing draft")
        voice().press(forDuration: 1.1)
        observation(contains: "finish=1")
        XCTAssertEqual(draft().value as? String, "Existing draft")
        tap("voice.fixture.emit")
        waitValue(draft(), "Existing draft fixture voice")
        observation(contains: "emit=1")
        XCTAssertFalse(app.descendants(matching: .any)["chat.message.0.user"].exists)
        XCTAssertFalse(app.buttons["chat.cancel"].exists, "voice completion must not submit")
    }

    func testSlideUpCancellationRejectsActuallyDeliveredLateResult() {
        launch()
        compose("Unchanged")
        let mic = voice()
        let start = mic.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.8, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -110)),
                    withVelocity: .slow, thenHoldForDuration: 0.2)
        observation(contains: "cancel=1")
        tap("voice.fixture.emit")
        observation(contains: "emit=1")
        XCTAssertEqual(draft().value as? String, "Unchanged")
        XCTAssertFalse(app.descendants(matching: .any)["chat.message.0.user"].exists)
    }

    func testNewConversationRejectsActuallyDeliveredLateResult() {
        launch()
        compose("Retained draft")
        voice().press(forDuration: 1.1)
        observation(contains: "finish=1")
        tap("chat.newConversation")
        observation(contains: "cancel=1")
        tap("voice.fixture.emit")
        observation(contains: "emit=1")
        XCTAssertEqual(draft().value as? String, "Retained draft")
        XCTAssertFalse(app.descendants(matching: .any)["chat.message.0.user"].exists)
    }

    func testBackgroundRejectsActuallyDeliveredLateResult() {
        launch()
        compose("Background draft")
        voice().press(forDuration: 1.1)
        observation(contains: "finish=1")
        XCUIDevice.shared.press(.home)
        app.activate()
        observation(contains: "cancel=1")
        tap("voice.fixture.emit")
        observation(contains: "emit=1")
        XCTAssertEqual(draft().value as? String, "Background draft")
        XCTAssertFalse(app.descendants(matching: .any)["chat.message.0.user"].exists)
    }

    func testLocalizedVoiceOverEntryAndActivation() {
        // A Simplified Chinese system shows Traditional Chinese.
        let cases = [("(zh-Hant)", "語音輸入", "取消語音輸入"),
                     ("(zh-Hans)", "語音輸入", "取消語音輸入"),
                     ("(en)", "Voice input", "Cancel voice input")]
        for (language, label, cancelLabel) in cases {
            launch(systemLanguages: language)
            XCTAssertEqual(voice().label, label)
            // Calls the actual UIButton accessibilityActivate() via a Debug-only
            // bridge; this does not claim that VoiceOver itself was enabled.
            tap("voice.fixture.accessibility")
            observation(contains: "start=1")
            tap("voice.fixture.accessibility")
            observation(contains: "finish=1")
            tap("voice.fixture.emit")
            waitValue(draft(), "fixture voice")
            XCTAssertFalse(app.descendants(matching: .any)["chat.message.0.user"].exists)
            tap("voice.fixture.accessibility")
            observation(contains: "start=2")
            tap("voice.fixture.cancelAccessibility")
            let action = app.staticTexts["voice.fixture.actionName"].firstMatch
            XCTAssertTrue(action.waitForExistence(timeout: 10))
            XCTAssertEqual(action.label, cancelLabel)
            observation(contains: "cancel=2")
            tap("voice.fixture.emit")
            observation(contains: "emit=2")
            XCTAssertEqual(draft().value as? String, "fixture voice", "VoiceOver cancellation must discard the actual stale callback")
        }
    }

    func testVoiceSettingOffAndDeviceChoiceControlActualComposer() {
        launch()
        tap("chat.menu")
        tap("navigation.settings")
        openModelSettings(in: app)
        revealLearningElement(app.buttons["settings.voice.open"], in: app)
        tap("settings.voice.open")
        let voiceSettings = app.navigationBars["語音轉文字"]
        XCTAssertTrue(voiceSettings.waitForExistence(timeout: 10))
        // The Play edition's option names: 手機自帶 (here the device's) and 不用.
        XCTAssertTrue(app.buttons["settings.voice.system"].label.hasPrefix("裝置自帶"))
        XCTAssertTrue(app.buttons["settings.voice.off"].label.hasPrefix("不用"))
        tap("settings.voice.off")
        voiceSettings.buttons.firstMatch.tap()
        returnFromModelSettings(in: app)
        tap("section.back")
        let mic = app.buttons["chat.voice"].firstMatch
        XCTAssertTrue(mic.waitForExistence(timeout: 10))
        XCTAssertFalse(mic.isEnabled)
        observation(contains: "start=0")
        // Reuse the isolated namespace and omit reset to check persistence.
        app.terminate()
        app.launchArguments.removeAll { $0 == "-UITestResetStorage" }
        app.launch()
        XCTAssertTrue(app.staticTexts["voice.fixture.observation"].waitForExistence(timeout: 10))
        XCTAssertTrue(mic.waitForExistence(timeout: 10))
        XCTAssertFalse(mic.isEnabled, "off choice survives application restart")
        tap("chat.menu")
        tap("navigation.settings")
        openModelSettings(in: app)
        revealLearningElement(app.buttons["settings.voice.open"], in: app)
        tap("settings.voice.open")
        XCTAssertTrue(voiceSettings.waitForExistence(timeout: 10))
        tap("settings.voice.system")
        voiceSettings.buttons.firstMatch.tap()
        returnFromModelSettings(in: app)
        tap("section.back")
        XCTAssertTrue(voice().isEnabled)
        voice().press(forDuration: 1.1)
        observation(contains: "finish=1")
        tap("voice.fixture.emit")
        waitValue(draft(), "fixture voice")
    }

    private func launch(systemLanguages: String = "(zh-Hant)") {
        app.terminate()
        app.launchArguments = ["-AppleLanguages", systemLanguages, "-AppleLocale", "zh_TW",
                               "-UITestMode", "-UITestNamespace", UUID().uuidString,
                               "-UITestResetStorage", "-UITestVoiceFixture"]
        app.launchEnvironment = [:]
        app.launch()
        XCTAssertTrue(app.staticTexts["chat.status"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["voice.fixture.observation"].waitForExistence(timeout: 10))
        observation(contains: "start=0")
    }
    private func draft() -> XCUIElement { chatDraftControl(in: app) }
    private func voice() -> XCUIElement {
        let mic = app.buttons["chat.voice"].firstMatch
        XCTAssertTrue(mic.waitForExistence(timeout: 10) && mic.isHittable)
        return mic
    }
    private func tap(_ identifier: String) {
        let button = app.buttons[identifier].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 10) && button.isHittable, identifier)
        button.tap()
    }
    private func compose(_ text: String) {
        let field = draft()
        XCTAssertTrue(field.waitForExistence(timeout: 10) && field.isHittable)
        field.tap(); field.typeText(text)
        tap("chat.dismissKeyboard")
        waitValue(field, text)
    }
    private func observation(contains text: String) {
        let element = app.staticTexts["voice.fixture.observation"].firstMatch
        let predicate = NSPredicate(format: "label CONTAINS %@", text)
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: 10), .completed)
    }
    private func waitValue(_ element: XCUIElement, _ value: String) {
        let predicate = NSPredicate(format: "value == %@", value)
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: 10), .completed)
    }
}
