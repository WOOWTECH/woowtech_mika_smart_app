import XCTest

final class MCPConversationUITests: XCTestCase {
    private var app = XCUIApplication()
    private let namespace = UUID().uuidString

    override func setUpWithError() throws {
        continueAfterFailure = false
        executionTimeAllowance = 180
        app.launchArguments = ["-AppleLanguages", "(zh-Hant)", "-AppleLocale", "zh_TW",
            "-UITestMode", "-UITestNamespace", namespace, "-UITestResetStorage", "-UITestMCPFixture"]
        app.launchEnvironment = [:]
        app.launch()
        connectFixture()
    }

    private func connectFixture() {
        navigateMikaSection("tools", in: app)
        tap("mcp.connect")
        waitForStatus("已連線，目錄擷取完成")
        let enabled = app.switches["mcp.enable.fixture_echo"]
        revealLearningElement(enabled, in: app)
        setSwitch(enabled, on: true)
        navigateMikaSection("chat", in: app)
        let chatEnabled = app.switches["chat.useMCP"]
        XCTAssertTrue(chatEnabled.waitForExistence(timeout: 5))
        setSwitch(chatEnabled, on: true)
    }

    func testMemorySwitchReportsBusyAndRetriesAfterActualMCPLease() {
        // Start a new isolated namespace so no production state or previous
        // fixture run can supply the result. The held fake executor is reached
        // through the real MCP runner and context-fenced executor.
        app.terminate()
        app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hant)", "-AppleLocale", "zh_TW",
            "-UITestMode", "-UITestNamespace", UUID().uuidString, "-UITestResetStorage",
            "-UITestMCPFixture", "-UITestMCPLeaseHold"]
        app.launchEnvironment = [:]
        app.launch()
        connectFixture()
        send("[fixture:mcp] hello")
        assertApproval()
        app.buttons["mcp.approval.approve"].tap()
        navigateMikaSection("memory", in: app)
        XCTAssertTrue(app.staticTexts["fixture.mcp.lease.holding"].waitForExistence(timeout: 10),
                      "The synthetic executor must enter its held call")
        let release = app.buttons["fixture.mcp.lease.release"]
        revealLearningElement(release, in: app)
        XCTAssertTrue(release.waitForExistence(timeout: 10), "The actual fixture executor must be holding before the switch is touched")
        let toggle = app.switches["memory.toggle.useMemory"].firstMatch
        revealLearningElement(toggle, in: app)
        XCTAssertEqual(toggle.value as? String, "1")
        let target = toggle.switches.firstMatch.exists ? toggle.switches.firstMatch : toggle
        XCTAssertTrue(target.isHittable)
        target.tap()
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 10))
        XCTAssertTrue(alert.staticTexts["設定未儲存"].exists)
        let message = alert.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "仍顯示開啟")).firstMatch
        XCTAssertTrue(message.exists)
        XCTAssertTrue(message.label.contains("請稍後重試"))
        alert.buttons["完成"].tap()
        let current = app.switches["memory.toggle.useMemory"].firstMatch
        revealLearningElement(current, in: app)
        XCTAssertEqual(current.value as? String, "1", "A failed write must never appear switched off")
        revealLearningElement(release, in: app)
        release.tap()
        // The completed event is published only after the real executor and
        // its lease return. Do not treat gate release as lock release.
        navigateMikaSection("chat", in: app)
        let activity = app.staticTexts["chat.mcpActivity"]
        let completed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "已收到 1 次結果"), object: activity)
        XCTAssertEqual(XCTWaiter.wait(for: [completed], timeout: 15), .completed)
        navigateMikaSection("memory", in: app)
        let retry = app.switches["memory.toggle.useMemory"].firstMatch
        revealLearningElement(retry, in: app)
        XCTAssertEqual(retry.value as? String, "1")
        setSwitch(retry, on: false)
        XCTAssertFalse(app.alerts.firstMatch.exists)
        // Reload the real store through a fresh app launch in the same isolated
        // namespace, without resetting it, to prove the retry was persisted.
        let args = app.launchArguments.filter { $0 != "-UITestResetStorage" && $0 != "-UITestMCPLeaseHold" }
        app.terminate()
        app = XCUIApplication(); app.launchArguments = args; app.launchEnvironment = [:]; app.launch()
        navigateMikaSection("memory", in: app)
        let restored = app.switches["memory.toggle.useMemory"].firstMatch
        revealLearningElement(restored, in: app)
        XCTAssertEqual(restored.value as? String, "0")
    }

    override func tearDownWithError() throws {
        if let testRun, testRun.failureCount > 0 {
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = "mcp-conversation-fixture-failure"
            attachment.lifetime = .keepAlways
            add(attachment)
            let tree = XCTAttachment(string: app.debugDescription)
            tree.name = "mcp-conversation-fixture-tree"
            tree.lifetime = .keepAlways
            add(tree)
        }
        app.terminate()
    }

    func testModelSelectedToolRequiresExactApprovalAndReturnsResult() {
        send("[fixture:mcp] hello")
        assertApproval()
        XCTAssertFalse(app.staticTexts["chat.message.1.assistant"].exists)
        app.buttons["mcp.approval.approve"].tap()
        assertAnswer("FIXTURE_CALL_1: hello")
        let draft = chatDraftControl(in: app).value as? String ?? ""
        XCTAssertTrue(draft.isEmpty || draft == "輸入訊息")
        XCTAssertTrue(app.staticTexts["chat.mcpActivity"].label.contains("1"))
    }

    func testSelectedResourceRequiresApprovalAndResultIsReviewable() {
        navigateMikaSection("tools", in: app)
        let resource = app.switches["mcp.resource.0"]
        revealLearningElement(resource, in: app)
        setSwitch(resource, on: true)
        navigateMikaSection("chat", in: app)
        send("[fixture:mcp-resource]")
        XCTAssertTrue(app.staticTexts["mcp.approval.name"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["mcp.approval.name"].label, "讀取 MCP 資源")
        XCTAssertTrue(app.staticTexts["mcp.approval.arguments"].label.contains("fixture://guide"))
        app.buttons["mcp.approval.approve"].tap()
        assertAnswer("FIXTURE_RESOURCE_OK")
        app.buttons["chat.mcpResults"].tap()
        XCTAssertTrue(app.staticTexts["mcp.result.0"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["mcp.result.0"].label.contains("FIXTURE_RESOURCE_OK"))
    }

    func testRefusalPreservesDraftAndMakesNoServerCall() {
        let prompt = "[fixture:mcp] hello"
        send(prompt)
        assertApproval()
        app.buttons["mcp.approval.decline"].tap()
        XCTAssertTrue(app.staticTexts["chat.error"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["chat.error"].label.contains("拒絕"))
        XCTAssertEqual(chatDraftControl(in: app).value as? String, prompt)
        XCTAssertFalse(app.staticTexts["chat.message.1.assistant"].exists)
        app.buttons["chat.send"].tap()
        assertApproval()
        app.buttons["mcp.approval.approve"].tap()
        // Same actor connection: count 1 proves the denied call never executed.
        assertAnswer("FIXTURE_CALL_1: hello")
    }

    func testBackgroundRevokesPendingApprovalAndRetainsDraft() {
        let prompt = "[fixture:mcp] hello"
        send(prompt)
        assertApproval()
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.buttons["chat.send"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["mcp.approval.approve"].exists)
        XCTAssertFalse(app.staticTexts["chat.message.1.assistant"].exists)
        XCTAssertEqual(chatDraftControl(in: app).value as? String, prompt)
        app.buttons["chat.send"].tap()
        XCTAssertTrue(app.staticTexts["chat.error"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["chat.error"].label.contains("連線"))
        navigateMikaSection("tools", in: app)
        waitForStatus("已中斷本機連線")
    }

    func testToolErrorPreservesDraftAndActualErrorResult() {
        send("[fixture:mcp-error]")
        XCTAssertTrue(app.staticTexts["mcp.approval.name"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["mcp.approval.name"].label, "fixture_echo")
        XCTAssertTrue(app.staticTexts["mcp.approval.arguments"].label.contains("error"))
        app.buttons["mcp.approval.approve"].tap()
        XCTAssertTrue(app.staticTexts["chat.error"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["chat.error"].label.contains("工具回報錯誤"))
        XCTAssertEqual(chatDraftControl(in: app).value as? String, "[fixture:mcp-error]")
        XCTAssertFalse(app.staticTexts["chat.message.1.assistant"].exists)
        app.buttons["chat.mcpResults"].tap()
        let result = app.staticTexts["mcp.result.0"]
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        XCTAssertTrue(result.label.contains("FIXTURE_CALL_1: error"))
        XCTAssertTrue(result.label.contains("\"isError\" : true"))
    }

    private func send(_ text: String) {
        let draft = chatDraftControl(in: app)
        XCTAssertTrue(draft.isHittable)
        draft.tap(); draft.typeText(text)
        XCTAssertEqual(draft.value as? String, text)
        app.buttons["chat.dismissKeyboard"].tap()
        app.buttons["chat.send"].tap()
    }
    private func assertApproval() {
        let name = app.staticTexts["mcp.approval.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 10))
        XCTAssertEqual(name.label, "fixture_echo")
        let text = app.staticTexts["mcp.approval.arguments"].label
        let object = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: String]
        XCTAssertEqual(object, ["text": "hello"])
        XCTAssertTrue(app.buttons["mcp.approval.approve"].isHittable)
        XCTAssertTrue(app.buttons["mcp.approval.decline"].isHittable)
    }
    private func assertAnswer(_ text: String) {
        let answer = app.staticTexts["chat.message.1.assistant"]
        XCTAssertTrue(answer.waitForExistence(timeout: 15))
        XCTAssertEqual(answer.label, text)
        XCTAssertFalse(app.staticTexts["chat.error"].exists)
    }
    private func tap(_ id: String) {
        let button = app.buttons[id]
        revealLearningElement(button, in: app)
        button.tap()
    }
    private func waitForStatus(_ text: String) {
        let expected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", text),
                                               object: app.staticTexts["mcp.status"])
        XCTAssertEqual(XCTWaiter.wait(for: [expected], timeout: 10), .completed)
    }
    private func setSwitch(_ toggle: XCUIElement, on: Bool) {
        let target = toggle.switches.firstMatch.exists ? toggle.switches.firstMatch : toggle
        XCTAssertTrue(target.isHittable)
        target.tap()
        let expected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", on ? "1" : "0"), object: toggle)
        XCTAssertEqual(XCTWaiter.wait(for: [expected], timeout: 5), .completed)
    }
}
