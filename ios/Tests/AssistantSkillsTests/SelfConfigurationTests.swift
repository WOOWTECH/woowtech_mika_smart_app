#if !SKILL_EXECUTION_SMOKE && !SKILLS_CORE_SMOKE
import Combine
import Foundation
@testable import AssistantSkills
#if !SELF_CONFIGURATION_SMOKE
import XCTest
#endif

/// Settings › 語言與外觀 keeps the appearance in its own defaults suite. Only the
/// user changes it; as on the Play build, no model tool or permission can.
@MainActor enum SelfConfigurationChecks {
    struct Failure: Error, LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }
    @MainActor final class Scope {
        let name = "SelfConfigurationTests." + UUID().uuidString
        let defaults: UserDefaults
        let store: SelfConfigurationStore
        init() {
            defaults = UserDefaults(suiteName: name)!
            store = SelfConfigurationStore(defaults: defaults)
        }
        func cleanup() { defaults.removePersistentDomain(forName: name) }
    }
    static var assertions = 0
    static let appearanceKey = "selfConfiguration.appearance.v1"
    static func expect(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
        assertions += 1
        if try !value() { throw Failure(message: message) }
    }

    static func defaultsAndIsolation() throws {
        let scope = Scope(), other = Scope(); defer { scope.cleanup(); other.cleanup() }
        try expect(scope.store.appearance == .system, "default follows system")
        try expect(scope.defaults.object(forKey: appearanceKey) == nil, "reading does not persist a default")
        scope.defaults.set("synthetic-secret-sentinel", forKey: "model.apiKey")
        scope.defaults.set("synthetic-login-sentinel", forKey: "browser.login")
        scope.store.setAppearanceFromUser(.light)
        let reopened = SelfConfigurationStore(defaults: UserDefaults(suiteName: scope.name)!)
        try expect(reopened.appearance == .light, "real defaults survive store recreation")
        try expect(other.store.appearance == .system, "separate defaults suite remains untouched")
        try expect(scope.defaults.string(forKey: "model.apiKey") == "synthetic-secret-sentinel"
            && scope.defaults.string(forKey: "browser.login") == "synthetic-login-sentinel", "manual edits do not touch other preferences")
        let written = Set((scope.defaults.persistentDomain(forName: scope.name) ?? [:]).keys)
        try expect(written == ["model.apiKey", "browser.login", appearanceKey], "the choice writes only the appearance key")
    }

    static func manualChangesPublishAndPersist() throws {
        let scope = Scope(); defer { scope.cleanup() }
        var observed: [SelfConfigurationAppearance] = []
        let subscription = scope.store.$appearance.sink { observed.append($0) }; defer { subscription.cancel() }
        for appearance in [SelfConfigurationAppearance.dark, .light, .system] {
            scope.store.setAppearanceFromUser(appearance)
            try expect(scope.store.appearance == appearance && observed.last == appearance, "appearance publishes immediately")
            try expect(SelfConfigurationStore(defaults: UserDefaults(suiteName: scope.name)!).appearance == appearance,
                       "the choice survives another store instance")
        }
        try expect(observed == [.system, .dark, .light, .system], "reactive theme changes include resetting to system")
    }

    /// Builds that let the model change the appearance also stored its
    /// permission and an authorization revision. The appearance still loads;
    /// the other keys are ignored and left as they are.
    static func olderStoredValues() throws {
        let scope = Scope(); defer { scope.cleanup() }
        scope.defaults.set("dark", forKey: appearanceKey)
        scope.defaults.set(true, forKey: "selfConfiguration.allow.v1")
        scope.defaults.set(UUID().uuidString, forKey: "selfConfiguration.authorization.v1")
        let store = SelfConfigurationStore(defaults: scope.defaults)
        try expect(store.appearance == .dark, "a stored appearance still loads")
        store.setAppearanceFromUser(.light)
        try expect(scope.defaults.string(forKey: appearanceKey) == "light", "a manual change keeps the stored key")
        try expect(scope.defaults.bool(forKey: "selfConfiguration.allow.v1"), "older keys are left alone")
        for value in ["", "Dark", "sepia"] {
            scope.defaults.set(value, forKey: appearanceKey)
            try expect(SelfConfigurationStore(defaults: scope.defaults).appearance == .system, "unknown stored value follows system")
            try expect(scope.defaults.string(forKey: appearanceKey) == value, "loading does not rewrite stored data")
        }
    }
}

#if SELF_CONFIGURATION_SMOKE
@main struct SelfConfigurationStandalone {
    @MainActor static func main() throws {
        try SelfConfigurationChecks.defaultsAndIsolation(); print("PASS isolated UserDefaults; only the appearance key is written")
        try SelfConfigurationChecks.manualChangesPublishAndPersist(); print("PASS persistence and immediate Combine appearance updates")
        try SelfConfigurationChecks.olderStoredValues(); print("PASS older stored values still load; unknown values follow system")
        let scope = SelfConfigurationChecks.Scope(); defer { scope.cleanup() }
        try SelfConfigurationChecks.expect(scope.store.preferredColorScheme == nil, "system appearance removes override")
        scope.store.setAppearanceFromUser(.dark)
        try SelfConfigurationChecks.expect(scope.store.preferredColorScheme == .dark, "actual SwiftUI color scheme is dark")
        scope.store.setAppearanceFromUser(.light)
        try SelfConfigurationChecks.expect(scope.store.preferredColorScheme == .light, "actual SwiftUI color scheme is light")
        scope.store.setAppearanceFromUser(.system)
        try SelfConfigurationChecks.expect(scope.store.preferredColorScheme == nil, "reset restores system scheme")
        print("PASS SwiftUI ColorScheme mapping; total \(SelfConfigurationChecks.assertions) assertions")
    }
}
#else
@MainActor final class SelfConfigurationTests: XCTestCase {
    func testDefaultAndIsolatedPersistence() throws { try SelfConfigurationChecks.defaultsAndIsolation() }
    func testManualChangesPublishAndPersist() throws { try SelfConfigurationChecks.manualChangesPublishAndPersist() }
    func testOlderStoredValuesStillLoad() throws { try SelfConfigurationChecks.olderStoredValues() }
}
#endif
#endif
