import AssistantMemory
import SwiftUI

struct UserProfileToolReviewView: View {
    @Environment(\.appLocalizer) private var localizer
    let review: UserProfileToolReview
    let approve: () -> Void
    let decline: () -> Void

    private var operation: AppText {
        switch review.op { case .add: return .toolReviewAdd; case .replace: return .toolReviewUpdate; case .delete: return .toolReviewDelete }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(localizer.text(.profileToolReviewHelp))
                    Text(localizer.text(operation)).font(.headline).accessibilityIdentifier("profileTool.operation")
                    Text(localizer.text(.toolReviewQuote)).font(.headline)
                    Text(verbatim: review.quote).textSelection(.enabled).accessibilityIdentifier("profileTool.quote")
                    if let before = review.before {
                        Text(localizer.text(.toolReviewBefore)).font(.headline)
                        Text(verbatim: before).textSelection(.enabled).accessibilityIdentifier("profileTool.before")
                    }
                    if let after = review.after {
                        Text(localizer.text(.toolReviewAfter)).font(.headline)
                        Text(verbatim: after).textSelection(.enabled).accessibilityIdentifier("profileTool.after")
                    } else {
                        Text(localizer.text(.profileToolReviewDeleted))
                    }
                }.padding()
            }
            .navigationTitle(localizer.text(.profileToolReviewTitle))
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Button(localizer.text(.profileToolReviewDecline), role: .cancel, action: decline)
                        .accessibilityIdentifier("profileTool.decline")
                    Spacer()
                    Button(localizer.text(.profileToolReviewApprove), action: approve)
                        .buttonStyle(.borderedProminent).accessibilityIdentifier("profileTool.approve")
                }.padding().background(.bar)
            }
        }
    }
}
