import Foundation

/// Markdown's inline marks in the files the assistant creates: **bold** or
/// __bold__, *italic* or _italic_, ***both***, and `code`. Marks pair the way
/// CommonMark pairs them (a mark next to a space does not open or close, and an
/// underscore inside a word is a letter); a mark without its pair, and one
/// after a backslash, stays as written. Exported answers keep their own rule,
/// bold only (DocumentInlineEmphasis), so their files do not change.
public enum DocumentInlineStyle {
    public struct Run: Equatable, Sendable {
        public let text: String
        public let bold: Bool
        public let italic: Bool
        public let code: Bool
        public init(text: String, bold: Bool = false, italic: Bool = false, code: Bool = false) {
            self.text = text; self.bold = bold; self.italic = italic; self.code = code
        }
    }

    /// How far back a closing mark looks for its opener, which keeps a line
    /// of unpaired marks linear.
    static let openerSearchDepth = 64

    public static func runs(_ text: String) -> [Run] {
        // Fenced or indented code is one code run, as the parser keeps it literal.
        if DocumentInlineEmphasis.isCode(text) { return [Run(text: text, code: true)] }
        var tokens = tokenize(Array(text))
        pair(&tokens)
        var bold = Array(repeating: 0, count: tokens.count + 1), italic = bold
        for token in tokens {
            for span in token.spans {
                if span.strong { bold[span.start] += 1; bold[span.end] -= 1 }
                else { italic[span.start] += 1; italic[span.end] -= 1 }
            }
        }
        var runs: [Run] = []
        var strong = 0, emphasis = 0
        for (index, token) in tokens.enumerated() {
            strong += bold[index]; emphasis += italic[index]
            let piece: String, code: Bool
            switch token.kind {
            case .text(let value): piece = value; code = false
            case .code(let value): piece = value; code = true
            case .mark(let mark): piece = String(repeating: mark, count: token.left); code = false
            }
            guard !piece.isEmpty else { continue }
            let run = Run(text: piece, bold: strong > 0, italic: emphasis > 0, code: code)
            if let last = runs.last, last.bold == run.bold, last.italic == run.italic, last.code == run.code {
                runs[runs.count - 1] = Run(text: last.text + piece, bold: run.bold, italic: run.italic, code: run.code)
            } else {
                runs.append(run)
            }
        }
        return runs.isEmpty ? [Run(text: "")] : runs
    }

    private struct Span { let start: Int; let end: Int; let strong: Bool }

    private struct Token {
        enum Kind { case text(String), code(String), mark(Character) }
        let kind: Kind
        var left = 0
        var canOpen = false, canClose = false
        /// Spans this closing mark ends, over the token indices between the pair.
        var spans: [Span] = []
    }

    private static func tokenize(_ characters: [Character]) -> [Token] {
        // The next backtick run of the same length, found once, so unmatched runs stay linear.
        var runStarts: [Int: Int] = [:], byLength: [Int: [Int]] = [:]
        var i = 0
        while i < characters.count {
            if characters[i] == "`" {
                let start = i
                while i < characters.count && characters[i] == "`" { i += 1 }
                runStarts[start] = i - start
                byLength[i - start, default: []].append(start)
            } else { i += 1 }
        }
        var closing: [Int: Int] = [:]
        for starts in byLength.values where starts.count > 1 {
            for pair in zip(starts, starts.dropFirst()) { closing[pair.0] = pair.1 }
        }
        var tokens: [Token] = [], text = ""
        func flush() {
            if !text.isEmpty { tokens.append(Token(kind: .text(text))); text = "" }
        }
        i = 0
        while i < characters.count {
            let character = characters[i]
            if character == "\\", i + 1 < characters.count, "\\`*_".contains(characters[i + 1]) {
                text.append(characters[i + 1]); i += 2
            } else if let length = runStarts[i] {
                if let end = closing[i] {
                    flush()
                    tokens.append(Token(kind: .code(String(characters[(i + length)..<end]))))
                    i = end + length
                } else {
                    text += String(characters[i..<(i + length)]); i += length
                }
            } else if character == "*" || character == "_" {
                let start = i
                while i < characters.count && characters[i] == character { i += 1 }
                let before = start > 0 ? characters[start - 1] : nil
                let after = i < characters.count ? characters[i] : nil
                // CommonMark's flanking rules for a run of marks.
                let leftFlanking = after.map { !$0.isWhitespace && (!isPunctuation($0) || before.map { $0.isWhitespace || isPunctuation($0) } ?? true) } ?? false
                let rightFlanking = before.map { !$0.isWhitespace && (!isPunctuation($0) || after.map { $0.isWhitespace || isPunctuation($0) } ?? true) } ?? false
                flush()
                var token = Token(kind: .mark(character), left: i - start)
                if character == "*" {
                    token.canOpen = leftFlanking; token.canClose = rightFlanking
                } else {
                    token.canOpen = leftFlanking && (!rightFlanking || before.map(isPunctuation) == true)
                    token.canClose = rightFlanking && (!leftFlanking || after.map(isPunctuation) == true)
                }
                tokens.append(token)
            } else {
                text.append(character); i += 1
            }
        }
        flush()
        return tokens
    }

    /// Pairs closing marks with the nearest opener of the same mark: two marks
    /// a side for bold, else one for italic; openers passed over cannot pair.
    private static func pair(_ tokens: inout [Token]) {
        var openers: [Int] = []
        for index in tokens.indices {
            guard case .mark(let mark) = tokens[index].kind else { continue }
            if tokens[index].canClose {
                while tokens[index].left > 0 {
                    let candidates = openers.suffix(openerSearchDepth)
                    guard let found = candidates.lastIndex(where: { opener in
                        if case .mark(mark) = tokens[opener].kind { return tokens[opener].left > 0 }
                        return false
                    }) else { break }
                    let opener = openers[found]
                    let strong = tokens[opener].left >= 2 && tokens[index].left >= 2
                    let used = strong ? 2 : 1
                    tokens[opener].left -= used; tokens[index].left -= used
                    tokens[index].spans.append(Span(start: opener + 1, end: index, strong: strong))
                    openers.removeSubrange((found + (tokens[opener].left > 0 ? 1 : 0))...)
                }
            }
            if tokens[index].canOpen && tokens[index].left > 0 { openers.append(index) }
        }
    }

    private static func isPunctuation(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { CharacterSet.punctuationCharacters.union(.symbols).contains($0) }
    }
}
