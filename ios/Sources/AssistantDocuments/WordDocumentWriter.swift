import Foundation

/// A Word document (.docx) from a parsed answer or model text: the title, then
/// headings, paragraphs with bold, italic and code (DocumentInlineStyle),
/// bulleted and numbered lists, and tables with a bold header row repeated on
/// each page. A4 with Word's built-in style names, so headings reach the
/// navigation pane and the table of contents.
public enum WordDocumentWriter {
    static let namespace = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
    /// A4 in twentieths of a point, with one-inch margins.
    static let pageWidth = 11_906, pageHeight = 16_838, margin = 1_440
    static var textWidth: Int { pageWidth - 2 * margin }

    public static func docx(_ report: DocumentReport, modified: Date = Date()) throws -> Data {
        let main = "application/vnd.openxmlformats-officedocument.wordprocessingml"
        return try OfficePackage.package([
            ("[Content_Types].xml", OfficePackage.contentTypes([
                ("/word/document.xml", main + ".document.main+xml"), ("/word/styles.xml", main + ".styles+xml"),
                ("/word/numbering.xml", main + ".numbering+xml"), ("/docProps/core.xml", OfficePackage.coreType)])),
            ("_rels/.rels", OfficePackage.rootRelationships(main: "word/document.xml")),
            ("word/_rels/document.xml.rels", OfficePackage.relationships([
                ("rId1", OfficePackage.officeRelationships + "/styles", "styles.xml"),
                ("rId2", OfficePackage.officeRelationships + "/numbering", "numbering.xml")])),
            ("word/document.xml", try document(report)),
            ("word/styles.xml", styles),
            ("word/numbering.xml", numbering(orderedLists: report.bodySections.filter {
                if case .list(_, true) = $0 { return true }; return false
            }.count)),
            ("docProps/core.xml", try OfficePackage.coreProperties(title: report.title, created: modified)),
        ], modified: modified)
    }

    static func document(_ report: DocumentReport) throws -> String {
        var output = OfficeXMLOutput(OfficePackage.declaration
            + #"<w:document xmlns:w="\#(namespace)" xmlns:r="\#(OfficePackage.officeRelationships)"><w:body>"#)
        try output.append(paragraph(style: "Title", runs: [DocumentInlineStyle.Run(text: report.title)]))
        // numId 1 is every bulleted list; each numbered list has its own, so it starts at 1.
        var nextNumbering = 2
        var endsWithTable = false
        for section in report.bodySections {
            try Task.checkCancellation()
            endsWithTable = false
            switch section {
            case .heading(let level, let text):
                try output.append(paragraph(style: "Heading\(level)", runs: DocumentInlineStyle.runs(text)))
            case .paragraph(let text):
                if DocumentInlineEmphasis.isCode(text) {
                    for line in codeLines(text) { try output.append(paragraph(style: "Code", runs: [.init(text: line, code: true)])) }
                } else {
                    try output.append(paragraph(style: nil, runs: DocumentInlineStyle.runs(text)))
                }
            case .list(let items, let ordered):
                let numbering = ordered ? nextNumbering : 1
                if ordered { nextNumbering += 1 }
                for item in items {
                    try Task.checkCancellation()
                    try output.append(paragraph(style: "ListParagraph", numbering: numbering, runs: DocumentInlineStyle.runs(item)))
                }
            case .table(let table):
                try output.append(try self.table(table))
                endsWithTable = true
            }
        }
        // Word wants a paragraph between a table and the section's properties.
        if endsWithTable { try output.append("<w:p/>") }
        try output.append(#"<w:sectPr><w:pgSz w:w="\#(pageWidth)" w:h="\#(pageHeight)"/>"#
            + #"<w:pgMar w:top="\#(margin)" w:right="\#(margin)" w:bottom="\#(margin)" w:left="\#(margin)" w:header="708" w:footer="708" w:gutter="0"/></w:sectPr>"#
            + "</w:body></w:document>")
        return output.value
    }

    /// A fenced block without its fence lines; indented code keeps its indent.
    static func codeLines(_ text: String) -> [String] {
        var lines = OfficePackage.lines(text).components(separatedBy: "\n")
        if let first = lines.first, first.drop(while: { $0 == " " }).hasPrefix("```") || first.drop(while: { $0 == " " }).hasPrefix("~~~") {
            let marker = first.drop(while: { $0 == " " }).first!
            lines.removeFirst()
            if let last = lines.last, !last.isEmpty,
               last.trimmingCharacters(in: .whitespaces).allSatisfy({ $0 == marker }) { lines.removeLast() }
        }
        return lines.isEmpty ? [""] : lines
    }

    static func paragraph(style: String?, numbering: Int? = nil, runs: [DocumentInlineStyle.Run],
                          bold: Bool = false) throws -> String {
        var properties = ""
        if let style { properties += #"<w:pStyle w:val="\#(style)"/>"# }
        if let numbering { properties += #"<w:numPr><w:ilvl w:val="0"/><w:numId w:val="\#(numbering)"/></w:numPr>"# }
        var xml = "<w:p>" + (properties.isEmpty ? "" : "<w:pPr>" + properties + "</w:pPr>")
        for run in runs { xml += try self.run(run, bold: bold) }
        return xml + "</w:p>"
    }

    /// One run; a line break inside a paragraph is a break, a tab a tab.
    static func run(_ run: DocumentInlineStyle.Run, bold: Bool = false) throws -> String {
        var properties = ""
        if run.code { properties += #"<w:rFonts w:ascii="Courier New" w:hAnsi="Courier New" w:cs="Courier New"/>"# }
        if run.bold || bold { properties += "<w:b/>" }
        if run.italic { properties += "<w:i/>" }
        var xml = "<w:r>" + (properties.isEmpty ? "" : "<w:rPr>" + properties + "</w:rPr>")
        for (index, line) in OfficePackage.lines(run.text).components(separatedBy: "\n").enumerated() {
            if index > 0 { xml += "<w:br/>" }
            for (offset, piece) in line.components(separatedBy: "\t").enumerated() {
                if offset > 0 { xml += "<w:tab/>" }
                if !piece.isEmpty { xml += #"<w:t xml:space="preserve">"# + (try OfficePackage.escaped(piece)) + "</w:t>" }
            }
        }
        return xml + "</w:r>"
    }

    static func table(_ table: DocumentTable) throws -> String {
        let width = textWidth / table.columns.count
        // The grid is also set on the table itself: Quick Look does not draw a style's borders.
        var output = OfficeXMLOutput(#"<w:tbl><w:tblPr><w:tblStyle w:val="TableGrid"/><w:tblW w:w="5000" w:type="pct"/>"#
            + "<w:tblBorders>" + ["top", "left", "bottom", "right", "insideH", "insideV"].map(border).joined() + "</w:tblBorders>"
            + #"<w:tblLook w:val="04A0" w:firstRow="1" w:lastRow="0" w:firstColumn="0" w:lastColumn="0" w:noHBand="0" w:noVBand="1"/></w:tblPr><w:tblGrid>"#
            + String(repeating: #"<w:gridCol w:w="\#(width)"/>"#, count: table.columns.count) + "</w:tblGrid>")
        func row(_ cells: [String], header: Bool) throws {
            var xml = "<w:tr>" + (header ? "<w:trPr><w:tblHeader/></w:trPr>" : "")
            for cell in cells {
                xml += #"<w:tc><w:tcPr><w:tcW w:w="\#(width)" w:type="dxa"/></w:tcPr>"#
                    + (try paragraph(style: nil, runs: DocumentInlineStyle.runs(cell), bold: header)) + "</w:tc>"
            }
            try output.append(xml + "</w:tr>")
        }
        try row(table.columns, header: true)
        for cells in table.rows {
            try Task.checkCancellation()
            try row(cells, header: false)
        }
        try output.append("</w:tbl>")
        return output.value
    }

    /// Word's built-in names (heading 1, Title, List Paragraph, Table Grid)
    /// with sizes in half points; East Asian text set as Traditional Chinese.
    static let styles: String = {
        let headings = [(1, 36, 360), (2, 32, 280), (3, 28, 240), (4, 26, 200), (5, 24, 200), (6, 22, 200)].map { level, size, before in
            #"<w:style w:type="paragraph" w:styleId="Heading\#(level)"><w:name w:val="heading \#(level)"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:uiPriority w:val="9"/><w:qFormat/>"#
                + #"<w:pPr><w:keepNext/><w:spacing w:before="\#(before)" w:after="120"/><w:outlineLvl w:val="\#(level - 1)"/></w:pPr><w:rPr><w:b/><w:sz w:val="\#(size)"/><w:szCs w:val="\#(size)"/></w:rPr></w:style>"#
        }.joined()
        return OfficePackage.declaration + #"<w:styles xmlns:w="\#(namespace)">"#
            + #"<w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="Calibri" w:hAnsi="Calibri" w:eastAsia="Microsoft JhengHei" w:cs="Calibri"/><w:sz w:val="22"/><w:szCs w:val="22"/><w:lang w:val="en-US" w:eastAsia="zh-TW" w:bidi="ar-SA"/></w:rPr></w:rPrDefault>"#
            + #"<w:pPrDefault><w:pPr><w:spacing w:after="160" w:line="276" w:lineRule="auto"/></w:pPr></w:pPrDefault></w:docDefaults>"#
            + #"<w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/><w:qFormat/></w:style>"#
            + #"<w:style w:type="paragraph" w:styleId="Title"><w:name w:val="Title"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:uiPriority w:val="10"/><w:qFormat/><w:pPr><w:spacing w:after="240"/></w:pPr><w:rPr><w:b/><w:sz w:val="48"/><w:szCs w:val="48"/></w:rPr></w:style>"#
            + headings
            + #"<w:style w:type="paragraph" w:styleId="ListParagraph"><w:name w:val="List Paragraph"/><w:basedOn w:val="Normal"/><w:uiPriority w:val="34"/><w:qFormat/><w:pPr><w:spacing w:after="60"/><w:ind w:left="720"/></w:pPr></w:style>"#
            + #"<w:style w:type="paragraph" w:customStyle="1" w:styleId="Code"><w:name w:val="Code"/><w:basedOn w:val="Normal"/><w:pPr><w:spacing w:after="0" w:line="240" w:lineRule="auto"/></w:pPr><w:rPr><w:rFonts w:ascii="Courier New" w:hAnsi="Courier New" w:cs="Courier New"/><w:sz w:val="20"/><w:szCs w:val="20"/></w:rPr></w:style>"#
            + #"<w:style w:type="table" w:default="1" w:styleId="TableNormal"><w:name w:val="Normal Table"/><w:uiPriority w:val="99"/><w:semiHidden/><w:unhideWhenUsed/><w:tblPr><w:tblInd w:w="0" w:type="dxa"/><w:tblCellMar><w:top w:w="0" w:type="dxa"/><w:left w:w="108" w:type="dxa"/><w:bottom w:w="0" w:type="dxa"/><w:right w:w="108" w:type="dxa"/></w:tblCellMar></w:tblPr></w:style>"#
            + #"<w:style w:type="table" w:styleId="TableGrid"><w:name w:val="Table Grid"/><w:basedOn w:val="TableNormal"/><w:uiPriority w:val="39"/><w:pPr><w:spacing w:after="0" w:line="240" w:lineRule="auto"/></w:pPr><w:tblPr><w:tblBorders>"#
            + ["top", "left", "bottom", "right", "insideH", "insideV"].map(border).joined() + "</w:tblBorders></w:tblPr></w:style>"
            + "</w:styles>"
    }()

    static func border(_ side: String) -> String {
        #"<w:\#(side) w:val="single" w:sz="4" w:space="0" w:color="auto"/>"#
    }

    /// numId 1 is every bulleted list. Each numbered list has a definition of
    /// its own, so it counts from 1 in Word and in Quick Look, which does not
    /// read a restart override.
    static func numbering(orderedLists: Int) -> String {
        func abstract(_ id: Int, format: String, text: String) -> String {
            #"<w:abstractNum w:abstractNumId="\#(id)"><w:multiLevelType w:val="hybridMultilevel"/><w:lvl w:ilvl="0"><w:start w:val="1"/><w:numFmt w:val="\#(format)"/><w:lvlText w:val="\#(text)"/><w:lvlJc w:val="left"/><w:pPr><w:ind w:left="720" w:hanging="360"/></w:pPr></w:lvl></w:abstractNum>"#
        }
        var xml = OfficePackage.declaration + #"<w:numbering xmlns:w="\#(namespace)">"#
            + abstract(0, format: "bullet", text: "•")
        for list in 0..<orderedLists { xml += abstract(list + 1, format: "decimal", text: "%1.") }
        xml += #"<w:num w:numId="1"><w:abstractNumId w:val="0"/></w:num>"#
        for list in 0..<orderedLists {
            xml += #"<w:num w:numId="\#(list + 2)"><w:abstractNumId w:val="\#(list + 1)"/></w:num>"#
        }
        return xml + "</w:numbering>"
    }
}
