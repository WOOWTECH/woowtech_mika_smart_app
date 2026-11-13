import XCTest

/// Synthetic in-process MCP/model fixtures through the encrypted learning
/// store. Like the Play build, neither the remote MCP call nor the local
/// memory/profile write shows an approval card, and the reply continues after
/// the model's own write. Neither fixture can persist a local proposal itself.
final class MCPLearningUITests: XCTestCase {
    private let app = XCUIApplication()
    private let namespace = UUID().uuidString
    private let memoryReceipt = "本次對話曾儲存記憶修改；可在資料頁查看目前內容。"
    private let profileReceipt = "本次對話曾儲存個人檔案；可在資料頁用「全部清除」刪除。"

    override func setUpWithError() throws {
        continueAfterFailure = false
        executionTimeAllowance = 240
    }

    override func tearDownWithError() throws {
        if let testRun, testRun.failureCount > 0 {
            // Only isolated synthetic fixtures; never use these attachments for
            // live MCP/model credentials or a personal learning store.
            let tree = XCTAttachment(string: app.debugDescription)
            tree.name = "mcp-learning-fixture-failure-AX"
            tree.lifetime = .keepAlways; add(tree)
            let screen = XCTAttachment(screenshot: app.screenshot())
            screen.name = "mcp-learning-fixture-failure-screen"
            screen.lifetime = .keepAlways; add(screen)
        }
        app.terminate()
    }

    func testRemoteCallThenMemorySaveFinishesAndUndoRemainsAbsentAfterRelaunch() {
        launch(); connectFixture()
        let prompt = "[fixture:mcp-memory] Remember preference Prefer jasmine tea"
        send(prompt)
        // Neither the remote call nor the local memory_save needs a tap.
        assertLabel(app.staticTexts["chat.message.1.assistant"].firstMatch, "MCP 記憶流程已完成。")
        assertLabel(app.staticTexts["chat.status"].firstMatch, "模型已設定")
        XCTAssertFalse(app.staticTexts["chat.error"].firstMatch.exists)
        assertLabel(app.staticTexts["chat.memoryReceipt"].firstMatch, memoryReceipt)
        assertLabel(app.staticTexts["chat.memoryNote.0"].firstMatch, "記住了：Prefer jasmine tea")
        XCTAssertFalse(app.staticTexts["chat.memoryNote.1"].firstMatch.exists)
        XCTAssertFalse(app.staticTexts["chat.profileReceipt"].firstMatch.exists)
        assertActivity(attempts: 1, results: 1, modelCalls: 3, failure: "none")
        let draft = chatDraftControl(in: app).value as? String ?? ""
        XCTAssertTrue(draft.isEmpty || draft == "輸入訊息")
        tap("chat.mcpResults")
        let result = app.staticTexts["mcp.result.0"].firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        revealLearningElement(result, in: app, visibility: .readableText)
        let object = try? JSONSerialization.jsonObject(with: Data(result.label.utf8)) as? [String: Any]
        XCTAssertEqual(object?["isError"] as? Bool, false)
        let content = object?["content"] as? [[String: String]]
        XCTAssertEqual(content, [["type": "text", "text": "FIXTURE_CALL_1: hello"]])
        XCTAssertFalse(app.staticTexts["mcp.result.1"].firstMatch.exists)
        let close = app.buttons["mcp.results.close"].firstMatch
        ready(close); XCTAssertEqual(close.label, "關閉")
        close.tap(); absent(result)

        openMemory(); assertSingleMemory("Prefer jasmine tea")
        navigate("chat")
        tap("chat.undoMemory.0")
        absent(app.staticTexts["chat.memoryNote.0"].firstMatch)
        XCTAssertFalse(app.buttons["chat.undoMemory.0"].firstMatch.exists)
        XCTAssertFalse(app.staticTexts["chat.learningError"].firstMatch.exists)
        assertLabel(app.staticTexts["chat.memoryReceipt"].firstMatch, memoryReceipt)
        openMemory(); assertEmptyMemories()
        launch(reset: false); openMemory(); assertEmptyMemories()
        selectSegment("pending"); assertEmptyPending()
    }

    func testProfileEditThenRemoteCallFinishes() {
        launch(); connectFixture()
        let prompt = "[fixture:mcp-profile] Please remember Prefer jasmine tea"
        send(prompt)
        // The profile_edit applies with no card; the remote call then runs.
        assertLabel(app.staticTexts["chat.message.1.assistant"].firstMatch, "MCP 個人檔案流程已完成。")
        XCTAssertFalse(app.staticTexts["chat.error"].firstMatch.exists)
        assertLabel(app.staticTexts["chat.profileReceipt"].firstMatch, profileReceipt)
        XCTAssertFalse(app.staticTexts["chat.memoryReceipt"].firstMatch.exists)
        XCTAssertFalse(app.staticTexts["chat.memoryNote.0"].firstMatch.exists)
        assertActivity(attempts: 1, results: 1, modelCalls: 3, failure: "none")
        let draft = chatDraftControl(in: app).value as? String ?? ""
        XCTAssertTrue(["", "輸入訊息", "繼續說點什麼…"].contains(draft), "the sent draft is cleared")
        tap("chat.mcpResults")
        let result = app.staticTexts["mcp.result.0"].firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        revealLearningElement(result, in: app, visibility: .readableText)
        XCTAssertTrue(result.label.contains("FIXTURE_CALL_1: hello"))
        let close = app.buttons["mcp.results.close"].firstMatch
        ready(close); close.tap(); absent(result)
        assertLabel(app.staticTexts["chat.profileReceipt"].firstMatch, profileReceipt)
        // The profile has no page of its own; Memory still lists no memory.
        openMemory(); assertEmptyMemories()
    }

    private func launch(reset: Bool = true) {
        app.terminate()
        app.launchArguments = ["-AppleLanguages", "(zh-Hant)", "-AppleLocale", "zh_TW",
                               "-UITestMode", "-UITestNamespace", namespace, "-UITestMCPFixture"]
        if reset { app.launchArguments.append("-UITestResetStorage") }
        app.launchEnvironment = [:]
        app.launch()
        XCTAssertTrue(app.staticTexts["chat.status"].firstMatch.waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["uitest.banner"].firstMatch.exists)
        assertLabel(app.staticTexts["chat.status"].firstMatch, "模型已設定")
    }

    private func connectFixture() {
        navigate("tools")
        tap("mcp.connect", scroll: true)
        assertLabel(app.staticTexts["mcp.status"].firstMatch, "已連線，目錄擷取完成")
        XCTAssertFalse(app.staticTexts["mcp.error"].firstMatch.exists)
        let enabled = app.switches["mcp.enable.fixture_echo"].firstMatch
        revealLearningElement(enabled, in: app)
        setSwitch(enabled, on: true)
        navigate("chat")
        setSwitch(app.switches["chat.useMCP"].firstMatch, on: true)
    }

    private func send(_ prompt: String) {
        let draft = chatDraftControl(in: app)
        writeASCII(prompt, into: draft)
        // Explicit native Done; newline is not a substitute for committing and
        // dismissing the keyboard before the Send button is hit-tested.
        tap("chat.dismissKeyboard")
        absent(app.keyboards.firstMatch)
        XCTAssertEqual(draft.value as? String, prompt)
        tap("chat.send")
    }

    private func assertActivity(attempts: Int, results: Int, modelCalls: Int, failure: String) {
        let activity = app.staticTexts["chat.mcpActivity"].firstMatch
        assertLabel(activity, "MCP 嘗試呼叫 \(attempts) 次；已收到 \(results) 次結果；工具錯誤 0 次。")
        let raw = activity.value as? String ?? ""
        var fields: [String: String] = [:]
        for field in raw.split(separator: ";") {
            let pair = field.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            XCTAssertEqual(pair.count, 2, "The fixed counter diagnostic must be well formed.")
            guard pair.count == 2 else { return }
            let key = String(pair[0])
            XCTAssertNil(fields[key], "Duplicate diagnostic fields cannot establish counters.")
            fields[key] = String(pair[1])
        }
        XCTAssertEqual(fields["attempts"], String(attempts))
        XCTAssertEqual(fields["results"], String(results))
        XCTAssertEqual(fields["toolErrors"], "0")
        XCTAssertEqual(fields["modelCalls"], String(modelCalls))
        XCTAssertEqual(fields["formatCorrections"], "0")
        XCTAssertEqual(fields["failure"], failure)
    }

    private func openMemory() {
        navigate("memory")
        XCTAssertFalse(app.staticTexts["memory.unavailable"].firstMatch.exists)
        XCTAssertFalse(app.staticTexts["memory.error"].firstMatch.exists)
        selectSegment("memories")
        let searchField = app.textFields["memory.search"].firstMatch
        let query = searchField.exists ? searchField.value as? String ?? "" : ""
        XCTAssertTrue(query.isEmpty || query == "搜尋",
                      "Data absence requires an unfiltered list.")
    }

    private func selectSegment(_ name: String) {
        let button = app.buttons["memory.segment.\(name)"].firstMatch
        ready(button)
        if button.value as? String != "已選取" { button.tap() }
        assertValue(button, "已選取")
    }

    private var memoryItems: XCUIElementQuery {
        app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@", "memory.item."))
    }

    private func assertSingleMemory(_ text: String) {
        let item = memoryItems.matching(NSPredicate(format: "label == %@", text)).firstMatch
        assertReadable(item, equals: text)
        XCTAssertEqual(memoryItems.count, 1)
        XCTAssertFalse(app.staticTexts["memory.error"].firstMatch.exists)
    }

    private func assertEmptyMemories() {
        assertReadable(app.staticTexts["memory.empty"].firstMatch, equals: "還沒有記住的事")
        XCTAssertFalse(memoryItems.firstMatch.exists)
    }

    private func assertEmptyPending() {
        assertReadable(app.staticTexts["memory.pending.empty"].firstMatch, equals: "沒有等你確認的東西")
        XCTAssertFalse(memoryItems.firstMatch.exists)
    }

    private func navigate(_ section: String) {
        navigateMikaSection(section, in: app)
        XCTAssertTrue(app.staticTexts["\(section).status"].firstMatch.waitForExistence(timeout: 5))
    }

    private func setSwitch(_ toggle: XCUIElement, on: Bool) {
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        let wanted = on ? "1" : "0"
        if toggle.value as? String != wanted {
            let nested = toggle.switches.firstMatch
            let target = nested.exists ? nested : toggle
            ready(target); target.tap()
        }
        assertValue(toggle, wanted)
    }

    private func writeASCII(_ text: String, into field: XCUIElement) {
        // The composer is a sibling below the messages ScrollView. Its full
        // native frame, not that ScrollView's viewport, governs visibility.
        ready(field)
        XCTAssertEqual(field.identifier, "chat.draft")
        let frame = field.frame
        XCTAssertFalse(frame.isEmpty)
        XCTAssertTrue(app.frame.contains(frame))
        XCTAssertLessThanOrEqual(frame.maxY, mikaUnobscuredBottom(in: app))
        let keyboard = app.keyboards.firstMatch
        if keyboard.exists { XCTAssertLessThanOrEqual(frame.maxY, keyboard.frame.minY) }
        field.tap()
        prepareLatinKeyboard()
        var remaining = text[...]
        var entered = ""
        while !remaining.isEmpty {
            let chunk = String(remaining.prefix(entered.isEmpty ? 1 : 16))
            field.typeText(chunk); entered += chunk; remaining = remaining.dropFirst(chunk.count)
            let actual = field.value as? String
            XCTAssertEqual(actual, entered, "Native input must match exactly; never repair or retry lost characters.")
            guard actual == entered else { return }
        }
        XCTAssertEqual(field.value as? String, text)
    }

    private func prepareLatinKeyboard() {
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        dismissKeyboardIntroductionIfPresented()
        let keyboard = app.keyboards.firstMatch
        func latin() -> Bool {
            keyboard.keys.matching(NSPredicate(format: "label IN %@", ["q", "Q"])).firstMatch.exists
                && keyboard.keys.matching(NSPredicate(format: "label IN %@", ["a", "A"])).firstMatch.exists
        }
        if latin() { return }
        // The native keyboard switch is localized by iOS, even when the app's
        // own test language is fixed. iOS 26 exposes the same visible globe as
        // 「下一個鍵盤」; earlier runtimes expose it as "Next keyboard".
        let globe = app.buttons.matching(NSPredicate(
            format: "label IN %@", ["Next keyboard", "下一個鍵盤"]
        )).firstMatch
        ready(globe)
        // On iOS 17 the system globe's accessibility frame can extend a
        // fraction of a point past the bottom edge while its tappable center
        // remains on screen. Hittability is checked above.
        XCTAssertTrue(
            app.frame.contains(CGPoint(x: globe.frame.midX, y: globe.frame.midY)),
            "The native keyboard switch must be visible"
        )
        globe.press(forDuration: 1)
        let english = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "English (US)")).firstMatch
        ready(english); english.tap()
        dismissKeyboardIntroductionIfPresented()
        let selected = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in latin() }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 10), .completed)
    }

    private func dismissKeyboardIntroductionIfPresented() {
        let button = app.buttons["Continue"].firstMatch
        guard button.waitForExistence(timeout: 3) else { return }
        let explanation = app.staticTexts["Speed up your typing by sliding your finger across the letters to compose a word."].firstMatch
        XCTAssertTrue(explanation.exists, "Only the known native keyboard introduction may be dismissed.")
        ready(button); button.tap(); absent(button)
    }

    private func assertReadable(_ element: XCUIElement, equals text: String) {
        revealLearningElement(element, in: app, visibility: .readableText)
        XCTAssertEqual(element.label, text)
    }

    private func assertLabel(_ element: XCUIElement, _ text: String) {
        let expected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND label == %@", text), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expected], timeout: 10), .completed)
    }

    private func assertValue(_ element: XCUIElement, _ text: String) {
        let expected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", text), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expected], timeout: 10), .completed)
    }

    private func tap(_ identifier: String, scroll: Bool = false) {
        let button = app.buttons[identifier].firstMatch
        if scroll { revealLearningElement(button, in: app) }
        ready(button); button.tap()
    }

    private func ready(_ element: XCUIElement) {
        let expected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND hittable == true AND enabled == true"), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expected], timeout: 10), .completed)
    }

    private func absent(_ element: XCUIElement) {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 5), .completed)
    }
}
