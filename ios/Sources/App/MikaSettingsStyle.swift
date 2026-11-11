#if os(iOS)
import SwiftUI

/// Settings-only translation of the Android Mika card and icon tokens. The
/// source vectors use a 24 point viewport, 1.7 point round strokes; rows use
/// 30 point tiles with 9 point corners, inside 16 point group cards.
struct MikaSettingsPalette {
    let scheme: ColorScheme

    var page: Color { scheme == .dark ? Color(red: 14/255, green: 14/255, blue: 16/255) : Color(red: 247/255, green: 247/255, blue: 248/255) }
    var surface: Color { scheme == .dark ? Color(red: 26/255, green: 26/255, blue: 29/255) : .white }
    var ink: Color { scheme == .dark ? Color(red: 242/255, green: 242/255, blue: 244/255) : Color(red: 28/255, green: 28/255, blue: 30/255) }
    var secondary: Color { scheme == .dark ? Color(red: 164/255, green: 165/255, blue: 173/255) : Color(red: 95/255, green: 96/255, blue: 104/255) }
    var hint: Color { scheme == .dark ? Color(red: 108/255, green: 109/255, blue: 117/255) : Color(red: 154/255, green: 155/255, blue: 163/255) }
    var border: Color { scheme == .dark ? .white.opacity(0.06) : .black.opacity(0.05) }
    var tile: Color { scheme == .dark ? .white.opacity(0.08) : .black.opacity(0.045) }
}

struct MikaSettingsGroupLabel: View {
    let title: String
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Text(verbatim: title)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(MikaSettingsPalette(scheme: scheme).hint)
            .padding(.top, 8)
            .padding(.bottom, 8)
    }
}

struct MikaSettingsCard<Content: View>: View {
    let content: Content
    @Environment(\.colorScheme) private var scheme

    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(MikaSettingsPalette(scheme: scheme).surface, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(MikaSettingsPalette(scheme: scheme).border, lineWidth: 0.5))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: scheme == .dark ? .clear : .black.opacity(0.035), radius: 6, y: 2)
    }
}

enum MikaSettingsIcon {
    case spark, globe, bell, key, heart, link
}

struct MikaSettingsIconTile: View {
    let icon: MikaSettingsIcon
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        MikaSettingsIconShape(icon: icon)
            .stroke(MikaSettingsPalette(scheme: scheme).ink,
                    style: StrokeStyle(lineWidth: 1.7, lineCap: .round, lineJoin: .round))
            .frame(width: 18, height: 18)
            .frame(width: 30, height: 30)
            .background(MikaSettingsPalette(scheme: scheme).tile, in: RoundedRectangle(cornerRadius: 9))
            .accessibilityHidden(true)
    }
}

struct MikaSettingsRow: View {
    enum Accessory {
        case chevron, none

        var symbol: String? {
            switch self {
            case .chevron: return "chevron.right"
            case .none: return nil
            }
        }
    }

    let icon: MikaSettingsIcon
    let title: String
    let subtitle: String?
    let value: String?
    let accessory: Accessory
    @Environment(\.colorScheme) private var scheme

    init(icon: MikaSettingsIcon, title: String, subtitle: String? = nil,
         value: String? = nil, accessory: Accessory = .chevron) {
        self.icon = icon; self.title = title; self.subtitle = subtitle
        self.value = value; self.accessory = accessory
    }

    var body: some View {
        let colors = MikaSettingsPalette(scheme: scheme)
        HStack(spacing: 14) {
            MikaSettingsIconTile(icon: icon)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: title).font(.body).foregroundStyle(colors.ink)
                if let subtitle {
                    Text(verbatim: subtitle).font(.caption).foregroundStyle(colors.hint)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 4)
            if let value {
                Text(verbatim: value).font(.subheadline).foregroundStyle(colors.hint)
                    .lineLimit(1)
            }
            if let symbol = accessory.symbol {
                Image(systemName: symbol).font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(colors.hint).accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 52)
        .contentShape(Rectangle())
    }
}

struct MikaSettingsIconShape: Shape {
    let icon: MikaSettingsIcon

    func path(in rect: CGRect) -> Path {
        var path = Path()
        switch icon {
        case .spark:
            path.move(to: CGPoint(x: 12, y: 3))
            for point in [(13.9, 8.6), (19.5, 10.5), (13.9, 12.4), (12, 18),
                          (10.1, 12.4), (4.5, 10.5), (10.1, 8.6), (12, 3)] {
                path.addLine(to: CGPoint(x: point.0, y: point.1))
            }
            path.move(to: CGPoint(x: 19, y: 17))
            for point in [(19.7, 19), (21.7, 19.7), (19.7, 20.4), (19, 22.4),
                          (18.3, 20.4), (16.3, 19.7), (18.3, 19), (19, 17)] {
                path.addLine(to: CGPoint(x: point.0, y: point.1))
            }
        case .globe:
            path.addEllipse(in: CGRect(x: 3, y: 3, width: 18, height: 18))
            path.move(to: CGPoint(x: 3, y: 12)); path.addLine(to: CGPoint(x: 21, y: 12))
            path.move(to: CGPoint(x: 12, y: 3))
            path.addCurve(to: CGPoint(x: 12, y: 21),
                          control1: CGPoint(x: 17.1, y: 8.2), control2: CGPoint(x: 17.1, y: 15.8))
            path.addCurve(to: CGPoint(x: 12, y: 3),
                          control1: CGPoint(x: 6.9, y: 15.8), control2: CGPoint(x: 6.9, y: 8.2))
        case .bell:
            path.move(to: CGPoint(x: 18, y: 16))
            path.addLine(to: CGPoint(x: 18, y: 11))
            path.addArc(center: CGPoint(x: 12, y: 11), radius: 6,
                        startAngle: .degrees(0), endAngle: .degrees(180), clockwise: true)
            path.addLine(to: CGPoint(x: 6, y: 16))
            path.addLine(to: CGPoint(x: 4, y: 18))
            path.addLine(to: CGPoint(x: 20, y: 18))
            path.closeSubpath()
            path.move(to: CGPoint(x: 10, y: 20.5))
            path.addQuadCurve(to: CGPoint(x: 14, y: 20.5), control: CGPoint(x: 12, y: 23))
        case .key:
            path.addEllipse(in: CGRect(x: 4, y: 11, width: 8, height: 8))
            path.move(to: CGPoint(x: 10.8, y: 12.2)); path.addLine(to: CGPoint(x: 20, y: 3))
            path.move(to: CGPoint(x: 17, y: 6)); path.addLine(to: CGPoint(x: 20, y: 9))
            path.move(to: CGPoint(x: 14.5, y: 8.5)); path.addLine(to: CGPoint(x: 16.5, y: 10.5))
        case .heart:
            path.move(to: CGPoint(x: 12, y: 21))
            path.addCurve(to: CGPoint(x: 3, y: 11),
                          control1: CGPoint(x: 8, y: 18), control2: CGPoint(x: 3, y: 15))
            path.addCurve(to: CGPoint(x: 12, y: 5.5),
                          control1: CGPoint(x: 3, y: 5), control2: CGPoint(x: 9, y: 3))
            path.addCurve(to: CGPoint(x: 21, y: 11),
                          control1: CGPoint(x: 15, y: 3), control2: CGPoint(x: 21, y: 5))
            path.addCurve(to: CGPoint(x: 12, y: 21),
                          control1: CGPoint(x: 21, y: 15), control2: CGPoint(x: 16, y: 18))
            path.closeSubpath()
        case .link:
            path.move(to: CGPoint(x: 9, y: 9))
            path.addLine(to: CGPoint(x: 12, y: 6))
            path.addCurve(to: CGPoint(x: 18, y: 12),
                          control1: CGPoint(x: 17, y: 1), control2: CGPoint(x: 23, y: 7))
            path.addLine(to: CGPoint(x: 15, y: 15))
            path.move(to: CGPoint(x: 9, y: 15))
            path.addLine(to: CGPoint(x: 12, y: 12))
            path.move(to: CGPoint(x: 15, y: 9))
            path.addLine(to: CGPoint(x: 12, y: 12))
            path.move(to: CGPoint(x: 9, y: 9))
            path.addLine(to: CGPoint(x: 6, y: 12))
            path.addCurve(to: CGPoint(x: 12, y: 18),
                          control1: CGPoint(x: 1, y: 17), control2: CGPoint(x: 7, y: 23))
            path.addLine(to: CGPoint(x: 15, y: 15))
        }
        return path.applying(CGAffineTransform(scaleX: rect.width / 24, y: rect.height / 24)
            .translatedBy(x: rect.minX, y: rect.minY))
    }
}
#endif
