import Foundation
import SwiftUI

/// Display-only formatting for assistant answers. The model's original bytes
/// remain in ChatEntry, the archive, and the streaming preview. This renderer
/// never loads a URL, evaluates HTML, creates an image, or runs code.
enum ChatReplyMarkdown {
    enum Fallback: Equatable {
        case tooLarge, rawHTML, image, extendedAttribute, unsafeLink, unclosedFence, invalidMarkdown
    }

    enum Mode: Equatable {
        case formatted
        case verbatim(Fallback)
    }

    /// What the bubble lays out. Android renders tables and code blocks as
    /// their own blocks, which one SwiftUI Text cannot; `text` keeps the whole
    /// reply as one string for accessibility, copying and the checks.
    enum Block: Equatable {
        case text(AttributedString)
        case code([String])
        case table(header: [AttributedString], rows: [[AttributedString]])
    }

    struct Result {
        let text: AttributedString
        let mode: Mode
        var blocks: [Block]
        var visibleText: String { String(text.characters) }
        /// True when the reply has a table or a code block to lay out.
        var hasRichBlocks: Bool { blocks.contains { if case .text = $0 { return false } else { return true } } }
    }

    static let maximumUTF8Bytes = 64 * 1024
    static let maximumLines = 512
    static let maximumStreamingUTF8Bytes = 8 * 1024
    private static let maximumLineUTF8Bytes = 8 * 1024

    static func render(_ source: String, streaming: Bool = false) -> AttributedString {
        parse(source, streaming: streaming).text
    }

    static func parse(_ source: String, streaming: Bool = false) -> Result {
        func raw(_ reason: Fallback) -> Result {
            Result(text: AttributedString(source), mode: .verbatim(reason), blocks: [.text(AttributedString(source))])
        }

        // The native Text has no image or HTML renderer. Showing the source
        // verbatim also preserves destinations that an inline parser might hide.
        let byteLimit = streaming ? maximumStreamingUTF8Bytes : maximumUTF8Bytes
        guard source.utf8.prefix(byteLimit + 1).count <= byteLimit else {
            return raw(.tooLarge)
        }
        guard !source.contains("<") || !source.contains(">") else { return raw(.rawHTML) }
        guard !source.contains("![") else { return raw(.image) }
        guard !source.contains("^[") else { return raw(.extendedAttribute) }

        let lines = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard lines.count <= maximumLines,
              lines.allSatisfy({ $0.utf8.count <= maximumLineUTF8Bytes }) else { return raw(.tooLarge) }

        var output: [AttributedString] = []
        var fence: Fence?
        var inTable = false
        // The same lines as blocks: paragraphs, fenced code, and tables.
        var blocks: [Block] = []
        var paragraph: [AttributedString] = []
        var codeLines: [String] = []
        var table: (header: [String], rows: [[String]], divider: Int)?
        // A display formula written between $$ (or \[ \]) lines of their own.
        var mathLines: [String]?
        func keep(_ line: AttributedString) { output.append(line); paragraph.append(line) }
        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            var joined = AttributedString()
            for (index, part) in paragraph.enumerated() {
                if index != 0 { joined += AttributedString("\n") }
                joined += part
            }
            blocks.append(.text(joined)); paragraph = []
        }
        func flushTable() throws {
            guard let current = table else { return }
            let width = current.header.count
            let rows = current.rows.map { row in Array((row + Array(repeating: "", count: max(0, width - row.count))).prefix(width)) }
            blocks.append(.table(header: try current.header.map { try inline($0) }, rows: try rows.map { try $0.map { try inline($0) } }))
            table = nil
        }
        do {
            for index in lines.indices {
                let line = lines[index]
                if let currentFence = fence {
                    if isClosingFence(line, for: currentFence) {
                        fence = nil
                        blocks.append(.code(codeLines)); codeLines = []
                        continue
                    }
                    output.append(code(line)); codeLines.append(line)
                    continue
                }
                if mathLines != nil {
                    if ChatReplyMath.isBlockDelimiter(line) {
                        keep(try inline(ChatReplyMath.display(mathLines ?? []), math: false)); mathLines = nil
                    } else {
                        mathLines?.append(line)
                    }
                    continue
                }
                if ChatReplyMath.isBlockDelimiter(line), !inTable {
                    flushParagraph(); try flushTable()
                    mathLines = []
                    continue
                }
                if isFenceCandidate(line) {
                    guard let opening = openingFence(line) else { return raw(.invalidMarkdown) }
                    fence = opening
                    flushParagraph(); try flushTable()
                    continue
                }
                if inTable {
                    if !line.isEmpty && line.contains("|") {
                        output.append(code(line))
                        if index != table?.divider { table?.rows.append(tableCells(line)) }
                        continue
                    }
                    inTable = false
                    try flushTable()
                }
                if lines.indices.contains(index + 1), isTableDivider(lines[index + 1], for: line) {
                    inTable = true
                    output.append(code(line))
                    flushParagraph()
                    table = (tableCells(line), [], index + 1)
                    continue
                }
                if line.hasPrefix("    ") {
                    // Indented code and unsupported list continuations stay
                    // literal; they must not gain an accidental Markdown link.
                    keep(code(line))
                } else if isRule(line) {
                    var rule = AttributedString("────────────")
                    rule.foregroundColor = .secondary
                    keep(rule)
                } else if let heading = heading(line) {
                    var title = try inline(heading.text)
                    // Text styles, so a heading grows with the person's text size (20, 17 and 16 pt by default).
                    title.font = heading.level == 1 ? .title3.weight(.semibold)
                        : heading.level == 2 ? .headline : .callout.weight(.semibold)
                    keep(title)
                } else if let quotation = quote(line) {
                    var marker = AttributedString("│ ")
                    marker.foregroundColor = .secondary
                    keep(marker + (try inline(quotation)))
                } else if let list = listItem(line) {
                    var marker = AttributedString(String(repeating: "  ", count: list.depth) + list.marker)
                    marker.foregroundColor = .secondary
                    keep(marker + (try inline(list.text)))
                } else {
                    keep(try inline(line))
                }
            }
            // An unclosed formula block stays as written.
            for line in mathLines ?? [] { keep(try inline(line)) }
            try flushTable()
            flushParagraph()
        } catch ParseError.unsafeLink {
            return raw(.unsafeLink)
        } catch {
            return raw(.invalidMarkdown)
        }
        guard fence == nil else { return raw(.unclosedFence) }
        guard !output.isEmpty || source.isEmpty else { return raw(.invalidMarkdown) }
        var joined = AttributedString()
        for (index, part) in output.enumerated() {
            if index != 0 { joined += AttributedString("\n") }
            joined += part
        }
        return Result(text: joined, mode: .formatted, blocks: blocks)
    }

    private enum ParseError: Error { case unsafeLink }

    private static func inline(_ source: String, math: Bool = true) throws -> AttributedString {
        let source = math ? ChatReplyMath.render(source) : source
        var options = AttributedString.MarkdownParsingOptions()
        options.interpretedSyntax = .inlineOnlyPreservingWhitespace
        options.allowsExtendedAttributes = false
        var result = try AttributedString(markdown: source, options: options, baseURL: nil)
        for run in result.runs {
            if let destination = run.link, !allowedLink(destination) { throw ParseError.unsafeLink }
        }
        // Chinese has no italic face, and inline code in a CJK sentence looks like the words
        // around it: emphasis also gets a dotted underline, and inline code a light fill, so
        // both show in any script (iPhone run of 283).
        for (intent, range) in result.runs[\.inlinePresentationIntent] {
            guard let intent else { continue }
            if intent.contains(.code) { result[range].backgroundColor = Color.primary.opacity(0.08) }
            if intent.contains(.emphasized) { result[range].underlineStyle = Text.LineStyle(pattern: .dot) }
        }
        return result
    }

    private static func allowedLink(_ destination: URL) -> Bool {
        guard let scheme = destination.scheme?.lowercased() else { return false }
        switch scheme {
        case "https", "http":
            return destination.host?.isEmpty == false && destination.user == nil && destination.password == nil
        case "mailto", "tel":
            return destination.absoluteString.count > scheme.count + 1
        default:
            return false
        }
    }

    private struct Fence {
        let character: Character
        let length: Int
    }

    private static func isFenceCandidate(_ line: String) -> Bool {
        let indentation = line.prefix(while: { $0 == " " }).count
        guard indentation <= 3 else { return false }
        let rest = line.dropFirst(indentation)
        guard let marker = rest.first, marker == "`" || marker == "~" else { return false }
        return rest.prefix(while: { $0 == marker }).count >= 3
    }

    private static func openingFence(_ line: String) -> Fence? {
        let indentation = line.prefix(while: { $0 == " " }).count
        guard indentation <= 3 else { return nil }
        let rest = line.dropFirst(indentation)
        guard let character = rest.first, character == "`" || character == "~" else { return nil }
        let length = rest.prefix(while: { $0 == character }).count
        guard length >= 3 else { return nil }
        if character == "`", rest.dropFirst(length).contains("`") { return nil }
        let info = rest.dropFirst(length).trimmingCharacters(in: .whitespaces)
        guard info.count <= 40,
              info.allSatisfy({ $0.isLetter || $0.isNumber || "_+.-".contains($0) }) else { return nil }
        return Fence(character: character, length: length)
    }

    private static func isClosingFence(_ line: String, for fence: Fence) -> Bool {
        let indentation = line.prefix(while: { $0 == " " }).count
        guard indentation <= 3 else { return false }
        let rest = line.dropFirst(indentation)
        let length = rest.prefix(while: { $0 == fence.character }).count
        return length >= fence.length && rest.dropFirst(length).allSatisfy(\.isWhitespace)
    }

    private static func heading(_ line: String) -> (level: Int, text: String)? {
        let indentation = line.prefix(while: { $0 == " " }).count
        guard indentation <= 3 else { return nil }
        let rest = line.dropFirst(indentation)
        let level = rest.prefix(while: { $0 == "#" }).count
        guard (1...6).contains(level), rest.dropFirst(level).first == " " else { return nil }
        return (level, String(rest.dropFirst(level + 1)))
    }

    private static func quote(_ line: String) -> String? {
        let indentation = line.prefix(while: { $0 == " " }).count
        guard indentation <= 3 else { return nil }
        let rest = line.dropFirst(indentation)
        guard rest.first == ">" else { return nil }
        var content = rest.dropFirst()
        if content.first == " " { content = content.dropFirst() }
        return String(content)
    }

    private static func listItem(_ line: String) -> (depth: Int, marker: String, text: String)? {
        let indentation = line.prefix(while: { $0 == " " }).count
        guard indentation <= 6 else { return nil }
        let rest = line.dropFirst(indentation)
        let depth = indentation / 2
        if let first = rest.first, "-*+".contains(first), rest.dropFirst().first == " " {
            return (depth, depth.isMultiple(of: 2) ? "• " : "◦ ", String(rest.dropFirst(2)))
        }
        let digits = rest.prefix(while: { $0.isNumber })
        guard (1...4).contains(digits.count),
              let delimiter = rest.dropFirst(digits.count).first, delimiter == "." || delimiter == ")",
              rest.dropFirst(digits.count + 1).first == " " else { return nil }
        return (depth, String(digits) + ". ", String(rest.dropFirst(digits.count + 2)))
    }

    private static func isRule(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let marker = trimmed.first, "-*_".contains(marker) else { return false }
        let marks = trimmed.filter { !$0.isWhitespace }
        return marks.count >= 3 && marks.allSatisfy { $0 == marker }
    }

    private static func tableCells(_ line: String) -> [String] {
        line.trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "|"))
            .split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func isTableDivider(_ divider: String, for header: String) -> Bool {
        guard header.contains("|"), divider.contains("|") else { return false }
        let headings = tableCells(header), rules = tableCells(divider)
        return headings.count == rules.count && !rules.isEmpty && rules.allSatisfy { cell in
            let center = cell.trimmingCharacters(in: CharacterSet(charactersIn: ":"))
            return center.count >= 3 && center.allSatisfy { $0 == "-" }
        }
    }

    private static func code(_ source: String) -> AttributedString {
        var text = AttributedString(source)
        text.font = .system(.body, design: .monospaced)
        return text
    }
}

/// LaTeX math in a reply, shown as Unicode text: `$E=mc^2$` as E=mc², `\frac{1}{3}` as
/// 1/3, Greek letters and the usual operators as their symbols. The reply keeps its
/// source; only what the chat shows changes. Inline code is left as written, and a
/// dollar sign is math only around something TeX-like with no space inside its edges
/// (Pandoc's rule), so prices such as $4,990 stay text.
enum ChatReplyMath {
    /// One line: inline `$…$`, `\(…\)` and one-line `$$…$$`, `\[…\]` outside inline code.
    static func render(_ line: String) -> String {
        guard line.contains("$") || line.contains("\\(") || line.contains("\\[") else { return line }
        var output = "", rest = Substring(line)
        // Inline code spans stay as written.
        while let tick = rest.firstIndex(of: "`") {
            output += mathOutsideCode(rest[..<tick])
            let run = rest[tick...].prefix { $0 == "`" }
            let afterRun = rest.index(tick, offsetBy: run.count)
            if let close = rest[afterRun...].range(of: String(run)) {
                output += rest[tick..<close.upperBound]
                rest = rest[close.upperBound...]
            } else {
                output += rest[tick...]
                rest = ""
            }
        }
        return output + mathOutsideCode(rest)
    }

    /// A line that opens or closes a display block written on lines of its own.
    static func isBlockDelimiter(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed == "$$" || trimmed == "\\[" || trimmed == "\\]"
    }

    /// A display block's lines, converted.
    static func display(_ lines: [String]) -> String { escaped(convert(lines.joined(separator: " "))) }

    private static func mathOutsideCode(_ text: Substring) -> String {
        var output = "", index = text.startIndex
        while index < text.endIndex {
            if let (end, tex) = delimited(text, at: index) {
                output += escaped(convert(tex)); index = end
            } else {
                output.append(text[index]); index = text.index(after: index)
            }
        }
        return output
    }

    /// The math starting at `index` and where it ends, or nil when this is not math.
    private static func delimited(_ text: Substring, at index: Substring.Index) -> (Substring.Index, String)? {
        let rest = text[index...]
        for (open, close) in [("$$", "$$"), ("\\[", "\\]"), ("\\(", "\\)")] where rest.hasPrefix(open) {
            let start = text.index(index, offsetBy: open.count)
            guard let end = text[start...].range(of: close) else { return nil }
            let tex = String(text[start..<end.lowerBound])
            return tex.trimmingCharacters(in: .whitespaces).isEmpty ? nil : (end.upperBound, tex)
        }
        guard rest.hasPrefix("$") else { return nil }
        let start = text.index(after: index)
        guard start < text.endIndex, !text[start].isWhitespace, !text[start].isNumber || texLike(text[start...]) else { return nil }
        var cursor = start
        while let close = text[cursor...].firstIndex(of: "$") {
            let before = text[text.index(before: close)]
            let after = text.index(after: close)
            let closes = !before.isWhitespace && before != "\\" && (after == text.endIndex || !text[after].isNumber)
            if closes {
                let tex = String(text[start..<close])
                return texLike(Substring(tex)) ? (after, tex) : nil
            }
            cursor = after
            guard cursor < text.endIndex else { break }
        }
        return nil
    }

    /// Something only math looks like: a command, a power, an index or an equation.
    private static func texLike(_ text: Substring) -> Bool {
        let upTo = text.prefix { $0 != "$" }
        return upTo.contains("\\") || upTo.contains("^") || upTo.contains("_") || upTo.contains("=")
    }

    /// The converted math as Markdown text: its own *, _ and the like are not Markdown.
    private static func escaped(_ text: String) -> String {
        var output = ""
        for character in text {
            if "\\*_`[]~<>#".contains(character) { output.append("\\") }
            output.append(character)
        }
        return output
    }

    // MARK: TeX to Unicode

    static func convert(_ tex: String) -> String {
        var scanner = Scanner(Array(tex))
        let text = scanner.sequence(until: nil)
        return text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    private struct Scanner {
        let characters: [Character]
        var position = 0
        init(_ characters: [Character]) { self.characters = characters }

        /// Text until `end` (a closing brace) or the end.
        mutating func sequence(until end: Character?) -> String {
            var output = ""
            while position < characters.count {
                let character = characters[position]
                if let end, character == end { position += 1; return output }
                switch character {
                case "\\": output += command()
                case "^": position += 1; output += script(superscripts, fallback: "^")
                case "_": position += 1; output += script(subscripts, fallback: "_")
                case "{": position += 1; output += sequence(until: "}")
                case "}": position += 1
                case "~": position += 1; output += " "
                default: position += 1; output.append(character)
                }
            }
            return output
        }

        /// One argument: a {group}, a command or one character.
        mutating func argument() -> String {
            while position < characters.count, characters[position] == " " { position += 1 }
            guard position < characters.count else { return "" }
            let character = characters[position]
            if character == "{" { position += 1; return sequence(until: "}") }
            if character == "\\" { return command() }
            position += 1
            return String(character)
        }

        mutating func script(_ table: [Character: Character], fallback: String) -> String {
            let body = argument()
            if body == "∘" || body == "°" { return "°" }
            let mapped = body.map { table[$0] }
            if !body.isEmpty, mapped.allSatisfy({ $0 != nil }) { return String(mapped.compactMap { $0 }) }
            return fallback + (body.count == 1 ? body : "(" + body + ")")
        }

        mutating func command() -> String {
            position += 1
            guard position < characters.count else { return "" }
            // A one-character command: spacing, or an escaped symbol.
            if !characters[position].isLetter {
                let symbol = characters[position]
                position += 1
                switch symbol {
                case ",", ":", ";", " ": return " "
                case "!": return ""
                case "\\": return " "
                default: return String(symbol)
                }
            }
            var name = ""
            while position < characters.count, characters[position].isLetter { name.append(characters[position]); position += 1 }
            switch name {
            case "frac", "dfrac", "tfrac":
                let top = argument(), bottom = argument()
                return simple(top) && simple(bottom) ? top + "/" + bottom : "(" + top + ")/(" + bottom + ")"
            case "sqrt":
                var index = ""
                if position < characters.count, characters[position] == "[" {
                    position += 1
                    while position < characters.count, characters[position] != "]" { index.append(characters[position]); position += 1 }
                    position += 1
                }
                let body = argument()
                let root = index.isEmpty ? "√" : String(index.compactMap { superscripts[$0] }) + "√"
                return root + (simple(body) ? body : "(" + body + ")")
            case "text", "mathrm", "mathbf", "mathit", "mathsf", "mathtt", "operatorname", "boldsymbol", "mathbb", "mathcal":
                return argument()
            case "left", "right", "big", "Big", "bigg", "Bigg", "displaystyle", "textstyle", "limits", "nolimits":
                return ""
            case "quad": return "  "
            case "qquad": return "    "
            default:
                return Self.symbols[name] ?? name
            }
        }

        private func simple(_ text: String) -> Bool {
            !text.isEmpty && text.count <= 6 && !text.contains(" ") && !text.contains("+") && !text.contains("-")
        }

        static let symbols: [String: String] = [
            "alpha": "α", "beta": "β", "gamma": "γ", "delta": "δ", "epsilon": "ε", "varepsilon": "ε", "zeta": "ζ",
            "eta": "η", "theta": "θ", "vartheta": "ϑ", "iota": "ι", "kappa": "κ", "lambda": "λ", "mu": "μ", "nu": "ν",
            "xi": "ξ", "pi": "π", "rho": "ρ", "sigma": "σ", "tau": "τ", "upsilon": "υ", "phi": "φ", "varphi": "φ",
            "chi": "χ", "psi": "ψ", "omega": "ω", "Gamma": "Γ", "Delta": "Δ", "Theta": "Θ", "Lambda": "Λ", "Xi": "Ξ",
            "Pi": "Π", "Sigma": "Σ", "Phi": "Φ", "Psi": "Ψ", "Omega": "Ω",
            "times": "×", "div": "÷", "cdot": "·", "pm": "±", "mp": "∓", "ast": "∗", "star": "⋆", "circ": "∘",
            "le": "≤", "leq": "≤", "ge": "≥", "geq": "≥", "ne": "≠", "neq": "≠", "approx": "≈", "sim": "∼",
            "simeq": "≃", "equiv": "≡", "propto": "∝", "ll": "≪", "gg": "≫", "infty": "∞", "partial": "∂",
            "nabla": "∇", "sum": "∑", "prod": "∏", "int": "∫", "iint": "∬", "oint": "∮", "to": "→",
            "rightarrow": "→", "leftarrow": "←", "Rightarrow": "⇒", "Leftarrow": "⇐", "leftrightarrow": "↔",
            "Leftrightarrow": "⇔", "mapsto": "↦", "in": "∈", "notin": "∉", "ni": "∋", "subset": "⊂", "subseteq": "⊆",
            "supset": "⊃", "supseteq": "⊇", "cup": "∪", "cap": "∩", "emptyset": "∅", "varnothing": "∅",
            "forall": "∀", "exists": "∃", "neg": "¬", "land": "∧", "lor": "∨", "wedge": "∧", "vee": "∨",
            "angle": "∠", "perp": "⊥", "parallel": "∥", "degree": "°", "ldots": "…", "cdots": "⋯", "dots": "…",
            "vdots": "⋮", "prime": "′", "hbar": "ℏ", "ell": "ℓ", "Re": "ℜ", "Im": "ℑ", "aleph": "ℵ",
            "langle": "⟨", "rangle": "⟩", "lfloor": "⌊", "rfloor": "⌋", "lceil": "⌈", "rceil": "⌉",
            "percent": "%", "%": "%", "lvert": "|", "rvert": "|", "vert": "|", "mid": "|",
        ]
    }

    private static let superscripts: [Character: Character] = [
        "0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴", "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹",
        "+": "⁺", "-": "⁻", "=": "⁼", "(": "⁽", ")": "⁾", "n": "ⁿ", "i": "ⁱ", "a": "ᵃ", "b": "ᵇ", "c": "ᶜ",
        "d": "ᵈ", "e": "ᵉ", "f": "ᶠ", "g": "ᵍ", "h": "ʰ", "j": "ʲ", "k": "ᵏ", "l": "ˡ", "m": "ᵐ", "o": "ᵒ",
        "p": "ᵖ", "r": "ʳ", "s": "ˢ", "t": "ᵗ", "u": "ᵘ", "v": "ᵛ", "w": "ʷ", "x": "ˣ", "y": "ʸ", "z": "ᶻ",
        "−": "⁻",
    ]
    private static let subscripts: [Character: Character] = [
        "0": "₀", "1": "₁", "2": "₂", "3": "₃", "4": "₄", "5": "₅", "6": "₆", "7": "₇", "8": "₈", "9": "₉",
        "+": "₊", "-": "₋", "=": "₌", "(": "₍", ")": "₎", "a": "ₐ", "e": "ₑ", "h": "ₕ", "i": "ᵢ", "j": "ⱼ",
        "k": "ₖ", "l": "ₗ", "m": "ₘ", "n": "ₙ", "o": "ₒ", "p": "ₚ", "r": "ᵣ", "s": "ₛ", "t": "ₜ", "u": "ᵤ",
        "v": "ᵥ", "x": "ₓ", "−": "₋",
    ]
}
