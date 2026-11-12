import Foundation

/// A bounded subset of Android's regex search. The matcher uses dynamic
/// programming, not a backtracking engine; each state is processed once per
/// input scalar. Empty matches are intentionally omitted from results.
public enum DocumentPatternError: Error, Equatable, Sendable {
    case invalidPattern, unsupportedPattern, budgetExceeded
}

public enum DocumentPatternSearch {
    private enum Atom: Sendable {
        case literal(UInt32), any, digit, word, space
        case characterClass(negated: Bool, ranges: [ClosedRange<UInt32>])

        func matches(_ code: UInt32, ignoreASCIICase: Bool) -> Bool {
            // Android searches individual lines; no atom crosses a line.
            guard code != 10, code != 13 else { return false }
            func fold(_ n: UInt32) -> UInt32 { ignoreASCIICase && (65...90).contains(n) ? n + 32 : n }
            switch self {
            case .literal(let expected): return fold(code) == fold(expected)
            case .any: return code != 0x85 && code != 0x2028 && code != 0x2029
            case .digit: return (48...57).contains(code)
            case .word: return (48...57).contains(code) || (65...90).contains(code) || (97...122).contains(code) || code == 95
            case .space: return code == 32 || code == 9 || code == 11 || code == 12
            case .characterClass(let negated, let ranges):
                let other = (65...90).contains(code) ? code + 32 : ((97...122).contains(code) ? code - 32 : code)
                let found = ranges.contains { $0.contains(code) || (ignoreASCIICase && $0.contains(other)) }
                return negated ? !found : found
            }
        }
    }
    private enum Repetition: Sendable { case one, zeroOrMore }
    private struct Term: Sendable { let atom: Atom; let repetition: Repetition }

    /// Greedy non-overlapping nonempty matches; no match crosses a line.
    /// Offsets/snippets/page identity always refer to the original snapshot.
    public static func search(source: DocumentTextSnapshot, pattern: String,
                              ignoreASCIICase: Bool = false, limit: Int = 20) throws -> DocumentSearchResult {
        try search(source: source, pattern: pattern, ignoreASCIICase: ignoreASCIICase, limit: limit, checkpoint: nil)
    }

    // Test seam is internal and never adds an App/model capability.
    static func search(source: DocumentTextSnapshot, pattern: String, ignoreASCIICase: Bool = false,
                       limit: Int = 20, checkpoint: (@Sendable () -> Void)?) throws -> DocumentSearchResult {
        guard (1...20).contains(limit) else { throw DocumentPatternError.invalidPattern }
        let terms = try compile(pattern)
        try Task.checkCancellation()
        var hits: [DocumentSearchHit] = [], work = 0
        func tick() throws {
            work += 1
            if work > 5_000_000 { throw DocumentPatternError.budgetExceeded }
            if work % 1024 == 0 {
                try Task.checkCancellation(); checkpoint?(); try Task.checkCancellation()
            }
        }
        for page in source.pages {
            try Task.checkCancellation()
            // Four UInt32/Int32 arrays of at most 262,145 elements bound extra
            // working storage to about 4 MiB per page, independently of regex.
            var scalars: [UInt32] = [], offsets: [Int32] = [0], byteOffset = 0
            let capacity = min(page.byteCount, 262_144)
            scalars.reserveCapacity(capacity); offsets.reserveCapacity(capacity + 1)
            for scalar in page.text.unicodeScalars {
                try tick()
                guard scalars.count < 262_144 else { throw DocumentPatternError.budgetExceeded }
                scalars.append(scalar.value); byteOffset += scalar.utf8.count
                offsets.append(Int32(byteOffset))
            }
            let count = scalars.count
            guard count > 0 else { continue }
            // next[i] is the end scalar index of the greedy suffix match at i,
            // or -1. The empty suffix matches at every position.
            var next = [Int32](repeating: -1, count: count + 1)
            var current = [Int32](repeating: -1, count: count + 1)
            for index in 0...count { try tick(); next[index] = Int32(index) }
            for term in terms.reversed() {
                try Task.checkCancellation()
                switch term.repetition {
                case .one: current[count] = -1
                case .zeroOrMore: current[count] = next[count]
                }
                for index in stride(from: count - 1, through: 0, by: -1) {
                    try tick()
                    let matches = term.atom.matches(scalars[index], ignoreASCIICase: ignoreASCIICase)
                    switch term.repetition {
                    case .one:
                        current[index] = matches ? next[index + 1] : -1
                    case .zeroOrMore:
                        // Consume when the rest can still match; otherwise skip.
                        current[index] = matches && current[index + 1] >= 0 ? current[index + 1] : next[index]
                    }
                }
                swap(&next, &current)
            }
            var index = 0
            while index < count {
                try tick()
                let end = Int(next[index])
                // Java regex may match empty here. The UI explicitly says these
                // are omitted; advance a scalar to guarantee progress.
                guard end > index else { index += 1; continue }
                guard end <= count else { throw DocumentPatternError.invalidPattern }
                guard hits.count < limit else {
                    try Task.checkCancellation()
                    return .init(hits: hits, truncated: true, sourceSHA256: source.sha256)
                }
                let offset = Int(offsets[index]), endOffset = Int(offsets[end])
                var snippetStart = max(0, offset - 64)
                while !boundary(page.bytes, snippetStart) { snippetStart += 1 }
                var snippetEnd = min(page.byteCount, snippetStart + 320)
                while !boundary(page.bytes, snippetEnd) { snippetEnd -= 1 }
                hits.append(.init(pageIndex: page.index, pageNumber: page.pageNumber,
                    offset: offset, length: endOffset - offset, snippetOffset: snippetStart,
                    snippet: String(decoding: page.bytes[snippetStart..<snippetEnd], as: UTF8.self)))
                index = end
            }
        }
        try Task.checkCancellation()
        return .init(hits: hits, truncated: false, sourceSHA256: source.sha256)
    }

    /// Android-like line results over one approved in-memory PDF snapshot.
    /// The virtual file is not a filesystem path. No partial result survives
    /// cancellation, the work budget, or an oversized page.
    public struct LineMatch: Sendable, Encodable {
        public let file: String
        public let line: Int
        public let text: String
        public let textTruncated: Bool
        public let pageIndex: Int
        public let pageNumber: Int
        /// Page-relative UTF-8 byte offset of the line start (kept for compatibility).
        public let offset: Int
        /// Leftmost match in this line, including a possible zero-length match.
        public let matchOffset: Int
        public let matchLength: Int
    }
    public struct LineResult: Sendable, Encodable {
        public let matches: [LineMatch]
        public let truncated: Bool
        public let sourceSHA256: String
    }
    public static let virtualFile = "/workspace/approved-document.txt"
    static func validatePattern(_ pattern: String) throws { _ = try compile(pattern) }

    public static func searchLines(source: DocumentTextSnapshot, pattern: String,
                                   deadline: ContinuousClock.Instant? = nil) throws -> LineResult {
        try searchLines(source: source, pattern: pattern, deadline: deadline, checkpoint: nil)
    }

    static func searchLines(source: DocumentTextSnapshot, pattern: String,
                            deadline: ContinuousClock.Instant? = nil,
                            checkpoint: (@Sendable () -> Void)?) throws -> LineResult {
        let terms = try compile(pattern)
        var matches: [LineMatch] = [], work = 0, lineNumber = 0
        func check() throws {
            try Task.checkCancellation()
            if let deadline, ContinuousClock.now >= deadline { throw DocumentQueryError.timedOut }
        }
        func tick() throws {
            work += 1
            if work > 5_000_000 { throw DocumentPatternError.budgetExceeded }
            if work % 1024 == 0 { try check(); checkpoint?(); try check() }
        }
        try check()
        for page in source.pages {
            try check()
            var scalars: [UInt32] = [], offsets: [Int32] = [0], byteOffset = 0
            for scalar in page.text.unicodeScalars {
                try tick()
                guard scalars.count < 262_144 else { throw DocumentPatternError.budgetExceeded }
                scalars.append(scalar.value); byteOffset += scalar.utf8.count
                offsets.append(Int32(byteOffset))
            }
            let count = scalars.count
            var next = [Int32](repeating: -1, count: count + 1)
            var current = [Int32](repeating: -1, count: count + 1)
            for index in 0...count { try tick(); next[index] = Int32(index) }
            for term in terms.reversed() {
                try check()
                switch term.repetition {
                case .one: current[count] = -1
                case .zeroOrMore: current[count] = next[count]
                }
                if count > 0 {
                    for index in stride(from: count - 1, through: 0, by: -1) {
                        try tick()
                        let found = term.atom.matches(scalars[index], ignoreASCIICase: false)
                        switch term.repetition {
                        case .one: current[index] = found ? next[index + 1] : -1
                        case .zeroOrMore: current[index] = found && current[index + 1] >= 0 ? current[index + 1] : next[index]
                        }
                    }
                }
                swap(&next, &current)
            }
            var start = 0
            while true {
                var end = start
                while end < count && scalars[end] != 10 && scalars[end] != 13 { try tick(); end += 1 }
                lineNumber += 1
                var found: (start: Int, end: Int)?
                for index in start...end {
                    try tick()
                    if next[index] >= 0 {
                        let matchEnd = Int(next[index])
                        guard matchEnd >= index && matchEnd <= end else { throw DocumentPatternError.invalidPattern }
                        found = (index, matchEnd); break
                    }
                }
                if let found {
                    guard matches.count < 20 else {
                        try check()
                        return .init(matches: matches, truncated: true, sourceSHA256: source.sha256)
                    }
                    let byteStart = Int(offsets[start]), byteEnd = Int(offsets[end])
                    var clipped = min(byteEnd, byteStart + 300)
                    while !boundary(page.bytes, clipped) { clipped -= 1 }
                    matches.append(.init(file: virtualFile, line: lineNumber,
                        text: String(decoding: page.bytes[byteStart..<clipped], as: UTF8.self), textTruncated: clipped < byteEnd,
                        pageIndex: page.index, pageNumber: page.pageNumber, offset: byteStart,
                        matchOffset: Int(offsets[found.start]),
                        matchLength: Int(offsets[found.end]) - Int(offsets[found.start])))
                }
                if end == count { break }
                start = end + 1
                if scalars[end] == 13 && start < count && scalars[start] == 10 { start += 1 }
            }
        }
        try check()
        return .init(matches: matches, truncated: false, sourceSHA256: source.sha256)
    }

    private static func boundary(_ data: Data, _ offset: Int) -> Bool {
        offset >= 0 && offset <= data.count && (offset == data.count || data[offset] & 0xc0 != 0x80)
    }

    private static func compile(_ pattern: String) throws -> [Term] {
        guard !pattern.isEmpty, pattern.utf8.count <= 256 else { throw DocumentPatternError.invalidPattern }
        let input = Array(pattern.unicodeScalars)
        var terms: [Term] = [], index = 0, repeated = false
        let metacharacters = ".\\{}[]()*+?|^$"
        func classScalar() throws -> UInt32 {
            guard index < input.count else { throw DocumentPatternError.invalidPattern }
            var scalar = input[index]; index += 1
            if scalar == "\\" {
                guard index < input.count else { throw DocumentPatternError.invalidPattern }
                scalar = input[index]; index += 1
                guard "\\[]-^".unicodeScalars.contains(scalar) else { throw DocumentPatternError.unsupportedPattern }
            } else if scalar == "[" { throw DocumentPatternError.unsupportedPattern }
            else if scalar == "-" { throw DocumentPatternError.invalidPattern }
            guard scalar.value >= 32, scalar.value != 127 else { throw DocumentPatternError.invalidPattern }
            return scalar.value
        }
        func parseClass() throws -> Atom {
            var negated = false, ranges: [ClosedRange<UInt32>] = []
            if index < input.count && input[index] == "^" { negated = true; index += 1 }
            while index < input.count && input[index] != "]" {
                if input[index] == "&", index + 1 < input.count, input[index + 1] == "&" {
                    throw DocumentPatternError.unsupportedPattern
                }
                let low = try classScalar()
                var high = low
                if index < input.count && input[index] == "-" {
                    index += 1
                    guard index < input.count, input[index] != "]" else { throw DocumentPatternError.invalidPattern }
                    high = try classScalar()
                    guard low <= high else { throw DocumentPatternError.invalidPattern }
                }
                ranges.append(low...high)
                guard ranges.count <= 16 else { throw DocumentPatternError.unsupportedPattern }
            }
            guard index < input.count, input[index] == "]", !ranges.isEmpty else { throw DocumentPatternError.invalidPattern }
            index += 1
            return .characterClass(negated: negated, ranges: ranges)
        }
        while index < input.count {
            let c = input[index]; index += 1
            guard c.value >= 32, c.value != 127 else { throw DocumentPatternError.invalidPattern }
            if c == "{" {
                guard let previous = terms.last, !repeated else { throw DocumentPatternError.invalidPattern }
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
                guard count <= 16, terms.count + count - 1 <= 64 else { throw DocumentPatternError.unsupportedPattern }
                terms.append(contentsOf: repeatElement(previous, count: count - 1)); repeated = true
                continue
            }
            if c == "*" || c == "+" {
                if repeated && c == "+" { throw DocumentPatternError.unsupportedPattern }
                guard let previous = terms.last, !repeated else { throw DocumentPatternError.invalidPattern }
                let star = Term(atom: previous.atom, repetition: .zeroOrMore)
                if c == "*" { terms[terms.count - 1] = star }
                else { terms.append(star) }
                repeated = true
                guard terms.count <= 64 else { throw DocumentPatternError.unsupportedPattern }
                continue
            }
            if c == "}" || c == "]" { throw DocumentPatternError.invalidPattern }
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
                    atom = .literal(escaped.value)
                }
            } else if c == "." { atom = .any }
            else if c == "[" { atom = try parseClass() }
            else if metacharacters.unicodeScalars.contains(c) { throw DocumentPatternError.unsupportedPattern }
            else { atom = .literal(c.value) }
            terms.append(Term(atom: atom, repetition: .one)); repeated = false
            guard terms.count <= 64 else { throw DocumentPatternError.unsupportedPattern }
        }
        guard !terms.isEmpty else { throw DocumentPatternError.invalidPattern }
        return terms
    }
}
