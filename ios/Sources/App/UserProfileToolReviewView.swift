import AssistantMemory
import SwiftUI

struct UserProfileToolReviewView: View {
    let review: UserProfileToolReview
    let approve: () -> Void
    let decline: () -> Void
    @Environment(\.appLocalizer) private var localizer

    private var operation: String {
        switch review.op {
        case .add: return localizer.text(.profileToolAdd)
        case .replace: return localizer.text(.profileToolReplace)
        case .delete: return localizer.text(.commonDelete)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(localizer.text(.profileToolIntro))
                    Text(operation).font(.headline).accessibilityIdentifier("profileTool.operation")
                    Text(localizer.text(.profileToolQuote)).font(.headline)
                    Text(verbatim: review.quote).textSelection(.enabled).accessibilityIdentifier("profileTool.quote")
                    if let before = review.before {
                        Text(localizer.text(.profileToolBefore)).font(.headline)
                        Text(verbatim: before).textSelection(.enabled).accessibilityIdentifier("profileTool.before")
                    }
                    if let after = review.after {
                        Text(localizer.text(.profileToolAfter)).font(.headline)
                        Text(verbatim: after).textSelection(.enabled).accessibilityIdentifier("profileTool.after")
                    } else {
                        Text(localizer.text(.profileToolDeleteNote))
                    }
                }.padding()
            }
            .navigationTitle(localizer.text(.profileToolTitle))
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Button(localizer.text(.profileToolDecline), role: .cancel, action: decline)
                        .accessibilityIdentifier("profileTool.decline")
                    Spacer()
                    Button(localizer.text(.profileToolApprove), action: approve)
                        .buttonStyle(.borderedProminent).accessibilityIdentifier("profileTool.approve")
                }.padding().background(.bar)
            }
        }
    }
}
