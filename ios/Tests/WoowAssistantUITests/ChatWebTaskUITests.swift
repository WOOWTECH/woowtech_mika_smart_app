import XCTest

/// Web tasks from chat on the native App path: a Debug website on 127.0.0.1
/// and the Debug model fixture (`-UITestChatWeb`), never an external site or
/// a model provider. The model is preconfigured for this namespace.
final class ChatWebTaskUITests: XCTestCase {
    private let app = XCUIApplication()
    private let namespace = UUID().uuidString
    override func setUpWithError() throws { continueAfterFailure = false; executionTimeAllowance = 240 }
    override func tearDownWithError() throws { app.terminate() }

    /// The 104 example now drives the browser: the task card shows steps and
    /// 停止, then the answer arrives with its sources and the card goes away.
    func testJobsExampleOpensPagesAndAnswersWithSources() {
        launch()
        let example = app.buttons["chat.emptyExample.web"]
        revealLearningElement(example, in: app)
        example.tap()
        tapSend()
        let card = app.descendants(matching: .any)["chat.web.card"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 30), "The task card replaces a text-only answer")
        XCTAssertTrue(app.buttons["chat.web.stop"].exists)
        let answer = app.staticTexts["chat.message.1.assistant"].firstMatch
        XCTAssertTrue(answer.waitForExistence(timeout: 120))
        XCTAssertTrue(answer.label.contains("WEB_TASK_JOBS_DONE"), answer.label)
        XCTAssertTrue(answer.label.contains("來源"), "Sources follow the answer")
        waitUntilGone(card, seconds: 10)
        XCTAssertEqual(chatDraftControl(in: app).value as? String ?? "", chatDraftControl(in: app).placeholderValue ?? "",
                       "The draft was sent and cleared")
    }

    /// 檢視過程 lists the steps with their pages.
    func testProcessSheetListsTheSteps() {
        launch()
        typeDraft("[fixture:web-stop]")
        tapSend()
        let card = app.descendants(matching: .any)["chat.web.card"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 30))
        let status = app.descendants(matching: .any)["chat.web.status"].firstMatch
        let read = NSPredicate(format: "label CONTAINS %@", "第 2 步")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: read, object: status)], timeout: 60), .completed)
        app.buttons["chat.web.viewProcess"].tap()
        let list = app.descendants(matching: .any)["chat.web.process"].firstMatch
        XCTAssertTrue(list.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "讀網頁")).firstMatch.exists)
        app.buttons["chat.web.process.done"].tap()
        app.buttons["chat.web.stop"].tap()
        XCTAssertTrue(app.staticTexts["chat.message.1.assistant"].firstMatch.waitForExistence(timeout: 30))
    }

    /// 停止 still writes the round into the conversation, like Android.
    func testStopWritesTheStoppedRound() {
        launch()
        typeDraft("[fixture:web-stop]")
        tapSend()
        let stop = app.buttons["chat.web.stop"]
        XCTAssertTrue(stop.waitForExistence(timeout: 30))
        let status = app.descendants(matching: .any)["chat.web.status"].firstMatch
        let read = NSPredicate(format: "label CONTAINS %@", "第 2 步")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: read, object: status)], timeout: 60), .completed)
        stop.tap()
        let answer = app.staticTexts["chat.message.1.assistant"].firstMatch
        XCTAssertTrue(answer.waitForExistence(timeout: 30))
        XCTAssertTrue(answer.label.hasPrefix("已停止。"), answer.label)
        XCTAssertTrue(answer.label.contains("已讀的頁面"))
        XCTAssertTrue(app.buttons["chat.send"].exists)
    }

    private func launch() {
        app.terminate()
        app.launchArguments = ["-AppleLanguages", "(zh-Hant)", "-AppleLocale", "zh_TW",
                               "-UITestMode", "-UITestNamespace", namespace, "-UITestResetStorage", "-UITestChatWeb"]
        app.launchEnvironment = [:]
        app.launch()
        XCTAssertTrue(app.staticTexts["uitest.banner"].firstMatch.waitForExistence(timeout: 15))
        XCTAssertTrue(chatDraftControl(in: app).waitForExistence(timeout: 15))
    }

    private func typeDraft(_ text: String) {
        let draft = chatDraftControl(in: app)
        draft.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        draft.typeText(text)
    }

    private func tapSend() {
        let send = app.buttons["chat.send"]
        XCTAssertTrue(send.waitForExistence(timeout: 5))
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: send)],
                                      timeout: 10), .completed)
        send.tap()
    }

    private func waitUntilGone(_ element: XCUIElement, seconds: TimeInterval) {
        let gone = NSPredicate(format: "exists == false")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: gone, object: element)], timeout: seconds), .completed)
    }
}
