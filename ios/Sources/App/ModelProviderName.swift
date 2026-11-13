import AssistantModels
import Foundation

/// Android ProviderConnection.displayName for iOS's one saved service: the
/// name of a provider preset at the same address, otherwise the host. The
/// table lives with the presets (ModelProviderPresets), which name a new
/// provider the same way.
enum ModelProviderName {
    static func name(for baseURL: URL) -> String {
        ModelProviderPresets.displayName(for: baseURL)
    }
}
