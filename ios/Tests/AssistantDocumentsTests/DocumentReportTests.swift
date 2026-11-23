import Foundation
import XCTest
@testable import AssistantDocuments

final class DocumentReportTests: XCTestCase {
    private func parse(_ source: String) throws -> DocumentReport {
        try .parseMarkdown(source: source, title: "報告", language: "zh-Hant")
    }

    private func rejects(_ error: DocumentError, _ operation: () throws -> Void,
                         file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try operation(), file: file, line: line) {
            XCTAssertEqual($0 as? DocumentError, error, file: file, line: line)
        }
    }

    func testSemanticBlocksAndUnicode() throws {
        let report = try parse("# 分析\n\n第一段 👩🏽‍💻。\n下一行。\n\n- 項目甲\n- 項目乙\n\n1. first\n2. second\n\n| 名稱 | 值 |\n| :--- | ---: |\n| 台灣 | 42 |")
        XCTAssertEqual(report.title, "報告")
        XCTAssertEqual(report.language, "zh-Hant")
        XCTAssertEqual(report.sections, [
            .heading(level: 1, text: "分析"), .paragraph(text: "第一段 👩🏽‍💻。\n下一行。"),
            .list(items: ["項目甲", "項目乙"], ordered: false), .list(items: ["first", "second"], ordered: true),
            .table(try DocumentTable(columns: ["名稱", "值"], rows: [["台灣", "42"]]))
        ])
    }

    func testBoldPairsAreDrawnBoldInHTMLAndKeptInCSV() throws {
        typealias Run = DocumentInlineEmphasis.Run
        XCTAssertEqual(DocumentInlineEmphasis.runs("• **計費期間**：2026"),
                       [Run(text: "• ", strong: false), Run(text: "計費期間", strong: true), Run(text: "：2026", strong: false)])
        XCTAssertEqual(DocumentInlineEmphasis.runs("a **b** c **d"),
                       [Run(text: "a ", strong: false), Run(text: "b", strong: true), Run(text: " c **d", strong: false)])
        for code in ["```python\ndef f(**kw, **more):\n```", "    x = a**b**c"] {
            XCTAssertEqual(DocumentInlineEmphasis.runs(code), [Run(text: code, strong: false)])
        }
        let report = try parse("**重點**\n\n- **計費期間**：9/15\n\n| 項目 | 金額 |\n| --- | --- |\n| **合計** | <1936> |")
        let html = try report.html()
        XCTAssertTrue(html.contains("<p><strong>重點</strong></p>"))
        XCTAssertTrue(html.contains("<li><strong>計費期間</strong>：9/15</li>"))
        XCTAssertTrue(html.contains("<td><strong>合計</strong></td><td>&lt;1936&gt;</td>"))
        XCTAssertTrue(try report.csv().contains("\"**合計**\""))
    }

    func testUnsupportedMarkupAndLinksStayLiteral() throws {
        let source = "> quotation\n![image](https://example.invalid/a.png)\n[link](javascript:alert(1))\n~~strike~~ **bold** <script>alert(1)</script>\n---\n####### too deep"
        XCTAssertEqual(try parse(source).sections, [.paragraph(text: source)])
        for list in ["3. three\n4. four", "1. one\n7. seven", "01. padded\n02. padded", "- parent\n  - child", "* * *", "- - -"] {
            XCTAssertEqual(try parse(list).sections, [.paragraph(text: list)])
        }
    }

    func testFencesAreLiteralIncludingLanguageAndUnclosedFence() throws {
        for source in ["```html\n<script>x</script>\n| a | b |\n| --- | --- |\n```", "~~~~swift\n# not a heading\n~~~\n~~~~", "```text\n- not a list"] {
            XCTAssertEqual(try parse(source).sections, [.paragraph(text: source)])
        }
        let indented = "    | A | B |\n    | --- | --- |\n    | literal | code |"
        XCTAssertEqual(try parse(indented).sections, [.paragraph(text: indented)])
    }

    func testEscapedPipesAndMatchedCodeRunsDoNotSplitCells() throws {
        let source = #"""
        | A | B | C |
        | --- | --- | --- |
        | a\|b | `c|d` | ``x`|y`` |
        | \\ | plain | trailing\| |
        """#
        let table = try XCTUnwrap(parse(source).tables.first)
        XCTAssertEqual(table.rows, [["a|b", "`c|d`", "``x`|y``"], [#"\\"#, "plain", "trailing|"]])
        XCTAssertEqual(MarkdownDocumentParser.tableCells("| `unclosed | b |"), ["`unclosed", "b"])
        XCTAssertEqual(MarkdownDocumentParser.tableCells("a | b"), ["a", "b"])
    }

    func testTableSyntaxOutsideTablesIsNotDiscarded() throws {
        let source = "a | b\n-- | --\nremaining text"
        XCTAssertEqual(try parse(source).sections, [.paragraph(text: source)])
        XCTAssertEqual(try parse("| H |\n| --- |\n| value |\n\nafter").sections.last, .paragraph(text: "after"))
    }

    func testRejectsRaggedEmptyAndInvalidTables() {
        for source in ["| A | B |\n| --- | --- |\n| one |", "| A | B |\n| --- | --- |\n| x | y | z |", "| A | B |\n| --- |\n| x | y |", "| A |\n| --- |", "| | B |\n| --- | --- |\n| x | y |"] {
            rejects(.invalidTable) { _ = try parse(source) }
        }
        rejects(.invalidTable) { _ = try DocumentTable(columns: [], rows: [[]]) }
        rejects(.invalidTable) { _ = try DocumentTable(columns: ["A"], rows: []) }
        rejects(.invalidTable) { _ = try DocumentTable(columns: ["A", "B"], rows: [["x"]]) }
    }

    func testBoundsForColumnsRowsAndCells() throws {
        rejects(.tooManyColumns) { _ = try DocumentTable(columns: Array(repeating: "H", count: 65), rows: [Array(repeating: "", count: 65)]) }
        rejects(.tooManyRows) { _ = try DocumentTable(columns: ["H"], rows: Array(repeating: [""], count: 5_001)) }
        let columns = Array(repeating: "H", count: 10)
        let row = Array(repeating: "", count: 10)
        let atLimit = try DocumentTable(columns: columns, rows: Array(repeating: row, count: 4_999))
        XCTAssertEqual((atLimit.rows.count + 1) * atLimit.columns.count, 50_000)
        rejects(.tooManyCells) { _ = try DocumentTable(columns: columns, rows: Array(repeating: row, count: 5_000)) }
        let half = try DocumentTable(columns: columns, rows: Array(repeating: row, count: 2_499))
        let one = try DocumentTable(columns: ["H"], rows: [[""]])
        let sections: [DocumentSection] = [.table(half), .table(half)]
        XCTAssertEqual(try DocumentReport(title: "R", language: "en", sections: sections).tables.count, 2)
        rejects(.tooManyCells) { _ = try DocumentReport(title: "R", language: "en", sections: sections + [.table(one)]) }
    }

    func testUTF8SourceBoundAndAggregateDirectModelBound() throws {
        let exact = String(repeating: "x", count: DocumentLimits.maximumSourceBytes)
        XCTAssertEqual(try parse(exact).sections, [.paragraph(text: exact)])
        rejects(.sourceTooLarge) { _ = try parse(exact + "x") }
        rejects(.sourceTooLarge) { _ = try parse(String(repeating: "中", count: DocumentLimits.maximumSourceBytes / 3 + 1)) }
        rejects(.sourceTooLarge) {
            _ = try DocumentReport(title: "R", language: "en", sections: [.paragraph(text: exact), .paragraph(text: exact)])
        }
    }

    func testInvalidMetadataEmptySectionsAndControlCharacters() {
        rejects(.emptyDocument) { _ = try parse(" \n\t ") }
        rejects(.emptyDocument) { _ = try DocumentReport(title: "R", language: "en", sections: []) }
        for title in ["", "  ", "bad\nname", String(repeating: "x", count: 1_025)] {
            rejects(.invalidTitle) { _ = try DocumentReport(title: title, language: "en", sections: [.paragraph(text: "x")]) }
        }
        for language in ["", "en\" onload=\"x", "en--US", "123", "en_US"] {
            rejects(.invalidLanguage) { _ = try DocumentReport(title: "R", language: language, sections: [.paragraph(text: "x")]) }
        }
        let invalidSections: [DocumentSection] = [.heading(level: 7, text: "x"), .heading(level: 0, text: "x"), .paragraph(text: " "), .list(items: [], ordered: false), .list(items: [""], ordered: true), .paragraph(text: "a\u{0}b")]
        for section in invalidSections {
            rejects(.invalidSection) { _ = try DocumentReport(title: "R", language: "en", sections: [section]) }
        }
    }

    func testSectionAndItemBounds() {
        rejects(.tooManySections) {
            _ = try DocumentReport(title: "R", language: "en", sections: Array(repeating: .paragraph(text: "x"), count: 10_001))
        }
        rejects(.tooManyListItems) {
            _ = try DocumentReport(title: "R", language: "en", sections: [.list(items: Array(repeating: "x", count: 50_001), ordered: false)])
        }
    }

    func testReportAndParserTableCountsAreBounded() throws {
        let table = try DocumentTable(columns: ["H"], rows: [["value"]])
        let atLimit = Array(repeating: DocumentSection.table(table), count: DocumentLimits.maximumTables)
        XCTAssertEqual(try DocumentReport(title: "R", language: "en", sections: atLimit).tables.count, 64)
        rejects(.tooManyTables) {
            _ = try DocumentReport(title: "R", language: "en", sections: atLimit + [.table(table)])
        }
        let source = String(repeating: "| H |\n| --- |\n| value |\n\n", count: 65)
        rejects(.tooManyTables) { _ = try parse(source) }
    }

    func testFilenameIsNormalizedBoundedSingleComponent() throws {
        func filename(_ title: String) throws -> String {
            try DocumentReport(title: title, language: "en", sections: [.paragraph(text: "x")]).safeFilename(format: .pdf)
        }
        XCTAssertEqual(try filename("../a/b\\c:*?\"<>|"), "abc.pdf")
        XCTAssertEqual(try filename("e\u{301}"), "é.pdf")
        XCTAssertEqual(try filename("..."), "document.pdf")
        XCTAssertEqual(try filename("CON"), "_CON.pdf")
        XCTAssertEqual(try filename("NUL.txt"), "_NUL.txt.pdf")
        for title in [String(repeating: "報", count: 100), String(repeating: "😀", count: 100), String(repeating: "e\u{301}", count: 100)] {
            let result = try filename(title)
            let base = String(result.dropLast(4))
            XCTAssertLessThanOrEqual(base.unicodeScalars.count, 80)
            XCTAssertLessThanOrEqual(base.utf8.count, 240)
            XCTAssertFalse(result.contains("/"))
        }
        XCTAssertEqual(Set(DocumentFormat.allCases).count, 3)
    }
}
