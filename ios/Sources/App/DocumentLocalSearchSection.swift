import AssistantSkills
import SwiftUI

/// Presents only an already-authorized in-memory extraction. It has no file,
/// service or model access. Closing/replacing the parent plan drops the state.
struct DocumentLocalSearchSection: View {
    @Binding var search: DocumentLocalSearch?
    let localizer: AppLocalizer

    var body: some View {
        if let current = search {
            Section(localizer.text(.localPDFSearchTitle)) {
                Text(verbatim: localizer.text(.localPDFSearchNotice))
                    .font(.caption)
                searchField
                Button(localizer.text(.localPDFSearchButton)) { search?.search() }
                    .accessibilityIdentifier("skillExecution.localSearch.search")
                if let error = current.error {
                    Text(verbatim: localizer.text(error == .invalidSearch ? .localPDFSearchInvalid : .localPDFSearchFailed))
                        .accessibilityIdentifier("skillExecution.localSearch.error")
                }
                if let found = current.result {
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

    @ViewBuilder private var searchField: some View {
        let field = TextField(localizer.text(.localPDFSearchPlaceholder), text: Binding(
            get: { search?.query ?? "" }, set: { search?.setQuery($0) }))
            .autocorrectionDisabled()
            .accessibilityIdentifier("skillExecution.localSearch.query")
        #if os(iOS)
        field.textInputAutocapitalization(.never)
        #else
        field
        #endif
    }
}
