import AssistantBrowser
import SwiftUI
import WebKit

@MainActor struct MultiSourceResearchView: View {
    @ObservedObject var chat: ChatSession
    @StateObject private var session = MultiSourceResearchSession()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var root1 = ""
    @State private var root2 = ""
    @State private var root3 = ""
    @State private var goal = ""
    @State private var discoveringSources = false
    @FocusState private var editing: Bool
    @Environment(\.appLocalizer) private var localizer

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Form {
                    Section(localizer.text(.multiResearchInputSection)) {
                        TextField(localizer.text(.multiResearchGoalPlaceholder), text: $goal, axis: .vertical)
                            .focused($editing).accessibilityIdentifier("multiResearch.goal")
                        Button(localizer.text(.multiResearchDiscover)) { editing = false; discoveringSources = true }
                            .accessibilityIdentifier("multiResearch.discoverSources")
                        rootField(localizer.text(.multiResearchRoot1), text: $root1, number: 1)
                        rootField(localizer.text(.multiResearchRoot2), text: $root2, number: 2)
                        rootField(localizer.text(.multiResearchRoot3), text: $root3, number: 3)
                        Text(localizer.text(.multiResearchDisclosure))
                            .font(.caption)
                        Button(localizer.text(.multiResearchStart), action: start)
                            .disabled(session.running).accessibilityIdentifier("multiResearch.start")
                    }.disabled(session.running)
                    Section(localizer.text(.multiResearchProgressSection)) {
                        Text(localizer.stored(session.status)).accessibilityIdentifier("multiResearch.status")
                            .accessibilityValue(testDiagnostic)
                        if let error = session.error { Text(localizer.stored(error)).foregroundStyle(.red).accessibilityIdentifier("multiResearch.error") }
                        if session.running {
                            Button(localizer.text(.multiResearchCancel)) { session.cancel() }.accessibilityIdentifier("multiResearch.cancel")
                        }
                    }
                    if let result = session.result {
                        Section(localizer.text(.multiResearchResultSection)) {
                            Text(localizer.text(result.partial ? .multiResearchPartial : .multiResearchCited)).accessibilityIdentifier("multiResearch.result")
                            Text(localizer.text(.multiResearchCitedCount(count: result.citedSourceCount))).accessibilityIdentifier("multiResearch.citedSourceCount")
                            Text(localizer.text(.multiResearchCitationNote))
                                .font(.caption)
                            ForEach(result.findings) { finding in
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(localizer.text(finding.kind == .inference ? .multiResearchInference : .multiResearchSourceContent)).font(.caption)
                                    Text(verbatim: finding.text)
                                    ForEach(Array(finding.citations.enumerated()), id: \.offset) { _, citation in
                                        citationView(citation)
                                    }
                                }
                            }
                            ForEach(Array(result.limitations.enumerated()), id: \.offset) { _, limitation in
                                Text(verbatim: localizer.stored(limitation)).font(.caption)
                            }
                        }
                    }
                    if !session.receipts.isEmpty {
                        Section(localizer.text(.multiResearchReceiptsSection)) {
                            ForEach(session.receipts) { receipt in
                                VStack(alignment: .leading) {
                                    Text(verbatim: receipt.observation.title).font(.caption)
                                    Text(verbatim: receipt.observation.url.absoluteString)
                                        .accessibilityIdentifier("multiResearch.receipt.\(receipt.id)")
                                    Text(receipt.observation.capturedAt, format: .dateTime).font(.caption)
                                }
                            }
                        }
                    }
                }.scrollDismissesKeyboard(.interactively)
                // Keep every isolated view in the scene, including covered
                // sources. No page controls or dialogs are available here.
                if !session.browsers.isEmpty {
                    ZStack {
                        ForEach(Array(session.browsers.enumerated()), id: \.offset) { index, browser in
                            MultiSourceWebView(webView: browser.webView).opacity(index == 0 ? 1 : 0)
                        }
                    }.frame(height: 100).allowsHitTesting(false).accessibilityHidden(true)
                }
            }
            .navigationTitle(localizer.text(.multiResearchTitle))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(localizer.text(.commonClose)) { session.cancel(); dismiss() }.accessibilityIdentifier("multiResearch.close")
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(localizer.text(.commonDone)) { editing = false }.accessibilityIdentifier("multiResearch.keyboardDone")
                }
            }
        }
        .sheet(isPresented: $discoveringSources) {
            ResearchSourceDiscoveryView(query: goal) { sources in
                guard !session.running, (2...3).contains(sources.count) else { return }
                root1 = sources[0].url.absoluteString
                root2 = sources[1].url.absoluteString
                root3 = sources.count == 3 ? sources[2].url.absoluteString : ""
            }
        }
        .onDisappear { session.cancel() }
        .onChange(of: scenePhase) { _, value in if value == .background { session.cancel() } }
    }

    private var testDiagnostic: String {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-LiveModelUITest") || MultiSourceResearchFixture.enabled { return session.diagnostic }
        #endif
        return ""
    }

    private func rootField(_ label: String, text: Binding<String>, number: Int) -> some View {
        TextField(label, text: text).keyboardType(.URL).textInputAutocapitalization(.never)
            .autocorrectionDisabled().focused($editing).accessibilityIdentifier("multiResearch.rootText\(number)")
    }

    private func start() {
        editing = false
        do {
            let roots = [root1, root2] + (root3.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? [] : [root3])
            let plan = try MultiSourceResearchPlan(goal: goal, rootAddresses: roots)
            session.start(plan: plan, using: chat)
        } catch { session.reportInvalidPlan(error) }
    }

    private func citationView(_ citation: MultiSourceResearchCitation) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: citation.quote).font(.callout)
                .accessibilityIdentifier("multiResearch.quote.\(citation.receipt.sourceID)")
            Link(destination: citation.receipt.observation.url) {
                Text(verbatim: citation.receipt.observation.title + " — " + citation.receipt.observation.url.absoluteString)
            }
            Text(localizer.text(.multiResearchReadAt(value: citation.receipt.observation.capturedAt.formatted(
                Date.FormatStyle(date: .numeric, time: .standard, locale: Locale(identifier: localizer.language.rawValue))))))
                .font(.caption)
            Text(localizer.text(.multiResearchPublished)).font(.caption)
        }
    }
}

private struct MultiSourceWebView: UIViewRepresentable {
    let webView: WKWebView
    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
