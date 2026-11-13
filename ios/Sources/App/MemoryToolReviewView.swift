import AssistantMemory
import SwiftUI

struct MemoryToolReviewView: View {
    let review: MemoryToolReview
    let approve: () -> Void
    let decline: () -> Void
    @Environment(\.appLocalizer) private var localizer

    private var operation: String {
        switch review.op {
        case .add: return localizer.text(.memoryToolAdd)
        case .update: return localizer.text(.memoryToolUpdate)
        case .delete: return localizer.text(.commonDelete)
        }
    }
    private var kind: String {
        switch review.kind {
        case .fact: return localizer.text(.memoryToolKindFact)
        case .preference: return localizer.text(.memoryToolKindPreference)
        case .procedure: return localizer.text(.memoryToolKindProcedure)
        case nil: return localizer.text(.memoryToolKindMemory)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(localizer.text(.memoryToolIntro))
                    Text(operation).font(.headline).accessibilityIdentifier("memoryTool.operation")
                    Text(kind).accessibilityIdentifier("memoryTool.kind")
                    Text(localizer.text(.profileToolQuote)).font(.headline)
                    Text(verbatim: review.quote).textSelection(.enabled).accessibilityIdentifier("memoryTool.quote")
                    if let before = review.before {
                        Text(localizer.text(.profileToolBefore)).font(.headline)
                        Text(verbatim: before.content).textSelection(.enabled).accessibilityIdentifier("memoryTool.before")
                    }
                    if let after = review.after {
                        Text(localizer.text(.profileToolAfter)).font(.headline)
                        Text(verbatim: after.content).textSelection(.enabled).accessibilityIdentifier("memoryTool.after")
                        Text(localizer.text(.memoryToolKeywords)).font(.headline)
                        Text(verbatim: after.keywords.isEmpty ? localizer.text(.memoryToolNoKeywords)
                             : after.keywords.joined(separator: localizer.text(.memoryToolKeywordSeparator)))
                            .accessibilityIdentifier("memoryTool.keywords")
                        if after.status == .pending {
                            Text(localizer.text(.memoryToolPendingNotice))
                                .accessibilityIdentifier("memoryTool.pendingNotice")
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .navigationTitle(localizer.text(.memoryToolTitle))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(localizer.text(.memoryToolDecline), action: decline).accessibilityIdentifier("memoryTool.decline")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(localizer.text(.commonApprove), action: approve).accessibilityIdentifier("memoryTool.approve")
                }
            }
        }
    }
}
