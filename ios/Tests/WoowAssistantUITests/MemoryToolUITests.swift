import XCTest

/// Fixture commands through ordinary Chat's real encrypted memory store, undo
/// and pending-procedure approval. Like the Play build, a memory tool applies
/// with no review sheet. Fixtures never seed/save memory directly. This class
/// is native UI coverage; the separate LiveModel method uses HTTP.
final class MemoryToolUITests: XCTestCase {
    private let app = XCUIApplication()
    private let namespace = UUID().uuidString
    private let receiptText = "本次對話曾儲存記憶修改；可在資料頁查看目前內容。"
    private let procedureText = "Check invoices before paying"

    override func setUpWithError() throws {
        continueAfterFailure = false
        // The undo cases relaunch and switch keyboards several times; on iPhone SE
        // (iOS 18.5) the delete case ran past 240 s in PR #36's run. 300 s is the
        // most this scope allows.
        executionTimeAllowance = 300
    }

    override func tearDownWithError() throws {
        if let testRun, testRun.failureCount > 0 {
            // Synthetic fixture text and dummy credentials only. The live case
            // has its own cleanup and must never attach screenshots or AX dumps.
            let tree = XCTAttachment(string: app.debugDescription)
            tree.name = "memory-tool-fixture-failure-AX"
            tree.lifetime = .keepAlways; add(tree)
            let screen = XCTAttachment(screenshot: app.screenshot())
            screen.name = "memory-tool-fixture-failure-screen"
            screen.lifetime = .keepAlways; add(screen)
        }
        app.terminate()
    }

    func testSaveCanBeUndoneAndRemainsAbsentAfterRelaunch() {
        launch(); configureModel()
        request("Remember preference Prefer jasmine tea", note: "記住了：Prefer jasmine tea")
        openMemory()
        assertSingleMemory("Prefer jasmine tea")
        navigate("chat")
        undoNote()
        assertLabel(app.staticTexts["chat.memoryReceipt"].firstMatch, receiptText)
        openMemory(); assertEmptyMemories()
        launch(reset: false); openMemory(); assertEmptyMemories()
        selectSegment("pending"); assertEmptyPending()
    }

    func testUpdateOfManualMemoryPersistsAfterRelaunch() {
        launch(); configureModel(); openMemory()
        addManualPreference("Prefer jasmine tea", keywords: "jasmine tea")
        let originalID = memory("Prefer jasmine tea").identifier
        navigate("chat")
        request("Update Prefer jasmine tea to Prefer coffee", note: "更新了：Prefer coffee")
        openMemory(); assertSingleMemory("Prefer coffee")
        XCTAssertEqual(memory("Prefer coffee").identifier, originalID)
        XCTAssertFalse(memory("Prefer jasmine tea").exists)
        launch(reset: false); openMemory(); assertSingleMemory("Prefer coffee")
        XCTAssertEqual(memory("Prefer coffee").identifier, originalID)
        XCTAssertFalse(memory("Prefer jasmine tea").exists)
        // Inspect the actual persisted keywords through the normal editor.
        tap(originalID.replacingOccurrences(of: "memory.item.", with: "memory.edit."), scroll: true)
        XCTAssertEqual(app.textViews["memory.editor.content"].firstMatch.value as? String, "Prefer coffee")
        XCTAssertEqual(app.textFields["memory.editor.keywords"].firstMatch.value as? String, "coffee")
        tap("memory.editor.cancel")
        absent(app.buttons["memory.editor.cancel"].firstMatch)
    }

    func testDeleteCanBeUndoneAndRestoresManualMemoryAfterRelaunch() {
        launch(); configureModel(); openMemory()
        addManualPreference("Prefer coffee", keywords: "coffee")
        let originalID = memory("Prefer coffee").identifier
        navigate("chat")
        request("Delete Prefer coffee", note: "已忘掉一條記憶")
        openMemory(); assertEmptyMemories()
        navigate("chat"); undoNote()
        openMemory(); assertSingleMemory("Prefer coffee")
        XCTAssertEqual(memory("Prefer coffee").identifier, originalID)
        launch(reset: false); openMemory(); assertSingleMemory("Prefer coffee")
        XCTAssertEqual(memory("Prefer coffee").identifier, originalID,
                       "Undo must restore the original encrypted entry, not save a new replacement.")
        selectSegment("pending"); assertEmptyPending()
    }

    func testSavedProcedureRequiresSeparateApprovalAndRelaunchesActive() {
        launch(); configureModel()
        savePendingProcedure()
        openMemory(); assertEmptyMemories()
        selectSegment("pending"); assertSingleMemory(procedureText)
        let pendingID = memory(procedureText).identifier
        navigate("chat")
        tap("chat.approveMemory.0")
        absent(app.staticTexts["chat.memoryNote.0"].firstMatch)
        assertLabel(app.staticTexts["chat.learningNotice"].firstMatch,
                    "已批准這條操作偏好，後續任務可以參考。")
        XCTAssertFalse(app.staticTexts["chat.learningError"].firstMatch.exists)
        launch(reset: false); openMemory(); assertSingleMemory(procedureText)
        XCTAssertEqual(memory(procedureText).identifier, pendingID)
        selectSegment("pending"); assertEmptyPending()
    }

    func testSavedProcedureCanBeRejectedAndRelaunchesAbsent() {
        launch(); configureModel()
        savePendingProcedure()
        openMemory(); assertEmptyMemories()
        selectSegment("pending"); assertSingleMemory(procedureText)
        navigate("chat")
        tap("chat.rejectMemory.0")
        absent(app.staticTexts["chat.memoryNote.0"].firstMatch)
        assertLabel(app.staticTexts["chat.learningNotice"].firstMatch,
                    "已拒絕這條操作偏好；有可用撤銷紀錄時恢復修改前內容。")
        XCTAssertFalse(app.staticTexts["chat.learningError"].firstMatch.exists)
        openMemory(); assertEmptyMemories()
        selectSegment("pending"); assertEmptyPending()
        launch(reset: false); openMemory(); assertEmptyMemories()
        selectSegment("pending"); assertEmptyPending()
    }

    private func savePendingProcedure() {
        request("Remember procedure Check invoices before paying", note: "待你確認做法：" + procedureText)
        ready(app.buttons["chat.approveMemory.0"].firstMatch)
        ready(app.buttons["chat.rejectMemory.0"].firstMatch)
    }

    /// The model's memory command applies at once and its reply continues.
    private func request(_ prompt: String, note: String) {
        let draft = chatDraftControl(in: app)
        writeASCII(prompt, into: draft, scroll: false)
        tap("chat.dismissKeyboard")
        XCTAssertEqual(draft.value as? String, prompt)
        tap("chat.send")
        let answer = app.staticTexts["chat.message.1.assistant"].firstMatch
        let error = app.staticTexts["chat.error"].firstMatch
        let finished = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in answer.exists || error.exists }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [finished], timeout: 15), .completed)
        XCTAssertFalse(error.exists)
        XCTAssertTrue(answer.exists)
        XCTAssertEqual(answer.label, "記憶工具已完成。")
        assertLabel(app.staticTexts["chat.status"].firstMatch, "模型已設定")
        assertLabel(app.staticTexts["chat.memoryReceipt"].firstMatch, receiptText)
        assertLabel(app.staticTexts["chat.memoryNote.0"].firstMatch, note)
        XCTAssertFalse(app.staticTexts["chat.memoryNote.1"].firstMatch.exists)
        XCTAssertFalse(app.staticTexts["chat.learningError"].firstMatch.exists)
        XCTAssertFalse(app.staticTexts["chat.profileReceipt"].firstMatch.exists)
        ready(app.buttons["chat.undoMemory.0"].firstMatch)
    }

    private func undoNote() {
        tap("chat.undoMemory.0")
        absent(app.staticTexts["chat.memoryNote.0"].firstMatch)
        XCTAssertFalse(app.buttons["chat.undoMemory.0"].firstMatch.exists)
        XCTAssertFalse(app.staticTexts["chat.learningError"].firstMatch.exists)
    }

    private func openMemory() {
        navigate("memory")
        XCTAssertFalse(app.staticTexts["memory.unavailable"].firstMatch.exists)
        XCTAssertFalse(app.staticTexts["memory.error"].firstMatch.exists)
        selectSegment("memories")
        let searchField = app.textFields["memory.search"].firstMatch
        let searchValue = searchField.exists ? searchField.value as? String ?? "" : ""
        XCTAssertTrue(searchValue.isEmpty || searchValue == "搜尋",
                      "Absence must be checked in the unfiltered memory list.")
    }

    private func selectSegment(_ name: String) {
        let button = app.buttons["memory.segment.\(name)"].firstMatch
        ready(button)
        if button.value as? String != "已選取" { button.tap() }
        assertValue(button, "已選取")
    }

    private func addManualPreference(_ text: String, keywords: String) {
        assertEmptyMemories()
        tap("memory.add", scroll: true)
        let kind = app.segmentedControls.buttons["偏好"].firstMatch
        ready(kind); kind.tap()
        XCTAssertTrue(kind.isSelected)
        writeASCII(text, into: app.textViews["memory.editor.content"].firstMatch)
        tap("memory.editor.done")
        absent(app.keyboards.firstMatch)
        let field = app.textFields["memory.editor.keywords"].firstMatch
        writeASCII(keywords, into: field)
        XCTAssertEqual(field.value as? String, keywords)
        tap("memory.editor.save")
        absent(app.buttons["memory.editor.save"].firstMatch)
        XCTAssertFalse(app.staticTexts["memory.error"].firstMatch.exists)
        assertSingleMemory(text)
    }

    private func memory(_ text: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label == %@",
                                            "memory.item.", text)).firstMatch
    }

    private func assertSingleMemory(_ text: String) {
        let item = memory(text)
        assertReadable(item, equals: text)
        XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@", "memory.item.")).count, 1)
        XCTAssertTrue(item.identifier.hasPrefix("memory.item."))
        XCTAssertFalse(app.staticTexts["memory.error"].firstMatch.exists)
    }

    private func assertEmptyMemories() {
        assertReadable(app.staticTexts["memory.empty"].firstMatch, equals: "還沒有記住的事")
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@", "memory.item.")).firstMatch.exists)
    }

    private func assertEmptyPending() {
        assertReadable(app.staticTexts["memory.pending.empty"].firstMatch, equals: "沒有等你確認的東西")
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@", "memory.item.")).firstMatch.exists)
    }

    private func launch(reset: Bool = true) {
        app.terminate()
        app.launchArguments = ["-AppleLanguages", "(zh-Hant)", "-AppleLocale", "zh_TW",
                               "-UITestMode", "-UITestNamespace", namespace, "-WoowSkipOnboarding"]
        if reset { app.launchArguments.append("-UITestResetStorage") }
        app.launchEnvironment = [:]
        app.launch()
        XCTAssertTrue(app.staticTexts["chat.status"].firstMatch.waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["uitest.banner"].firstMatch.exists)
        if !reset { assertLabel(app.staticTexts["chat.status"].firstMatch, "模型已設定") }
    }

    private func configureModel() {
        navigate("settings")
        openModelSettings(in: app)
        writeASCII("https://model.invalid/v1", into: app.textFields["settings.baseURL"].firstMatch)
        tap("settings.dismissKeyboard")
        writeASCII("fixture", into: app.textFields["settings.model"].firstMatch)
        tap("settings.dismissKeyboard")
        let key = app.secureTextFields["settings.apiKey"].firstMatch
        revealLearningElement(key, in: app)
        ready(key); key.tap()
        prepareLatinKeyboard()
        key.typeText("fixture-key")
        tap("settings.dismissKeyboard")
        tap("setup.test", scroll: true)
        agreeToModelConsent(in: app)
        XCTAssertTrue(app.staticTexts["settings.notice"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["settings.error"].firstMatch.exists)
        returnFromModelSettings(in: app)
        navigate("chat")
        assertLabel(app.staticTexts["chat.status"].firstMatch, "模型已設定")
    }

    private func navigate(_ section: String) {
        navigateMikaSection(section, in: app)
        XCTAssertTrue(app.staticTexts["\(section).status"].firstMatch.waitForExistence(timeout: 5))
    }

    private func writeASCII(_ text: String, into field: XCUIElement, chunkSize: Int = 16, scroll: Bool = true) {
        if scroll { revealLearningElement(field, in: app) }
        ready(field)
        if !scroll {
            // Same composer as the four 856e8ec profile-tool failures: it is
            // outside the messages ScrollView, so inspect its native bounds.
            XCTAssertEqual(field.identifier, "chat.draft")
            let frame = field.frame
            XCTAssertFalse(frame.isEmpty)
            XCTAssertTrue(app.frame.contains(frame))
            XCTAssertLessThanOrEqual(frame.maxY, mikaUnobscuredBottom(in: app))
            let keyboard = app.keyboards.firstMatch
            if keyboard.exists { XCTAssertLessThanOrEqual(frame.maxY, keyboard.frame.minY) }
        }
        field.tap()
        prepareLatinKeyboard()
        var remaining = text[...]
        var entered = ""
        while !remaining.isEmpty {
            let chunk = String(remaining.prefix(entered.isEmpty ? 1 : chunkSize))
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
        let globe = app.buttons["Next keyboard"].firstMatch
        ready(globe); globe.press(forDuration: 1)
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
        let predicate = NSPredicate(format: "exists == true AND label == %@", text)
        if predicate.evaluate(with: element) { return }
        let expected = XCTNSPredicateExpectation(predicate: predicate, object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expected], timeout: 10), .completed)
    }

    private func assertValue(_ element: XCUIElement, _ text: String) {
        let predicate = NSPredicate(format: "value == %@", text)
        if predicate.evaluate(with: element) { return }
        let expected = XCTNSPredicateExpectation(predicate: predicate, object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expected], timeout: 10), .completed)
    }

    private func tap(_ identifier: String, scroll: Bool = false) {
        let button = app.buttons[identifier].firstMatch
        if scroll { revealLearningElement(button, in: app) }
        ready(button); button.tap()
    }

    private func ready(_ element: XCUIElement) {
        // 61f current reached the undo scenarios' final relaunch checks after
        // the 240s allowance. Avoid entering a polling expectation when its
        // exact predicate already holds; preserve every readiness requirement
        // and the original bounded wait when the UI is still transitioning.
        let predicate = NSPredicate(format: "exists == true AND hittable == true AND enabled == true")
        if predicate.evaluate(with: element) { return }
        let ready = XCTNSPredicateExpectation(predicate: predicate, object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 10), .completed)
    }

    private func absent(_ element: XCUIElement) {
        let predicate = NSPredicate(format: "exists == false")
        if predicate.evaluate(with: element) { return }
        let gone = XCTNSPredicateExpectation(predicate: predicate, object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 5), .completed)
    }
}
