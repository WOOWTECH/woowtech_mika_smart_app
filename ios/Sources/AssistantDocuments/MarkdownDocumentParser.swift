import Foundation

/// Deliberately small block grammar. Inline Markdown/HTML/links and unsupported blocks
/// remain literal, including code fences. No external resources or HTML parser are used.
enum MarkdownDocumentParser {
    static func parse(source: String, title: String, language: String) throws -> DocumentReport {
        guard source.utf8.count <= DocumentLimits.maximumSourceBytes else { throw DocumentError.sourceTooLarge }
        guard !source.documentIsBlank else { throw DocumentError.emptyDocument }
        let normalized = source.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.components(separatedBy: "\n")
        var sections: [DocumentSection] = [], paragraph: [String] = []
        var index = 0, totalCells = 0, totalItems = 0, totalTables = 0
        func append(_ section: DocumentSection) throws {
            guard sections.count < DocumentLimits.maximumSections else { throw DocumentError.tooManySections }
            sections.append(section)
        }
        func flush() throws {
            if !paragraph.isEmpty {
                try append(.paragraph(text: paragraph.joined(separator: "\n")))
                paragraph.removeAll(keepingCapacity: true)
            }
        }
        while index < lines.count {
            try Task.checkCancellation()
            let line = lines[index]
            if line.documentIsBlank { try flush(); index += 1; continue }
            // Indented code is outside the semantic subset; never reinterpret its table/list syntax.
            if line.hasPrefix("    ") || line.hasPrefix("\t") {
                paragraph.append(line)
                index += 1
                continue
            }
            if let fence = openingFence(line) {
                try flush()
                var literal = [line]
                index += 1
                while index < lines.count {
                    try Task.checkCancellation()
                    let next = lines[index]
                    literal.append(next)
                    index += 1
                    if isClosingFence(next, marker: fence.marker, length: fence.length) { break }
                }
                try append(.paragraph(text: literal.joined(separator: "\n")))
                continue
            }
            if index + 1 < lines.count, let columns = tableCells(line),
               let delimiter = tableCells(lines[index + 1]), isDelimiter(delimiter) {
                try flush()
                totalTables += 1
                guard totalTables <= DocumentLimits.maximumTables else { throw DocumentError.tooManyTables }
                guard columns.count == delimiter.count else { throw DocumentError.invalidTable }
                guard columns.count <= DocumentLimits.maximumColumns else { throw DocumentError.tooManyColumns }
                var rows: [[String]] = []
                index += 2
                while index < lines.count, !lines[index].documentIsBlank,
                      let row = tableCells(lines[index]) {
                    try Task.checkCancellation()
                    guard row.count == columns.count else { throw DocumentError.invalidTable }
                    guard rows.count < DocumentLimits.maximumRows else { throw DocumentError.tooManyRows }
                    guard totalCells + (rows.count + 2) * columns.count <= DocumentLimits.maximumCells else {
                        throw DocumentError.tooManyCells
                    }
                    rows.append(row)
                    index += 1
                }
                let table = try DocumentTable(columns: columns, rows: rows)
                totalCells += (rows.count + 1) * columns.count
                try append(.table(table))
                continue
            }
            if let heading = heading(line) {
                try flush()
                try append(.heading(level: heading.level, text: heading.text))
                index += 1
                continue
            }
            if let first = listItem(line), !first.ordered || first.number == 1 {
                try flush()
                var items = [first.text]
                var original = [line]
                var supported = true
                index += 1
                while index < lines.count, let item = listItem(lines[index]), item.ordered == first.ordered {
                    try Task.checkCancellation()
                    if item.ordered && item.number != items.count + 1 { supported = false }
                    items.append(item.text)
                    original.append(lines[index])
                    index += 1
                }
                // Continuations/nesting are outside the subset; preserve the entire block literally.
                while index < lines.count, !lines[index].documentIsBlank,
                      lines[index].first == " " || lines[index].first == "\t" {
                    try Task.checkCancellation()
                    supported = false
                    original.append(lines[index])
                    index += 1
                }
                if supported {
                    totalItems += items.count
                    guard totalItems <= DocumentLimits.maximumListItems else { throw DocumentError.tooManyListItems }
                    try append(.list(items: items, ordered: first.ordered))
                } else {
                    try append(.paragraph(text: original.joined(separator: "\n")))
                }
                continue
            }
            paragraph.append(line)
            index += 1
        }
        try flush()
        return try DocumentReport(title: title, language: language, sections: sections)
    }

    private static func heading(_ line: String) -> (level: Int, text: String)? {
        let prefix = line.prefix(while: { $0 == "#" })
        guard (1...6).contains(prefix.count) else { return nil }
        let rest = line.dropFirst(prefix.count)
        guard rest.first == " " || rest.first == "\t" else { return nil }
        let text = String(rest.drop(while: { $0 == " " || $0 == "\t" }))
        guard !text.documentIsBlank else { return nil }
        return (prefix.count, text)
    }

    private static func listItem(_ line: String) -> (ordered: Bool, number: Int, text: String)? {
        guard let first = line.first else { return nil }
        if ["-", "*", "_"].contains(first) {
            let compact = line.filter { $0 != " " && $0 != "\t" }
            if compact.count >= 3, compact.allSatisfy({ $0 == first }) { return nil }
        }
        if ["-", "*", "+"].contains(first) {
            let rest = line.dropFirst()
            guard rest.first == " " || rest.first == "\t" else { return nil }
            let text = String(rest.drop(while: { $0 == " " || $0 == "\t" }))
            return text.documentIsBlank ? nil : (false, 0, text)
        }
        let digits = line.prefix(while: { $0.isASCII && $0.isNumber })
        guard !digits.isEmpty, digits.count <= 9, let number = Int(digits),
              String(digits) == String(number) else { return nil }
        let rest = line.dropFirst(digits.count)
        guard rest.first == ".", rest.dropFirst().first == " " || rest.dropFirst().first == "\t" else { return nil }
        let text = String(rest.dropFirst().drop(while: { $0 == " " || $0 == "\t" }))
        return text.documentIsBlank ? nil : (true, number, text)
    }

    private static func openingFence(_ line: String) -> (marker: Character, length: Int)? {
        let trimmed = line.drop(while: { $0 == " " })
        guard let first = trimmed.first, first == "`" || first == "~" else { return nil }
        let length = trimmed.prefix(while: { $0 == first }).count
        return length >= 3 ? (first, length) : nil
    }

    private static func isClosingFence(_ line: String, marker: Character, length: Int) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.count >= length && trimmed.allSatisfy { $0 == marker }
    }

    private static func isDelimiter(_ cells: [String]) -> Bool {
        !cells.isEmpty && cells.allSatisfy { value in
            var part = value[...]
            if part.first == ":" { part = part.dropFirst() }
            if part.last == ":" { part = part.dropLast() }
            return part.count >= 3 && part.allSatisfy { $0 == "-" }
        }
    }

    /// Pipes escaped with an odd number of backslashes or inside matched backtick runs
    /// are cell content. Unmatched backticks stay literal and do not hide delimiters.
    static func tableCells(_ line: String) -> [String]? {
        guard line.contains("|") else { return nil }
        let characters = Array(line.trimmingCharacters(in: .whitespaces))
        guard !characters.isEmpty else { return nil }
        var runs: [Int: Int] = [:], positions: [Int: [Int]] = [:]
        var i = 0
        while i < characters.count {
            if characters[i] == "`" {
                let start = i
                while i < characters.count && characters[i] == "`" { i += 1 }
                let length = i - start
                runs[start] = length
                positions[length, default: []].append(start)
            } else { i += 1 }
        }
        // Precompute the next equal-length run; parsing remains linear even on unmatched runs.
        var nextRun: [Int: Int] = [:]
        for occurrences in positions.values where occurrences.count > 1 {
            for pair in zip(occurrences, occurrences.dropFirst()) { nextRun[pair.0] = pair.1 }
        }
        var cells: [String] = [], cell = "", separators: [Int] = []
        i = 0
        while i < characters.count {
            if characters[i] == "\\", i + 1 < characters.count {
                if characters[i + 1] == "|" { cell.append("|") }
                else { cell.append(characters[i]); cell.append(characters[i + 1]) }
                i += 2
            } else if let length = runs[i], let closing = nextRun[i] {
                cell += String(characters[i..<(closing + length)])
                i = closing + length
            } else if characters[i] == "|" {
                cells.append(cell.trimmingCharacters(in: .whitespaces))
                cell = ""
                separators.append(i)
                i += 1
            } else { cell.append(characters[i]); i += 1 }
        }
        guard !separators.isEmpty else { return nil }
        cells.append(cell.trimmingCharacters(in: .whitespaces))
        if separators.last == characters.count - 1 { cells.removeLast() }
        if separators.first == 0 { cells.removeFirst() }
        return cells
    }
}
