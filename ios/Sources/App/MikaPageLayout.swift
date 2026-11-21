import SwiftUI

/// Keep readable content centred on wide windows without narrowing the canvas.
/// A background inside the 720 pt chat frame exposed the navigation host's
/// black/white gutters on iPad. Paint after expanding, including container safe
/// areas; this changes neither keyboard avoidance nor transcript geometry.
enum MikaPageLayout {
    static let readableWidth: CGFloat = 720
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
