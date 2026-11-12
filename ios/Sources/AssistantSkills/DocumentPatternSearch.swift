import Foundation

/// A fixed-width subset of Android's regex search. No backtracking engine is
/// invoked, so unsupported constructs cannot hide an uninterruptible match.
public enum DocumentPatternError: Error, Equatable, Sendable {
    case invalidPattern, unsupportedPattern, budgetExceeded
}

public enum DocumentPatternSearch {
    private enum Atom: Sendable {
        case literal(Unicode.Scalar), any, digit, word, space

        func matches(_ value: Unicode.Scalar, ignoreASCIICase: Bool) -> Bool {
            let code = value.value
            switch self {
            case .literal(let expected):
                func fold(_ n: UInt32) -> UInt32 { ignoreASCIICase && (65...90).contains(n) ? n + 32 : n }
                return fold(code) == fold(expected.value)
            case .any: return code != 10 && code != 13
            case .digit: return (48...57).contains(code)
            case .word: return (48...57).contains(code) || (65...90).contains(code) || (97...122).contains(code) || code == 95
            case .space: return code == 32 || code == 9
            }
        }
    }

    /// Matches are non-overlapping and may not cross lines. Offsets, snippets,
    /// page numbers and selection indices always come from the original snapshot.
    public static func search(source: DocumentTextSnapshot, pattern: String,
                              ignoreASCIICase: Bool = false, limit: Int = 20) throws -> DocumentSearchResult {
        try search(source: source, pattern: pattern, ignoreASCIICase: ignoreASCIICase, limit: limit, checkpoint: nil)
    }

    // Test seam is internal and never adds an App/model capability.
    static func search(source: DocumentTextSnapshot, pattern: String, ignoreASCIICase: Bool = false,
                       limit: Int = 20, checkpoint: (@Sendable () -> Void)?) throws -> DocumentSearchResult {
        guard (1...20).contains(limit) else { throw DocumentPatternError.invalidPattern }
        let atoms = try compile(pattern)
        try Task.checkCancellation()
        var hits: [DocumentSearchHit] = [], work = 0
        for page in source.pages {
            try Task.checkCancellation()
            let scalars = page.text.unicodeScalars
            var start = scalars.startIndex, offset = 0
            while start < scalars.endIndex {
                var cursor = start, endOffset = offset, matched = true
                for atom in atoms {
                    work += 1
                    if work > 5_000_000 { throw DocumentPatternError.budgetExceeded }
                    if work % 1024 == 0 {
                        try Task.checkCancellation(); checkpoint?(); try Task.checkCancellation()
                    }
                    guard cursor < scalars.endIndex else { matched = false; break }
                    let scalar = scalars[cursor]
                    // Like Android's lineSequence(), no pattern crosses a line.
                    guard scalar.value != 10, scalar.value != 13, atom.matches(scalar, ignoreASCIICase: ignoreASCIICase) else {
                        matched = false; break
                    }
                    endOffset += scalar.utf8.count
                    scalars.formIndex(after: &cursor)
                }
                if matched {
                    guard hits.count < limit else {
                        try Task.checkCancellation()
                        return .init(hits: hits, truncated: true, sourceSHA256: source.sha256)
                    }
                    var snippetStart = max(0, offset - 64)
                    while !boundary(page.bytes, snippetStart) { snippetStart += 1 }
                    var snippetEnd = min(page.byteCount, max(endOffset, snippetStart + 320))
                    while !boundary(page.bytes, snippetEnd) { snippetEnd -= 1 }
                    hits.append(.init(pageIndex: page.index, pageNumber: page.pageNumber,
                        offset: offset, length: endOffset - offset, snippetOffset: snippetStart,
                        snippet: String(decoding: page.bytes[snippetStart..<snippetEnd], as: UTF8.self)))
                    start = cursor; offset = endOffset
                } else {
                    offset += scalars[start].utf8.count
                    scalars.formIndex(after: &start)
                }
            }
        }
        try Task.checkCancellation()
        return .init(hits: hits, truncated: false, sourceSHA256: source.sha256)
    }

    private static func boundary(_ data: Data, _ offset: Int) -> Bool {
        offset >= 0 && offset <= data.count && (offset == data.count || data[offset] & 0xc0 != 0x80)
    }

    private static func compile(_ pattern: String) throws -> [Atom] {
        guard !pattern.isEmpty, pattern.utf8.count <= 256 else { throw DocumentPatternError.invalidPattern }
        let input = Array(pattern.unicodeScalars)
        var atoms: [Atom] = [], index = 0, repeated = false
        let metacharacters = ".\\{}[]()*+?|^$"
        while index < input.count {
            let c = input[index]; index += 1
            guard c.value >= 32, c.value != 127 else { throw DocumentPatternError.invalidPattern }
            if c == "{" {
                guard let previous = atoms.last, !repeated else { throw DocumentPatternError.invalidPattern }
                var digits = ""
                while index < input.count && (48...57).contains(input[index].value) {
                    digits.unicodeScalars.append(input[index]); index += 1
                }
                guard index < input.count, input[index] == "}" else {
                    if index < input.count && input[index] == "," { throw DocumentPatternError.unsupportedPattern }
                    throw DocumentPatternError.invalidPattern
                }
                index += 1
                guard !digits.isEmpty, let count = Int(digits), count > 0 else { throw DocumentPatternError.invalidPattern }
                guard count <= 16, atoms.count + count - 1 <= 64 else { throw DocumentPatternError.unsupportedPattern }
                atoms.append(contentsOf: repeatElement(previous, count: count - 1)); repeated = true
                continue
            }
            if c == "}" { throw DocumentPatternError.invalidPattern }
            let atom: Atom
            if c == "\\" {
                guard index < input.count else { throw DocumentPatternError.invalidPattern }
                let escaped = input[index]; index += 1
                switch escaped {
                case "d": atom = .digit
                case "w": atom = .word
                case "s": atom = .space
                default:
                    guard metacharacters.unicodeScalars.contains(escaped) else { throw DocumentPatternError.unsupportedPattern }
                    atom = .literal(escaped)
                }
            } else if c == "." { atom = .any }
            else if metacharacters.unicodeScalars.contains(c) { throw DocumentPatternError.unsupportedPattern }
            else { atom = .literal(c) }
            atoms.append(atom); repeated = false
            guard atoms.count <= 64 else { throw DocumentPatternError.unsupportedPattern }
        }
        guard !atoms.isEmpty else { throw DocumentPatternError.invalidPattern }
        return atoms
    }
}
