import SwiftUI

/// Keep readable content centred on wide windows without narrowing the canvas.
/// A background inside the 720 pt chat frame exposed the navigation host's
/// black/white gutters on iPad. Paint after expanding, including container safe
/// areas; this changes neither keyboard avoidance nor transcript geometry.
enum MikaPageLayout {
    static let readableWidth: CGFloat = 720
}

/// Unlike a maxHeight frame, this keeps short content at its natural height.
/// A ViewThatFits child can switch to scrolling when its ideal height exceeds
/// the budget, without geometry-to-state updates during keyboard animation.
struct MikaContentHeightLimit: Layout {
    let maximumHeight: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let content = subviews.first else { return .zero }
        let ideal = content.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil))
        return CGSize(width: ideal.width, height: min(ideal.height, max(0, maximumHeight)))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, anchor: .topLeading,
                             proposal: ProposedViewSize(bounds.size))
    }
}

extension View {
    func mikaReadableColumn(maxWidth: CGFloat = MikaPageLayout.readableWidth) -> some View {
        frame(maxWidth: maxWidth)
            .frame(maxWidth: .infinity)
    }

    func mikaPageCanvas(_ color: Color) -> some View {
        background { color.ignoresSafeArea(.container) }
    }
}

/// Done stays in the page layout, avoiding SwiftUI's InputAccessoryBar frame.
/// Focus owns visibility, including when a hardware keyboard is connected.
struct MikaKeyboardDoneBar: View {
    struct Action {
        let title: String
        let identifier: String
        let perform: () -> Void
    }

    let title: String
    let identifier: String
    var leadingAction: Action? = nil
    let dismiss: () -> Void
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        HStack(spacing: 0) {
            if let leadingAction {
                actionButton(leadingAction.title, identifier: leadingAction.identifier, action: leadingAction.perform)
            }
            Spacer(minLength: 0)
            actionButton(title, identifier: identifier, action: dismiss)
        }
        .frame(maxWidth: .infinity)
        .background {
            if reduceTransparency { Color(uiColor: .systemBackground) }
            else { Rectangle().fill(.regularMaterial) }
        }
    }

    private func actionButton(_ title: String, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.tint)
        .accessibilityIdentifier(identifier)
    }
}
