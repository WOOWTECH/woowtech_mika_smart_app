import SwiftUI
import UIKit

@main
struct WoowAssistantApp: App {
    @UIApplicationDelegateAdaptor(TaskNotificationAppDelegate.self) private var notificationDelegate
    #if DEBUG && targetEnvironment(simulator)
    /// Explicit, isolated simulator fixture. Release and ordinary launches use
    /// the system's unmodified Dynamic Type setting.
    private static var accessibilitySizeFixtureEnabled: Bool {
        let args = ProcessInfo.processInfo.arguments
        let flag = "-UITestChatAccessibilitySize"
        guard args.filter({ $0 == flag }).count == 1,
              args.filter({ $0 == "-UITestMode" }).count == 1,
              args.filter({ $0 == "-UITestNamespace" }).count == 1,
              !args.contains(where: { $0.hasPrefix("-Live") }),
              let index = args.firstIndex(of: "-UITestNamespace"), args.indices.contains(index + 1),
              let id = UUID(uuidString: args[index + 1]),
              id.uuidString.lowercased() == args[index + 1].lowercased() else { return false }
        return true
    }

    /// UI-test launches only. After each action XCUITest waits up to 60 s for the
    /// App's animations to finish and on CI intermittently never hears that they
    /// did (first context-menu press, the keyboard's suggestion bar, page find),
    /// which pushed whole cases past their time allowance.
    private static let uiTestAnimationsDisabled =
        ProcessInfo.processInfo.arguments.filter({ $0 == "-UITestMode" }).count == 1

    init() {
        if Self.uiTestAnimationsDisabled { UIView.setAnimationsEnabled(false) }
    }
    #endif
    var body: some Scene {
        WindowGroup {
            Group {
                #if DEBUG && targetEnvironment(simulator)
                if Self.accessibilitySizeFixtureEnabled {
                    ContentView().dynamicTypeSize(.accessibility5)
                } else {
                    ContentView()
                }
                #else
                ContentView()
                #endif
            }
            #if DEBUG && targetEnvironment(simulator)
            .transaction { transaction in
                guard Self.uiTestAnimationsDisabled else { return }
                transaction.animation = nil
                transaction.disablesAnimations = true
            }
            #endif
        }
    }
}
