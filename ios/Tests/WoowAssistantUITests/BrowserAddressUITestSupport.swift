import XCTest

/// Play's browser address, focused for typing. The start page shows it as the
/// search box. On an open page the address is the `browser.addressPill` button;
/// tapping it opens this field with the whole URL selected, so typed text
/// replaces it, as on Play. A submitting "\n" folds the field away (into the
/// page's pill), so never read the returned element after typing one.
@discardableResult
func focusBrowserAddress(in app: XCUIApplication, timeout: TimeInterval = 30,
                         file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
    let field = app.textFields["browser.address"]
    let pill = app.buttons["browser.addressPill"]
    let shown = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in field.exists || pill.exists }, object: nil)
    guard XCTWaiter.wait(for: [shown], timeout: timeout) == .completed else {
        XCTFail("Neither the start page's address field nor a page's address pill appeared", file: file, line: line)
        return field
    }
    let onPage = !field.exists
    let editing = !onPage && app.buttons["browser.address.cancel"].exists
    if !editing {
        // DEBUG launches clear website data asynchronously; like a running
        // task, that keeps the address disabled until it finishes.
        let target = onPage ? pill : field
        let usable = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == true AND hittable == true AND enabled == true"), object: target)
        XCTAssertEqual(XCTWaiter.wait(for: [usable], timeout: timeout), .completed,
                       "The browser address must be operable", file: file, line: line)
        XCTAssertTrue(app.frame.contains(target.frame), "The browser address must fit inside the app window",
                      file: file, line: line)
        // A second tap on the opened field would drop the URL's selection.
        target.tap()
        if onPage {
            XCTAssertTrue(field.waitForExistence(timeout: 5), "The address pill must open the address field",
                          file: file, line: line)
        }
    }
    XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5),
                  "The address keyboard must appear before typing", file: file, line: line)
    return field
}
