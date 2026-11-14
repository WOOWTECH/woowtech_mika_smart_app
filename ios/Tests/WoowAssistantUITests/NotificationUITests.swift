import XCTest

/// Play's notification page with real authorization, the native
/// test-notification banner, iOS Settings and preference persistence in an
/// isolated simulator. Audible sound still needs a person.
final class NotificationUITests: XCTestCase {
    private let app = XCUIApplication()
    private let namespace = UUID().uuidString
    private var observedBannerCandidate: String?

    override func setUpWithError() throws {
        continueAfterFailure = false
        // Three launches, a system banner and a round trip to iOS Settings.
        executionTimeAllowance = 300
    }

    override func tearDownWithError() throws {
        if let testRun, testRun.failureCount > 0 {
            if let observedBannerCandidate {
                let candidate = XCTAttachment(string: observedBannerCandidate)
                candidate.name = "Observed bounded system banner candidate (diagnostic only)"
                candidate.lifetime = .keepAlways; add(candidate)
            }
            let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
            for (name, application) in [("App at failure", app), ("System at failure", springboard)] {
                let screenshot = XCTAttachment(screenshot: application.screenshot())
                screenshot.name = name; screenshot.lifetime = .keepAlways; add(screenshot)
            }
        }
        app.terminate()
    }

    func testExplicitAllowSurvivesRelaunchAndAnAppOptOutTurnsBackOnWithoutAPrompt() throws {
        launch(reset: true)
        try openSettings()
        // Like the Play page: off by default, so the master switch offers 去開啟
        // and both kinds read 已關閉.
        try assertMaster(allowed: false)
        try assertKinds("已關閉")
        let before = try authorization()
        // Permission belongs to the simulator's App, not a UserDefaults suite.
        // Do not invent a private resetAuthorizationStatus raw value.
        XCTAssertTrue(["notDetermined", "authorized"].contains(before),
                      "The banner case requires full authorization; provisional or denied states are separate cases.")
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        XCTAssertFalse(springboard.alerts.firstMatch.exists, "Opening settings must not ask for permission.")
        try tap(app.buttons["notifications.enabled"])

        var promptObserved = false
        if before == "notDetermined" {
            let alert = springboard.alerts.firstMatch
            XCTAssertTrue(alert.waitForExistence(timeout: 15), "去開啟 must show the actual system prompt.")
            let snapshot = try alert.snapshot()
            var labels: [String] = []
            func visit(_ node: XCUIElementSnapshot) {
                labels.append(node.label)
                node.children.forEach(visit)
            }
            visit(snapshot)
            let text = labels.joined(separator: " ")
            XCTAssertTrue(text.contains("渥屋助理") || text.contains("WoowAssistant"))
            XCTAssertTrue(text.contains("通知") || text.localizedCaseInsensitiveContains("notifications"),
                          "Only this App's notification prompt may be accepted.")
            let allow = alert.buttons.matching(NSPredicate(format: "label IN %@", ["Allow", "允許", "允许"])).firstMatch
            try tap(allow, scroll: false)
            promptObserved = true
        }
        try wait("The master switch and the actual system grant must both be ready.", seconds: 15) {
            self.master.value as? String == "已允許"
                && self.app.staticTexts["notifications.authorization"].value as? String == "authorized"
        }
        let granted = try authorization()
        XCTAssertEqual(granted, "authorized")
        try assertMaster(allowed: true)
        // One App-level iOS setting: with banners on, both kinds pop up.
        try assertKinds("會彈出")
        print("NOTIFICATION_SETTINGS enabled=1 systemPromptObserved=\(promptObserved ? 1 : 0)")

        // The explicit test action uses the production UN adapter. Require a
        // new actual system banner, not a scheduling receipt inside the App.
        XCTAssertNil(notificationBanner(in: springboard))
        try tap(app.buttons["notifications.test"])
        var observedBanner: SystemBanner?
        try wait("The system must actually display the fixed test notification.", seconds: 15) {
            observedBanner = self.notificationBanner(in: springboard)
            return observedBanner != nil
        }
        guard let banner = observedBanner else { throw Failure.readiness }
        let screenshot = XCTAttachment(screenshot: springboard.screenshot())
        screenshot.name = "Actual notification banner before opening"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        let subtree = XCTAttachment(string: banner.labels.joined(separator: "\n"))
        subtree.name = "Matching system banner subtree"
        subtree.lifetime = .keepAlways
        add(subtree)
        print("NOTIFICATION_SETTINGS actualSystemBanner=1 audibleSoundVerified=0")

        // Open from a pushed Settings screen. The root must actually pop that
        // screen, not merely change the selected section underneath it.
        springboard.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: banner.frame.midX, dy: banner.frame.midY)).tap()
        try wait("Opening the notification must reveal the root conversation.", seconds: 10) {
            self.app.state == .runningForeground
                && self.app.staticTexts["chat.status"].exists
                && !self.app.navigationBars["通知"].exists
                && self.app.buttons["chat.menu"].exists
                && !self.app.descendants(matching: .any)["drawer.panel"].exists
        }
        print("NOTIFICATION_SETTINGS actualBannerTap=1 rootChatVisible=1")

        app.terminate()
        launch(reset: false)
        try openSettings()
        try assertMaster(allowed: true)
        XCTAssertEqual(try authorization(), granted)
        // Like Play's channel rows, a kind opens where iOS changes it. Coming
        // back refreshes the page; there is no refresh button any more.
        try tap(app.buttons["notifications.attention"])
        let systemSettings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        XCTAssertTrue(systemSettings.wait(for: .runningForeground, timeout: 15),
                      "需要你處理 must open the App's notification settings in iOS Settings.")
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        try assertMaster(allowed: true)
        try assertKinds("會彈出")
        systemSettings.terminate()
        print("NOTIFICATION_SETTINGS relaunchEnabled=1 kindOpensSystemSettings=1")

        // An App opt-out saved by an earlier build: the preference is cleared
        // while iOS still allows notifications. 去開啟 turns them back on
        // without asking again, so nobody is stuck with them off.
        app.terminate()
        launch(reset: true)
        try openSettings()
        try assertMaster(allowed: false)
        try assertKinds("已關閉")
        XCTAssertEqual(try authorization(), granted)
        try tap(app.buttons["notifications.enabled"])
        try wait("去開啟 must turn the notifications back on.", seconds: 10) {
            self.master.value as? String == "已允許"
        }
        XCTAssertFalse(springboard.alerts.firstMatch.exists, "iOS already allows them: no second prompt.")
        try assertMaster(allowed: true)
        try assertKinds("會彈出")
        XCTAssertEqual(try authorization(), granted)
        print("NOTIFICATION_SETTINGS appOptOutTurnedBackOn=1 systemPermissionRetained=1")
    }

    private func launch(reset: Bool) {
        app.launchArguments = ["-AppleLanguages", "(zh-Hant)", "-AppleLocale", "zh_TW",
                               "-UITestMode", "-UITestNamespace", namespace, "-WoowSkipOnboarding"]
        if reset { app.launchArguments.append("-UITestResetStorage") }
        app.launchEnvironment = [:]
        app.launch()
        XCTAssertTrue(app.staticTexts["chat.status"].waitForExistence(timeout: 15))
    }

    private func openSettings() throws {
        navigateMikaSection("settings", in: app)
        let entry = app.buttons["settings.notifications"]
        revealLearningElement(entry, in: app)
        try tap(entry)
        XCTAssertTrue(master.waitForExistence(timeout: 10))
    }

    /// Play's 通知總開關: a button with 去開啟 only while notifications cannot
    /// be delivered; 已允許 otherwise.
    private var master: XCUIElement { app.descendants(matching: .any)["notifications.enabled"].firstMatch }

    private func assertMaster(allowed: Bool) throws {
        let master = self.master
        try wait("The master switch must show the actual state.", seconds: 10) {
            master.exists && master.value as? String == (allowed ? "已允許" : "去開啟")
        }
        XCTAssertTrue(master.label.hasPrefix("通知總開關"), master.label)
        if allowed {
            XCTAssertTrue(master.label.contains("允許渥屋助理發通知") && !master.label.contains("不允許"), master.label)
        } else {
            XCTAssertTrue(master.label.contains("現在不允許渥屋助理發通知"), master.label)
        }
        XCTAssertEqual(app.buttons["notifications.enabled"].exists, !allowed,
                       "Like Play, only a master switch that is off can be tapped.")
    }

    /// iOS has one notification setting for the App, so both kinds always
    /// show the same state.
    private func assertKinds(_ state: String) throws {
        for (identifier, title) in [("notifications.attention", "需要你處理"), ("notifications.result", "任務結果")] {
            let row = app.buttons[identifier]
            try wait("Both kinds must show the App-level state.", seconds: 10) {
                row.exists && row.value as? String == state
            }
            XCTAssertTrue(row.label.hasPrefix(title), row.label)
        }
    }

    /// The raw iOS authorization, exposed for UI tests only.
    private func authorization() throws -> String {
        let value = app.staticTexts["notifications.authorization"]
        if !value.exists { revealLearningElement(value, in: app, visibility: .readableText) }
        try wait("Actual system authorization must finish refreshing.", seconds: 10) {
            guard value.exists, let raw = value.value as? String else { return false }
            return ["notDetermined", "denied", "authorized", "provisional", "ephemeral"].contains(raw)
        }
        return value.value as? String ?? "unknown"
    }

    private struct SystemBanner { let frame: CGRect; let labels: [String] }

    private func notificationBanner(in springboard: XCUIApplication) -> SystemBanner? {
        guard let snapshot = try? springboard.snapshot(), !snapshot.frame.isEmpty else { return nil }
        var smallest: SystemBanner?
        @discardableResult func visit(_ node: XCUIElementSnapshot) -> [String] {
            let visible = !node.frame.isEmpty && node.frame.intersects(snapshot.frame)
            var labels = visible && !node.label.isEmpty ? [node.label] : []
            for child in node.children { labels += visit(child) }
            let bounded = visible && node.elementType != .application && node.elementType != .window
                && node.frame.height < snapshot.frame.height * 0.5
            if bounded, observedBannerCandidate == nil,
               labels.contains(where: { $0.contains("通知測試") }),
               labels.contains(where: { $0.contains("這是渥屋助理的測試通知。") }) {
                // Retain the first transient candidate even if exact matching
                // fails and the OS removes the banner before tearDown runs.
                observedBannerCandidate = "frame=\(node.frame); identifier=\(node.identifier)\n"
                    + labels.prefix(20).map { String($0.prefix(500)) }.joined(separator: "\n")
            }
            // iOS 18's compact short look shows an App icon, not App-name text.
            // Match exact fields in one bounded system subtree. The subsequent
            // actual tap must open this App's root Chat to establish attribution.
            if bounded,
               hasExactField("通知測試", in: labels),
               hasExactField("這是渥屋助理的測試通知。", in: labels) {
                if smallest == nil || node.frame.width * node.frame.height
                    < smallest!.frame.width * smallest!.frame.height {
                    smallest = SystemBanner(frame: node.frame, labels: labels)
                }
            }
            return labels
        }
        visit(snapshot)
        return smallest
    }

    // AX may expose separate labels or combine fields in one announcement.
    // Match a complete field, never a substring inside unrelated body text.
    private func hasExactField(_ expected: String, in labels: [String]) -> Bool {
        labels.contains { label in
            label == expected || label.components(separatedBy: CharacterSet(charactersIn: ",\n"))
                .contains { $0.trimmingCharacters(in: .whitespacesAndNewlines) == expected }
        }
    }

    private func tap(_ element: XCUIElement, scroll: Bool = true) throws {
        if scroll && !element.isHittable { revealLearningElement(element, in: app) }
        try wait("The exact native control must be hittable.", seconds: 5) { element.isHittable }
        XCTAssertTrue(element.exists)
        XCTAssertTrue(element.isEnabled)
        XCTAssertFalse(element.frame.isEmpty)
        element.tap()
    }

    private func wait(_ message: String, seconds: TimeInterval, condition: @escaping () -> Bool) throws {
        if condition() { return }
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)
        guard XCTWaiter.wait(for: [expectation], timeout: seconds) == .completed else {
            XCTFail(message)
            throw Failure.readiness
        }
    }

    private enum Failure: Error { case readiness }
}
