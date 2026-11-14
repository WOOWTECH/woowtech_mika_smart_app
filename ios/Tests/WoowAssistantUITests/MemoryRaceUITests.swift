import XCTest

/// Deterministic production-App race regressions. Only the model transport is a
/// DEBUG fixture; persistence, state generations and UI are the real components.
final class MemoryRaceUITests: XCTestCase {
    func testClearWhileReplyPendingPublishesWithoutRepopulatingAndNewChatHidesOldNotes() {
        continueAfterFailure = false
        executionTimeAllowance = 240
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hant)", "-AppleLocale", "zh_TW",
                               "-UITestMode", "-UITestNamespace", UUID().uuidString, "-UITestResetStorage"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.staticTexts["chat.status"].waitForExistence(timeout: 10))
        navigateMikaSection("settings", in: app)
        openModelSettings(in: app)
        fill(app.textFields["settings.baseURL"], "https://model.example.invalid/v1\n")
        reveal(app.textFields["settings.model"], in: app)
        fill(app.textFields["settings.model"], "fixture-model\n")
        reveal(app.secureTextFields["settings.apiKey"], in: app)
        fill(app.secureTextFields["settings.apiKey"], "fixture-key-not-real\n")
        reveal(app.buttons["setup.test"], in: app)
        app.buttons["setup.test"].tap()
        agreeToModelConsent(in: app)
        XCTAssertTrue(app.staticTexts["settings.notice"].waitForExistence(timeout: 5))
        returnFromModelSettings(in: app)
        navigateMikaSection("chat", in: app)
        send("[fixture:remember-after-delay] 我喜歡喝茶", in: app)
        navigateMikaSection("memory", in: app)
        let clear = app.buttons["memory.clear"]
        reveal(clear, in: app); clear.tap()
        XCTAssertTrue(app.staticTexts["memory.clear.stage"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["memory.clear.continue"].waitForExistence(timeout: 5))
        app.buttons["memory.clear.continue"].tap()
        XCTAssertTrue(app.buttons["memory.clear.confirm"].waitForExistence(timeout: 5))
        app.buttons["memory.clear.confirm"].tap()
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.buttons["memory.clear.confirm"])
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 5), .completed)
        navigateMikaSection("chat", in: app)
        // Prove the clear happened before the main reply, not after extraction.
        XCTAssertEqual(app.staticTexts["chat.status"].label, "正在處理")
        // Like the Play build, the clear never stops the pending reply; only its
        // extraction is skipped, so the old message cannot refill cleared memory.
        let reply = app.staticTexts["chat.message.1.assistant"]
        XCTAssertTrue(reply.waitForExistence(timeout: 65))
        XCTAssertTrue(reply.label.hasPrefix("測試回覆："))
        XCTAssertFalse(app.staticTexts["chat.error"].exists)
        XCTAssertFalse(app.staticTexts["chat.learning"].exists)
        XCTAssertFalse(app.staticTexts["chat.memoryNote.0"].exists)
        navigateMikaSection("memory", in: app)
        XCTAssertTrue(app.staticTexts["memory.empty"].waitForExistence(timeout: 5))

        navigateMikaSection("chat", in: app)
        send("[fixture:remember] 我喜歡喝茶", in: app)
        XCTAssertTrue(app.staticTexts["chat.memoryNote.0"].waitForExistence(timeout: 10))
        app.buttons["chat.newConversation"].tap()
        XCTAssertFalse(app.staticTexts["chat.memoryNote.0"].exists)
        XCTAssertFalse(app.buttons["chat.undoMemory.0"].exists)
        navigateMikaSection("memory", in: app)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
                                                          "memory.item.", "喝茶")).firstMatch.exists)
    }

    private func send(_ text: String, in app: XCUIApplication) {
        fill(chatDraftControl(in: app), text)
        app.buttons["chat.dismissKeyboard"].tap()
        app.buttons["chat.send"].tap()
    }
    private func fill(_ field: XCUIElement, _ text: String) {
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND hittable == true"), object: field)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 5), .completed)
        field.tap(); field.typeText(text)
    }
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        revealLearningElement(element, in: app)
    }
}
