import AssistantDocuments
import PDFKit
import XCTest
@testable import WoowAssistant

/// Real native rendering/file IO with synthetic documents. This is not a
/// provider, business-data or physical-device acceptance test.
final class DocumentExportIntegrationTests: XCTestCase {
    func testChinesePDFRetainsTextThroughParagraphAndTablePagination() throws {
        let table = try DocumentTable(columns: ["項目", "說明"], rows: [
            ["跨頁儲存格", String(repeating: "繁體中文與 English 123，表格內容必須保留。\n", count: 150) + "TABLE_END_MARKER"],
            ["最後一列", "最後一列不可遺失"]
        ])
        let report = try DocumentReport(title: "中文跨頁報告", language: "zh-Hant", sections: [
            .heading(level: 1, text: "中文測試"),
            .paragraph(text: String(repeating: "長段落與 English 456，內容要完整。\n", count: 180) + "PARAGRAPH_END_MARKER"),
            .table(table), .paragraph(text: "DOCUMENT_END_MARKER")
        ])
        let data = try DocumentPDFRenderer.render(report)
        XCTAssertTrue(data.starts(with: Data("%PDF-".utf8)))
        let document = try XCTUnwrap(PDFDocument(data: data))
        XCTAssertGreaterThan(document.pageCount, 2)
        let text = try XCTUnwrap(document.string).filter { !$0.isWhitespace }
        for sentinel in ["中文跨頁報告", "PARAGRAPH_END_MARKER", "TABLE_END_MARKER", "最後一列不可遺失", "DOCUMENT_END_MARKER"] {
            XCTAssertTrue(text.contains(sentinel), "Missing PDF text: \(sentinel)")
        }
    }

    func testExportsUseDistinctFilesAndRetainBytesAfterRelease() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = DocumentExportStore(storageRoot: root)
        let source = "# 報告\n\n| 項目 | 值 |\n| --- | --- |\n| 中文 | =1+1 |\n| 編號 | 00123 |"
        let csv = try await store.generate(source: source, title: "../中文報告", language: "zh-Hant", format: .csv, table: 0)
        let html = try await store.generate(source: source, title: "../中文報告", language: "zh-Hant", format: .html, table: nil)
        XCTAssertNotEqual(csv.url.deletingLastPathComponent(), html.url.deletingLastPathComponent())
        XCTAssertEqual(try Data(contentsOf: csv.url), csv.data)
        XCTAssertEqual(csv.protectedCells, 1)
        XCTAssertTrue(csv.data.starts(with: [0xEF, 0xBB, 0xBF]))
        XCTAssertTrue(String(decoding: csv.data, as: UTF8.self).contains("'=1+1"))
        await store.release(csv.id)
        XCTAssertEqual(try Data(contentsOf: csv.url), csv.data, "Closing a sheet must not invalidate an external consumer's file")
        await store.release(html.id)
    }

    func testInvalidTableDoesNotCreateAFile() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = DocumentExportStore(storageRoot: root)
        do {
            _ = try await store.generate(source: "| A | B |\n| --- | --- |\n| only one |", title: "Invalid", language: "en", format: .csv, table: 0)
            XCTFail("Ragged tables must not export as successful files")
        } catch {
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
        }
    }

    func testCleanupPreservesPinnedFilesAndStartsRetentionAtRelease() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = DocumentExportStore(storageRoot: root)
        let first = try await store.generate(source: "First", title: "First", language: "en", format: .html, table: nil)
        let folder = first.url.deletingLastPathComponent()
        let expired = Date(timeIntervalSinceNow: -48 * 60 * 60)
        try FileManager.default.setAttributes([.modificationDate: expired], ofItemAtPath: folder.path)
        let second = try await store.generate(source: "Second", title: "Second", language: "en", format: .html, table: nil)
        XCTAssertEqual(try Data(contentsOf: first.url), first.data, "An active consumer remains pinned regardless of age")
        await store.release(first.id)
        let refreshed = try XCTUnwrap(folder.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
        XCTAssertGreaterThan(refreshed, Date(timeIntervalSinceNow: -60))
        try FileManager.default.setAttributes([.modificationDate: expired], ofItemAtPath: folder.path)
        let third = try await store.generate(source: "Third", title: "Third", language: "en", format: .html, table: nil)
        XCTAssertFalse(FileManager.default.fileExists(atPath: first.url.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.url.path))
        await store.release(second.id)
        await store.release(third.id)
    }
}
