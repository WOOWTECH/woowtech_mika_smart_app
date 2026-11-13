#if os(iOS)
import AssistantSkills
import SwiftUI

/// Android LanguageScreen (Play edition, 465a17c9): 外觀 first, then 語言,
/// each a single-choice list that applies at once. Only Play's choices are
/// offered: no 简体中文, and no model permission to change the appearance.
@MainActor
struct MikaLanguageAppearanceView: View {
    @ObservedObject var preferences: SelfConfigurationStore
    @ObservedObject var languages: AppLanguageStore
    @State private var languageSaveFailed = false
    @Environment(\.colorScheme) private var colorScheme
    private var palette: MikaSettingsPalette { MikaSettingsPalette(scheme: colorScheme) }
    private var localizer: AppLocalizer { AppLocalizer(language: languages.resolved) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                MikaSettingsGroupLabel(title: localizer.text(.appearanceTitle))
                MikaSettingsCard {
                    VStack(spacing: 0) {
                        ForEach(Array(SelfConfigurationAppearance.allCases.enumerated()), id: \.element) { index, value in
                            if index > 0 { Divider().padding(.leading, 50) }
                            MikaSettingsRadioRow(title: appearanceName(value),
                                                 subtitle: value == .system ? localizer.text(.appearanceSystemDetail) : nil,
                                                 selected: preferences.appearance == value) {
                                if preferences.appearance != value { preferences.setAppearanceFromUser(value) }
                            }
                            .accessibilityIdentifier("selfConfiguration.appearance." + value.rawValue)
                        }
                    }
                }
                MikaSettingsGroupLabel(title: localizer.text(.languageTitle))
                    .padding(.top, 8)
                MikaSettingsCard {
                    VStack(spacing: 0) {
                        ForEach(Array(AppLanguage.settingsChoices.enumerated()), id: \.element) { index, choice in
                            if index > 0 { Divider().padding(.leading, 50) }
                            MikaSettingsRadioRow(title: localizer.languageName(choice),
                                                 subtitle: choice == .system ? localizer.text(.languageSystemDetail) : nil,
                                                 selected: languages.language == choice) {
                                if languages.language != choice { languageSaveFailed = !languages.setFromUser(choice) }
                            }
                            .accessibilityIdentifier("settings.language." + choice.rawValue)
                        }
                    }
                }
                if languageSaveFailed {
                    Text(verbatim: localizer.text(.languageSaveFailed))
                        .font(.footnote).foregroundStyle(palette.bad)
                        .padding(.horizontal, 16).padding(.top, 8)
                        .accessibilityIdentifier("settings.language.error")
                }
            }
            .padding(.horizontal, 16).padding(.bottom, 20)
        }
        .background(palette.page)
        .navigationTitle(localizer.text(.languageAppearanceTitle))
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Android appearance_system, appearance_light and appearance_dark.
    private func appearanceName(_ value: SelfConfigurationAppearance) -> String {
        switch value {
        case .system: return localizer.text(.appearanceFollowSystem)
        case .light: return localizer.text(.appearanceAlwaysLight)
        case .dark: return localizer.text(.appearanceAlwaysDark)
        }
    }
}
#endif
