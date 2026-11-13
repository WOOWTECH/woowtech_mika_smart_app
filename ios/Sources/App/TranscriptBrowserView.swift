import AssistantSkills
import Combine
import SwiftUI

@MainActor struct TranscriptBrowserView: View {
    @ObservedObject var browser: BrowserSession
    @ObservedObject var chat: ChatSession
    @State private var page: BrowserTranscriptText?
    @State private var source: TranscriptSnapshot?
    @State private var preparing = false
    @State private var showEditor = false
    @State private var error: String?
    @State private var task: Task<Void, Never>?
    @State private var operationID: UUID?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLocalizer) private var localizer

    var body: some View {
        NavigationStack {
            Form {
                Section(localizer.text(.transcriptBrowserSection)) {
                    Text(localizer.text(.transcriptBrowserIntro))
                    Text(localizer.text(.transcriptBrowserLimits))
                        .font(.footnote)
                    Button(localizer.text(preparing ? .transcriptBrowserReading : .transcriptBrowserCapture)) { capture() }
                        .disabled(preparing).accessibilityIdentifier("transcript.browser.capture")
                    if let error { Text(verbatim: error).foregroundStyle(.red).accessibilityIdentifier("transcript.browser.error") }
                }
                if let page {
                    Section(localizer.text(.transcriptBrowserCheckSection)) {
                        Text(verbatim: page.title).accessibilityIdentifier("transcript.browser.title")
                        Text(verbatim: page.url.absoluteString).textSelection(.enabled).accessibilityIdentifier("transcript.browser.url")
                        Text(localizer.text(.transcriptBrowserSize(bytes: page.text.utf8.count, date: page.capturedAt.formatted(
                            Date.FormatStyle(date: .numeric, time: .shortened, locale: Locale(identifier: localizer.language.rawValue))))))
                        if page.omittedRegions > 0 {
                            Text(localizer.text(.transcriptBrowserOmitted(count: page.omittedRegions)))
                                .accessibilityIdentifier("transcript.browser.omittedRegions")
                        }
                        DisclosureGroup(localizer.text(.transcriptBrowserFullText)) {
                            Text(verbatim: page.text).textSelection(.enabled).accessibilityIdentifier("transcript.browser.source")
                        }
                        Button(localizer.text(.transcriptBrowserApprove)) {
                            do {
                                source = try .fromUserApprovedWebPage(title: page.title, text: page.text, url: page.url)
                                showEditor = true; error = nil
                            } catch { self.error = localizer.text(.transcriptBrowserSnapshotFailed) }
                        }.accessibilityIdentifier("transcript.browser.approve")
                    }
                }
            }
            .navigationTitle(localizer.text(.transcriptBrowserTitle))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(localizer.text(.commonClose)) { dismiss() }.accessibilityIdentifier("transcript.browser.close")
                }
            }
            .navigationDestination(isPresented: $showEditor) {
                if let source {
                    TranscriptView(learning: chat.learning, modelAccess: chat.modelAccess,
                        modelChanges: chat.$savedSettings.dropFirst().map { _ in () }.eraseToAnyPublisher(),
                        approvedSource: source)
                }
            }
        }
        .onDisappear { operationID = nil; task?.cancel(); task = nil; preparing = false }
    }

    private func capture() {
        task?.cancel(); page = nil; source = nil; error = nil; preparing = true
        let id = UUID(); operationID = id
        task = Task {
            do {
                let captured = try await browser.textForTranscript()
                guard operationID == id, !Task.isCancelled else { return }
                page = captured; preparing = false; task = nil
            } catch {
                guard operationID == id, !Task.isCancelled else { return }
                preparing = false; task = nil
                self.error = (error as? TranscriptError).map { localizer.text(.transcriptError($0)) }
                    ?? localizer.text(.transcriptBrowserCaptureFailed)
            }
        }
    }
}
