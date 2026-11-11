import XCTest

/// Simulator-only synthetic files and in-process fake client; never a model service.
final class ChatAttachmentComposerUITests: XCTestCase {
    private let app = XCUIApplication()
    override func setUpWithError() throws {
        continueAfterFailure = false
        executionTimeAllowance = 180
        #if !targetEnvironment(simulator)
        throw XCTSkip("The isolated attachment fixture runs only on a simulator")
        #endif
    }
    override func tearDownWithError() throws { app.terminate() }

    func testMemoryRestrictionPreservesDraftAndAttachmentAcrossSections() {
        launch(); compose("[attachment-fixture:ok]")
        open(); tap("attachment.fixture.select")
        exists("chat.attachment.filename")
        exists("chat.attachment.hostIssue")
        XCTAssertFalse(app.buttons["chat.attachment.confirm"].exists)
        tap("chat.attachment.done")
        XCTAssertFalse(app.buttons["chat.send"].isEnabled)
        XCTAssertEqual(chatDraftControl(in: app).value as? String, "[attachment-fixture:ok]")
        disableMemory()
        tap("chat.attachment.review")
        exists("chat.attachment.filename")
        tap("chat.attachment.confirm"); exists("chat.attachment.confirmed")
        tap("chat.attachment.done"); tap("chat.send")
        assertLabel("chat.message.1.assistant", "ATTACHMENT_FIXTURE_RECEIVED_ONCE")
        XCTAssertFalse(app.buttons["chat.attachment.review"].exists)
    }

    func testMCPRestrictionIsVisibleAndKeepsDraft() {
        launch(); disableMemory(); tap("attachment.fixture.enableMCP"); compose("MCP draft")
        open(); tap("attachment.fixture.select"); exists("chat.attachment.filename")
        let issue = app.staticTexts["chat.attachment.hostIssue"].firstMatch
        XCTAssertTrue(issue.waitForExistence(timeout: 10)); XCTAssertTrue(issue.label.contains("MCP"))
        XCTAssertFalse(app.buttons["chat.attachment.confirm"].exists)
        tap("chat.attachment.done")
        XCTAssertEqual(chatDraftControl(in: app).value as? String, "MCP draft")
        let toggle = app.switches["chat.useMCP"].firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 10)); toggle.tap()
        tap("chat.attachment.review"); exists("chat.attachment.filename")
        tap("chat.attachment.confirm"); exists("chat.attachment.confirmed")
    }

    func testOversizeCancellationAndChangingDraftRequiresNewConfirmation() {
        launch(); disableMemory(); compose("initial question")
        open(); tap("attachment.fixture.oversize"); exists("chat.attachment.error")
        tap("attachment.fixture.select"); exists("chat.attachment.filename")
        tap("attachment.fixture.cancel"); exists("chat.attachment.filename")
        tap("chat.attachment.confirm"); exists("chat.attachment.confirmed")
        tap("chat.attachment.done")
        let field = chatDraftControl(in: app)
        field.tap(); field.typeText(" changed")
        tap("chat.dismissKeyboard")
        XCTAssertFalse(app.buttons["chat.send"].isEnabled)
        tap("chat.attachment.review")
        XCTAssertFalse(app.staticTexts["chat.attachment.confirmed"].exists)
        tap("chat.attachment.confirm"); exists("chat.attachment.confirmed")
    }

    func testSystemPickerCancellationKeepsSyntheticSelection() {
        launch(); disableMemory(); compose("Keep selected attachment")
        open(); tap("attachment.fixture.select"); exists("chat.attachment.filename")
        tap("chat.attachment.select")
        let cancel = app.buttons.matching(NSPredicate(format: "label IN %@", ["Cancel", "取消"])).firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 15), "The native document picker must be presented")
        cancel.tap()
        exists("chat.attachment.filename")
        XCTAssertFalse(app.staticTexts["chat.attachment.error"].exists)
    }

    func testFailedReplacementCannotReconfirmPreviousFileAfterDraftEdit() {
        launch(); disableMemory(); compose("Original draft")
        open(); tap("attachment.fixture.select"); exists("chat.attachment.filename")
        tap("chat.attachment.confirm"); exists("chat.attachment.confirmed")
        tap("attachment.fixture.failReplacement"); exists("chat.attachment.selectionRetry")
        XCTAssertFalse(app.buttons["chat.attachment.confirm"].exists)
        tap("chat.attachment.done")
        let field = chatDraftControl(in: app)
        field.tap(); field.typeText(" changed"); tap("chat.dismissKeyboard")
        tap("chat.attachment.review"); exists("chat.attachment.selectionRetry")
        XCTAssertFalse(app.buttons["chat.attachment.confirm"].exists)
        tap("chat.attachment.done")
        XCTAssertFalse(app.buttons["chat.send"].isEnabled)
        XCTAssertEqual(field.value as? String, "Original draft changed")
        tap("chat.attachment.removeInline")
        XCTAssertTrue(app.buttons["chat.send"].isEnabled)
    }

    func testFailureAndCancellationKeepDraftAndRequireReselection() {
        for prompt in ["[attachment-fixture:fail]", "[attachment-fixture:wait]"] {
            launch(); disableMemory(); compose(prompt)
            open(); tap("attachment.fixture.select"); exists("chat.attachment.filename")
            tap("chat.attachment.confirm"); tap("chat.attachment.done"); tap("chat.send")
            if prompt.hasSuffix("wait]") { tap("chat.cancel") }
            exists("chat.attachment.issue")
            XCTAssertEqual(chatDraftControl(in: app).value as? String, prompt)
            XCTAssertFalse(app.buttons["chat.send"].isEnabled)
            XCTAssertFalse(app.descendants(matching: .any)["chat.message.0.user"].exists)
            tap("chat.attachment.removeInline")
            XCTAssertTrue(app.buttons["chat.send"].isEnabled)
        }
    }

    func testNewConversationRequiresExplicitRemoval() {
        launch(); disableMemory(); compose("Keep draft")
        open(); tap("attachment.fixture.select"); exists("chat.attachment.filename")
        tap("chat.attachment.done"); tap("chat.newConversation")
        exists("chat.attachment.issue")
        XCTAssertEqual(chatDraftControl(in: app).value as? String, "Keep draft")
        XCTAssertTrue(app.buttons["chat.attachment.review"].exists)
    }

    func testLocalizedAccessibleAttachmentEntryAndLimits() {
        let cases = [("(zh-Hant)", "加入圖片或文字附件", "檔案超過大小限制。"),
                     ("(zh-Hans)", "添加图片或文字附件", "文件超过大小限制。"),
                     ("(en)", "Add image or text attachment", "The file exceeds the size limit.")]
        for (language, label, errorText) in cases {
            launch(language: language)
            let entry = app.buttons["chat.attachment.open"].firstMatch
            XCTAssertTrue(entry.waitForExistence(timeout: 10))
            XCTAssertEqual(entry.label, label)
            entry.tap(); tap("attachment.fixture.oversize")
            let error = app.staticTexts["chat.attachment.error"].firstMatch
            XCTAssertTrue(error.waitForExistence(timeout: 10))
            XCTAssertEqual(error.label, errorText)
            XCTAssertTrue(app.buttons["chat.attachment.select"].exists)
        }
    }

    private func launch(language: String = "(zh-Hant)") {
        app.terminate()
        app.launchArguments = ["-AppleLanguages", language, "-AppleLocale", "zh_TW", "-UITestMode",
                               "-UITestNamespace", UUID().uuidString, "-UITestResetStorage",
                               "-UITestAttachmentComposer"]
        app.launchEnvironment = [:]; app.launch()
        exists("chat.status")
    }
    private func open() { tap("chat.attachment.open") }
    private func compose(_ value: String) {
        let field = chatDraftControl(in: app)
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap(); field.typeText(value); tap("chat.dismissKeyboard")
        XCTAssertEqual(field.value as? String, value)
    }
    private func disableMemory() {
        navigateMikaSection("memory", in: app)
        let toggle = app.switches["memory.toggle.useMemory"].firstMatch
        revealLearningElement(toggle, in: app)
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        if toggle.value as? String == "1" {
            let native = toggle.switches.firstMatch
            (native.exists ? native : toggle).tap()
        }
        let off = NSPredicate(format: "value == %@", "0")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: off, object: toggle)], timeout: 10), .completed)
        navigateMikaSection("chat", in: app)
    }
    private func tap(_ id: String) {
        let element = app.buttons[id].firstMatch
        XCTAssertTrue(element.waitForExistence(timeout: 10), id)
        for _ in 0..<4 where !element.isHittable { app.swipeUp() }
        for _ in 0..<4 where !element.isHittable { app.swipeDown() }
        XCTAssertTrue(element.isHittable, id)
        element.tap()
    }
    private func exists(_ id: String) {
        XCTAssertTrue(app.descendants(matching: .any)[id].firstMatch.waitForExistence(timeout: 15), id)
    }
    private func assertLabel(_ id: String, _ value: String) {
        let element = app.descendants(matching: .any)[id].firstMatch
        let predicate = NSPredicate(format: "label == %@", value)
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: 15), .completed)
    }
}
