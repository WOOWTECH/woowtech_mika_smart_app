import Foundation
import XCTest
@testable import AssistantDocuments

final class DocumentExportTests: XCTestCase {
    func testInferredTitleIsPrintedOnceWithoutRemovingOtherHeadings() throws {
        let source = "# 文件驗收\n\n正文\n\n# 文件驗收\n\n末段"
        let report = try DocumentReport.parseMarkdown(source: source, title: "文件驗收", language: "zh-Hant")
        let html = try report.html()
        XCTAssertEqual(html.components(separatedBy: "<h1>文件驗收</h1>").count - 1, 2)
        XCTAssertTrue(html.contains("<p>正文</p>"))
        XCTAssertTrue(html.contains("<p>末段</p>"))
        XCTAssertEqual(report.sections.count, 4, "Export must not mutate the source model")
        let renamed = try DocumentReport.parseMarkdown(source: source, title: "自訂標題", language: "zh-Hant")
        XCTAssertTrue(try renamed.html().contains("<h1>自訂標題</h1>"))
        XCTAssertEqual(try renamed.html().components(separatedBy: "<h1>文件驗收</h1>").count - 1, 2)
        let subsection = try DocumentReport.parseMarkdown(source: "## 文件驗收\n正文", title: "文件驗收", language: "zh-Hant")
        XCTAssertTrue(try subsection.html().contains("<h2>文件驗收</h2>"))
    }

    private func report(_ table: DocumentTable) throws -> DocumentReport {
        try .init(title: "Export", language: "en", sections: [.table(table)])
    }

    func testHTMLIsSelfContainedEscapedAndPreservesEverySection() throws {
        let hostile = #"<script>alert("x")</script><img src='https://example.invalid/x'>&"#
        let table = try DocumentTable(columns: [hostile], rows: [[hostile]])
        let report = try DocumentReport(title: hostile, language: "zh-Hant", sections: [
            .heading(level: 2, text: hostile), .paragraph(text: hostile + "\n[link](https://example.invalid)"),
            .list(items: [hostile], ordered: true), .table(table)
        ])
        let html = try report.html()
        XCTAssertTrue(html.contains("<meta charset=\"utf-8\">"))
        XCTAssertTrue(html.contains("default-src 'none'"))
        XCTAssertTrue(html.contains("script-src 'none'"))
        XCTAssertTrue(html.contains("connect-src 'none'"))
        XCTAssertTrue(html.contains("form-action 'none'"))
        XCTAssertFalse(html.contains("<script"))
        XCTAssertFalse(html.contains("<img"))
        XCTAssertFalse(html.contains("<a "))
        XCTAssertTrue(html.contains("&lt;script&gt;alert(&quot;x&quot;)&lt;/script&gt;"))
        XCTAssertTrue(html.contains("&#39;https://example.invalid/x&#39;"))
        XCTAssertTrue(html.contains("[link](https://example.invalid)"))
        XCTAssertTrue(html.contains("<h2>"))
        XCTAssertTrue(html.contains("<ol><li>"))
        XCTAssertTrue(html.contains("<th scope=\"col\">"))
        XCTAssertTrue(html.contains("white-space:pre-wrap"))
        XCTAssertEqual(String(data: Data(html.utf8), encoding: .utf8), html)
    }

    func testCSVExactBOMQuotesCRLFAndEmbeddedNewlines() throws {
        let table = try DocumentTable(columns: ["名字", "Notes"], rows: [
            ["甲,乙", "He said \"hello\""], ["😀", "first\nsecond\rthird\r\nfourth"], ["", "tail"]
        ])
        let csv = try report(table).csv()
        XCTAssertEqual(csv, "\u{FEFF}\"名字\",\"Notes\"\r\n\"甲,乙\",\"He said \"\"hello\"\"\"\r\n\"😀\",\"first\r\nsecond\r\nthird\r\nfourth\"\r\n\"\",\"tail\"\r\n")
        XCTAssertEqual(Array(csv.utf8.prefix(3)), [0xEF, 0xBB, 0xBF])
    }

    func testFormulaProtectionUsesActualSelectedHeadersAndCells() throws {
        let triggers = ["=SUM(A1:A2)", " +cmd", "\u{00A0}-42", "  @call", "\tplain", " \rplain", "\nplain", " \t", "\u{FEFF}=1"]
        let safe = ["42", "text = x", "'already safe", "text\tinside", "", "   "]
        let table = try DocumentTable(columns: ["=header"], rows: (triggers + safe).map { [$0] })
        let other = try DocumentTable(columns: ["plain"], rows: [["value"]])
        let report = try DocumentReport(title: "R", language: "en", sections: [.table(table), .table(other)])
        XCTAssertEqual(try report.formulaProtectedCellCount(), triggers.count + 1)
        XCTAssertEqual(try report.formulaProtectedCellCount(tableIndex: 1), 0)
        let csv = try report.csv()
        XCTAssertTrue(csv.hasPrefix("\u{FEFF}\"'=header\"\r\n"))
        XCTAssertTrue(csv.contains("\"' +cmd\""))
        XCTAssertTrue(csv.contains("\"'\tplain\""))
        XCTAssertTrue(csv.contains("\"' \r\nplain\""))
        XCTAssertTrue(csv.contains("\"text = x\""))
        XCTAssertFalse(csv.contains("\"'text = x\""))
        XCTAssertEqual(try report.csv(tableIndex: 1), "\u{FEFF}\"plain\"\r\n\"value\"\r\n")
    }

    func testMissingAndOutOfRangeTableRejects() throws {
        let report = try DocumentReport(title: "R", language: "en", sections: [.paragraph(text: "not a table")])
        for index in [-1, 0, Int.max] {
            XCTAssertThrowsError(try report.csv(tableIndex: index)) {
                XCTAssertEqual($0 as? DocumentError, .tableIndexOutOfBounds)
            }
            XCTAssertThrowsError(try report.formulaProtectedCellCount(tableIndex: index)) {
                XCTAssertEqual($0 as? DocumentError, .tableIndexOutOfBounds)
            }
        }
    }

    func testOutputBoundRejectsWithoutPartialAppend() throws {
        var output = DocumentOutput()
        try output.append(String(repeating: "x", count: DocumentLimits.maximumOutputBytes))
        XCTAssertThrowsError(try output.append("x")) { XCTAssertEqual($0 as? DocumentError, .outputTooLarge) }
        XCTAssertEqual(output.value.utf8.count, DocumentLimits.maximumOutputBytes)
    }

    func testAsyncHelpersMatchSynchronousExports() async throws {
        let source = "| 名稱 | 值 |\n| --- | --- |\n| 中文 | =1+1 |"
        let report = try await DocumentReport.parseMarkdownAsync(source: source, title: "R", language: "zh-Hant")
        let html = try await report.htmlAsync()
        let csv = try await report.csvAsync()
        XCTAssertEqual(html, try report.html())
        XCTAssertEqual(csv, try report.csv())
    }

    func testCancelledGenerationDoesNotReturnPartialOutput() async throws {
        let task = Task { () async throws -> DocumentReport in
            // Cancellation is set before work even if this task starts immediately.
            withUnsafeCurrentTask { $0?.cancel() }
            return try await DocumentReport.parseMarkdownAsync(source: "# Heading\ntext", title: "R", language: "en")
        }
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
    }
}
