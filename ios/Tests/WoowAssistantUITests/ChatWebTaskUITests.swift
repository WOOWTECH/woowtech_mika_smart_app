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
        // An empty field reports "" on iOS 18.5 and its placeholder on iOS 26.
        let draft = chatDraftControl(in: app), value = draft.value as? String ?? ""
        XCTAssertTrue(value.isEmpty || value == draft.placeholderValue, "The draft was sent and cleared")
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
        XCTAssertTrue(answer.label.contains("FIXTURE_STOP_SUMMARY"), "The model's short account follows 已停止。")
        XCTAssertTrue(answer.label.contains("已讀的頁面"))
        XCTAssertTrue(app.buttons["chat.send"].exists)
    }

    /// Ordering waits on the card's 允許這一次 for that one step (Android's
    /// confirmation card); the order then goes through and paying is left to the user.
    func testOrderWaitsForAllowThisOnce() {
        launch()
        typeDraft("[fixture:web-order]")
        tapSend()
        let allow = app.buttons["chat.web.consent.allow"]
        XCTAssertTrue(allow.waitForExistence(timeout: 60))
        // Like Play's card: the kind of step, then where, the button, what it sends and the amount.
        XCTAssertEqual(app.staticTexts["chat.web.consent.title"].firstMatch.label, "要你同意：下單")
        let detail = app.staticTexts["chat.web.consent.detail"].firstMatch.label
        XCTAssertTrue(detail.hasPrefix("在 ") && detail.contains("目標：送出訂單") && detail.contains("內容：無線耳機 1 副")
                      && detail.contains("金額：NT$ 1,290"), detail)
        XCTAssertTrue(app.staticTexts["花錢的操作每次都要你同意。"].exists)
        allow.tap()
        let answer = app.staticTexts["chat.message.1.assistant"].firstMatch
        XCTAssertTrue(answer.waitForExistence(timeout: 60))
        XCTAssertTrue(answer.label.contains("WEB_TASK_ORDER_DONE"), answer.label)
    }

    /// 拒絕 keeps the order unsent.
    func testRefusingTheOrderSendsNothing() {
        launch()
        typeDraft("[fixture:web-order]")
        tapSend()
        let refuse = app.buttons["chat.web.consent.refuse"]
        XCTAssertTrue(refuse.waitForExistence(timeout: 60))
        refuse.tap()
        let answer = app.staticTexts["chat.message.1.assistant"].firstMatch
        XCTAssertTrue(answer.waitForExistence(timeout: 60))
        XCTAssertTrue(answer.label.contains("WEB_TASK_ORDER_REFUSED"), answer.label)
    }

    /// 我來處理 gives the page to the user with 渥屋助理在等你：登入; 處理好了
    /// hands it back and the task goes on.
    func testSignInIsHandedToTheUserAndBack() {
        launch()
        typeDraft("[fixture:web-login]")
        tapSend()
        let takeOver = app.buttons["chat.web.takeOver"]
        XCTAssertTrue(takeOver.waitForExistence(timeout: 60))
        XCTAssertTrue(app.staticTexts["chat.web.handover.title"].firstMatch.label.contains("登入"))
        takeOver.tap()
        let waiting = app.staticTexts["chat.web.waitingOnYou"].firstMatch
        XCTAssertTrue(waiting.waitForExistence(timeout: 10))
        XCTAssertEqual(waiting.label, "渥屋助理在等你：登入")
        app.buttons["chat.web.expanded.handBack"].tap()
        let answer = app.staticTexts["chat.message.1.assistant"].firstMatch
        XCTAssertTrue(answer.waitForExistence(timeout: 60))
        XCTAssertTrue(answer.label.contains("WEB_TASK_LOGIN_DONE"), answer.label)
    }

    /// 需要你回答: a choice goes back to the task.
    func testQuestionChoiceReachesTheTask() {
        launch()
        typeDraft("[fixture:web-ask]")
        tapSend()
        let option = app.buttons["chat.web.question.option.1"]
        XCTAssertTrue(option.waitForExistence(timeout: 60))
        XCTAssertEqual(app.staticTexts["chat.web.question.prompt"].firstMatch.label, "要找哪個城市的職缺？")
        option.tap()
        let answer = app.staticTexts["chat.message.1.assistant"].firstMatch
        XCTAssertTrue(answer.waitForExistence(timeout: 60))
        XCTAssertTrue(answer.label.hasPrefix("WEB_TASK_ASK_DONE：台中"), answer.label)
    }

    private func launch() {
        app.terminate()
        app.launchArguments = ["-AppleLanguages", "(zh-Hant)", "-AppleLocale", "zh_TW",
                               "-UITestMode", "-UITestNamespace", namespace, "-UITestResetStorage", "-UITestChatWeb", "-WoowSkipOnboarding"]
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
