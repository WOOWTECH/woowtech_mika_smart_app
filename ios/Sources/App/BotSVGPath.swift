#if WOOWTECHBOT
import SwiftUI

/// Minimal SVG path-data reader, so the Android robot art can be carried over verbatim as the same
/// path strings it was drawn from. It understands M L H V C S Q T A Z in absolute and relative form;
/// anything else makes the whole path empty rather than half drawn.
enum BotSVGPath {
    static func path(_ data: String) -> Path {
        var parser = Parser(Array(data.unicodeScalars))
        return parser.parse() ?? Path()
    }

    private struct Parser {
        private let scalars: [Unicode.Scalar]
        private var index = 0
        private var path = Path()
        private var current = CGPoint.zero
        private var start = CGPoint.zero
        private var lastCubic: CGPoint?
        private var lastQuad: CGPoint?

        init(_ scalars: [Unicode.Scalar]) { self.scalars = scalars }

        mutating func parse() -> Path? {
            var command: Character?
            while true {
                skipSeparators()
                guard index < scalars.count else { return path }
                let scalar = scalars[index]
                if Self.isCommand(scalar) {
                    command = Character(scalar)
                    index += 1
                } else if command == nil {
                    return nil
                } else if command == "M" { command = "L" } else if command == "m" { command = "l" }
                guard let active = command, run(active) else { return nil }
                // Z takes no numbers: anything but a command after it is malformed (and would never advance).
                if active == "Z" || active == "z" { command = nil }
            }
        }

        private static func isCommand(_ scalar: Unicode.Scalar) -> Bool {
            "MmLlHhVvCcSsQqTtAaZz".unicodeScalars.contains(scalar)
        }

        private mutating func skipSeparators() {
            while index < scalars.count, scalars[index] == " " || scalars[index] == "," || scalars[index] == "\n" || scalars[index] == "\t" || scalars[index] == "\r" {
                index += 1
            }
        }

        private mutating func number() -> CGFloat? {
            skipSeparators()
            var text = ""
            var seenDot = false, seenExponent = false
            while index < scalars.count {
                let scalar = scalars[index]
                let character = Character(scalar)
                if (character == "-" || character == "+"), text.isEmpty || text.last == "e" || text.last == "E" {
                    text.append(character)
                } else if character.isNumber, scalar.isASCII {
                    text.append(character)
                } else if character == ".", !seenDot, !seenExponent {
                    seenDot = true
                    text.append(character)
                } else if (character == "e" || character == "E"), !seenExponent, !text.isEmpty {
                    seenExponent = true
                    text.append(character)
                } else {
                    break
                }
                index += 1
            }
            return Double(text).map { CGFloat($0) }
        }

        private mutating func flag() -> Bool? {
            skipSeparators()
            guard index < scalars.count, scalars[index] == "0" || scalars[index] == "1" else { return nil }
            defer { index += 1 }
            return scalars[index] == "1"
        }

        private mutating func point(relative: Bool) -> CGPoint? {
            guard let x = number(), let y = number() else { return nil }
            return relative ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
        }

        private mutating func run(_ command: Character) -> Bool {
            let relative = command.isLowercase
            switch command {
            case "M", "m":
                guard let p = point(relative: relative) else { return false }
                path.move(to: p); current = p; start = p; lastCubic = nil; lastQuad = nil
            case "L", "l":
                guard let p = point(relative: relative) else { return false }
                path.addLine(to: p); current = p; lastCubic = nil; lastQuad = nil
            case "H", "h":
                guard let x = number() else { return false }
                current = CGPoint(x: relative ? current.x + x : x, y: current.y)
                path.addLine(to: current); lastCubic = nil; lastQuad = nil
            case "V", "v":
                guard let y = number() else { return false }
                current = CGPoint(x: current.x, y: relative ? current.y + y : y)
                path.addLine(to: current); lastCubic = nil; lastQuad = nil
            case "C", "c":
                guard let c1 = point(relative: relative), let c2 = point(relative: relative), let end = point(relative: relative) else { return false }
                path.addCurve(to: end, control1: c1, control2: c2); current = end; lastCubic = c2; lastQuad = nil
            case "S", "s":
                let c1 = lastCubic.map { CGPoint(x: 2 * current.x - $0.x, y: 2 * current.y - $0.y) } ?? current
                guard let c2 = point(relative: relative), let end = point(relative: relative) else { return false }
                path.addCurve(to: end, control1: c1, control2: c2); current = end; lastCubic = c2; lastQuad = nil
            case "Q", "q":
                guard let c = point(relative: relative), let end = point(relative: relative) else { return false }
                path.addQuadCurve(to: end, control: c); current = end; lastQuad = c; lastCubic = nil
            case "T", "t":
                let c = lastQuad.map { CGPoint(x: 2 * current.x - $0.x, y: 2 * current.y - $0.y) } ?? current
                guard let end = point(relative: relative) else { return false }
                path.addQuadCurve(to: end, control: c); current = end; lastQuad = c; lastCubic = nil
            case "A", "a":
                guard let rx = number(), let ry = number(), let rotation = number(), let large = flag(), let sweep = flag(),
                      let end = point(relative: relative) else { return false }
                arc(to: end, rx: rx, ry: ry, rotation: rotation, large: large, sweep: sweep)
                lastCubic = nil; lastQuad = nil
            case "Z", "z":
                path.closeSubpath(); current = start; lastCubic = nil; lastQuad = nil
            default:
                return false
            }
            return true
        }

        /// SVG endpoint arc → centre parameterisation (SVG 1.1 implementation notes F.6), drawn as cubics.
        private mutating func arc(to end: CGPoint, rx rawRx: CGFloat, ry rawRy: CGFloat, rotation: CGFloat, large: Bool, sweep: Bool) {
            var rx = abs(rawRx), ry = abs(rawRy)
            let from = current
            current = end
            if from == end { return }
            if rx == 0 || ry == 0 { path.addLine(to: end); return }
            let phi = rotation * .pi / 180
            let cosPhi = cos(phi), sinPhi = sin(phi)
            let dx = (from.x - end.x) / 2, dy = (from.y - end.y) / 2
            let x1 = cosPhi * dx + sinPhi * dy
            let y1 = -sinPhi * dx + cosPhi * dy
            let lambda = (x1 * x1) / (rx * rx) + (y1 * y1) / (ry * ry)
            if lambda > 1 { rx *= lambda.squareRoot(); ry *= lambda.squareRoot() }
            let numerator = rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1
            let denominator = rx * rx * y1 * y1 + ry * ry * x1 * x1
            var factor = denominator == 0 ? 0 : max(0, numerator / denominator).squareRoot()
            if large == sweep { factor = -factor }
            let cxp = factor * rx * y1 / ry
            let cyp = -factor * ry * x1 / rx
            let cx = cosPhi * cxp - sinPhi * cyp + (from.x + end.x) / 2
            let cy = sinPhi * cxp + cosPhi * cyp + (from.y + end.y) / 2
            func angle(_ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> CGFloat {
                let value = atan2(ux * vy - uy * vx, ux * vx + uy * vy)
                return value
            }
            let theta1 = angle(1, 0, (x1 - cxp) / rx, (y1 - cyp) / ry)
            var delta = angle((x1 - cxp) / rx, (y1 - cyp) / ry, (-x1 - cxp) / rx, (-y1 - cyp) / ry)
            if !sweep, delta > 0 { delta -= 2 * .pi }
            if sweep, delta < 0 { delta += 2 * .pi }
            let segments = max(1, Int(ceil(abs(delta) / (.pi / 2))))
            let step = delta / CGFloat(segments)
            let handle = 4.0 / 3.0 * tan(step / 4)
            var angle1 = theta1
            for _ in 0..<segments {
                let angle2 = angle1 + step
                let p1 = CGPoint(x: cos(angle1) - handle * sin(angle1), y: sin(angle1) + handle * cos(angle1))
                let p2 = CGPoint(x: cos(angle2) + handle * sin(angle2), y: sin(angle2) - handle * cos(angle2))
                let p3 = CGPoint(x: cos(angle2), y: sin(angle2))
                func map(_ p: CGPoint) -> CGPoint {
                    let x = rx * p.x, y = ry * p.y
                    return CGPoint(x: cosPhi * x - sinPhi * y + cx, y: sinPhi * x + cosPhi * y + cy)
                }
                path.addCurve(to: map(p3), control1: map(p1), control2: map(p2))
                angle1 = angle2
            }
        }
    }
}

/// A path drawn in `viewBox` units, scaled to fit the frame it is given.
struct BotSVGShape: Shape {
    let data: String
    let viewBox: CGSize
    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width / viewBox.width, rect.height / viewBox.height)
        let origin = CGPoint(x: rect.minX + (rect.width - viewBox.width * scale) / 2, y: rect.minY + (rect.height - viewBox.height * scale) / 2)
        return BotSVGPath.path(data).applying(CGAffineTransform(translationX: origin.x, y: origin.y).scaledBy(x: scale, y: scale))
    }
}
#endif
