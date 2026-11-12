#if os(iOS)
import SwiftUI

/// Only choices backed by the current device driver are offered. Provider
/// selection needs an actual provider inventory and verified protocol first.
@MainActor
struct VoiceSettingsView: View {
    @ObservedObject var languages: AppLanguageStore
    @ObservedObject private var preferences = VoicePreferences.shared
    init(languages: AppLanguageStore) { self.languages = languages }
    private var localizer: AppLocalizer { AppLocalizer(language: languages.resolved) }
    var body: some View {
        Form {
            Section {
                choice(.system, title: .voiceChoiceSystem, selected: preferences.choice == .system || preferences.choice == .automatic)
                choice(.off, title: .voiceChoiceOff, selected: preferences.choice == .off)
                if preferences.choice == .unavailable {
                    Text(localizer.text(.voiceChoiceUnknown))
                }
                if preferences.saveFailed {
                    Text(localizer.text(.voiceChoiceSaveFailed))
                        .accessibilityIdentifier("settings.voice.saveFailed")
                }
            } footer: {
                Text(localizer.text(.voiceChoiceNotice))
            }
        }
        .navigationTitle(localizer.text(.voiceChoiceTitle))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { preferences.refresh() }
    }
    private func choice(_ value: VoiceChoice, title: AppText, selected: Bool) -> some View {
        Button { preferences.select(value) } label: {
            HStack {
                Text(localizer.text(title))
                Spacer()
                if selected { Image(systemName: "checkmark").accessibilityHidden(true) }
            }
            .contentShape(Rectangle())
        }
        .accessibilityIdentifier(value == .system ? "settings.voice.system" : "settings.voice.off")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
#endif
