import Foundation

public enum DocumentFormat: String, CaseIterable, Hashable, Sendable {
    case html, pdf, csv
}

/// Stable error cases for the app's localized presentation. Content is never included in errors.
public enum DocumentError: Error, Equatable, Sendable {
    case emptyDocument, invalidTitle, invalidLanguage, invalidSection, invalidTable
    case tableIndexOutOfBounds, sourceTooLarge, tooManySections, tooManyListItems
    case tooManyTables, tooManyColumns, tooManyRows, tooManyCells, outputTooLarge
}

public enum DocumentLimits {
    public static let maximumSourceBytes = 1_048_576
    public static let maximumContentBytes = maximumSourceBytes + maximumTitleBytes + 63
    public static let maximumOutputBytes = 16 * 1_048_576
    public static let maximumColumns = 64
    public static let maximumTables = 64
    public static let maximumRows = 5_000
    /// Includes column headers, across all tables in a report.
    public static let maximumCells = 50_000
    public static let maximumSections = 10_000
    public static let maximumListItems = 50_000
    public static let maximumTitleBytes = 1_024
}

public struct DocumentTable: Equatable, Sendable {
    public let columns: [String]
    public let rows: [[String]]

    public init(columns: [String], rows: [[String]]) throws {
        guard !columns.isEmpty, !rows.isEmpty,
              columns.allSatisfy({ !$0.documentIsBlank }) else { throw DocumentError.invalidTable }
        guard columns.count <= DocumentLimits.maximumColumns else { throw DocumentError.tooManyColumns }
        guard rows.count <= DocumentLimits.maximumRows else { throw DocumentError.tooManyRows }
        guard (rows.count + 1) * columns.count <= DocumentLimits.maximumCells else {
            throw DocumentError.tooManyCells
        }
        var bytes = 0
        for column in columns { try DocumentValidation.add(column, to: &bytes) }
        for row in rows {
            try Task.checkCancellation()
            guard row.count == columns.count else { throw DocumentError.invalidTable }
            for cell in row { try DocumentValidation.add(cell, to: &bytes) }
        }
        self.columns = columns
        self.rows = rows
    }
}

public enum DocumentSection: Equatable, Sendable {
    case heading(level: Int, text: String)
    case paragraph(text: String)
    case list(items: [String], ordered: Bool)
    case table(DocumentTable)
}

public struct DocumentReport: Equatable, Sendable {
    public let title: String
    public let language: String
    public let sections: [DocumentSection]

    /// Renderers already print the document title. Coalesce only an identical
    /// leading H1; keep the source model and later/different headings intact.
    public var bodySections: ArraySlice<DocumentSection> {
        if case .heading(let level, let text)? = sections.first, level == 1, text == title {
            return sections.dropFirst()
        }
        return sections[...]
    }

    public var tables: [DocumentTable] {
        sections.compactMap { if case .table(let table) = $0 { return table }; return nil }
    }

    public init(title: String, language: String, sections: [DocumentSection]) throws {
        guard !title.documentIsBlank, title.utf8.count <= DocumentLimits.maximumTitleBytes,
              !title.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw DocumentError.invalidTitle
        }
        // A conservative BCP-47-shaped tag, safe for HTML and Core Text language hints.
        let parts = language.split(separator: "-", omittingEmptySubsequences: false)
        guard !language.isEmpty, language.utf8.count <= 63,
              parts.allSatisfy({ !$0.isEmpty && $0.count <= 8 }),
              parts[0].utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0) }),
              language.utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0)
                  || (48...57).contains($0) || $0 == 45 }) else { throw DocumentError.invalidLanguage }
        guard !sections.isEmpty else { throw DocumentError.emptyDocument }
        guard sections.count <= DocumentLimits.maximumSections else { throw DocumentError.tooManySections }
        var bytes = 0, cells = 0, items = 0, tables = 0
        try DocumentValidation.add(title, to: &bytes)
        try DocumentValidation.add(language, to: &bytes)
        for section in sections {
            try Task.checkCancellation()
            switch section {
            case .heading(let level, let text):
                guard (1...6).contains(level), !text.documentIsBlank else { throw DocumentError.invalidSection }
                try DocumentValidation.add(text, to: &bytes)
            case .paragraph(let text):
                guard !text.documentIsBlank else { throw DocumentError.invalidSection }
                try DocumentValidation.add(text, to: &bytes)
            case .list(let values, _):
                guard !values.isEmpty else { throw DocumentError.invalidSection }
                items += values.count
                guard items <= DocumentLimits.maximumListItems else { throw DocumentError.tooManyListItems }
                for value in values {
                    guard !value.documentIsBlank else { throw DocumentError.invalidSection }
                    try DocumentValidation.add(value, to: &bytes)
                }
            case .table(let table):
                tables += 1
                guard tables <= DocumentLimits.maximumTables else { throw DocumentError.tooManyTables }
                cells += (table.rows.count + 1) * table.columns.count
                guard cells <= DocumentLimits.maximumCells else { throw DocumentError.tooManyCells }
                for column in table.columns { try DocumentValidation.add(column, to: &bytes) }
                for row in table.rows {
                    for cell in row { try DocumentValidation.add(cell, to: &bytes) }
                }
            }
        }
        self.title = title
        self.language = language
        self.sections = sections
    }

    public static func parseMarkdown(source: String, title: String, language: String) throws -> Self {
        try MarkdownDocumentParser.parse(source: source, title: title, language: language)
    }

    /// NFC, a single path component, at most 80 Unicode scalars before the extension.
    /// Restricting scalars also bounds UTF-8 filename bytes and pathological combining sequences.
    public func safeFilename(format: DocumentFormat) -> String {
        let unsafe = CharacterSet.controlCharacters.union(.illegalCharacters)
            .union(CharacterSet(charactersIn: "/\\:*?\"<>|"))
        let normalized = title.precomposedStringWithCanonicalMapping
        var base = "", scalars = 0, bytes = 0
        for character in normalized {
            let values = character.unicodeScalars
            if values.contains(where: { unsafe.contains($0) || $0.properties.generalCategory == .format }) {
                continue
            }
            // Keep the entire grapheme, or none of it, while enforcing the scalar bound.
            if scalars + values.count > 80 || bytes + String(character).utf8.count > 240 { break }
            base.append(character)
            scalars += values.count
            bytes += String(character).utf8.count
        }
        base = base.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
        if base.isEmpty { base = "document" }
        let reserved = ["CON", "PRN", "AUX", "NUL"]
            + (1...9).flatMap { ["COM\($0)", "LPT\($0)"] }
        if reserved.contains(String(base.split(separator: ".").first ?? "").uppercased()) { base = "_" + base }
        while base.unicodeScalars.count > 80 || base.utf8.count > 240 { base = String(base.dropLast()) }
        return base + "." + format.rawValue
    }

    func table(at index: Int) throws -> DocumentTable {
        guard index >= 0 else { throw DocumentError.tableIndexOutOfBounds }
        var current = 0
        for section in sections {
            if case .table(let table) = section {
                if current == index { return table }
                current += 1
            }
        }
        throw DocumentError.tableIndexOutOfBounds
    }
}

enum DocumentValidation {
    static func add(_ text: String, to bytes: inout Int) throws {
        let size = text.utf8.count
        guard size <= DocumentLimits.maximumContentBytes - bytes else { throw DocumentError.sourceTooLarge }
        // NUL and non-text C0 controls cannot round-trip through HTML/PDF. Reject, never strip.
        guard !text.unicodeScalars.contains(where: {
            ($0.value < 32 && $0.value != 9 && $0.value != 10 && $0.value != 13) || $0.value == 127
        }) else { throw DocumentError.invalidSection }
        bytes += size
    }
}

extension String {
    var documentIsBlank: Bool { trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}
