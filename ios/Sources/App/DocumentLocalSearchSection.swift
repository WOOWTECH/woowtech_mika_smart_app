import AssistantSkills
import SwiftUI

/// Presents only an already-authorized in-memory extraction. It has no file,
/// service or model access. Closing/replacing the parent plan stops searches.
struct DocumentLocalSearchSection: View {
    @Binding var search: DocumentLocalSearch?
    let localizer: AppLocalizer
    @FocusState private var searchFocused: Bool
    @State private var patternMode = false
    @StateObject private var patternSearch = DocumentPatternSearchController()

    var body: some View {
        Group {
            if let current = search {
                Section(localizer.text(.localPDFSearchTitle)) {
                    Text(verbatim: localizer.text(.localPDFSearchNotice)).font(.caption)
                    searchField
                    Toggle(localizer.text(.localPDFSearchPatternMode), isOn: Binding(
                        get: { patternMode }, set: { value in
                            patternSearch.reset(); search?.clearResults(); patternMode = value
                        }))
                        .accessibilityIdentifier("skillExecution.localSearch.patternMode")
                    if patternMode {
                        Text(verbatim: localizer.text(.localPDFSearchPatternHelp)).font(.caption)
                            .accessibilityIdentifier("skillExecution.localSearch.patternHelp")
                    }
                    Toggle(localizer.text(.localPDFSearchIgnoreASCIICase), isOn: Binding(
                        get: { search?.ignoreASCIICase ?? false },
                        set: { patternSearch.reset(); search?.setIgnoreASCIICase($0) }))
                        .accessibilityIdentifier("skillExecution.localSearch.ignoreASCIICase")
                    if isRunning {
                        Button(localizer.text(.localPDFSearchStop)) { patternSearch.reset() }
                            .accessibilityIdentifier("skillExecution.localSearch.stop")
                        Text(verbatim: localizer.text(.localPDFSearchRunning)).font(.caption)
                            .accessibilityIdentifier("skillExecution.localSearch.running")
                    } else {
                        Button(localizer.text(.localPDFSearchButton)) { performSearch() }
                            .accessibilityIdentifier("skillExecution.localSearch.search")
                    }
                    if let message = errorText(current) {
                        Text(verbatim: localizer.text(message))
                            .accessibilityIdentifier("skillExecution.localSearch.error")
                    }
                    if let found = displayedResult(current) {
                        Text(verbatim: localizer.text(found.hits.isEmpty ? .localPDFSearchEmpty :
                            (found.truncated ? .localPDFSearchTruncated(count: found.hits.count) : .localPDFSearchCount(count: found.hits.count))))
                            .accessibilityIdentifier("skillExecution.localSearch.summary")
                        ForEach(Array(found.hits.enumerated()), id: \.offset) { _, hit in
                            VStack(alignment: .leading) {
                                Text(verbatim: localizer.text(.localPDFSearchHit(page: hit.pageNumber, index: hit.pageIndex)))
                                    .accessibilityIdentifier("skillExecution.localSearch.hit.\(hit.pageIndex)")
                                Text(verbatim: hit.snippet).textSelection(.enabled)
                            }
                        }
                    }
                }
            }
        }
        .onDisappear { patternSearch.reset() }
        #if os(iOS)
        .onChange(of: search?.source.id) { _, _ in patternSearch.reset() }
        #else
        .onChange(of: search?.source.id) { _ in patternSearch.reset() }
        #endif
    }

    private var isRunning: Bool {
        if patternSearch.sourceID == search?.source.id, case .running = patternSearch.state { return true }
        return false
    }

    private func displayedResult(_ current: DocumentLocalSearch) -> DocumentSearchResult? {
        guard patternMode else { return current.result }
        if patternSearch.sourceID == current.source.id, case .completed(let value) = patternSearch.state { return value }
        return nil
    }

    private func errorText(_ current: DocumentLocalSearch) -> AppText? {
        guard patternMode else {
            guard let error = current.error else { return nil }
            return error == .invalidSearch ? .localPDFSearchInvalid : .localPDFSearchFailed
        }
        guard patternSearch.sourceID == current.source.id else { return nil }
        switch patternSearch.state {
        case .failed(.invalidPattern): return .localPDFSearchPatternInvalid
        case .failed(.unsupportedPattern): return .localPDFSearchPatternUnsupported
        case .failed(.budgetExceeded): return .localPDFSearchPatternBudget
        case .failedUnexpectedly: return .localPDFSearchFailed
        default: return nil
        }
    }

    @ViewBuilder private var searchField: some View {
        let field = TextField(localizer.text(.localPDFSearchPlaceholder), text: Binding(
            get: { search?.query ?? "" }, set: { patternSearch.reset(); search?.setQuery($0) }))
            .autocorrectionDisabled()
            .focused($searchFocused)
            .onSubmit { if !isRunning { performSearch() } }
            .accessibilityIdentifier("skillExecution.localSearch.query")
        #if os(iOS)
        field.textInputAutocapitalization(.never).submitLabel(.search)
        #else
        field
        #endif
    }

    private func performSearch() {
        guard let current = search else { return }
        if patternMode {
            search?.clearResults()
            patternSearch.start(source: current.source, pattern: current.query, ignoreASCIICase: current.ignoreASCIICase)
        } else { search?.search() }
        searchFocused = false
    }
}
