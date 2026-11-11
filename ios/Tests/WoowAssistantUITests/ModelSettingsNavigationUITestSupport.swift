import XCTest

/// Navigate through the same Settings > Model link and native Back control
/// that people use. These tests launch with zh-Hant; localized titles have a
/// separate language UI check.
func openModelSettings(in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
    let root = app.navigationBars["設定"]
    XCTAssertTrue(root.waitForExistence(timeout: 10), file: file, line: line)
    let link = app.buttons["settings.modelJump"]
    XCTAssertTrue(link.waitForExistence(timeout: 10), file: file, line: line)
    XCTAssertTrue(link.isEnabled && link.isHittable, file: file, line: line)
    XCTAssertFalse(app.textFields["settings.baseURL"].exists,
                   "Model fields belong to the destination, not the Settings root.", file: file, line: line)
    link.tap()
    XCTAssertTrue(app.navigationBars["模型"].waitForExistence(timeout: 10), file: file, line: line)
    XCTAssertTrue(app.textFields["settings.baseURL"].waitForExistence(timeout: 10), file: file, line: line)
    XCTAssertFalse(link.isHittable, file: file, line: line)
}

func returnFromModelSettings(in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
    let detail = app.navigationBars["模型"]
    XCTAssertTrue(detail.waitForExistence(timeout: 10), file: file, line: line)
    let back = detail.buttons.firstMatch
    XCTAssertTrue(back.waitForExistence(timeout: 5) && back.isEnabled && back.isHittable,
                  file: file, line: line)
    back.tap()
    XCTAssertTrue(app.navigationBars["設定"].waitForExistence(timeout: 10), file: file, line: line)
    XCTAssertTrue(app.buttons["settings.modelJump"].waitForExistence(timeout: 5), file: file, line: line)
    XCTAssertFalse(app.textFields["settings.baseURL"].isHittable, file: file, line: line)
}
