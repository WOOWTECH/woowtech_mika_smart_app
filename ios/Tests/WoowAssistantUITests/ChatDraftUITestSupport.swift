import XCTest

/// A vertical SwiftUI TextField may expose either AX type. Resolve by its
/// production identifier so a not-yet-rendered TextView can still be awaited.
func chatDraftControl(in app: XCUIApplication) -> XCUIElement {
    app.descendants(matching: .any)["chat.draft"].firstMatch
}
