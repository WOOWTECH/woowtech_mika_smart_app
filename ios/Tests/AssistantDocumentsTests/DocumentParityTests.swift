import AssistantDocuments
import Foundation
import XCTest

final class DocumentParityTests: XCTestCase {
    func testSharedAndroidIOSFixtureProducesExactCSVAndEscapedHTML() throws {
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let url = Bundle(for: Self.self).url(forResource: "parity-v1", withExtension: "json")
            ?? repository.appendingPathComponent("test-fixtures/documents/parity-v1.json")
        let data = try Data(contentsOf: url)
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let report = try DocumentReport.parseMarkdown(source: XCTUnwrap(fixture["source"] as? String),
                                                       title: XCTUnwrap(fixture["title"] as? String),
                                                       language: XCTUnwrap(fixture["language"] as? String))
        XCTAssertEqual(report.tables.first?.rows, fixture["rows"] as? [[String]])
        XCTAssertEqual(try report.csv(tableIndex: 0), fixture["expectedCSV"] as? String)
        let html = try report.html()
        XCTAssertTrue(html.contains("&lt;script&gt;alert(1)&lt;/script&gt;"))
        XCTAssertFalse(html.contains("<script>"))
    }
}
