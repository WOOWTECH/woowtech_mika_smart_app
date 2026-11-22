import Combine
import Foundation
import UIKit
import XCTest
@testable import WoowAssistant

/// Own-center notifications exercise the real publisher without sending fake
/// keyboard events to the hosted app or relying on a window/keyboard fixture.
@MainActor
final class ChatKeyboardDockIntegrationTests: XCTestCase {
    func testDurationOnlyKeyboardNotificationUpdatesTimingWithoutPublishing() {
        let center = NotificationCenter()
        let dock = ChatKeyboardDock(notificationCenter: center)
        var publications = 0
        let observation = dock.objectWillChange.sink { publications += 1 }
        defer { observation.cancel() }

        let duration = 0.4
        XCTAssertNotEqual(dock.animationDuration, duration)
        XCTAssertNil(dock.frameInWindow)
        center.post(name: UIResponder.keyboardWillHideNotification, object: nil,
                    userInfo: [UIResponder.keyboardAnimationDurationUserInfoKey: NSNumber(value: duration)])

        XCTAssertEqual(dock.animationDuration, duration, "The real notification must update timing synchronously")
        XCTAssertNil(dock.frameInWindow, "A duration-only hide notification must leave reserved space unchanged")
        XCTAssertEqual(publications, 0, "Timing alone must not publish a SwiftUI layout update")
    }
}
