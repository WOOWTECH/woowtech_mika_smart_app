import XCTest

/// Actual English screens after a user changes the app language. The system
/// stays zh-Hant and storage is isolated; no model, MCP or notification action
/// is authorized by these cases.
final class AppLanguagePhase2UITests: XCTestCase {
    private let app = XCUIApplication()
    private let namespace = UUID().uuidString
    private let chatDraft = "Tea draft 42"

    override func setUpWithError() throws {
        continueAfterFailure = false
        executionTimeAllowance = 240
    }

    override func tearDownWithError() throws { app.terminate() }

    func testEnglishMCPAndNotificationsKeepUnsentChatDraft() {
        launchAndEnterDraft()
        chooseEnglishInSettings()
        assertEnglishModelNavigation()

        tapRoot("chat")
        XCTAssertTrue(app.navigationBars["woowtech agent"].exists)
        let menu = app.buttons["chat.menu"]
        XCTAssertEqual(menu.label, "Menu")
        XCTAssertEqual(app.buttons["chat.newConversation"].label, "New chat")
        tapChrome(menu)
        XCTAssertEqual(app.buttons["drawer.close"].label, "Close menu")
        XCTAssertEqual(app.buttons["navigation.browser"].label, "Browser")
        XCTAssertEqual(app.buttons["navigation.memory"].label, "Memory and skills")
        XCTAssertEqual(app.buttons["navigation.tools"].label, "MCP servers")
        XCTAssertEqual(app.buttons["navigation.settings"].label, "Settings")
        tapChrome(app.buttons["drawer.close"])

        tapRoot("tools")
        exactVisibleText("tools.status", "MCP servers")
        exactVisibleText("mcp.status", "MCP is not configured")
        exactText("mcp.testIsolation", "Isolated UI test mode: no MCP network requests.")
        exactVisibleText("mcp.endpointStatus", "No endpoint saved.")

        tapRoot("settings")
        tapContent(app.buttons["settings.notifications"])
        XCTAssertTrue(app.navigationBars["Notifications"].waitForExistence(timeout: 10))
        // Play's notification page in English. Storage was reset, so task
        // notifications are off whatever iOS allows.
        let master = app.buttons["notifications.enabled"]
        XCTAssertTrue(master.waitForExistence(timeout: 10))
        revealLearningElement(master, in: app)
        XCTAssertTrue(master.label.hasPrefix("All notifications"), master.label)
        XCTAssertTrue(master.label.contains("woowtech agent can’t send notifications, so you won’t see task results or alerts"),
                      master.label)
        XCTAssertEqual(master.value as? String, "Turn on")
        exactText("notifications.group", "Task notifications")
        for (identifier, title, purpose) in [
            ("notifications.attention", "Needs you", "When you need to take over, approve or answer"),
            ("notifications.result", "Task results", "When a task finishes")
        ] {
            let row = app.buttons[identifier]
            revealLearningElement(row, in: app)
            XCTAssertTrue(row.label.hasPrefix(title) && row.label.contains(purpose), row.label)
            XCTAssertEqual(row.value as? String, "Off")
        }
        exactText("notifications.footer", "On iOS, only you can change whether notifications pop up or make a sound, in Settings. "
                  + "Both kinds of task notifications share the same settings. To turn notifications off, turn off "
                  + "“Allow Notifications” there. Tap either kind above to open woowtech agent’s notification settings. "
                  + "Path: Settings › Notifications › woowtech agent")
        let testNotification = app.buttons["notifications.test"]
        XCTAssertTrue(testNotification.waitForExistence(timeout: 10))
        XCTAssertFalse(testNotification.isEnabled,
                       "Changing language must not enable local notifications.")

        tapChrome(app.navigationBars["Notifications"].buttons.firstMatch)
        tapRoot("chat")
        XCTAssertEqual(chatDraftControl(in: app).value as? String, chatDraft)
    }

    func testEnglishBrowserSearchKeepsUnsentChatDraft() {
        launchAndEnterDraft()
        chooseEnglishInSettings()

        tapRoot("browser")
        let searchSettings = app.buttons["browser.searchEngine.open"]
        tapChrome(searchSettings, timeout: 30) // Isolated WebKit data removal may still be finishing.
        XCTAssertTrue(app.navigationBars["Search engines"].waitForExistence(timeout: 10))
        let google = app.buttons["browser.searchEngine.select.google"]
        revealLearningElement(google, in: app)
        XCTAssertEqual(google.value as? String, "Selected")
        tapContent(app.buttons["browser.searchEngine.select.bing"])
        XCTAssertEqual(app.buttons["browser.searchEngine.select.bing"].value as? String, "Selected")
        let add = app.buttons["browser.searchEngine.add"]
        revealLearningElement(add, in: app)
        XCTAssertEqual(add.label, "Add and use")
        tapChrome(app.buttons["browser.searchEngine.close"])

        let start = app.descendants(matching: .any)["browser.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["browser.start.history.empty"].label, "No browsing history yet")

        tapRoot("chat")
        XCTAssertEqual(chatDraftControl(in: app).value as? String, chatDraft)
    }

    private func launchAndEnterDraft() {
        app.launchArguments = ["-AppleLanguages", "(zh-Hant)", "-AppleLocale", "zh_TW",
                               "-UITestMode", "-UITestNamespace", namespace, "-UITestResetStorage"]
        app.launchEnvironment = [:]
        app.launch()
        let draft = chatDraftControl(in: app)
        XCTAssertTrue(draft.waitForExistence(timeout: 10))
        XCTAssertTrue(draft.isEnabled && draft.isHittable)
        draft.tap()
        prepareLatinKeyboard()
        draft.typeText(chatDraft)
        XCTAssertEqual(draft.value as? String, chatDraft, "The actual unsent input must arrive before switching screens.")
        let done = app.buttons["chat.dismissKeyboard"]
        XCTAssertTrue(done.waitForExistence(timeout: 5) && done.isHittable)
        done.tap()
        let keyboardGone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"),
                                                     object: app.keyboards.firstMatch)
        XCTAssertEqual(XCTWaiter.wait(for: [keyboardGone], timeout: 10), .completed)
    }

    private func chooseEnglishInSettings() {
        tapRoot("settings")
        tapContent(app.buttons["settings.appearance"])
        let english = app.buttons["settings.language.en"]
        tapContent(english)
        XCTAssertTrue(app.navigationBars["Language and appearance"].waitForExistence(timeout: 5))
        XCTAssertTrue(english.isSelected)
        let back = app.navigationBars.buttons.element(boundBy: 0)
        XCTAssertTrue(back.waitForExistence(timeout: 5) && back.isHittable)
        back.tap()
        XCTAssertTrue(app.staticTexts["settings.status"].waitForExistence(timeout: 5))
    }

    private func assertEnglishModelNavigation() {
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        tapContent(app.buttons["settings.modelJump"])
        let detail = app.navigationBars["Model"]
        XCTAssertTrue(detail.waitForExistence(timeout: 5))
        // With no provider yet, the add form is open on Android's first chip.
        XCTAssertTrue(app.secureTextFields["settings.apiKey"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["settings.appearance"].isHittable)
        tapChrome(detail.buttons.firstMatch)
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["settings.modelJump"].isHittable)
        XCTAssertFalse(app.secureTextFields["settings.apiKey"].isHittable)
    }

    private func tapRoot(_ section: String) {
        navigateMikaSection(section, in: app)
    }

    private func tapContent(_ element: XCUIElement, timeout: TimeInterval = 10) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout))
        revealLearningElement(element, in: app)
        let ready = NSPredicate(format: "exists == true AND enabled == true AND hittable == true")
        if !ready.evaluate(with: element) {
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: ready, object: element)],
                                          timeout: timeout), .completed)
        }
        XCTAssertFalse(element.frame.isEmpty)
        element.tap()
    }

    private func tapChrome(_ element: XCUIElement, timeout: TimeInterval = 10) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout))
        let ready = NSPredicate(format: "exists == true AND enabled == true AND hittable == true")
        if !ready.evaluate(with: element) {
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: ready, object: element)],
                                          timeout: timeout), .completed)
        }
        XCTAssertTrue(app.frame.contains(element.frame) && !element.frame.isEmpty)
        element.tap()
    }

    private func exactText(_ identifier: String, _ expected: String) {
        let element = app.staticTexts[identifier]
        revealLearningElement(element, in: app)
        XCTAssertTrue(element.waitForExistence(timeout: 10))
        let exact = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", expected), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [exact], timeout: 5), .completed)
    }

    private func exactVisibleText(_ identifier: String, _ expected: String) {
        let element = app.staticTexts[identifier]
        XCTAssertTrue(element.waitForExistence(timeout: 10))
        XCTAssertTrue(app.frame.contains(element.frame) && element.isHittable)
        let exact = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", expected), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [exact], timeout: 5), .completed)
    }

    private func prepareLatinKeyboard() {
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 5))
        func hasLatinKeys() -> Bool {
            keyboard.keys.matching(NSPredicate(format: "label IN %@", ["q", "Q"])).firstMatch.exists
                && keyboard.keys.matching(NSPredicate(format: "label IN %@", ["a", "A"])).firstMatch.exists
        }
        let introduction = app.buttons["Continue"].firstMatch
        if introduction.exists {
            XCTAssertTrue(app.staticTexts["Speed up your typing by sliding your finger across the letters to compose a word."].firstMatch.exists)
            XCTAssertTrue(introduction.isHittable)
            introduction.tap()
        }
        if hasLatinKeys() { return }
        let globe = app.buttons.matching(NSPredicate(format: "label IN %@", ["Next keyboard", "下一個鍵盤"])).firstMatch
        XCTAssertTrue(globe.waitForExistence(timeout: 5) && globe.isHittable)
        globe.press(forDuration: 1)
        let english = app.descendants(matching: .any).matching(
            NSPredicate(format: "label == %@", "English (US)")).firstMatch
        XCTAssertTrue(english.waitForExistence(timeout: 5) && english.isHittable)
        english.tap()
        if introduction.exists {
            XCTAssertTrue(introduction.isHittable)
            introduction.tap()
        }
        let latin = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in hasLatinKeys() }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [latin], timeout: 10), .completed)
    }
}
