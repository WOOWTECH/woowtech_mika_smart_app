import Combine
import Foundation

public enum SelfConfigurationAppearance: String, CaseIterable, Codable, Sendable {
    case system, light, dark
}

/// The App appearance chosen in Settings › 語言與外觀. Only the user changes it:
/// like the Play build, no model tool or permission can list or set it.
/// Inject the app's existing isolated defaults suite. Older builds also kept a
/// model permission and an authorization revision here; those keys are ignored.
@MainActor public final class SelfConfigurationStore: ObservableObject {
    @Published public private(set) var appearance: SelfConfigurationAppearance
    private let defaults: UserDefaults
    private static let appearanceKey = "selfConfiguration.appearance.v1"

    public init(defaults: UserDefaults) {
        self.defaults = defaults
        appearance = SelfConfigurationAppearance(rawValue: defaults.string(forKey: Self.appearanceKey) ?? "") ?? .system
    }

    /// Only a direct user action should call this API.
    public func setAppearanceFromUser(_ value: SelfConfigurationAppearance) {
        defaults.set(value.rawValue, forKey: Self.appearanceKey)
        appearance = value
    }
}
