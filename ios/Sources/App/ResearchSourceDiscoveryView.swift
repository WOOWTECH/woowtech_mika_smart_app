import AssistantBrowser
import SwiftUI
import WebKit

@MainActor struct ResearchSourceDiscoveryView: View {
    @StateObject private var session: ResearchSourceDiscoverySession
    private let onApply: ([ResearchSourceDiscoveryCandidate]) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @FocusState private var editing: Bool
    @Environment(\.appLocalizer) private var localizer

    init(query: String, onApply: @escaping ([ResearchSourceDiscoveryCandidate]) -> Void) {
        _session = StateObject(wrappedValue: ResearchSourceDiscoverySession(query: query))
        self.onApply = onApply
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Form {
                    Section(localizer.text(.sourceDiscoveryProviderSection)) {
                        Text(localizer.text(.sourceDiscoveryProviderTitle(session.provider)))
                        Text(session.provider.origin.absoluteString).font(.caption)
                        Text(localizer.text(.sourceDiscoveryProviderDisclosure(session.provider))).font(.caption)
                    }
                    Section(localizer.text(.sourceDiscoveryFindSection)) {
                        TextField(localizer.text(.sourceDiscoveryQueryPlaceholder), text: Binding(get: { session.query }, set: { session.setQuery($0) }), axis: .vertical)
                            .focused($editing).autocorrectionDisabled()
                            .disabled(session.running).accessibilityIdentifier("sourceDiscovery.query")
                        Button(localizer.text(.sourceDiscoverySearch)) { editing = false; session.search() }
                            .disabled(session.running || session.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .accessibilityIdentifier("sourceDiscovery.search")
                        Text(localizer.stored(session.status)).accessibilityIdentifier("sourceDiscovery.status")
                        if session.running {
                            ProgressView()
                            Button(localizer.text(.sourceDiscoveryCancel)) { session.cancel() }.accessibilityIdentifier("sourceDiscovery.cancel")
                        }
                        if let error = session.error {
                            Text(verbatim: localizer.stored(error)).foregroundStyle(.red).accessibilityIdentifier("sourceDiscovery.error")
                        }
                    }
                    if let result = session.result {
                        Section(localizer.text(.sourceDiscoveryPickSection)) {
                            Text(localizer.text(.sourceDiscoveryPickNote))
                                .font(.caption)
                            ForEach(Array(result.candidates.enumerated()), id: \.element.id) { index, candidate in
                                Button { session.toggle(candidate.id) } label: {
                                    HStack(alignment: .top) {
                                        Image(systemName: session.selectedIDs.contains(candidate.id) ? "checkmark.circle.fill" : "circle")
                                        VStack(alignment: .leading, spacing: 5) {
                                            Text(verbatim: candidate.title)
                                            Text(verbatim: candidate.url.absoluteString).font(.caption)
                                        }.foregroundStyle(.primary)
                                    }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                }
                                .accessibilityIdentifier("sourceDiscovery.candidate.\(index)")
                                .accessibilityValue(candidateValue(candidate))
                            }
                            if result.truncated {
                                Text(localizer.text(.sourceDiscoveryTruncated)).font(.caption)
                            }
                        }
                    }
                }
                .scrollDismissesKeyboard(.interactively)
                .accessibilityIdentifier("sourceDiscovery.form")
                if let browser = session.browser {
                    DiscoveryWebView(webView: browser.webView)
                        .frame(height: 100).allowsHitTesting(false).accessibilityHidden(true)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if session.result != nil {
                    VStack(spacing: 6) {
                        Text(localizer.text(.sourceDiscoverySelectedCount(count: session.selectedIDs.count)))
                            .font(.caption).accessibilityIdentifier("sourceDiscovery.selectionCount")
                        Button(action: applySelection) {
                            Text(localizer.text(.sourceDiscoveryApply)).frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.borderedProminent).disabled(!session.canApply)
                        .accessibilityIdentifier("sourceDiscovery.apply")
                    }.padding(.horizontal).padding(.vertical, 8).background(.regularMaterial)
                }
            }
            .navigationTitle(localizer.text(.sourceDiscoveryTitle))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(localizer.text(.commonClose)) { session.cancel(notice: false); dismiss() }
                        .accessibilityIdentifier("sourceDiscovery.close")
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(localizer.text(.commonDone)) { editing = false }.accessibilityIdentifier("sourceDiscovery.keyboardDone")
                }
            }
        }
        .onDisappear { session.cancel(notice: false) }
        .onChange(of: scenePhase) { _, phase in if phase != .active { session.cancel() } }
    }

    private func applySelection() {
        guard let sources = session.selectedSources() else { return }
        session.cancel(notice: false); onApply(sources); dismiss()
    }

    private func candidateValue(_ candidate: ResearchSourceDiscoveryCandidate) -> String {
        let selection = localizer.text(session.selectedIDs.contains(candidate.id) ? .commonSelected : .commonUnselected)
        #if DEBUG
        // Observe the same real URL displayed in the row; never seed or select
        // a result. Private native tests need not infer a URL from a title.
        if ProcessInfo.processInfo.arguments.contains("-LiveModelUITest") {
            return selection + "\n" + candidate.url.absoluteString
        }
        #endif
        return selection
    }
}

private struct DiscoveryWebView: UIViewRepresentable {
    let webView: WKWebView
    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
