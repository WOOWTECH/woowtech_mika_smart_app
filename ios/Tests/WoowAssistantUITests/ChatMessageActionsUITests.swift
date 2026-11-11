import XCTest

/// Exercises the real chat, archive and native menus with the existing isolated
/// synthetic model. No conversation, quote, branch or UI result is pre-seeded.
final class ChatMessageActionsUITests: XCTestCase {
    private let app = XCUIApplication()
    private let namespace = UUID().uuidString

    override func setUpWithError() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("This isolated fixture suite runs only on a simulator")
        #else
        continueAfterFailure = false; executionTimeAllowance = 300
        #endif
    }
    override func tearDownWithError() throws {
        #if targetEnvironment(simulator)
        app.terminate()
        #endif
    }

    func testQuoteRemovalSendAndEncryptedRestore() {
        launch(); configure()
        send("Alpha", assistantIndex: 1)
        compose("Keep this")
        selectAction("quote", messageIndex: 1)
        let preview = app.descendants(matching: .any)["chat.quote.preview"].firstMatch
        XCTAssertTrue(preview.waitForExistence(timeout: 10))
        XCTAssertEqual(draft().value as? String, "Keep this")
        tap("chat.quote.remove")
        absent(preview)
        XCTAssertEqual(draft().value as? String, "Keep this")
        selectAction("quote", messageIndex: 1)
        XCTAssertTrue(preview.waitForExistence(timeout: 10))
        tap("chat.send")
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.alerts.firstMatch.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "整份對話封存")).firstMatch.waitForExistence(timeout: 5))
        tap("chat.quote.upgrade.cancel")
        XCTAssertEqual(draft().value as? String, "Keep this")
        XCTAssertTrue(preview.exists)
        tap("chat.send"); tap("chat.quote.upgrade.confirm")
        assertLabel(node("chat.message.2.user"), "Keep this")
        let sent = app.descendants(matching: .any)["chat.quote.sent.2"].firstMatch
        XCTAssertTrue(sent.waitForExistence(timeout: 10))
        assertLabel(node("chat.quote.sent.2.text"), "測試回覆：Alpha")
        XCTAssertTrue(node("chat.message.3.assistant").waitForExistence(timeout: 15))
        absent(preview)
        XCTAssertFalse(app.staticTexts["chat.archiveNotice"].firstMatch.exists)

        launch(reset: false)
        openArchive()
        let original = archiveRow("Alpha")
        ready(original); original.tap()
        let archived = node("archive.turn.1.user")
        XCTAssertTrue(archived.waitForExistence(timeout: 10))
        XCTAssertEqual(archived.label, "Keep this")
        XCTAssertTrue(node("archive.turn.1.quote").waitForExistence(timeout: 10))
        assertLabel(node("archive.turn.1.quote.text"), "測試回覆：Alpha")
        tap("archive.open")
        assertLabel(node("chat.message.2.user"), "Keep this")
        XCTAssertTrue(app.descendants(matching: .any)["chat.quote.sent.2"].firstMatch.waitForExistence(timeout: 10))
    }

    func testBranchPreservesSourceAndBlocksUnsentDraft() {
        launch(); configure()
        send("Alpha", assistantIndex: 1)
        send("Beta", assistantIndex: 3)
        compose("Retain draft")
        openActions(messageIndex: 1)
        let quote = action("quote")
        ready(quote)
        XCTAssertFalse(action("branch").exists, "Branch must not discard an unsent draft")
        quote.tap()
        XCTAssertEqual(draft().value as? String, "Retain draft")
        tap("chat.quote.remove")
        XCTAssertEqual(draft().value as? String, "Retain draft")
        clearDraft("Retain draft")
        selectAction("branch", messageIndex: 1)
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.alerts.firstMatch.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "整份對話封存")).firstMatch.waitForExistence(timeout: 5))
        tap("chat.branch.upgrade.cancel")
        assertLabel(node("chat.message.2.user"), "Beta")
        selectAction("branch", messageIndex: 1); tap("chat.branch.upgrade.confirm")
        assertLabel(node("chat.message.0.user"), "Alpha")
        assertLabel(node("chat.message.1.assistant"), "測試回覆：Alpha")
        absent(node("chat.message.2.user"))
        XCTAssertFalse(app.staticTexts["chat.archiveNotice"].firstMatch.exists)

        launch(reset: false); openArchive()
        let source = archiveRow("Alpha")
        let branch = archiveRow("Alpha · 分支")
        XCTAssertTrue(source.waitForExistence(timeout: 10))
        XCTAssertTrue(branch.waitForExistence(timeout: 10))
        ready(source); source.tap()
        assertLabel(node("archive.turn.1.user"), "Beta")
        assertLabel(node("archive.turn.1.assistant"), "測試回覆：Beta")
        tap("archive.open")
        assertLabel(node("chat.message.2.user"), "Beta")
    }

    func testLiteralMarkerIsNotAnAssistantQuoteAndCanBeCopied() {
        launch(); configure()
        let marker = "> [Quoting your earlier reply]"
        send(marker, assistantIndex: 1)
        assertLabel(node("chat.message.0.user"), marker)
        XCTAssertFalse(node("chat.quote.sent.0").exists)
        selectAction("copy", messageIndex: 0)
        let field = draft(); ready(field); field.tap(); prepareKeyboard(); field.press(forDuration: 1)
        let predicate = NSPredicate(format: "label IN %@", ["貼上", "Paste"])
        let item = app.menuItems.matching(predicate).firstMatch
        let paste = item.waitForExistence(timeout: 5) ? item : app.buttons.matching(predicate).firstMatch
        ready(paste); paste.tap(); assertValue(field, marker)
    }

    func testPendingQuoteNewConversationCancelsVoiceAndRequiresConfirmation() {
        launch(voice: true); configure(); send("Alpha", assistantIndex: 1)
        compose("Keep text")
        selectAction("quote", messageIndex: 1)
        tap("voice.fixture.accessibility"); observation("start=1")
        tap("chat.newConversation"); observation("cancel=1")
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.alerts.firstMatch.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "未送出的引用")).firstMatch.waitForExistence(timeout: 5))
        tap("chat.new.cancel")
        XCTAssertTrue(node("chat.quote.preview").exists)
        XCTAssertEqual(draft().value as? String, "Keep text")
        tap("voice.fixture.emit"); observation("emit=1")
        XCTAssertEqual(draft().value as? String, "Keep text")
        tap("chat.newConversation"); tap("chat.new.confirm")
        absent(node("chat.quote.preview"))
        XCTAssertEqual(draft().value as? String, "Keep text")
        absent(node("chat.message.0.user"))
    }

    func testLongQuoteCanExpandInComposerAndArchive() {
        launch(); configure()
        let text = String(repeating: "LongQuote", count: 16)
        send(text, assistantIndex: 1)
        selectAction("quote", messageIndex: 1)
        tap("chat.quote.expand")
        XCTAssertEqual(app.buttons["chat.quote.expand"].firstMatch.label, "收合引用")
        assertLabel(node("chat.quote.preview.text"), "測試回覆：" + text)
        compose("Follow-up"); tap("chat.send"); tap("chat.quote.upgrade.confirm")
        let sent = node("chat.quote.sent.2.text")
        XCTAssertTrue(sent.waitForExistence(timeout: 15))
        tap("chat.quote.sent.2.expand")
        assertLabel(sent, "測試回覆：" + text)
        launch(reset: false); openArchive()
        let original = archiveRow(String(text.prefix(60)))
        ready(original); original.tap()
        let archiveQuote = node("archive.turn.1.quote.text")
        XCTAssertTrue(archiveQuote.waitForExistence(timeout: 10))
        tap("archive.turn.1.quote.expand")
        assertLabel(archiveQuote, "測試回覆：" + text)
        let visible = archiveQuote.frame.intersection(node("archive.turn.1.quote").frame)
            .intersection(app.windows.firstMatch.frame)
        XCTAssertFalse(visible.isNull)
        XCTAssertGreaterThan(visible.height, 0)
        let window = app.windows.firstMatch
        window.coordinate(withNormalizedOffset: .zero).withOffset(
            CGVector(dx: visible.midX - window.frame.minX, dy: visible.midY - window.frame.minY)
        ).press(forDuration: 1)
        let selection = NSPredicate(format: "label IN %@",
            ["Copy", "複製", "复制", "拷貝", "Select All", "全選", "全选"])
        let canSelect = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let item = self.app.menuItems.matching(selection).firstMatch
            let button = self.app.buttons.matching(selection).firstMatch
            return (item.exists && item.isHittable) || (button.exists && button.isHittable)
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [canSelect], timeout: 5), .completed,
                       "Expanded archive quote must expose a native text selection action")
    }

    func testCopyUsesRenderedAssistantText() {
        launch(); configure()
        let marker = "COPY" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
        compose("**" + marker + "**"); tap("chat.send")
        assertLabel(node("chat.message.1.assistant"), "測試回覆：" + marker)
        selectAction("copy", messageIndex: 1)
        let field = draft(); ready(field); field.tap(); prepareKeyboard()
        field.press(forDuration: 1)
        let predicate = NSPredicate(format: "label IN %@", ["貼上", "Paste"])
        let nativeItem = app.menuItems.matching(predicate).firstMatch
        let button = app.buttons.matching(predicate).firstMatch
        let paste = nativeItem.waitForExistence(timeout: 5) ? nativeItem : button
        ready(paste); paste.tap()
        assertValue(field, "測試回覆：" + marker)
    }

    func testCancelledPartialNeverOffersMessageActions() {
        launch(streaming: true); configure(); disableMemory()
        compose("[fixture:stream-cancel]"); tap("chat.send")
        assertLabel(node("chat.partialReply"), "串流測試：第一段")
        assertLabel(app.staticTexts["chat.partialStatus"].firstMatch, "回覆產生中・尚未完成，未保存")
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "chat.message.actions.")).count, 0)
        tap("chat.cancel")
        assertLabel(app.staticTexts["chat.partialStatus"].firstMatch, "已取消・部分回覆未保存")
        assertLabel(node("chat.partialReply"), "串流測試：第一段")
        XCTAssertEqual(draft().value as? String, "[fixture:stream-cancel]")
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "chat.message.actions.")).count, 0)
        openArchive()
        XCTAssertTrue(app.staticTexts["archive.empty"].firstMatch.waitForExistence(timeout: 10))
    }

    func testSavedReplyCannotBranchWhileLaterTurnIsUnfinished() {
        launch(streaming: true); configure(); disableMemory()
        compose("[fixture:stream-complete]"); tap("chat.send")
        let completed = node("chat.message.1.assistant")
        let complete = NSPredicate(format: "exists == true AND label == %@", "串流測試：第一段；完整回覆。")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: complete, object: completed)], timeout: 50), .completed)
        XCTAssertEqual(completed.label, "串流測試：第一段；完整回覆。")
        compose("[fixture:stream-cancel]"); tap("chat.send")
        assertLabel(node("chat.partialReply"), "串流測試：第一段")
        openActions(messageIndex: 1)
        let quote = action("quote"); ready(quote)
        XCTAssertFalse(action("branch").exists, "A later in-flight turn must block branching from a saved reply")
        quote.tap()
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 10))
        let close = alert.buttons["關閉"].firstMatch
        ready(close); close.tap()
        XCTAssertFalse(app.descendants(matching: .any)["chat.quote.preview"].firstMatch.exists)
        tap("chat.cancel")
        assertLabel(app.staticTexts["chat.partialStatus"].firstMatch, "已取消・部分回覆未保存")
        XCTAssertEqual(draft().value as? String, "[fixture:stream-cancel]")
        assertLabel(node("chat.message.1.assistant"), "串流測試：第一段；完整回覆。")
        openActions(messageIndex: 1)
        let copy = action("copy"); ready(copy)
        XCTAssertFalse(action("branch").exists, "A retained partial and draft must still block branching")
        copy.tap()
    }

    func testActiveVoicePreventsBranchAndKeepsActualVoiceResult() {
        launch(voice: true); configure()
        send("Alpha", assistantIndex: 1)
        tap("voice.fixture.accessibility")
        observation("start=1")
        openActions(messageIndex: 1)
        let quote = action("quote")
        ready(quote)
        XCTAssertFalse(action("branch").exists, "Active voice is unfinished composer work")
        quote.tap()
        XCTAssertTrue(app.descendants(matching: .any)["chat.quote.preview"].firstMatch.waitForExistence(timeout: 10))
        observation("cancel=0")
        tap("voice.fixture.accessibility")
        observation("finish=1")
        tap("voice.fixture.emit")
        observation("emit=1")
        assertValue(draft(), "fixture voice")
        XCTAssertTrue(app.descendants(matching: .any)["chat.quote.preview"].firstMatch.exists)
        assertLabel(node("chat.message.0.user"), "Alpha")
    }

    private func launch(reset: Bool = true, voice: Bool = false, streaming: Bool = false) {
        app.terminate()
        app.launchArguments = ["-AppleLanguages", "(zh-Hant)", "-AppleLocale", "zh_TW",
                               "-UITestMode", "-UITestNamespace", namespace]
        if reset { app.launchArguments.append("-UITestResetStorage") }
        if voice { app.launchArguments.append("-UITestVoiceFixture") }
        if streaming { app.launchArguments.append("-UITestChatStreaming") }
        app.launchEnvironment = [:]; app.launch()
        XCTAssertTrue(app.staticTexts["chat.status"].firstMatch.waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["uitest.banner"].firstMatch.exists)
        if voice { XCTAssertTrue(app.staticTexts["voice.fixture.observation"].firstMatch.waitForExistence(timeout: 10)) }
    }
    private func configure() {
        navigateMikaSection("settings", in: app); openModelSettings(in: app)
        write("https://model.invalid/v1", to: app.textFields["settings.baseURL"].firstMatch, scroll: true)
        tap("settings.dismissKeyboard")
        write("fixture", to: app.textFields["settings.model"].firstMatch, scroll: true)
        tap("settings.dismissKeyboard")
        write("fixture-key", to: app.secureTextFields["settings.apiKey"].firstMatch, scroll: true)
        tap("settings.dismissKeyboard")
        let save = app.buttons["settings.save"].firstMatch
        revealLearningElement(save, in: app); ready(save); save.tap()
        XCTAssertTrue(app.staticTexts["settings.notice"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["settings.error"].firstMatch.exists)
        returnFromModelSettings(in: app); navigateMikaSection("chat", in: app)
        assertLabel(app.staticTexts["chat.status"].firstMatch, "模型已設定")
    }
    private func disableMemory() {
        navigateMikaSection("memory", in: app)
        let toggle = app.switches["memory.toggle.useMemory"].firstMatch
        revealLearningElement(toggle, in: app); ready(toggle)
        XCTAssertEqual(toggle.value as? String, "1")
        let native = toggle.switches.firstMatch
        let target = native.exists ? native : toggle
        ready(target); target.tap(); assertValue(toggle, "0")
        XCTAssertFalse(app.staticTexts["memory.error"].firstMatch.exists)
        navigateMikaSection("chat", in: app)
    }
    private func node(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }
    private func draft() -> XCUIElement { chatDraftControl(in: app) }
    private func compose(_ text: String) {
        let field = draft(); write(text, to: field, scroll: false); tap("chat.dismissKeyboard")
        assertValue(field, text)
    }
    private func send(_ text: String, assistantIndex: Int) {
        compose(text); tap("chat.send")
        assertLabel(node("chat.message.\(assistantIndex).assistant"), "測試回覆：" + text)
        XCTAssertFalse(app.staticTexts["chat.error"].firstMatch.exists)
        XCTAssertFalse(app.staticTexts["chat.archiveNotice"].firstMatch.exists)
    }
    private func clearDraft(_ value: String) {
        let field = draft(); ready(field); field.tap(); prepareKeyboard()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count))
        let empty = NSPredicate { _, _ in
            guard let current = field.value as? String else { return true }
            return current.isEmpty || current == "輸入訊息"
        }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: empty, object: nil)], timeout: 10), .completed)
        XCTAssertFalse(app.buttons["chat.send"].firstMatch.isEnabled)
        tap("chat.dismissKeyboard")
    }
    private func openActions(messageIndex: Int) {
        let menu = app.buttons["chat.message.actions.\(messageIndex)"].firstMatch
        let transcript = app.scrollViews["chat.transcript"].firstMatch
        for _ in 0..<5 where !menu.isHittable { transcript.swipeDown() }
        ready(menu); menu.tap()
    }
    private func action(_ name: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "chat.message.\(name).")).firstMatch
    }
    private func selectAction(_ name: String, messageIndex: Int) {
        openActions(messageIndex: messageIndex)
        let item = action(name); ready(item); item.tap()
    }
    private func archiveRow(_ title: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label == %@", "archive.row.", title)).firstMatch
    }
    private func openArchive() { tap("chat.menu"); tap("drawer.archive") }
    private func observation(_ text: String) {
        let element = app.staticTexts["voice.fixture.observation"].firstMatch
        let predicate = NSPredicate(format: "label CONTAINS %@", text)
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: 10), .completed)
    }
    private func write(_ text: String, to field: XCUIElement, scroll: Bool) {
        if scroll { revealLearningElement(field, in: app) }
        ready(field); field.tap(); prepareKeyboard()
        var entered = "", remaining = text[...]
        while !remaining.isEmpty {
            let chunk = String(remaining.prefix(entered.isEmpty ? 1 : 16))
            field.typeText(chunk); entered += chunk; remaining = remaining.dropFirst(chunk.count)
            if field.elementType != .secureTextField { XCTAssertEqual(field.value as? String, entered) }
        }
    }
    private func prepareKeyboard() {
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        let intro = app.buttons["Continue"].firstMatch
        if intro.waitForExistence(timeout: 2) { ready(intro); intro.tap() }
        let keyboard = app.keyboards.firstMatch
        func latin() -> Bool {
            keyboard.keys.matching(NSPredicate(format: "label IN %@", ["q", "Q"])).firstMatch.exists
                && keyboard.keys.matching(NSPredicate(format: "label IN %@", ["a", "A"])).firstMatch.exists
        }
        if latin() { return }
        let globe = app.buttons.matching(NSPredicate(format: "label IN %@", ["Next keyboard", "下一個鍵盤"])).firstMatch
        ready(globe); globe.press(forDuration: 1)
        let english = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "English (US)")).firstMatch
        ready(english); english.tap()
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in latin() }, object: nil)], timeout: 10), .completed)
    }
    private func tap(_ id: String) { let button = app.buttons[id].firstMatch; ready(button); button.tap() }
    private func ready(_ element: XCUIElement) {
        let hittable = NSPredicate(format: "exists == true AND hittable == true AND enabled == true")
        if !hittable.evaluate(with: element) {
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: hittable, object: element)], timeout: 10), .completed)
        }
        XCTAssertTrue(element.exists); XCTAssertTrue(element.isHittable); XCTAssertTrue(element.isEnabled)
    }
    private func absent(_ element: XCUIElement) {
        let absent = NSPredicate(format: "exists == false")
        if !absent.evaluate(with: element) {
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: absent, object: element)], timeout: 10), .completed)
        }
        XCTAssertFalse(element.exists)
    }
    private func assertValue(_ element: XCUIElement, _ value: String) {
        let predicate = NSPredicate(format: "exists == true AND value == %@", value)
        if !predicate.evaluate(with: element) {
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: 10), .completed)
        }
        XCTAssertEqual(element.value as? String, value)
    }
    private func assertLabel(_ element: XCUIElement, _ value: String) {
        let predicate = NSPredicate(format: "exists == true AND label == %@", value)
        if !predicate.evaluate(with: element) {
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: 15), .completed)
        }
        XCTAssertEqual(element.label, value)
    }
}
