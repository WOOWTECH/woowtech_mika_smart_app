import XCTest

/// Native document UI, real renderers and system dialogs. Only the source reply
/// uses the isolated model fixture; no commercial/provider acceptance is implied.
final class DocumentExportUITests: XCTestCase {
    private let app = XCUIApplication()
    private let namespace = UUID().uuidString
    override func setUpWithError() throws { continueAfterFailure = false; executionTimeAllowance = 240 }
    override func tearDownWithError() throws {
        defer { app.terminate() }
        if let testRun, testRun.failureCount > 0 {
            let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            screenshot.name = "document-failure-screen"; screenshot.lifetime = .keepAlways
            add(screenshot)
            let state = app.state
            let hierarchy = state == .runningForeground ? app.debugDescription : "App is not in the foreground."
            let diagnostics = XCTAttachment(string: "App state: \(state.rawValue)\n\(hierarchy)")
            diagnostics.name = "document-failure-state-and-AX"; diagnostics.lifetime = .keepAlways
            add(diagnostics)
        }
    }

    func testSelectedAnswerCSVPreviewAndSaveCancellation() {
        launch()
        send("Report\n\n| Item | Value |\n| --- | --- |\n| Formula | =1+1 |\n| Code | 00123 |\n\n<script>alert('DOC_SCRIPT')</script>")
        let reply = app.descendants(matching: .any)["chat.message.1.assistant"].firstMatch
        ready(reply); reply.press(forDuration: 1)
        tap("chat.messageMenu.document")
        let csv = app.segmentedControls["document.format"].buttons["CSV"]
        ready(csv); csv.tap()
        tap("document.generate")
        assertText("document.status", contains: "文件已產生")
        reveal("document.protectedCells")
        assertText("document.protectedCells", contains: "1 個")
        tap("document.preview", reveal: true)
        let content = app.descendants(matching: .any)["document.preview.content"].firstMatch
        XCTAssertTrue(content.waitForExistence(timeout: 10))
        // The SwiftUI preview wrapper publishes this identifier on the native
        // text view, overriding its makeUIView identifier (native-4 AX evidence).
        XCTAssertTrue((app.textViews["document.preview.content"].firstMatch.value as? String ?? "").contains("'=1+1"))
        tap("document.preview.done")
        tap("document.save", reveal: true)
        cancelSavePicker()
        assertText("document.status", contains: "已取消操作")
        XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "文件已匯出")).firstMatch.exists)
        capture("csv-save-cancelled")

        // Exercise the real restricted WKWebView, including escaped untrusted
        // content. A successful writer alone does not prove preview navigation.
        let html = app.segmentedControls["document.format"].buttons["HTML"]
        for _ in 0..<6 where !html.isHittable { app.swipeDown() }
        ready(html); html.tap()
        tap("document.generate", reveal: true)
        assertText("document.status", contains: "文件已產生")
        tap("document.preview", reveal: true)
        let web = app.webViews.firstMatch
        XCTAssertTrue(web.waitForExistence(timeout: 10))
        let literal = web.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "<script>alert('DOC_SCRIPT')</script>")).firstMatch
        XCTAssertTrue(literal.waitForExistence(timeout: 15), "HTML must load and display script markup as inert text")
        XCTAssertFalse(app.alerts.firstMatch.exists)
        capture("html-inert-script-preview")
    }

    func testExplicitLocalRequestCreatesPDFWithoutAnotherModelTurn() {
        launch()
        send("Local report with English 123 and a final sentinel REPORT_END.")
        let draft = chatDraftControl(in: app)
        ready(draft); draft.tap(); draft.typeText("export the previous answer as PDF")
        tap("chat.dismissKeyboard")
        tap("chat.send")
        XCTAssertTrue(app.textFields["document.title"].waitForExistence(timeout: 10))
        tap("document.generate")
        assertText("document.status", contains: "文件已產生")
        tap("document.preview", reveal: true)
        XCTAssertTrue(app.descendants(matching: .any)["document.preview.content"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["無法預覽文件，請關閉預覽後重試。"].exists)
        capture("pdf-preview")
        tap("document.preview.done")
        tap("document.done")
        XCTAssertEqual(draft.value as? String, "export the previous answer as PDF", "The local operation must not lose the draft")
        XCTAssertFalse(app.descendants(matching: .any)["chat.message.2.user"].firstMatch.exists,
                       "A confirmed local export does not issue a new model request")
    }

    func testInvalidSourceErrorSurvivesFormatAndTitleChanges() {
        launch()
        // The ordinary isolated reply fixture echoes this malformed table.
        // No new runtime fixture or production source-editing flow is needed.
        send("Invalid source\n\n| A | B |\n| --- | --- |\n| only one |")
        let reply = app.descendants(matching: .any)["chat.message.1.assistant"].firstMatch
        ready(reply); reply.press(forDuration: 1)
        tap("chat.messageMenu.document")
        let status = app.staticTexts["document.status"].firstMatch
        let generate = app.buttons["document.generate"].firstMatch
        let expected = "內容為空、表格欄位不一致或超出支援大小，無法產生文件。請先調整來源內容。"
        func assertInvalidState() {
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "exists == true AND label == %@", expected), object: status)], timeout: 10), .completed)
            XCTAssertTrue(generate.exists)
            XCTAssertFalse(generate.isEnabled, "Changing output options cannot make an invalid source exportable")
            XCTAssertFalse(app.staticTexts["document.filename"].firstMatch.exists)
        }
        assertInvalidState()
        for format in ["CSV", "HTML", "PDF"] {
            let option = app.segmentedControls["document.format"].buttons[format]
            ready(option); option.tap()
            XCTAssertTrue(option.isSelected)
            assertInvalidState()
        }
        let title = app.textFields["document.title"]
        ready(title); title.tap(); title.typeText(" revised")
        XCTAssertTrue((title.value as? String ?? "").contains("revised"))
        assertInvalidState()
        capture("invalid-source-still-explained-after-output-edits")

        // A different immutable source gets its own validation state. Use the
        // same ordinary chat/echo/export path, without a relaunch or reset.
        tap("document.done")
        send("Valid source\n\n| A | B |\n| --- | --- |\n| retained | valid |", assistantIndex: 3)
        let validReply = app.descendants(matching: .any)["chat.message.3.assistant"].firstMatch
        ready(validReply); validReply.press(forDuration: 1)
        tap("chat.messageMenu.document")
        let csv = app.segmentedControls["document.format"].buttons["CSV"]
        ready(csv); csv.tap()
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == true AND enabled == true"), object: generate)], timeout: 10), .completed)
        XCTAssertFalse(status.exists, "The previous source's validation failure must not leak into a new export")
        tap("document.generate")
        assertText("document.status", contains: "文件已產生")
        let filename = app.staticTexts["document.filename"].firstMatch
        XCTAssertTrue(filename.waitForExistence(timeout: 10))
        XCTAssertTrue(filename.label.hasSuffix(".csv"))
        capture("valid-source-export-after-invalid-source-dismissal")
    }

    private func launch() {
        app.launchArguments = ["-AppleLanguages", "(zh-Hant)", "-AppleLocale", "zh_TW", "-UITestMode",
                               "-UITestNamespace", namespace, "-UITestResetStorage", "-UITestMCPFixture", "-WoowSkipOnboarding"]
        app.launchEnvironment = [:]
        app.launch()
        XCTAssertTrue(app.staticTexts["uitest.banner"].firstMatch.waitForExistence(timeout: 15))
    }

    private func send(_ source: String, assistantIndex: Int = 1) {
        let draft = chatDraftControl(in: app)
        ready(draft); draft.tap(); draft.typeText(source)
        tap("chat.dismissKeyboard"); tap("chat.send")
        XCTAssertTrue(app.descendants(matching: .any)["chat.message.\(assistantIndex).assistant"].firstMatch.waitForExistence(timeout: 30))
        XCTAssertFalse(app.staticTexts["chat.error"].exists)
    }

    private func ready(_ element: XCUIElement) {
        XCTAssertTrue(element.waitForExistence(timeout: 10))
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"),
                                                                     object: element)], timeout: 10), .completed)
        XCTAssertTrue(element.isEnabled)
    }

    private func cancelSavePicker() {
        // Recent Files pickers can open inside a folder without a Cancel button
        // (native-5 screenshot/AX). Exercise their actual sheet dismissal, too.
        let bar = app.navigationBars["FullDocumentManagerViewControllerNavigationBar"].firstMatch
        ready(bar)
        // iOS 26.2 exposes the visible Save label without an identifier;
        // iOS 27 also supplies DOCPicker.actionButton. Scope both to Files.
        let save = bar.buttons.matching(NSPredicate(
            format: "identifier == %@ OR label IN %@", "DOCPicker.actionButton", ["儲存", "Save"])).firstMatch
        ready(save)
        let cancel = app.buttons.matching(NSPredicate(format: "label IN %@", ["取消", "Cancel"])).firstMatch
        if cancel.exists {
            ready(cancel); cancel.tap()
        } else {
            bar.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
                .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9)))
        }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"), object: save)], timeout: 10), .completed)
    }

    private func reveal(_ id: String) {
        let element = app.descendants(matching: .any)[id].firstMatch
        for _ in 0..<5 where !element.isHittable { app.swipeUp() }
    }

    private func tap(_ id: String, reveal shouldReveal: Bool = false) {
        if shouldReveal { reveal(id) }
        let button = app.buttons[id].firstMatch
        ready(button); button.tap()
    }

    private func assertText(_ id: String, contains text: String) {
        let element = app.staticTexts[id].firstMatch
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == true AND label CONTAINS %@", text), object: element)], timeout: 30), .completed)
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways
        add(attachment)
    }
}
