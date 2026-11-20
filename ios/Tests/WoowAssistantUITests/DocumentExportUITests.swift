import XCTest

/// Native document UI, real renderers and system dialogs. Only the source reply
/// uses the isolated model fixture; no commercial/provider acceptance is implied.
final class DocumentExportUITests: XCTestCase {
    private let app = XCUIApplication()
    private let namespace = UUID().uuidString
    override func setUpWithError() throws { continueAfterFailure = false; executionTimeAllowance = 240 }
    override func tearDownWithError() throws { app.terminate() }

    func testSelectedAnswerCSVPreviewAndSaveCancellation() {
        launch()
        send("Report\n\n| Item | Value |\n| --- | --- |\n| Formula | =1+1 |\n| Code | 00123 |")
        let reply = app.descendants(matching: .any)["chat.message.1.assistant"].firstMatch
        ready(reply); reply.press(forDuration: 1)
        tap("chat.messageMenu.document")
        let csv = app.segmentedControls["document.format"].buttons["CSV"]
        ready(csv); csv.tap()
        tap("document.generate")
        assertText("document.status", contains: "File created")
        reveal("document.protectedCells")
        assertText("document.protectedCells", contains: "1 cells")
        tap("document.preview", reveal: true)
        let content = app.descendants(matching: .any)["document.preview.content"].firstMatch
        XCTAssertTrue(content.waitForExistence(timeout: 10))
        XCTAssertTrue((app.textViews["document.csv.content"].value as? String ?? "").contains("'=1+1"))
        tap("document.preview.done")
        tap("document.save", reveal: true)
        let cancel = app.buttons["Cancel"].firstMatch
        ready(cancel); cancel.tap()
        assertText("document.status", contains: "cancelled")
        XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "File exported")).firstMatch.exists)
        capture("csv-save-cancelled")
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
        assertText("document.status", contains: "File created")
        tap("document.preview", reveal: true)
        XCTAssertTrue(app.descendants(matching: .any)["document.preview.content"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Unable to preview the document. Close the preview and try again."].exists)
        capture("pdf-preview")
        tap("document.preview.done")
        tap("document.done")
        XCTAssertEqual(draft.value as? String, "export the previous answer as PDF", "The local operation must not lose the draft")
        XCTAssertFalse(app.descendants(matching: .any)["chat.message.2.user"].firstMatch.exists,
                       "A confirmed local export does not issue a new model request")
    }

    private func launch() {
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-UITestMode",
                               "-UITestNamespace", namespace, "-UITestResetStorage", "-UITestMCPFixture", "-WoowSkipOnboarding"]
        app.launchEnvironment = [:]
        app.launch()
        XCTAssertTrue(app.staticTexts["uitest.banner"].firstMatch.waitForExistence(timeout: 15))
    }

    private func send(_ source: String) {
        let draft = chatDraftControl(in: app)
        ready(draft); draft.tap(); draft.typeText(source)
        tap("chat.dismissKeyboard"); tap("chat.send")
        XCTAssertTrue(app.descendants(matching: .any)["chat.message.1.assistant"].firstMatch.waitForExistence(timeout: 30))
        XCTAssertFalse(app.staticTexts["chat.error"].exists)
    }

    private func ready(_ element: XCUIElement) {
        XCTAssertTrue(element.waitForExistence(timeout: 10))
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"),
                                                                     object: element)], timeout: 10), .completed)
        XCTAssertTrue(element.isEnabled)
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
