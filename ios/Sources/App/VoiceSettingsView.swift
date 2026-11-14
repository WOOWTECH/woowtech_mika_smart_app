#if os(iOS)
import SwiftUI
#if canImport(Speech)
import Speech
#endif

/// Android SpeechModelScreen (Play edition): a short explanation, then the
/// built-in recognizer with its state, and 不用. Only choices backed by the
/// device driver are offered; provider models need a provider inventory first.
@MainActor
struct VoiceSettingsView: View {
    @ObservedObject var languages: AppLanguageStore
    @ObservedObject private var preferences = VoicePreferences.shared
    @Environment(\.colorScheme) private var colorScheme
    @State private var deviceRecognition = VoiceSettingsView.deviceRecognitionAvailable()
    init(languages: AppLanguageStore) { self.languages = languages }
    private var localizer: AppLocalizer { AppLocalizer(language: languages.resolved) }
    private var palette: MikaSettingsPalette { MikaSettingsPalette(scheme: colorScheme) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: localizer.text(.voiceChoiceHint))
                    .font(.subheadline).foregroundStyle(palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4).padding(.bottom, 12)
                    .accessibilityIdentifier("settings.voice.hint")
                MikaSettingsCard {
                    VStack(spacing: 0) {
                        MikaSettingsRadioRow(
                            title: localizer.text(.voiceChoiceSystem),
                            subtitle: localizer.text(deviceRecognition ? .voiceChoiceSystemNote : .voiceChoiceSystemNone),
                            selected: preferences.choice == .system || preferences.choice == .automatic,
                            action: { preferences.select(.system) }
                        ) {
                            MikaSettingsPill(text: localizer.text(deviceRecognition ? .voiceChoiceAvailable : .voiceChoiceMissing),
                                             tone: deviceRecognition ? .ok : .plain)
                                .padding(.top, 2)
                        }
                        .accessibilityIdentifier("settings.voice.system")
                        Divider().padding(.leading, 50)
                        MikaSettingsRadioRow(title: localizer.text(.voiceChoiceOff),
                                             subtitle: localizer.text(.voiceChoiceOffNote),
                                             selected: preferences.choice == .off,
                                             action: { preferences.select(.off) })
                            .accessibilityIdentifier("settings.voice.off")
                    }
                }
                if preferences.choice == .unavailable {
                    Text(verbatim: localizer.text(.voiceChoiceUnknown))
                        .font(.footnote).foregroundStyle(palette.hint)
                        .padding(.horizontal, 16).padding(.top, 8)
                }
                if preferences.saveFailed {
                    Text(verbatim: localizer.text(.voiceChoiceSaveFailed))
                        .font(.footnote).foregroundStyle(palette.bad)
                        .padding(.horizontal, 16).padding(.top, 8)
                        .accessibilityIdentifier("settings.voice.saveFailed")
                }
            }
            .padding(.horizontal, 16).padding(.bottom, 20)
        }
        .background(palette.page)
        .navigationTitle(localizer.text(.voiceChoiceTitle))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            preferences.refresh()
            deviceRecognition = Self.deviceRecognitionAvailable()
        }
    }

    /// The same test the device driver makes before it records: on-device
    /// recognition for the current locale. Asks for no permission. The model
    /// page's speech card shows it too.
    nonisolated static func deviceRecognitionAvailable() -> Bool {
        #if canImport(Speech)
        guard let recognizer = SFSpeechRecognizer(locale: .current) else { return false }
        return recognizer.isAvailable && recognizer.supportsOnDeviceRecognition
        #else
        return false
        #endif
    }
}
#endif
