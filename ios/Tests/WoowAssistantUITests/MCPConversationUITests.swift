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

    func testMemorySwitchChangesWhileAnMCPCallIsHeld() {
        // Start a new isolated namespace so no production state or previous
        // fixture run can supply the result. The held fake executor is reached
        // through the real MCP runner.
        app.terminate()
        app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hant)", "-AppleLocale", "zh_TW",
            "-UITestMode", "-UITestNamespace", UUID().uuidString, "-UITestResetStorage",
            "-UITestMCPFixture", "-UITestMCPLeaseHold"]
        app.launchEnvironment = [:]
        app.launch()
        connectFixture()
        // No approval card: the selected tool runs and holds at once.
        send("[fixture:mcp] hello")
        navigateMikaSection("memory", in: app)
        XCTAssertTrue(app.staticTexts["fixture.mcp.lease.holding"].waitForExistence(timeout: 10),
                      "The synthetic executor must enter its held call")
        let release = app.buttons["fixture.mcp.lease.release"]
        revealLearningElement(release, in: app)
        XCTAssertTrue(release.waitForExistence(timeout: 10), "The actual fixture executor must be holding before the switch is touched")
        // Like the Play build, the running MCP call does not lock memory.
        let toggle = app.switches["memory.toggle.useMemory"].firstMatch
        revealLearningElement(toggle, in: app)
        XCTAssertEqual(toggle.value as? String, "1")
        setSwitch(toggle, on: false)
        XCTAssertFalse(app.alerts.firstMatch.exists)
        revealLearningElement(release, in: app)
        release.tap()
        // The turn still finishes after the change.
        navigateMikaSection("chat", in: app)
        let activity = app.staticTexts["chat.mcpActivity"]
        let completed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "已收到 1 次結果"), object: activity)
        XCTAssertEqual(XCTWaiter.wait(for: [completed], timeout: 15), .completed)
        XCTAssertTrue(app.staticTexts["chat.message.1.assistant"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["chat.error"].exists)
        // Reload the real store through a fresh app launch in the same isolated
        // namespace, without resetting it, to prove the change was persisted.
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

    /// Like the Play build, a selected tool runs with no approval card: the
    /// answer arrives with no tap, and the results list shows the call.
    func testSelectedToolRunsWithoutApprovalAndReturnsResult() {
        send("[fixture:mcp] hello")
        assertAnswer("FIXTURE_CALL_1: hello")
        let draft = chatDraftControl(in: app).value as? String ?? ""
        XCTAssertTrue(["", "輸入訊息", "繼續說點什麼…"].contains(draft), "the sent draft is cleared")
        assertAudit(attempts: 1, results: 1)
        app.buttons["chat.mcpResults"].tap()
        let result = app.staticTexts["mcp.result.0"]
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        XCTAssertTrue(result.label.contains("FIXTURE_CALL_1: hello"))
        XCTAssertFalse(app.staticTexts["mcp.result.1"].exists)
    }

    /// Like the Play build, discovered resources are offered without a picker
    /// and read with no approval card.
    func testDiscoveredResourceIsReadWithoutApprovalAndResultIsReviewable() {
        send("[fixture:mcp-resource]")
        assertAnswer("FIXTURE_RESOURCE_OK")
        assertAudit(attempts: 1, results: 1)
        app.buttons["chat.mcpResults"].tap()
        XCTAssertTrue(app.staticTexts["mcp.result.0"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["mcp.result.0"].label.contains("FIXTURE_RESOURCE_OK"))
    }

    /// The tool selection is the limit: a tool that is not selected never runs.
    func testUnselectedToolNeverRunsAndTheTurnIsNotDone() {
        navigateMikaSection("tools", in: app)
        let enabled = app.switches["mcp.enable.fixture_echo"]
        revealLearningElement(enabled, in: app)
        setSwitch(enabled, on: false)
        navigateMikaSection("chat", in: app)
        // The offered resource keeps MCP on for this chat; the model still asks for fixture_echo.
        XCTAssertEqual(app.switches["chat.useMCP"].value as? String, "1")
        let prompt = "[fixture:mcp] hello"
        send(prompt)
        // Like the Play build the turn stays as 沒有完成 with its reason.
        let failed = app.descendants(matching: .any)["chat.message.1.assistant"]
        XCTAssertTrue(failed.waitForExistence(timeout: 10))
        XCTAssertTrue(failed.label.hasPrefix("沒有完成"), failed.label)
        XCTAssertFalse(app.staticTexts["chat.error"].exists)
        XCTAssertNotEqual(chatDraftControl(in: app).value as? String, prompt)
        XCTAssertFalse(app.buttons["chat.mcpResults"].exists)
        navigateMikaSection("tools", in: app)
        revealLearningElement(enabled, in: app)
        setSwitch(enabled, on: true)
        navigateMikaSection("chat", in: app)
        send(prompt)
        // Same actor connection: count 1 proves the unselected call never ran.
        assertAnswer("FIXTURE_CALL_1: hello", index: 3)
    }

    /// Leaving the app stops a tool call that is still running (held by the
    /// fixture) and disconnects MCP; like the Play build the turn stays as 已停止。
    func testBackgroundStopsRunningToolAndDisconnects() {
        app.terminate()
        app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hant)", "-AppleLocale", "zh_TW",
            "-UITestMode", "-UITestNamespace", UUID().uuidString, "-UITestResetStorage",
            "-UITestMCPFixture", "-UITestMCPLeaseHold"]
        app.launchEnvironment = [:]
        app.launch()
        connectFixture()
        let prompt = "[fixture:mcp] hello"
        send(prompt)
        let dispatched = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "MCP 嘗試呼叫 1 次"),
                                                   object: app.staticTexts["chat.mcpActivity"])
        XCTAssertEqual(XCTWaiter.wait(for: [dispatched], timeout: 10), .completed, "The call must be running with no approval card")
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.buttons["chat.send"].waitForExistence(timeout: 10))
        let stopped = app.descendants(matching: .any)["chat.message.1.assistant"]
        XCTAssertTrue(stopped.waitForExistence(timeout: 10))
        XCTAssertEqual(stopped.label, "已停止。")
        XCTAssertNotEqual(chatDraftControl(in: app).value as? String, prompt)
        // Nothing can be sent until MCP is connected again; the draft stays.
        send(prompt)
        XCTAssertTrue(app.staticTexts["chat.error"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["chat.error"].label.contains("連線"))
        XCTAssertEqual(chatDraftControl(in: app).value as? String, prompt)
        navigateMikaSection("tools", in: app)
        waitForStatus("已中斷本機連線")
    }

    /// Like the Play build a tool error leaves the turn as 沒有完成 with its reason.
    func testToolErrorShowsNotDoneAndActualErrorResult() {
        send("[fixture:mcp-error]")
        let failed = app.descendants(matching: .any)["chat.message.1.assistant"]
        XCTAssertTrue(failed.waitForExistence(timeout: 10))
        XCTAssertTrue(failed.label.hasPrefix("沒有完成") && failed.label.contains("工具回報錯誤"), failed.label)
        XCTAssertFalse(app.staticTexts["chat.error"].exists)
        XCTAssertNotEqual(chatDraftControl(in: app).value as? String, "[fixture:mcp-error]")
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
    /// The fixed run counters behind the activity line: one call, one result.
    private func assertAudit(attempts: Int, results: Int) {
        let fields = (app.staticTexts["chat.mcpActivity"].value as? String ?? "").components(separatedBy: ";")
        XCTAssertTrue(fields.contains("attempts=\(attempts)"))
        XCTAssertTrue(fields.contains("results=\(results)"))
        XCTAssertTrue(fields.contains("failure=none"))
    }
    private func assertAnswer(_ text: String, index: Int = 1) {
        let answer = app.staticTexts["chat.message.\(index).assistant"]
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
