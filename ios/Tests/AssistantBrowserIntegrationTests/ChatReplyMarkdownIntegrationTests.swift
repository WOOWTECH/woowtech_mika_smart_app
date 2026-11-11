#if os(iOS) && canImport(XCTest)
import XCTest
@testable import WoowAssistant

final class ChatReplyMarkdownIntegrationTests: XCTestCase {
    func testNativeAttributedReplyHasInlineStylesAndOnlyUserOpenedLink() {
        let answer = ChatReplyMarkdown.parse("# Summary\n\n**Ready** and [source](https://example.org)\n\n- First")
        XCTAssertEqual(answer.mode, .formatted)
        XCTAssertEqual(answer.visibleText, "Summary\n\nReady and source\n\n• First")
        XCTAssertTrue(answer.text.runs.contains { $0.link?.absoluteString == "https://example.org" })
        XCTAssertTrue(answer.text.runs.contains { String(answer.text[$0.range].characters) == "Ready"
            && $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true })
    }

    func testUnsupportedMarkupRemainsVisibleAndHasNoActionableLink() {
        let source = "Do not open [this](file:///private/data) or ![image](https://example.org/a.png)"
        let answer = ChatReplyMarkdown.parse(source)
        XCTAssertEqual(answer.mode, .verbatim(.image))
        XCTAssertEqual(answer.visibleText, source)
        XCTAssertFalse(answer.text.runs.contains { $0.link != nil })
    }

    func testPartialAndLargeRepliesDoNotRewriteSource() {
        let partial = "```swift\nlet value = 1"
        let displayed = ChatReplyMarkdown.parse(partial)
        XCTAssertEqual(displayed.mode, .verbatim(.unclosedFence))
        XCTAssertEqual(displayed.visibleText, partial)
        let oversized = String(repeating: "a", count: ChatReplyMarkdown.maximumUTF8Bytes + 1)
        XCTAssertEqual(ChatReplyMarkdown.parse(oversized).visibleText, oversized)
    }
}
#endif
