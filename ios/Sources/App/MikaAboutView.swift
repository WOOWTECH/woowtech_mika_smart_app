#if os(iOS)
import SwiftUI
import UIKit

/// Installed version and user-initiated project resource links.
@MainActor struct MikaAboutView: View {
    @ObservedObject var languages: AppLanguageStore
    let info: MikaAboutInfo
    @Environment(\.colorScheme) private var colorScheme
    @State private var showingDiagnostics = false
    @State private var copiedDiagnostics = false

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
                        Button { copiedDiagnostics = false; showingDiagnostics = true } label: {
                            HStack {
                                Text(verbatim: copy.text(.diagnostics)).foregroundStyle(palette.ink)
                                Spacer(minLength: 8)
                                Image(systemName: "chevron.right").foregroundStyle(palette.secondary)
                                    .accessibilityHidden(true)
                            }
                            .padding(.horizontal, 16)
                            .frame(minHeight: 52)
                            .contentShape(Rectangle())
                        }
                        .accessibilityIdentifier("settings.about.diagnostics")
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
        .sheet(isPresented: $showingDiagnostics) {
            let report = MikaAboutDiagnostics(info: info, osVersion: ProcessInfo.processInfo.operatingSystemVersion,
                                              language: languages.resolved).text
            NavigationStack {
                VStack(alignment: .leading, spacing: 16) {
                    Text(verbatim: copy.text(.diagnosticsNote)).font(.subheadline)
                    ScrollView {
                        Text(verbatim: report).frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .accessibilityIdentifier("settings.about.diagnostics.report")
                    }
                    HStack {
                        Button {
                            UIPasteboard.general.string = report
                            copiedDiagnostics = true
                        } label: { Text(verbatim: copy.text(copiedDiagnostics ? .diagnosticsCopied : .diagnosticsCopy)) }
                        .accessibilityIdentifier("settings.about.diagnostics.copy")
                        Spacer()
                        ShareLink(item: report) { Text(verbatim: copy.text(.diagnosticsShare)) }
                            .accessibilityIdentifier("settings.about.diagnostics.share")
                    }
                }
                .padding()
                .navigationTitle(copy.text(.diagnostics))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) {
                    Button(copy.text(.close)) { showingDiagnostics = false }
                } }
            }
        }
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
