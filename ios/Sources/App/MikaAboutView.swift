#if os(iOS)
import AssistantSkills
import SwiftUI
import UIKit

/// Android AboutScreen, woowtech Play edition (465a17c9): the hero with the
/// installed version, 回報問題 (copy diagnostics, then email them), the data
/// note and the copyright line. Play has no GitHub entries, so neither does iOS.
@MainActor struct MikaAboutView: View {
    @ObservedObject var languages: AppLanguageStore
    let info: MikaAboutInfo
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL
    @State private var showingFeedback = false

    private var palette: MikaSettingsPalette { MikaSettingsPalette(scheme: colorScheme) }
    private var copy: MikaAboutCopy { MikaAboutCopy(language: languages.resolved) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(spacing: 0) {
                    Image("AboutBrandIcon")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 72, height: 72)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .accessibilityHidden(true)
                    Text(verbatim: AppLocalizer(language: languages.resolved).text(.shellBrandTitle))
                        .font(.title2.bold())
                        .foregroundStyle(palette.ink)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 12)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("settings.about.appName")
                    Text(verbatim: copy.text(.tagline))
                        .font(.footnote)
                        .foregroundStyle(palette.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                        .accessibilityIdentifier("settings.about.tagline")
                    // One line, as on Android: 版本 0.1.0 · 建置 42.
                    HStack(spacing: 6) {
                        Text(verbatim: info.version.map(copy.version) ?? copy.text(.unavailable))
                            .accessibilityIdentifier("settings.about.version")
                        if let build = info.build {
                            Text(verbatim: "· " + copy.build(build))
                                .accessibilityIdentifier("settings.about.build")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(palette.hint)
                    .multilineTextAlignment(.center)
                    .padding(.top, 10)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 14)
                .padding(.bottom, 18)
                MikaSettingsCard {
                    VStack(spacing: 0) {
                        Button { showingFeedback = true } label: {
                            MikaSettingsRow(icon: .bug, title: copy.text(.feedback), subtitle: copy.text(.feedbackDetail))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("settings.about.feedback")
                        Divider().padding(.leading, 60)
                        // The same policy the AI-sharing consent links to.
                        Button { openURL(MikaPrivacyPolicy.url) } label: {
                            MikaSettingsRow(icon: .shield, title: copy.text(.privacyPolicy),
                                            subtitle: copy.text(.privacyPolicyDetail))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("settings.about.privacyPolicy")
                    }
                }
                HStack(alignment: .top, spacing: 10) {
                    MikaSettingsIconShape(icon: .shield)
                        .stroke(palette.ok, style: StrokeStyle(lineWidth: 1.7, lineCap: .round, lineJoin: .round))
                        .frame(width: 18, height: 18)
                        .padding(.top, 1)
                        .accessibilityHidden(true)
                    Text(verbatim: copy.text(.dataNote))
                        .font(.footnote)
                        .foregroundStyle(palette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("settings.about.dataNote")
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(palette.softColor(for: .ok), in: RoundedRectangle(cornerRadius: 14))
                .padding(.top, 12)
                // Play's About › Released under Apache-2.0 license → Licenses.
                NavigationLink {
                    MikaLicensesView(language: languages.resolved)
                } label: {
                    let parts = copy.releasedUnderParts
                    (Text(verbatim: parts.before) + Text(verbatim: copy.text(.licenseLink)).foregroundColor(.accentColor)
                        + Text(verbatim: parts.after))
                        .font(.caption)
                        .foregroundStyle(palette.hint)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .padding(.top, 20)
                .accessibilityIdentifier("settings.about.license")
                Text(verbatim: copy.text(.copyright))
                    .font(.caption)
                    .foregroundStyle(palette.hint)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
                    .padding(.bottom, 20)
                    .accessibilityIdentifier("settings.about.copyright")
            }
            .padding(.horizontal, 16)
        }
        .background(palette.page)
        .navigationTitle(copy.text(.title))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingFeedback) {
            MikaAboutFeedbackSheet(languages: languages, info: info) { showingFeedback = false }
        }
    }
}

/// Play's LicensesScreen: the Apache-2.0 text, then the one third-party
/// component (upstream Mika) with its NOTICE. Both texts come from the bundled
/// upstream archive, the same copies the built-in skills are read from.
@MainActor struct MikaLicensesView: View {
    let language: AppDisplayLanguage
    @Environment(\.colorScheme) private var colorScheme
    @State private var texts: (license: String, notice: String)?
    @State private var failed = false

    private var palette: MikaSettingsPalette { MikaSettingsPalette(scheme: colorScheme) }
    private var copy: MikaAboutCopy { MikaAboutCopy(language: language) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let texts {
                    MikaSettingsCard { monospaced(texts.license).accessibilityIdentifier("settings.license.text") }
                    Text(verbatim: copy.thirdParty(1))
                        .font(.footnote.weight(.semibold)).foregroundStyle(palette.secondary)
                        .padding(.top, 8)
                    MikaSettingsCard {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(verbatim: "wangzan101/Mika").font(.body.weight(.semibold)).foregroundStyle(palette.ink)
                            Text(verbatim: "Apache-2.0 · " + String(BundledSkillCatalog.pinnedCommit.prefix(8)))
                                .font(.footnote).foregroundStyle(palette.secondary)
                            Text(verbatim: copy.text(.upstreamNote))
                                .font(.footnote).foregroundStyle(palette.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            monospaced(texts.notice).padding(.top, 6).accessibilityIdentifier("settings.license.notice")
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                    }
                } else if failed {
                    Text(verbatim: copy.text(.licenseUnavailable))
                        .font(.footnote).foregroundStyle(palette.secondary)
                        .accessibilityIdentifier("settings.license.error")
                }
                Text(verbatim: copy.text(.licensesFooter))
                    .font(.caption).foregroundStyle(palette.hint)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }
            .padding(16)
        }
        .background(palette.page)
        .navigationTitle(copy.text(.licenseTitle))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard texts == nil, !failed else { return }
            if let catalog = try? BundledSkillCatalog.bundled() {
                texts = (catalog.license.content, catalog.notice.content)
            } else { failed = true }
        }
    }

    private func monospaced(_ text: String) -> some View {
        Text(verbatim: text.trimmingCharacters(in: .whitespacesAndNewlines))
            .font(.system(size: 11.5, design: .monospaced))
            .foregroundStyle(palette.secondary)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
    }
}

/// Android FeedbackSheet without GitHub: one way to report, copying the
/// diagnostics to email them to the address in the explanation.
@MainActor private struct MikaAboutFeedbackSheet: View {
    @ObservedObject var languages: AppLanguageStore
    let info: MikaAboutInfo
    let close: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    private var palette: MikaSettingsPalette { MikaSettingsPalette(scheme: colorScheme) }
    private var copy: MikaAboutCopy { MikaAboutCopy(language: languages.resolved) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(verbatim: copy.text(.feedbackSheetDetail))
                        .font(.footnote)
                        .foregroundStyle(palette.hint)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("settings.about.feedback.detail")
                    MikaSettingsCard {
                        NavigationLink {
                            MikaAboutDiagnosticsView(languages: languages, info: info, close: close)
                        } label: {
                            MikaSettingsRow(icon: .copy, title: copy.text(.diagnosticsCopyTitle),
                                            subtitle: copy.text(.diagnosticsCopyDetail))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("settings.about.diagnostics")
                    }
                }
                .padding(16)
            }
            .background(palette.page)
            .navigationTitle(copy.text(.feedback))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(copy.text(.close), action: close) } }
        }
    }
}

/// Android DiagnosticsSheet: what the report leaves out, the report itself,
/// then copy and share.
@MainActor private struct MikaAboutDiagnosticsView: View {
    @ObservedObject var languages: AppLanguageStore
    let info: MikaAboutInfo
    let close: () -> Void
    @State private var copied = false

    private var copy: MikaAboutCopy { MikaAboutCopy(language: languages.resolved) }

    var body: some View {
        let report = MikaAboutDiagnostics(info: info, osVersion: ProcessInfo.processInfo.operatingSystemVersion,
                                          language: languages.resolved).text
        VStack(alignment: .leading, spacing: 16) {
            Text(verbatim: copy.text(.diagnosticsNote)).font(.subheadline)
            ScrollView {
                Text(verbatim: report)
                    .font(.system(.footnote, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("settings.about.diagnostics.report")
            }
            HStack {
                Button {
                    UIPasteboard.general.string = report
                    copied = true
                } label: { Text(verbatim: copy.text(copied ? .diagnosticsCopied : .diagnosticsCopy)) }
                .accessibilityIdentifier("settings.about.diagnostics.copy")
                Spacer()
                ShareLink(item: report) { Text(verbatim: copy.text(.diagnosticsShare)) }
                    .accessibilityIdentifier("settings.about.diagnostics.share")
            }
        }
        .padding()
        .navigationTitle(copy.text(.diagnostics))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button(copy.text(.close), action: close) } }
    }
}
#endif
