import Foundation

/// The store build's first launch (Android Onboarding.kt): the welcome page,
/// then the model setup. It starts only while there is no main model and the
/// setup was never finished, so whoever already chose a model never sees it.
enum Onboarding {
    /// Android ProgressDots: 歡迎 and 設定模型.
    static let steps = 2

    /// Android Onboarding.start for the store build, which has no phone step.
    static func starts(hasMainModel: Bool, modelSetupDone: Bool) -> Bool {
        !hasMainModel && !modelSetupDone
    }

    /// UI tests that start from the chat pass -WoowSkipOnboarding (Debug
    /// builds only). It is not a -UITest flag, which the fixtures that accept
    /// only their own -UITest arguments would refuse.
    static var skippedForUITests: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-WoowSkipOnboarding")
        #else
        return false
        #endif
    }
}

/// Android OnboardingState: whether the first launch's model setup was
/// finished (下一步; 稍後再說 is not), kept in the App's own defaults. A UI
/// test (Debug only) keeps it in its namespace and clears it with the rest of
/// that namespace.
struct OnboardingState {
    static let modelSetupDoneKey = "onboarding.modelSetupDone.v1"
    private let defaults: UserDefaults

    init(defaults: UserDefaults) { self.defaults = defaults }

    var modelSetupDone: Bool { defaults.bool(forKey: Self.modelSetupDoneKey) }

    func markModelSetupDone() { defaults.set(true, forKey: Self.modelSetupDoneKey) }

    /// This launch's state, resolved once, so a test's reset runs once.
    static let application = resolve(arguments: ProcessInfo.processInfo.arguments)

    /// Nil for a UI test launch without one valid namespace: the flow then
    /// never starts, and the user's own defaults are never read or written.
    static func resolve(arguments: [String]) -> OnboardingState? {
        #if DEBUG
        guard arguments.contains(where: { $0.hasPrefix("-UITest") || $0.hasPrefix("-Live") }) else {
            return OnboardingState(defaults: .standard)
        }
        let modes = [("-UITestMode", "-UITestNamespace"), ("-LiveModelUITest", "-LiveModelUITestNamespace")]
        let selected = modes.filter { arguments.contains($0.0) }
        guard selected.count == 1, let mode = selected.first,
              arguments.filter({ $0 == mode.1 }).count == 1,
              let index = arguments.firstIndex(of: mode.1), arguments.indices.contains(index + 1),
              let namespace = UUID(uuidString: arguments[index + 1]) else { return nil }
        let suite = "io.woowtech.assistant.onboarding.v1.test." + namespace.uuidString
        guard let defaults = UserDefaults(suiteName: suite) else { return nil }
        if arguments.contains("-UITestResetStorage") || arguments.contains("-LiveModelUITestCleanup") {
            defaults.removePersistentDomain(forName: suite)
        }
        return OnboardingState(defaults: defaults)
        #else
        return OnboardingState(defaults: .standard)
        #endif
    }
}
