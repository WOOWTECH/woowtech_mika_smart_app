import XCTest

/// Settings › MCP 伺服器 lists the saved servers; a server's own page (endpoint,
/// token, test, tools, delete) opens in place, so the section's back control
/// stays available to navigateMikaSection.
func openMCPServer(_ index: Int, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
    let back = app.buttons["mcp.backToServers"]
    if back.exists && back.isHittable { back.tap() }
    let row = app.buttons["mcp.server.\(index)"]
    XCTAssertTrue(row.waitForExistence(timeout: 10), "MCP server \(index) must be listed", file: file, line: line)
    revealLearningElement(row, in: app)
    row.tap()
    XCTAssertTrue(app.buttons["mcp.backToServers"].waitForExistence(timeout: 10), "the server's page opens", file: file, line: line)
}

/// Waits until a server's row in the list says this, like Android's 可用 · N 個工具.
func waitForMCPServerRow(_ index: Int, contains text: String, in app: XCUIApplication, timeout: TimeInterval = 15,
                         file: StaticString = #filePath, line: UInt = #line) {
    let row = app.buttons["mcp.server.\(index)"]
    let shown = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", text), object: row)
    XCTAssertEqual(XCTWaiter.wait(for: [shown], timeout: timeout), .completed,
                   "MCP server \(index) should show \(text); it shows \(row.exists ? row.label : "nothing")", file: file, line: line)
}
