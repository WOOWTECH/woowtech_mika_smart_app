#if os(iOS)
import SwiftUI

/// Installed-version details only. No update check or external service is
/// implied by this page.
@MainActor struct MikaAboutView: View {
    @ObservedObject var languages: AppLanguageStore
    let info: MikaAboutInfo
    @Environment(\.colorScheme) private var colorScheme

    private var palette: MikaSettingsPalette { MikaSettingsPalette(scheme: colorScheme) }
    private var copy: MikaAboutCopy { MikaAboutCopy(language: languages.resolved) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: AppLocalizer(language: languages.resolved).text(.shellBrandTitle))
                    .font(.title2.bold())
                    .foregroundStyle(palette.ink)
                    .padding(.top, 24)
                    .accessibilityIdentifier("settings.about.appName")
                Text(verbatim: copy.text(.installedVersion))
                    .font(.subheadline)
                    .foregroundStyle(palette.secondary)
                    .padding(.top, 6).padding(.bottom, 20)
                MikaSettingsCard {
                    VStack(spacing: 0) {
                        fact(copy.text(.version), value: info.version ?? copy.text(.unavailable),
                             identifier: "settings.about.version")
                        Divider().padding(.leading, 16)
                        fact(copy.text(.build), value: info.build ?? copy.text(.unavailable),
                             identifier: "settings.about.build")
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .background(palette.page)
        .navigationTitle(copy.text(.title))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func fact(_ label: String, value: String, identifier: String) -> some View {
        HStack(spacing: 12) {
            Text(verbatim: label).foregroundStyle(palette.ink)
            Spacer(minLength: 8)
            Text(verbatim: value)
                .foregroundStyle(palette.secondary)
                .multilineTextAlignment(.trailing)
                .accessibilityIdentifier(identifier)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 52)
    }
}
#endif
