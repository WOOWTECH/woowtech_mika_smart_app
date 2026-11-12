import Combine
import Foundation

/// Observe the revision, not just the displayed choice: a system->off->system
/// change invalidates an older recording even if the final label is unchanged.
@MainActor
final class ChatVoicePreferenceBinding {
    private var changes: AnyCancellable?
    init(preferences: VoicePreferences, controller: ChatVoiceController) {
        changes = preferences.$observedAuthorization.dropFirst().sink { [weak controller] _ in
            controller?.authorizationChanged()
        }
    }
}
