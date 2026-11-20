import XCTest

/// 用帳號登入 · 不用填 Key with the DEBUG sign-in fixture (-UITestAccountSignIn): the
/// sign-ins open no page and reach no server, and their sessions hold dummy strings in this
/// test's own Keychain service. The fixture buttons stand in for the person approving on
/// OpenAI's or xAI's page. Real accounts are tested by a person on a device.
final class ModelAccountSignInUITests: XCTestCase {
    private let namespace = UUID().uuidString

    override func setUpWithError() throws {
        continueAfterFailure = false
        executionTimeAllowance = 300
    }

    func testChatGPTExplainsFirstThenSignsInAndSignsOutOnThisDeviceOnly() {
        let app = launch()
        openSettings(in: app)
        openModelSettings(in: app)
        XCTAssertTrue(app.staticTexts["signin.group"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["signin.group"].label, "用帳號登入 · 不用填 Key")
        let row = app.buttons["signin.chatGPT"]
        revealLearningElement(row, in: app)
        XCTAssertTrue(tapExpecting(row, app.buttons["signin.start"]))
        // The explanation comes first: nothing starts before 使用 ChatGPT 繼續.
        XCTAssertEqual(app.staticTexts["signin.title"].label, "用你的 ChatGPT 方案")
        waitLabel(app.staticTexts["signin.fixture"], "Fixture: 0,0")
        attach("chatgpt-explanation", app)
        app.buttons["signin.start"].tap()
        waitLabel(app.staticTexts["signin.fixture"], "Fixture: 1,0")
        XCTAssertTrue(app.staticTexts["signin.waiting"].exists)
        XCTAssertTrue(app.buttons["signin.cancel"].exists)
        attach("chatgpt-waiting", app)
        app.buttons["signin.fixture.approve"].tap()
        // No main model yet: its first model becomes the main one after the consent.
        agreeToModelConsent(in: app)
        XCTAssertTrue(app.navigationBars["ChatGPT"].waitForExistence(timeout: 15))
        waitLabel(app.staticTexts["provider.account.status"], "已登入")
        XCTAssertEqual(app.staticTexts["provider.account.label"].label, "fixture@example.invalid")
        XCTAssertTrue(app.buttons["provider.model.gpt-fixture"].exists)
        XCTAssertTrue(app.buttons["provider.model.gpt-fixture-mini"].exists)
        XCTAssertTrue(app.buttons["provider.delete"].exists)
        attach("chatgpt-provider", app)
        let signOut = app.buttons["provider.account.signOut"]
        revealLearningElement(signOut, in: app)
        signOut.tap()
        waitLabel(app.staticTexts["provider.account.status"], "已退出登入")
        // Only this device's sign-in is cleared: the provider and its models stay.
        XCTAssertTrue(app.buttons["provider.account.signIn"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["provider.model.gpt-fixture"].exists)
        attach("chatgpt-signed-out", app)
        returnFromModelProvider("ChatGPT", in: app)
        let main = app.buttons["models.role.main"]
        revealLearningElement(main, in: app)
        XCTAssertTrue(main.label.contains("gpt-fixture"), main.label)
        XCTAssertTrue(app.buttons["models.provider.ChatGPT"].exists)
    }

    func testXAIShowsItsRiskBeforeSigningInThenTheCodeWithCopyReopenCancelAndRefusal() {
        let app = launch()
        openSettings(in: app)
        openModelSettings(in: app)
        let row = app.buttons["signin.xai"]
        revealLearningElement(row, in: app)
        XCTAssertTrue(tapExpecting(row, app.buttons["signin.start"]))
        XCTAssertEqual(app.staticTexts["signin.title"].label, "用 xAI 帳號登入")
        XCTAssertTrue(app.staticTexts["signin.risk"].label.contains("xAI 官方命令列工具的公開登入入口"))
        XCTAssertTrue(app.buttons["signin.useKey"].exists)
        waitLabel(app.staticTexts["signin.fixture"], "Fixture: 0,0")
        attach("xai-explanation", app)
        app.buttons["signin.start"].tap()
        let code = app.staticTexts["signin.code"]
        XCTAssertTrue(code.waitForExistence(timeout: 10))
        XCTAssertEqual(code.label, "WOOW-FIX1")
        attach("xai-code", app)
        app.buttons["signin.copyReopen"].tap()
        waitLabel(app.staticTexts["signin.fixture"], "Fixture: 1,1")
        XCTAssertTrue(app.staticTexts["signin.copied"].exists)
        app.buttons["signin.cancel"].tap()
        XCTAssertTrue(app.buttons["signin.start"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["signin.code"].exists, "cancelling drops the code")
        // A refusal on xAI's page says why, and another try can start.
        app.buttons["signin.start"].tap()
        XCTAssertTrue(code.waitForExistence(timeout: 10))
        app.buttons["signin.fixture.refuse"].tap()
        let failed = app.staticTexts["signin.failed"]
        XCTAssertTrue(failed.waitForExistence(timeout: 10))
        XCTAssertEqual(failed.label, "已取消登入。")
        app.buttons["signin.start"].tap()
        XCTAssertTrue(code.waitForExistence(timeout: 10))
        app.buttons["signin.fixture.approve"].tap()
        agreeToModelConsent(in: app)
        XCTAssertTrue(app.navigationBars["xAI / Grok"].waitForExistence(timeout: 15))
        waitLabel(app.staticTexts["provider.account.status"], "已登入")
        let note = app.staticTexts["provider.account.note403"]
        revealLearningElement(note, in: app, visibility: .readableText)
        XCTAssertTrue(note.label.contains("403"))
        XCTAssertTrue(app.buttons["provider.model.grok-fixture"].exists)
        attach("xai-provider", app)
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hant)", "-AppleLocale", "zh_TW", "-UITestMode", "-UITestNamespace", namespace,
                               "-WoowSkipOnboarding", "-UITestResetStorage", "-UITestAccountSignIn"]
        app.launch()
        XCTAssertTrue(app.staticTexts["chat.status"].waitForExistence(timeout: 30))
        return app
    }

    private func openSettings(in app: XCUIApplication) {
        navigateMikaSection("settings", in: app)
        XCTAssertTrue(app.staticTexts["settings.status"].waitForExistence(timeout: 10))
    }

    private func waitLabel(_ element: XCUIElement, _ label: String, file: StaticString = #filePath, line: UInt = #line) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", label), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 15), .completed,
                       "\(element.identifier) should read \(label); it reads \(element.exists ? element.label : "nothing")",
                       file: file, line: line)
    }

    private func attach(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
