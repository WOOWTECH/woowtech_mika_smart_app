#if os(iOS)
import SwiftUI

/// Installed version and user-initiated project resource links.
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
                Text(verbatim: copy.text(.resources))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(palette.secondary)
                    .padding(.top, 24).padding(.bottom, 8)
                MikaSettingsCard {
                    VStack(spacing: 0) {
                        resource(.repository, url: MikaAboutLinks.repository, identifier: "repository")
                        Divider().padding(.leading, 16)
                        resource(.guide, url: MikaAboutLinks.guide, identifier: "guide")
                        Divider().padding(.leading, 16)
                        resource(.feedback, url: MikaAboutLinks.feedback, identifier: "feedback")
                        Divider().padding(.leading, 16)
                        resource(.license, url: MikaAboutLinks.license, identifier: "license")
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .background(palette.page)
        .navigationTitle(copy.text(.title))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func resource(_ key: MikaAboutKey, url: URL, identifier: String) -> some View {
        Link(destination: url) {
            HStack(spacing: 12) {
                Text(verbatim: copy.text(key)).foregroundStyle(palette.ink)
                Spacer(minLength: 8)
                Image(systemName: "arrow.up.right").foregroundStyle(palette.secondary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .accessibilityIdentifier("settings.about." + identifier)
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
