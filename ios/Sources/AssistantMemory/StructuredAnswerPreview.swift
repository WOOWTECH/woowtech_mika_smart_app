import Foundation

/// A deliberately narrow display parser for the structured ordinary-chat wire
/// format. It recognizes an action-first `finish` envelope, and emits only the
/// decoded `answer` string. All other envelopes are buffered by the caller for
/// the existing whole-command validator. A preview is never authorization.
struct StructuredAnswerPreview {
    private enum Phase { case prefix, answer, closed, finished, rejected }
    private enum Escape {
        case none, marker, digits(remaining: Int, value: UInt16)
        case lowSlash(high: UInt16), lowU(high: UInt16)
        case lowDigits(high: UInt16, remaining: Int, value: UInt16)
    }

    private static let prefix = ["{", "\"action\"", ":", "\"finish\"", ",", "\"answer\"", ":", "\""].map { Array($0.utf8) }
    private var phase = Phase.prefix
    private var token = 0, tokenByte = 0
    private var escape = Escape.none
    private var literal: [UInt8] = []
    private(set) var current: String?
    var isRejected: Bool { phase == .rejected }

    /// Delivers a new visible value, if any. Input is already bounded by the
    /// whole-turn 24 KiB limit. No malformed escape or unfinished surrogate is
    /// ever decoded as replacement text.
    mutating func append(_ delta: String) -> String? {
        guard !delta.isEmpty else { return nil }
        let old = current
        for byte in delta.utf8 {
            switch phase {
            case .prefix: consumePrefix(byte)
            case .answer: consumeAnswer(byte)
            case .closed:
                if byte == 125 { phase = .finished }
                else if !Self.space(byte) { phase = .rejected }
            case .finished:
                if !Self.space(byte) { phase = .rejected }
            case .rejected: break
            }
        }
        if phase == .answer || phase == .closed || phase == .finished { flushLiteral() }
        if phase == .rejected { current = nil }
        return current != old ? current : nil
    }

    private mutating func consumePrefix(_ byte: UInt8) {
        if tokenByte == 0 && Self.space(byte) { return }
        let expected = Self.prefix[token]
        guard byte == expected[tokenByte] else { phase = .rejected; return }
        tokenByte += 1
        if tokenByte == expected.count {
            token += 1; tokenByte = 0
            if token == Self.prefix.count { phase = .answer }
        }
    }

    private mutating func consumeAnswer(_ byte: UInt8) {
        switch escape {
        case .none:
            if byte == 34 { flushLiteral(); phase = .closed }
            else if byte == 92 { flushLiteral(); escape = .marker }
            else if byte < 32 { phase = .rejected }
            else { literal.append(byte) }
        case .marker:
            switch byte {
            case 34: add("\"")
            case 92: add("\\")
            case 47: add("/")
            case 98: add("\u{08}")
            case 102: add("\u{0C}")
            case 110: add("\n")
            case 114: add("\r")
            case 116: add("\t")
            case 117: escape = .digits(remaining: 4, value: 0)
            default: phase = .rejected
            }
        case .digits(let remaining, let value):
            guard let digit = Self.hex(byte) else { phase = .rejected; return }
            let next = (value << 4) | digit
            if remaining > 1 { escape = .digits(remaining: remaining - 1, value: next) }
            else if (0xD800...0xDBFF).contains(next) { escape = .lowSlash(high: next) }
            else if let scalar = UnicodeScalar(UInt32(next)) { add(String(scalar)) }
            else { phase = .rejected }
        case .lowSlash(let high):
            if byte == 92 { escape = .lowU(high: high) }
            else { phase = .rejected }
        case .lowU(let high):
            if byte == 117 { escape = .lowDigits(high: high, remaining: 4, value: 0) }
            else { phase = .rejected }
        case .lowDigits(let high, let remaining, let value):
            guard let digit = Self.hex(byte) else { phase = .rejected; return }
            let next = (value << 4) | digit
            if remaining > 1 { escape = .lowDigits(high: high, remaining: remaining - 1, value: next) }
            else if (0xDC00...0xDFFF).contains(next) {
                let codepoint = 0x10000 + (UInt32(high - 0xD800) << 10) + UInt32(next - 0xDC00)
                if let scalar = UnicodeScalar(codepoint) { add(String(scalar)) }
                else { phase = .rejected }
            } else { phase = .rejected }
        }
    }

    private mutating func add(_ value: String) {
        current = (current ?? "") + value
        escape = .none
    }

    private mutating func flushLiteral() {
        guard !literal.isEmpty else { return }
        guard let value = String(bytes: literal, encoding: .utf8) else {
            phase = .rejected; current = nil; literal.removeAll(); return
        }
        current = (current ?? "") + value
        literal.removeAll(keepingCapacity: true)
    }

    private static func space(_ byte: UInt8) -> Bool { byte == 32 || byte == 9 || byte == 10 || byte == 13 }
    private static func hex(_ byte: UInt8) -> UInt16? {
        switch byte {
        case 48...57: return UInt16(byte - 48)
        case 65...70: return UInt16(byte - 55)
        case 97...102: return UInt16(byte - 87)
        default: return nil
        }
    }
}
