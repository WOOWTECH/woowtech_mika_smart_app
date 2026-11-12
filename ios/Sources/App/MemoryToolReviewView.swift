import AssistantMemory
import SwiftUI

struct MemoryToolReviewView: View {
    @Environment(\.appLocalizer) private var localizer
    let review: MemoryToolReview
    let approve: () -> Void
    let decline: () -> Void

    private var operation: AppText {
        switch review.op { case .add: return .toolReviewAdd; case .update: return .toolReviewUpdate; case .delete: return .toolReviewDelete }
    }
    private var kind: AppText {
        switch review.kind { case .fact: return .toolReviewKindFact; case .preference: return .toolReviewKindPreference; case .procedure: return .toolReviewKindProcedure; case nil: return .toolReviewKindMemory }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(localizer.text(.memoryToolReviewHelp))
                    Text(localizer.text(operation)).font(.headline).accessibilityIdentifier("memoryTool.operation")
                    Text(localizer.text(kind)).accessibilityIdentifier("memoryTool.kind")
                    Text(localizer.text(.toolReviewQuote)).font(.headline)
                    Text(verbatim: review.quote).textSelection(.enabled).accessibilityIdentifier("memoryTool.quote")
                    if let before = review.before {
                        Text(localizer.text(.toolReviewBefore)).font(.headline)
                        Text(verbatim: before.content).textSelection(.enabled).accessibilityIdentifier("memoryTool.before")
                    }
                    if let after = review.after {
                        Text(localizer.text(.toolReviewAfter)).font(.headline)
                        Text(verbatim: after.content).textSelection(.enabled).accessibilityIdentifier("memoryTool.after")
                        Text(localizer.text(.toolReviewKeywords)).font(.headline)
                        Text(verbatim: after.keywords.isEmpty ? localizer.text(.toolReviewNone) : after.keywords.joined(separator: localizer.text(.attachmentDataSeparator)))
                            .accessibilityIdentifier("memoryTool.keywords")
                        if after.status == .pending {
                            Text(localizer.text(.memoryToolReviewPending))
                                .accessibilityIdentifier("memoryTool.pendingNotice")
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .navigationTitle(localizer.text(.memoryToolReviewTitle))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(localizer.text(.memoryToolReviewDecline), action: decline).accessibilityIdentifier("memoryTool.decline")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(localizer.text(.memoryToolReviewApprove), action: approve).accessibilityIdentifier("memoryTool.approve")
                }
            }
        }
    }
}
