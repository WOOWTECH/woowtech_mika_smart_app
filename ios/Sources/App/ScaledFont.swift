import SwiftUI

/// A system font of a fixed design size that follows the person's text size like a text
/// style does: `size` at the default size, scaled with the style nearest to it. The
/// screens were drawn at fixed sizes; this keeps that look and lets it grow.
struct ScaledSystemFont: ViewModifier {
    @ScaledMetric private var size: CGFloat
    private let weight: Font.Weight
    private let design: Font.Design

    init(size: CGFloat, weight: Font.Weight, design: Font.Design) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: Self.style(near: size))
        self.weight = weight
        self.design = design
    }

    func body(content: Content) -> some View {
        content.font(.system(size: size, weight: weight, design: design))
    }

    /// The text style whose default size is nearest, so each size grows at its own pace.
    static func style(near size: CGFloat) -> Font.TextStyle {
        switch size {
        case ..<12: return .caption2
        case ..<13: return .caption
        case ..<14.5: return .footnote
        case ..<16: return .subheadline
        case ..<18: return .body
        case ..<21: return .title3
        case ..<25: return .title2
        default: return .title
        }
    }
}

extension View {
    func scaledFont(size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> some View {
        modifier(ScaledSystemFont(size: size, weight: weight, design: design))
    }
}
