import AssistantSkills
import Combine
import SwiftUI

/// Source archive with explicit entry points to supported local capabilities.
@MainActor
struct SkillCatalogView: View {
    @Environment(\.appLocalizer) private var localizer
    @ObservedObject var store: LearningStore
    let modelAccess: () throws -> ModelAccess
    let modelChanges: AnyPublisher<Void, Never>
    @Environment(\.dismiss) private var dismiss
    @State private var catalog: BundledSkillCatalog?
    @State private var failure: AppText?
    @State private var query = ""
    @FocusState private var searchFocused: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                Text(localizer.text(.catalogTitle))
                    .font(.title2.bold())
                    .accessibilityIdentifier("catalog.status")
                if let catalog {
                    HStack(spacing: 12) {
                        Image(systemName: "square.stack.3d.up")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(brandAccent)
                            .frame(width: 32, height: 32)
                            .background(brandAccent.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
                            .accessibilityHidden(true)
                        Text(localizer.text(.catalogCount(total: catalog.entries.count, matches: catalog.search(query).count)))
                            .font(.subheadline.weight(.semibold))
                            .accessibilityIdentifier("catalog.count")
                        Spacer(minLength: 0)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5))
                    .shadow(color: colorScheme == .dark ? .clear : .black.opacity(0.04), radius: 6, y: 2)
                    TextField(localizer.text(.catalogSearch), text: $query)
                        .textFieldStyle(.roundedBorder).autocorrectionDisabled()
                        .focused($searchFocused).onSubmit { searchFocused = false }
                        .submitLabel(.search).accessibilityIdentifier("catalog.search")
                }
            }
            .padding(.horizontal)
            .padding(.top, 12)
            .padding(.bottom, 4)
            if let catalog {
                List {
                    Section {
                        Text(localizer.text(.catalogScope))
                            .accessibilityIdentifier("catalog.scope")
                        Text(localizer.text(.catalogCapabilities))
                            .font(.footnote).accessibilityIdentifier("catalog.capabilities")
                    }
                    Section(localizer.text(.catalogSection)) {
                        ForEach(catalog.search(query)) { entry in
                            NavigationLink {
                                SkillCatalogDetail(store: store, catalog: catalog, entry: entry, modelAccess: modelAccess, modelChanges: modelChanges)
                            } label: {
                                HStack(alignment: .top, spacing: 12) {
                                    Image(systemName: iconName(for: entry.id))
                                        .font(.system(size: 16))
                                        .foregroundStyle(.primary)
                                        .frame(width: 30, height: 30)
                                        .background(Color.primary.opacity(colorScheme == .dark ? 0.07 : 0.04),
                                                    in: RoundedRectangle(cornerRadius: 9))
                                        .accessibilityHidden(true)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(verbatim: entry.title)
                                            .font(.body.weight(.medium))
                                        Text(verbatim: entry.id)
                                            .font(.caption).foregroundStyle(.secondary)
                                        Text(verbatim: localizer.text(AppLocalizer.skillReadiness(id: entry.id)))
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                            .accessibilityIdentifier("catalog.entry.\(entry.id)")
                        }
                        if catalog.search(query).isEmpty {
                            Text(localizer.text(.catalogEmpty))
                                .accessibilityIdentifier("catalog.empty")
                        }
                    }
                    Section(localizer.text(.catalogSource)) {
                        Text(localizer.text(.catalogProvenance(commit: BundledSkillCatalog.pinnedCommit)))
                            .font(.caption).textSelection(.enabled)
                            .accessibilityIdentifier("catalog.provenance")
                        documentLink(catalog.license, title: .catalogLicense, identifier: "catalog.license")
                        documentLink(catalog.notice, title: .catalogNotice, identifier: "catalog.notice")
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .scrollDismissesKeyboard(.interactively)
            } else if let failure {
                Text(localizer.text(failure))
                    .accessibilityIdentifier("catalog.error")
                    .padding(.horizontal)
                Button(localizer.text(.catalogReload)) { load() }
                    .accessibilityIdentifier("catalog.retry")
                    .padding(.horizontal)
                Spacer()
            } else {
                ProgressView(localizer.text(.catalogLoading))
                    .padding(.horizontal)
                Spacer()
            }
        }
        .tint(brandAccent)
        .background(pageBackground)
        .navigationTitle(localizer.text(.catalogNavigation))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(localizer.text(.commonClose)) { dismiss() }.accessibilityIdentifier("catalog.close")
            }
        }
        .task { if catalog == nil { load() } }
    }

    private func load() {
        do { catalog = try BundledSkillCatalog.bundled(); failure = nil }
        catch { failure = (error as? SkillCatalogError).map(AppLocalizer.skillCatalogError) ?? .catalogLoadFailure }
    }

    private func iconName(for id: String) -> String {
        switch id {
        case "configure-mika": return "slider.horizontal.3"
        case "content-transcribe": return "text.bubble"
        case "documents": return "doc.text"
        case "info-research": return "globe"
        case "messaging": return "bubble.left.and.bubble.right"
        case "skill-authoring": return "square.and.pencil"
        default: return "square.stack.3d.up"
        }
    }

    private var brandAccent: Color {
        colorScheme == .dark
            ? Color(red: 97.0 / 255, green: 131.0 / 255, blue: 252.0 / 255)
            : Color(red: 64.0 / 255, green: 105.0 / 255, blue: 251.0 / 255)
    }

    private var pageBackground: Color {
        colorScheme == .dark
            ? Color(red: 14.0 / 255, green: 14.0 / 255, blue: 16.0 / 255)
            : Color(red: 247.0 / 255, green: 247.0 / 255, blue: 248.0 / 255)
    }

    private var cardBackground: Color {
        colorScheme == .dark
            ? Color(red: 26.0 / 255, green: 26.0 / 255, blue: 29.0 / 255)
            : .white
    }

    private func documentLink(_ document: SkillCatalogDocument, title: AppText, identifier: String) -> some View {
        NavigationLink {
            CatalogTextView(title: .message(title), text: document.content, document: document)
        } label: { Text(localizer.text(title)) }
        .accessibilityIdentifier(identifier)
    }
}

@MainActor
private struct SkillCatalogDetail: View {
    @Environment(\.appLocalizer) private var localizer
    @ObservedObject var store: LearningStore
    @EnvironmentObject private var preferences: SelfConfigurationStore
    let catalog: BundledSkillCatalog
    let entry: SkillCatalogEntry
    let modelAccess: () throws -> ModelAccess
    let modelChanges: AnyPublisher<Void, Never>
    @State private var importFailed = false
    @State private var retainedImportError: String?

    private var pending: Bool { store.skills.pending.contains { $0.name == entry.adaptationName } }
    private var installed: Bool { store.skills.installed.contains { $0.name == entry.adaptationName } }

    var body: some View {
        List {
            if entry.id == "content-transcribe" {
                Section(localizer.text(.catalogTranscriptSection)) {
                    NavigationLink { TranscriptView(learning: store, modelAccess: modelAccess, modelChanges: modelChanges) } label: {
                        Text(localizer.text(.catalogTranscriptOpen))
                    }.accessibilityIdentifier("catalog.content-transcribe.open")
                    Text(localizer.text(.catalogTranscriptHelp))
                        .font(.caption)
                }
            }
            if entry.id == "configure-mika" {
                Section(localizer.text(.catalogAppearanceSection)) {
                    NavigationLink { SelfConfigurationView(store: preferences, modelAccess: modelAccess) } label: {
                        Text(localizer.text(.catalogAppearanceOpen))
                    }.accessibilityIdentifier("catalog.configure-mika.open")
                    Text(localizer.text(.catalogAppearanceHelp))
                        .font(.caption)
                }
            }
            if entry.id == "skill-authoring" {
                Section(localizer.text(.catalogAuthorSection)) {
                    NavigationLink { SkillAuthoringView(store: store, catalog: catalog) } label: {
                        Text(localizer.text(.catalogAuthorOpen))
                    }
                    .disabled(!store.available)
                    .accessibilityIdentifier("catalog.skill-authoring.open")
                    NavigationLink { SkillAgentView(store: store, modelAccess: modelAccess) } label: {
                        Text(localizer.text(.catalogAgentOpen))
                    }
                    .disabled(!store.available)
                    .accessibilityIdentifier("catalog.skill-authoring.agent")
                    Text(localizer.text(.catalogAuthorHelp))
                        .font(.caption)
                }
            }
            if entry.id == "documents" {
                Section(localizer.text(.catalogDocumentsSection)) {
                    NavigationLink { SkillExecutionView(learning: store, modelAccess: modelAccess, modelChanges: modelChanges) } label: { Text(localizer.text(.catalogPDFOpen)) }
                        .accessibilityIdentifier("catalog.documents.execute")
                    NavigationLink { SkillPDFAssemblyView() } label: { Text(localizer.text(.catalogPDFAssembly)) }
                        .accessibilityIdentifier("catalog.documents.assemble")
                    Text(localizer.text(.catalogDocumentsHelp))
                        .font(.caption)
                }
            }
            Section(localizer.text(.catalogAdaptationSection)) {
                Text(verbatim: entry.adaptationScope).accessibilityIdentifier("catalog.adaptation.scope")
                NavigationLink {
                    CatalogTextView(title: .message(.catalogAdaptationTitle), text: entry.adaptationMarkdown)
                } label: { Text(localizer.text(.catalogAdaptationRead)) }
                .accessibilityIdentifier("catalog.adaptation.fullText")
                Button(localizer.text(.catalogImport)) {
                    importFailed = !store.importCatalogSkill(id: entry.id, catalog: catalog)
                    retainedImportError = importFailed ? store.error : nil
                }
                .disabled(!store.available || pending || installed)
                .accessibilityIdentifier("catalog.import")
                if pending {
                    Text(localizer.text(.catalogPending))
                        .accessibilityIdentifier("catalog.import.pending")
                } else if installed {
                    Text(localizer.text(.catalogInstalled))
                        .accessibilityIdentifier("catalog.import.installed")
                }
                if !store.available {
                    Text(localizer.text(.catalogStorageUnavailable))
                        .accessibilityIdentifier("catalog.import.unavailable")
                }
                if importFailed { Text(verbatim: retainedImportError ?? localizer.text(.catalogNotImported)).foregroundStyle(.red).accessibilityIdentifier("catalog.import.error") }
            }
            Section(localizer.text(.catalogRequirements)) {
                Text(verbatim: localizer.text(AppLocalizer.skillReadiness(id: entry.id))).accessibilityIdentifier("catalog.readiness")
                ForEach(entry.requirements, id: \.rawValue) { requirement in
                    Text(verbatim: localizer.text(AppLocalizer.skillRequirement(requirement)))
                        .accessibilityIdentifier("catalog.requirement.\(requirement.rawValue)")
                }
            }
            Section(localizer.text(.catalogOriginalSection)) {
                NavigationLink {
                    CatalogTextView(title: .original(entry.id + "/SKILL.md"), text: entry.original.content, document: entry.original)
                } label: { Text(localizer.text(.catalogOriginalRead)) }
                .accessibilityIdentifier("catalog.original")
                ForEach(entry.assets) { asset in
                    NavigationLink {
                        CatalogTextView(title: .original(URL(fileURLWithPath: asset.path).lastPathComponent),
                                        text: asset.content, document: asset)
                    } label: {
                        Text(verbatim: asset.path.components(separatedBy: "/").suffix(2).joined(separator: "/"))
                    }
                    .accessibilityIdentifier("catalog.asset.\(URL(fileURLWithPath: asset.path).lastPathComponent)")
                }
                Text(localizer.text(.catalogAttribution))
                    .font(.footnote).accessibilityIdentifier("catalog.attribution")
            }
        }
        .navigationTitle(entry.title)
        .navigationBarTitleDisplayMode(.inline)
        .listStyle(.insetGrouped)
    }
}

/// Verbatim text prevents Markdown links, embedded HTML and source code from
/// becoming actions. Even files whose upstream manifest says runnable are inert.
private struct CatalogTextView: View {
    @Environment(\.appLocalizer) private var localizer
    enum Title {
        case message(AppText), original(String)
        func text(using localizer: AppLocalizer) -> String {
            switch self {
            case .message(let message): return localizer.text(message)
            case .original(let text): return text
            }
        }
    }
    let title: Title
    let text: String
    var document: SkillCatalogDocument? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(localizer.text(.catalogTextSafety))
                    .font(.footnote).accessibilityIdentifier("catalog.document.safety")
                if let document {
                    Text(verbatim: document.path + "\nSHA-256: " + document.sha256 + "\n" + document.sourceURL.absoluteString)
                        .font(.caption).textSelection(.enabled)
                        .accessibilityIdentifier("catalog.document.provenance")
                }
                Text(verbatim: text)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("catalog.document")
            }
            .padding()
        }
        .navigationTitle(title.text(using: localizer))
        .navigationBarTitleDisplayMode(.inline)
    }
}
