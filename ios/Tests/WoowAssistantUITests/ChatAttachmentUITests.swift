import XCTest

/// The Android-aligned attach panel, tray and send path with the real ChatSession.
/// `-UITestAttachments` shows a test-only button that adds one generated photo and
/// one short note; the system pickers and the user's own photos are never involved.
final class ChatAttachmentUITests: XCTestCase {
    private let app = XCUIApplication()
    private let namespace = UUID().uuidString
    override func setUpWithError() throws { continueAfterFailure = false; executionTimeAllowance = 300 }
    override func tearDownWithError() throws { app.terminate() }

    func testPlusOpensAttachPanelWithAndroidTilesAndClosesBackToKeyboard() {
        launch()
        let toggle = app.buttons["chat.attach.toggle"].firstMatch
        ready(toggle)
        XCTAssertEqual(toggle.label, "新增附件")
        toggle.tap()
        XCTAssertTrue(app.otherElements["chat.attach.panel"].firstMatch.waitForExistence(timeout: 10))
        for (id, label) in [("chat.attach.camera", "相機"), ("chat.attach.album", "相簿"), ("chat.attach.files", "檔案")] {
            let tile = app.buttons[id].firstMatch
            XCTAssertTrue(tile.exists && tile.isHittable, id)
            XCTAssertEqual(tile.label, label)
        }
        XCTAssertEqual(toggle.label, "收起附件面板")
        ready(toggle); toggle.tap()
        // The keyboard comes back first, then the panel leaves; slow simulators need the room.
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 15), "× brings the keyboard back, as on Android")
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"),
                                             object: app.otherElements["chat.attach.panel"])
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 15), .completed)
    }

    func testTrayShowsPhotoAndFileRemovesOneAndSendsAttachmentAlone() {
        launch(attachments: true); configure()
        addFixtureAttachments()
        let tray = app.descendants(matching: .any)["chat.attach.tray"].firstMatch
        XCTAssertTrue(tray.waitForExistence(timeout: 15))
        XCTAssertTrue(app.descendants(matching: .any)["chat.attach.item.1"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["chat.attach.remove.0"].firstMatch.label, "去掉fixture-photo.png")
        tap("chat.attach.remove.0")
        let second = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"),
                                               object: app.descendants(matching: .any)["chat.attach.item.1"].firstMatch)
        XCTAssertEqual(XCTWaiter.wait(for: [second], timeout: 10), .completed)
        XCTAssertEqual(app.buttons["chat.attach.remove.0"].firstMatch.label, "去掉fixture-notes.txt")

        // No words: on Android an attachment alone can start a task.
        XCTAssertTrue(app.buttons["chat.send"].firstMatch.isEnabled)
        tap("chat.send")
        assertContains(identifiedText("chat.message.1.assistant"), "收到附件 1 個（圖片 0）")
        XCTAssertTrue(app.descendants(matching: .any)["chat.message.0.attachments"].firstMatch.exists)
        XCTAssertFalse(app.descendants(matching: .any)["chat.message.0.user"].firstMatch.exists,
                       "Attachments alone get no empty bubble; the 附件 lines are not shown")
        let trayGone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: tray)
        XCTAssertEqual(XCTWaiter.wait(for: [trayGone], timeout: 10), .completed)
        XCTAssertFalse(app.staticTexts["chat.error"].firstMatch.exists)
        assertRecentTitle("fixture-notes.txt")
    }

    func testPhotoReachesModelOnlyAfterSeesImagesIsOn() {
        launch(attachments: true); configure()
        addFixtureAttachments()
        tap("chat.send")
        assertContains(identifiedText("chat.message.1.assistant"), "收到附件 1 個（圖片 0）")
        let notice = app.descendants(matching: .any)["chat.attach.notice"].firstMatch
        XCTAssertTrue(notice.waitForExistence(timeout: 10), "An unseen photo is explained, never dropped silently")
        tap("chat.attach.notice.dismiss")

        navigate("settings")
        openModelSettings(in: app)
        // As on Android, 能看圖 belongs to each model: its provider's page › 用作.
        openModelUseAs(provider: "model.invalid", model: "fixture", in: app)
        let sees = app.switches["useAs.seesImages"].firstMatch
        ready(sees)
        XCTAssertEqual(sees.value as? String, "0")
        turnOn(sees)
        closeModelUseAs(provider: "model.invalid", in: app)
        returnFromModelSettings(in: app)
        navigate("chat")

        addFixtureAttachments()
        tap("chat.send")
        // The second turn of the same conversation.
        assertContains(identifiedText("chat.message.3.assistant"), "收到附件 2 個（圖片 1）")
        assertRecentTitle("照片和檔案")
    }

    // MARK: - Helpers (same native paths as ChatStreamingUITests)

    private func launch(reset: Bool = true, attachments: Bool = false) {
        app.terminate()
        app.launchArguments = ["-AppleLanguages", "(zh-Hant)", "-AppleLocale", "zh_TW",
                               "-UITestMode", "-UITestNamespace", namespace, "-WoowSkipOnboarding"]
        if reset { app.launchArguments.append("-UITestResetStorage") }
        if attachments { app.launchArguments.append("-UITestAttachments") }
        app.launchEnvironment = [:]; app.launch()
        XCTAssertTrue(app.staticTexts["chat.status"].firstMatch.waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["uitest.banner"].firstMatch.exists)
    }
    /// The sidebar titles an attachment-only first message like Android, never by its 附件 lines.
    private func assertRecentTitle(_ title: String) {
        tap("chat.menu")
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label == %@",
                                                   "drawer.recent.row.", title)).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), title)
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label BEGINSWITH %@",
                                                        "drawer.recent.row.", "附件:")).firstMatch.exists)
    }
    /// Taps the switch itself, as the other settings tests do; the row's middle is its label.
    /// A tap that lands while the reveal scroll settles can be lost, so a switch still off gets one more.
    private func turnOn(_ toggle: XCUIElement) {
        let on = NSPredicate(format: "value == %@", "1")
        for _ in 0..<2 where !on.evaluate(with: toggle) {
            let native = toggle.switches.firstMatch
            let target = native.waitForExistence(timeout: 2) ? native : toggle
            ready(target); target.tap()
            _ = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: on, object: toggle)], timeout: 4)
        }
        XCTAssertEqual(toggle.value as? String, "1")
        XCTAssertFalse(app.staticTexts["settings.error"].firstMatch.exists)
    }
    private func addFixtureAttachments() {
        tap("uitest.attach.fixture")
        XCTAssertTrue(app.descendants(matching: .any)["chat.attach.item.1"].firstMatch.waitForExistence(timeout: 15))
    }
    private func configure() {
        navigate("settings")
        openModelSettings(in: app)
        write("https://model.invalid/v1", field: app.textFields["settings.baseURL"].firstMatch, scroll: true)
        dismissSettingsKeyboard()
        write("fixture", field: app.textFields["settings.model"].firstMatch, scroll: true, verifyEachCharacter: true)
        dismissSettingsKeyboard()
        let key = app.secureTextFields["settings.apiKey"].firstMatch
        revealLearningElement(key, in: app); ready(key); key.tap(); prepareKeyboard(); key.typeText("fixture-key")
        tap("settings.dismissKeyboard"); tap("setup.test", scroll: true)
        agreeToModelConsent(in: app)
        XCTAssertTrue(app.staticTexts["settings.notice"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["settings.error"].firstMatch.exists)
        returnFromModelSettings(in: app)
        navigate("chat"); assertLabel(app.staticTexts["chat.status"].firstMatch, "模型已設定")
    }
    private func dismissSettingsKeyboard() {
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        tap("settings.dismissKeyboard")
        let keyboardAbsent = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"), object: app.keyboards.firstMatch)
        XCTAssertEqual(XCTWaiter.wait(for: [keyboardAbsent], timeout: 15), .completed)
    }
    private func identifiedText(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }
    private func navigate(_ section: String) {
        navigateMikaSection(section, in: app)
        XCTAssertTrue(app.staticTexts[section + ".status"].firstMatch.waitForExistence(timeout: 5))
    }
    private func write(_ text: String, field: XCUIElement, scroll: Bool, verifyEachCharacter: Bool = false) {
        if scroll { revealLearningElement(field, in: app) }
        ready(field)
        field.tap(); prepareKeyboard()
        var entered = "", remaining = text[...]
        while !remaining.isEmpty {
            let chunk = String(remaining.prefix(verifyEachCharacter ? 1 : (entered.isEmpty ? 1 : 16)))
            field.typeText(chunk); entered += chunk; remaining = remaining.dropFirst(chunk.count)
            if verifyEachCharacter {
                let prefix = NSPredicate(format: "value == %@", entered)
                if !prefix.evaluate(with: field) {
                    XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: prefix, object: field)],
                                                 timeout: 3), .completed)
                }
            }
            XCTAssertEqual(field.value as? String, entered)
            guard field.value as? String == entered else { return }
        }
    }
    private func prepareKeyboard() {
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5)); dismissIntroduction()
        let keyboard = app.keyboards.firstMatch
        func latin() -> Bool {
            keyboard.keys.matching(NSPredicate(format: "label IN %@", ["q", "Q"])).firstMatch.exists
                && keyboard.keys.matching(NSPredicate(format: "label IN %@", ["a", "A"])).firstMatch.exists
        }
        if latin() { return }
        let globe = app.buttons.matching(NSPredicate(format: "label IN %@", ["Next keyboard", "下一個鍵盤"])).firstMatch
        ready(globe); globe.press(forDuration: 1)
        let english = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "English (US)")).firstMatch
        ready(english); english.tap(); dismissIntroduction()
        if !latin() {
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in latin() }, object: nil)],
                                          timeout: 10), .completed)
        }
    }
    private func dismissIntroduction() {
        let button = app.buttons["Continue"].firstMatch
        guard button.waitForExistence(timeout: 3) else { return }
        ready(button); button.tap()
    }
    private func tap(_ id: String, scroll: Bool = false) {
        let button = app.buttons[id].firstMatch
        if scroll { revealLearningElement(button, in: app) }
        ready(button); XCTAssertTrue(app.frame.contains(button.frame)); button.tap()
    }
    private func ready(_ element: XCUIElement) {
        let hittable = NSPredicate(format: "hittable == true")
        if !hittable.evaluate(with: element) {
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: hittable, object: element)], timeout: 10), .completed)
        }
        XCTAssertTrue(element.exists); XCTAssertTrue(element.isEnabled)
    }
    private func assertLabel(_ element: XCUIElement, _ value: String) {
        let predicate = NSPredicate(format: "exists == true AND label == %@", value)
        if !predicate.evaluate(with: element) {
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: 15), .completed)
        }
        XCTAssertEqual(element.label, value)
    }
    private func assertContains(_ element: XCUIElement, _ value: String) {
        let predicate = NSPredicate(format: "exists == true AND label CONTAINS %@", value)
        if !predicate.evaluate(with: element) {
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: 15), .completed)
        }
        XCTAssertTrue(element.label.contains(value), element.label)
    }
}
