import Foundation

public enum SpreadsheetCell: Equatable, Sendable {
    case text(String)
    case number(Double)
    case boolean(Bool)
    case empty
}

public struct SpreadsheetSheet: Equatable, Sendable {
    public let name: String
    /// The first row is the header, drawn bold and kept in view while scrolling.
    public let rows: [[SpreadsheetCell]]
    public init(name: String, rows: [[SpreadsheetCell]]) { self.name = name; self.rows = rows }
}

/// An Excel workbook (.xlsx) of named sheets. Numbers are numbers and text is
/// shared strings, so nothing is ever a formula: a cell such as =1+1 stays
/// text, which is why the CSV export's apostrophe is not needed here. A
/// true/false value is the text TRUE or FALSE, since Quick Look leaves
/// Excel's own boolean cells blank.
public enum SpreadsheetWriter {
    static let namespace = "http://schemas.openxmlformats.org/spreadsheetml/2006/main"

    public static func xlsx(title: String, sheets: [SpreadsheetSheet], modified: Date = Date()) throws -> Data {
        guard !sheets.isEmpty, sheets.count <= DocumentCreationLimits.maximumSheets else { throw DocumentCreationError.tooManySheets }
        let names = uniqueSheetNames(sheets.map(\.name))
        var strings = SharedStrings()
        var worksheets: [String] = []
        for sheet in sheets {
            try Task.checkCancellation()
            worksheets.append(try worksheet(sheet, strings: &strings))
        }
        let main = "application/vnd.openxmlformats-officedocument.spreadsheetml"
        var overrides: [(part: String, type: String)] = [("/xl/workbook.xml", main + ".sheet.main+xml")]
        overrides += worksheets.indices.map { ("/xl/worksheets/sheet\($0 + 1).xml", main + ".worksheet+xml") }
        overrides += [("/xl/styles.xml", main + ".styles+xml"), ("/xl/sharedStrings.xml", main + ".sharedStrings+xml"),
                      ("/docProps/core.xml", OfficePackage.coreType)]
        var relationships: [(id: String, type: String, target: String)] = worksheets.indices.map {
            ("rId\($0 + 1)", OfficePackage.officeRelationships + "/worksheet", "worksheets/sheet\($0 + 1).xml")
        }
        relationships += [("rId\(worksheets.count + 1)", OfficePackage.officeRelationships + "/styles", "styles.xml"),
                          ("rId\(worksheets.count + 2)", OfficePackage.officeRelationships + "/sharedStrings", "sharedStrings.xml")]
        var workbook = OfficePackage.declaration + #"<workbook xmlns="\#(namespace)" xmlns:r="\#(OfficePackage.officeRelationships)">"#
            + #"<bookViews><workbookView/></bookViews><sheets>"#
        for (index, name) in names.enumerated() {
            workbook += #"<sheet name="\#(try OfficePackage.escaped(name))" sheetId="\#(index + 1)" r:id="rId\#(index + 1)"/>"#
        }
        workbook += "</sheets></workbook>"
        var parts: [(name: String, xml: String)] = [
            ("[Content_Types].xml", OfficePackage.contentTypes(overrides)),
            ("_rels/.rels", OfficePackage.rootRelationships(main: "xl/workbook.xml")),
            ("xl/workbook.xml", workbook),
            ("xl/_rels/workbook.xml.rels", OfficePackage.relationships(relationships)),
        ]
        parts += worksheets.enumerated().map { (name: "xl/worksheets/sheet\($0.offset + 1).xml", xml: $0.element) }
        parts += [("xl/styles.xml", styles), ("xl/sharedStrings.xml", try strings.xml()),
                  ("docProps/core.xml", try OfficePackage.coreProperties(title: title, created: modified))]
        return try OfficePackage.package(parts, modified: modified)
    }

    static func worksheet(_ sheet: SpreadsheetSheet, strings: inout SharedStrings) throws -> String {
        var output = OfficeXMLOutput(OfficePackage.declaration + #"<worksheet xmlns="\#(namespace)">"#)
        if sheet.rows.count > 1 {
            try output.append(#"<sheetViews><sheetView workbookViewId="0"><pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews>"#)
        }
        // Widths from the longest text in each column, wide characters counted twice.
        var widths: [Int: Int] = [:]
        for row in sheet.rows {
            for (column, cell) in row.enumerated() {
                let shown: String
                switch cell {
                case .text(let text): shown = text.components(separatedBy: "\n").max(by: { $0.count < $1.count }) ?? ""
                case .number(let value): shown = number(value)
                case .boolean(let value): shown = value ? "TRUE" : "FALSE"
                case .empty: continue
                }
                let size = shown.unicodeScalars.reduce(0) { $0 + ($1.value > 0x2E7F ? 2 : 1) }
                widths[column] = max(widths[column] ?? 0, size)
            }
        }
        if !widths.isEmpty {
            try output.append("<cols>" + widths.keys.sorted().map { column in
                #"<col min="\#(column + 1)" max="\#(column + 1)" width="\#(min(60, max(8, widths[column]! + 2)))" customWidth="1"/>"#
            }.joined() + "</cols>")
        }
        try output.append("<sheetData>")
        for (index, row) in sheet.rows.enumerated() {
            try Task.checkCancellation()
            var xml = #"<row r="\#(index + 1)">"#
            for (column, cell) in row.enumerated() {
                let reference = columnName(column) + String(index + 1)
                // Style 1 is the bold header.
                let style = index == 0 ? #" s="1""# : ""
                switch cell {
                case .empty: continue
                case .text(let text):
                    xml += #"<c r="\#(reference)"\#(style) t="s"><v>\#(try strings.index(of: OfficePackage.lines(text)))</v></c>"#
                case .number(let value):
                    xml += #"<c r="\#(reference)"\#(style)><v>\#(number(value))</v></c>"#
                case .boolean(let value):
                    xml += #"<c r="\#(reference)"\#(style) t="s"><v>\#(try strings.index(of: value ? "TRUE" : "FALSE"))</v></c>"#
                }
            }
            try output.append(xml + "</row>")
        }
        try output.append("</sheetData></worksheet>")
        return output.value
    }

    /// A, B … Z, AA …
    static func columnName(_ index: Int) -> String {
        var number = index + 1, name = ""
        while number > 0 {
            let remainder = (number - 1) % 26
            name = String(UnicodeScalar(UInt8(65 + remainder))) + name
            number = (number - 1) / 26
        }
        return name
    }

    /// Whole numbers without a decimal point; others as Swift's shortest exact text.
    static func number(_ value: Double) -> String {
        if value.rounded() == value, abs(value) < 9_007_199_254_740_992 { return String(Int64(value)) }
        return "\(value)"
    }

    /// Excel's rules: 1–31 characters without : \ / ? * [ ], not starting or
    /// ending with an apostrophe, unique ignoring case. Others are renamed.
    static func uniqueSheetNames(_ names: [String]) -> [String] {
        var taken: Set<String> = []
        return names.enumerated().map { index, raw in
            var name = String(raw.unicodeScalars.filter {
                !":\\/?*[]".unicodeScalars.contains($0) && !CharacterSet.controlCharacters.contains($0)
            }.map(Character.init)).trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: "'")))
            if name.isEmpty || name.lowercased() == "history" { name = "Sheet\(index + 1)" }
            name = prefix(name, utf16: 31)
            var candidate = name, number = 2
            while taken.contains(candidate.lowercased()) {
                let suffix = " (\(number))"
                candidate = prefix(name, utf16: 31 - suffix.utf16.count) + suffix
                number += 1
            }
            taken.insert(candidate.lowercased())
            return candidate
        }
    }

    /// Whole characters within Excel's count of UTF-16 units.
    static func prefix(_ text: String, utf16 limit: Int) -> String {
        var result = ""
        for character in text {
            guard result.utf16.count + character.utf16.count <= limit else { break }
            result.append(character)
        }
        return result
    }

    struct SharedStrings {
        private var order: [String] = []
        private var indexes: [String: Int] = [:]
        private var uses = 0

        mutating func index(of text: String) throws -> Int {
            guard OfficePackage.isXMLText(text) else { throw DocumentCreationError.invalidText }
            uses += 1
            if let index = indexes[text] { return index }
            indexes[text] = order.count
            order.append(text)
            return order.count - 1
        }

        func xml() throws -> String {
            var output = OfficeXMLOutput(OfficePackage.declaration
                + #"<sst xmlns="\#(SpreadsheetWriter.namespace)" count="\#(uses)" uniqueCount="\#(order.count)">"#)
            for text in order { try output.append(#"<si><t xml:space="preserve">"# + (try OfficePackage.escaped(text)) + "</t></si>") }
            try output.append("</sst>")
            return output.value
        }
    }

    /// Excel requires the first two fills (none, gray125); style 1 is the bold header font.
    static let styles = OfficePackage.declaration + #"<styleSheet xmlns="\#(namespace)">"#
        + #"<fonts count="2"><font><sz val="11"/><name val="Calibri"/><family val="2"/></font><font><b/><sz val="11"/><name val="Calibri"/><family val="2"/></font></fonts>"#
        + #"<fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills>"#
        + #"<borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>"#
        + #"<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>"#
        + #"<cellXfs count="2"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/><xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/></cellXfs>"#
        + #"<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>"#
        + "</styleSheet>"
}
