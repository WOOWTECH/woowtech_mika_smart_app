#if WOOWTECHBOT
import AssistantPersistence
import SwiftUI

/// A conversation's identity tile (Android `BotUiAvatar.kt`): a coloured rounded square with the design's robot, drawn in
/// its own 32-unit space (a 24-unit body at translate(5, 5) scale(.92)), or an uploaded picture cropped the same way.
struct BotAvatar: View {
    let avatar: BotConversationAvatar

    /// woowtechbot's eleven bot colours, in the website's order; `BotConversationAvatar.colorIndex` indexes this list.
    static let colors: [(zh: String, en: String, color: Color)] = [
        ("綠色", "Green", Color(botHex: 0x009957)), ("藍色", "Blue", Color(botHex: 0x377FE6)), ("紅色", "Red", Color(botHex: 0xD94B52)),
        ("橘色", "Orange", Color(botHex: 0xE78531)), ("紫色", "Purple", Color(botHex: 0x8057C8)), ("青色", "Cyan", Color(botHex: 0x0EA5C6)),
        ("粉色", "Pink", Color(botHex: 0xD84F8B)), ("黃色", "Yellow", Color(botHex: 0xD8A729)), ("青綠", "Teal", Color(botHex: 0x01A492)),
        ("珊瑚", "Coral", Color(botHex: 0xE5634E)), ("銀色", "Silver", Color(botHex: 0xA8ADB4)),
    ]
    /// Orange, yellow and silver are too light for a white robot, so the automatic face is dark there.
    private static let darkInkColors: Set<Int> = [3, 7, 10]
    private static let darkInk = Color(botHex: 0x111111)
    private static let classicBody = BotSVGPath.path("M10 7h4a7 7 0 0 1 7 7v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-6a7 7 0 0 1 7-7Z")
    private static let squareEars = BotSVGPath.path("M4 9 2 4h2l3 4M20 9l2-5h-2l-3 4")
    private static let eyes = BotSVGPath.path("M6.3 14.6q1.7-3 3.4 0M14.3 14.6q1.7-3 3.4 0")

    var body: some View {
        Group {
            if let data = avatar.jpeg, let image = UIImage(data: data) {
                GeometryReader { proxy in
                    let side = min(proxy.size.width, proxy.size.height)
                    Image(uiImage: image).resizable().scaledToFill().frame(width: side, height: side)
                        .clipShape(RoundedRectangle(cornerRadius: side * 0.27))
                }
            } else {
                Canvas { context, size in Self.draw(avatar, in: context, size: size) }
            }
        }
        .aspectRatio(1, contentMode: .fit).accessibilityHidden(true)
    }

    private static func draw(_ avatar: BotConversationAvatar, in context: GraphicsContext, size: CGSize) {
        let index = min(max(avatar.colorIndex, 0), colors.count - 1)
        let tile = colors[index].color
        let ink: Color
        switch avatar.faceMode {
        case 1: ink = .white
        case 2: ink = darkInk
        default: ink = darkInkColors.contains(index) ? darkInk : .white
        }
        let unit = min(size.width, size.height) / 32
        context.fill(Path(roundedRect: CGRect(x: 0, y: 0, width: 32 * unit, height: 32 * unit), cornerRadius: 8.5 * unit), with: .color(tile))
        var body = context
        body.translateBy(x: 5 * unit, y: 5 * unit)
        body.scaleBy(x: 0.92 * unit, y: 0.92 * unit)
        func roundRect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> Path {
            Path(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerRadius: r)
        }
        func circle(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat) -> Path {
            Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: 2 * r, height: 2 * r))
        }
        switch avatar.robot {
        case 0:
            body.fill(classicBody, with: .color(ink))
            body.fill(roundRect(1, 14, 3, 5, 1), with: .color(ink))
            body.fill(roundRect(20, 14, 3, 5, 1), with: .color(ink))
            body.fill(Path(CGRect(x: 11, y: 4, width: 2, height: 5)), with: .color(ink))
            body.fill(circle(12, 4, 2), with: .color(ink))
            body.stroke(eyes, with: .color(tile), lineWidth: 1.6)
        case 1:
            body.fill(roundRect(3, 7, 18, 14, 4), with: .color(ink))
            body.fill(squareEars, with: .color(ink))
            body.stroke(eyes, with: .color(tile), lineWidth: 1.6)
            body.fill(roundRect(9, 18, 6, 1.4, 0.7), with: .color(tile))
        default:
            body.fill(roundRect(3, 6, 18, 16, 8), with: .color(ink))
            body.fill(Path(CGRect(x: 11, y: 3, width: 2, height: 5)), with: .color(ink))
            body.fill(circle(12, 3, 1.5), with: .color(ink))
            body.stroke(eyes, with: .color(tile), lineWidth: 1.6)
            body.fill(circle(12, 18, 1.2), with: .color(tile))
        }
    }
}

extension Color {
    init(botHex hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xff) / 255, green: Double((hex >> 8) & 0xff) / 255, blue: Double(hex & 0xff) / 255)
    }
}
#endif
