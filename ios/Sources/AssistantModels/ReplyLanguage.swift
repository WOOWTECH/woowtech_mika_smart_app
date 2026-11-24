import Foundation

/// Play's ReplyLanguage: whether a final answer follows the user's language,
/// counted by the writing system of its letters (Unicode script), with no model
/// or word list. Pure functions.
///
/// Scripts form families: Han and kana count together, as Japanese when kana are
/// at least `kanaShare` of the two and as Chinese otherwise; Hangul is Korean;
/// Latin, Cyrillic and the other scripts are a family each. Digits, punctuation,
/// spaces and Markdown marks are not letters.
///
/// Fair across scripts: Chinese and Japanese are written without spaces, so each
/// character is a unit; the other scripts count words, not letters (letters of one
/// script in a row are one word). Latin and Cyrillic words without a lowercase
/// letter (GB, OS, model codes) are mostly units and abbreviations and do not count.
///
/// Left out of the answer: text inside quotes (「」『』“”"" 《》) and brackets (()
/// and （）), code, web addresses and angle-bracket tags, mostly copied or labelled
/// originals that should stay. A line, or a cell split by | or 、, holding a single
/// run of one family of at most `nameUnits` units is taken as a name or a label (an
/// app in a list, a cell in a table) and left out too.
///
/// A mismatch needs at least `minUserUnits` units in the user's words, at least
/// `minAnswerUnits` in the rest of the answer, and the answer's largest family to
/// hold at least `mismatchShare` of it while not being the user's largest family.
public enum ReplyLanguage {
    public static let minUserUnits = 3
    public static let minAnswerUnits = 20
    public static let mismatchShare = 0.6
    public static let nameUnits = 6
    public static let kanaShare = 0.1

    /// A family; `display` is how the model is told about it.
    public struct Family: Hashable, Sendable {
        public let display: String
        public init(_ display: String) { self.display = display }
    }

    public static let chinese = Family("Chinese")
    public static let japanese = Family("Japanese")
    public static let korean = Family("Korean")

    /// The answer's family and the user's.
    public struct Mismatch: Equatable, Sendable {
        public let answer: Family
        public let user: Family
        public init(answer: Family, user: Family) { self.answer = answer; self.user = user }
    }

    /// Both families when the answer's text is clearly not in the language of the
    /// user's words; nil otherwise, or when there is too little text to tell.
    public static func mismatch(user: String, answer: String) -> Mismatch? {
        let u = orderedUnits(user, skipNames: false)
        let a = orderedUnits(stripQuoted(answer), skipNames: true)
        let userTotal = u.reduce(0) { $0 + $1.units }, answerTotal = a.reduce(0) { $0 + $1.units }
        guard userTotal >= minUserUnits, answerTotal >= minAnswerUnits,
              let userFamily = largest(u), let answerFamily = largest(a) else { return nil }
        guard Double(answerFamily.units) >= Double(answerTotal) * mismatchShare,
              answerFamily.family != userFamily.family else { return nil }
        return Mismatch(answer: answerFamily.family, user: userFamily.family)
    }

    /// Units per family in `text` (see the type's notes); with `skipNames`, a line
    /// or cell holding a single short run is not counted.
    public static func units(_ text: String, skipNames: Bool) -> [Family: Int] {
        Dictionary(orderedUnits(text, skipNames: skipNames).map { ($0.family, $0.units) }, uniquingKeysWith: +)
    }

    /// The answer without what is inside quotes, brackets and code, web addresses
    /// and tags (brackets can nest: inner and outer pairs both go).
    public static func stripQuoted(_ text: String) -> String {
        var s = replace(fence, in: text)
        for expression in [inlineCode, url, tag, quotes] { s = replace(expression, in: s) }
        while true {
            let next = replace(parens, in: s)
            if next == s { return s }
            s = next
        }
    }

    // MARK: Counting

    /// First-seen order, so a tie goes to the family that came first, as in Play.
    private static func orderedUnits(_ text: String, skipNames: Bool) -> [(family: Family, units: Int)] {
        let cells = text.components(separatedBy: cellSeparators).map { cell in runs(of: cell).filter { $0.units > 0 } }
        let counted = (skipNames ? cells.filter { !($0.count == 1 && $0[0].units <= nameUnits) } : cells).flatMap { $0 }
        let han = counted.filter { $0.script == .han }.reduce(0) { $0 + $1.units }
        let kana = counted.filter { $0.script == .kana }.reduce(0) { $0 + $1.units }
        let cjk = kana > 0 && Double(kana) >= Double(han + kana) * kanaShare ? japanese : chinese
        var out: [(family: Family, units: Int)] = []
        for run in counted {
            let family: Family
            switch run.script {
            case .han, .kana: family = cjk
            case .hangul: family = korean
            default: family = Family(run.script.rawValue + " script")
            }
            if let index = out.firstIndex(where: { $0.family == family }) { out[index].units += run.units } else { out.append((family, run.units)) }
        }
        return out
    }

    private static func largest(_ units: [(family: Family, units: Int)]) -> (family: Family, units: Int)? {
        var best: (family: Family, units: Int)?
        for item in units where best.map({ item.units > $0.units }) ?? true { best = item }
        return best
    }

    /// Scripts as runs are keyed: Han and kana stay apart until a whole text is
    /// counted. Letters of the scripts not listed share `other`.
    private enum Script: String {
        case han = "Han", kana = "Kana", hangul = "Hangul", latin = "Latin", cyrillic = "Cyrillic", greek = "Greek"
        case arabic = "Arabic", hebrew = "Hebrew", thai = "Thai", devanagari = "Devanagari", other = "Other"
    }

    /// Letters of one script in a row: `units` characters for Han and kana, words otherwise.
    private struct Run { let script: Script; var units: Int }

    /// Letters of one script separated only by spaces, hyphens, apostrophes,
    /// combining marks or letters of no particular script stay in one run. Han and
    /// kana count each character; other scripts count each word, except Latin and
    /// Cyrillic words without a lowercase letter.
    private static func runs(of cell: String) -> [Run] {
        var out: [Run] = []
        var current: Int?
        var word: [Unicode.Scalar] = []
        func endWord() {
            if !word.isEmpty, let index = current, countsAsWord(word) { out[index].units += 1 }
            word.removeAll()
        }
        for scalar in cell.unicodeScalars {
            let category = scalar.properties.generalCategory
            if category == .nonspacingMark || category == .spacingMark { continue }
            if isLetter(category) {
                // A letter of no particular script (the long vowel mark ー and the like) goes with its neighbours.
                guard let script = script(of: scalar) else { continue }
                if current.map({ out[$0].script }) != script {
                    endWord()
                    out.append(Run(script: script, units: 0)); current = out.count - 1
                }
                if script == .han || script == .kana { out[current!].units += 1 } else { word.append(scalar) }
            } else if scalar == " " || scalar == "-" || scalar == "'" || scalar == "\u{2019}" {
                endWord()
            } else {
                endWord()
                current = nil
            }
        }
        endWord()
        return out
    }

    private static func countsAsWord(_ word: [Unicode.Scalar]) -> Bool {
        guard let first = word.first, let script = script(of: first), script == .latin || script == .cyrillic else { return true }
        return word.contains { $0.properties.isLowercase }
    }

    private static func isLetter(_ category: Unicode.GeneralCategory) -> Bool {
        switch category {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter: return true
        default: return false
        }
    }

    /// The script of a letter, by the Unicode ranges that matter here; nil for
    /// letters of the Common script (shared marks such as ー).
    private static func script(of scalar: Unicode.Scalar) -> Script? {
        switch scalar.value {
        case 0x30FC, 0xFF70, 0xFF9E...0xFF9F, 0x3006, 0x3031...0x3035, 0x303C, 0x02B9...0x02DF, 0x02E5...0x02FF,
             0xA700...0xA721, 0xA788...0xA78A:
            return nil
        case 0x2E80...0x2FDF, 0x3005, 0x303B, 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF, 0x20000...0x323AF:
            return .han
        case 0x3041...0x309F, 0x30A0...0x30FF, 0x31F0...0x31FF, 0xFF66...0xFF9D, 0x1B000...0x1B16F:
            return .kana
        case 0x1100...0x11FF, 0x3131...0x318E, 0xA960...0xA97F, 0xAC00...0xD7FF, 0xFFA0...0xFFDC:
            return .hangul
        case 0x0041...0x005A, 0x0061...0x007A, 0x00AA, 0x00BA, 0x00C0...0x00D6, 0x00D8...0x00F6, 0x00F8...0x02B8,
             0x02E0...0x02E4, 0x1D00...0x1D25, 0x1D2C...0x1D5C, 0x1D62...0x1D65, 0x1D6B...0x1D77, 0x1D79...0x1DBE,
             0x1E00...0x1EFF, 0x2071, 0x207F, 0x2090...0x209C, 0x2C60...0x2C7F, 0xA722...0xA787, 0xA78B...0xA7FF,
             0xAB30...0xAB5A, 0xAB5C...0xAB64, 0xFB00...0xFB06, 0xFF21...0xFF3A, 0xFF41...0xFF5A:
            return .latin
        case 0x0400...0x052F, 0x1C80...0x1C8F, 0x1D2B, 0x1D78, 0xA640...0xA69F:
            return .cyrillic
        case 0x0370...0x03FF, 0x1D26...0x1D2A, 0x1D5D...0x1D61, 0x1D66...0x1D6A, 0x1F00...0x1FFF:
            return .greek
        case 0x0600...0x06FF, 0x0750...0x077F, 0x08A0...0x08FF, 0xFB50...0xFDFF, 0xFE70...0xFEFF:
            return .arabic
        case 0x0590...0x05FF, 0xFB1D...0xFB4F:
            return .hebrew
        case 0x0E00...0x0E7F:
            return .thai
        case 0x0900...0x097F, 0xA8E0...0xA8FF:
            return .devanagari
        default:
            return .other
        }
    }

    // MARK: Patterns

    /// Lines, table cells and items listed with 、 are each a cell.
    private static let cellSeparators = CharacterSet(charactersIn: "\n|、")
    private static let fence = pattern("```[\\s\\S]*?```")
    private static let inlineCode = pattern("`[^`\\n]*`")
    /// Play's \b: ICU counts CJK characters as word characters, so a link right
    /// after Chinese text needs the ASCII boundary spelled out.
    private static let url = pattern("(?i)(?<![A-Za-z0-9_])(?:https?://|www\\.)\\S+")
    private static let tag = pattern("<[^<>\\n]*>")
    private static let quotes = pattern("「[^」\\n]*」|『[^』\\n]*』|“[^”\\n]*”|\"[^\"\\n]*\"|《[^》\\n]*》")
    /// Only the innermost pair, again and again until none is left; half-width and
    /// full-width brackets can pair with each other.
    private static let parens = pattern("[(（][^()（）\\n]*[)）]")

    private static func pattern(_ source: String) -> NSRegularExpression {
        // The patterns are constants; a typo shows on the first check run.
        try! NSRegularExpression(pattern: source)
    }

    private static func replace(_ expression: NSRegularExpression, in text: String) -> String {
        expression.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: " ")
    }
}
