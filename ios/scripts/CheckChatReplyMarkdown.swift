import Foundation
import SwiftUI

@main
enum CheckChatReplyMarkdown {
    static func main() {
        func expect(_ condition: @autoclosure () -> Bool, _ reason: String) {
            precondition(condition(), reason)
        }
        func hasLink(_ result: ChatReplyMarkdown.Result) -> Bool {
            result.text.runs.contains { $0.link != nil }
        }

        let plain = ChatReplyMarkdown.parse("Original 🧋 text\nsecond line")
        expect(plain.mode == .formatted, "Plain answer should render")
        expect(plain.visibleText == "Original 🧋 text\nsecond line", "Plain answer bytes stay visible")

        let inline = ChatReplyMarkdown.parse("**bold** *italic* `code` ~~removed~~ [site](https://example.org)")
        expect(inline.visibleText == "bold italic code removed site", "Supported inline markers become styled text")
        expect(inline.text.runs.contains { String(inline.text[$0.range].characters) == "bold"
            && $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true }, "Bold intent")
        expect(inline.text.runs.contains { String(inline.text[$0.range].characters) == "italic"
            && $0.inlinePresentationIntent?.contains(.emphasized) == true }, "Italic intent")
        expect(inline.text.runs.contains { String(inline.text[$0.range].characters) == "code"
            && $0.inlinePresentationIntent?.contains(.code) == true }, "Code intent")
        expect(inline.text.runs.contains { String(inline.text[$0.range].characters) == "removed"
            && $0.inlinePresentationIntent?.contains(.strikethrough) == true }, "Strike intent")
        expect(inline.text.runs.contains { $0.link?.absoluteString == "https://example.org" }, "Only explicit native link")

        let blocks = ChatReplyMarkdown.parse("# Heading\n\n- one\n  - two\n7. third\n> source\n\n```swift\nlet x = 1\n```\n---")
        expect(blocks.mode == .formatted, "Common blocks format")
        expect(blocks.visibleText == "Heading\n\n• one\n  ◦ two\n7. third\n│ source\n\nlet x = 1\n────────────", "Block content and order")
        expect(blocks.text.runs.contains { String(blocks.text[$0.range].characters) == "Heading" && $0.font != nil }, "Heading font")
        expect(blocks.text.runs.contains { String(blocks.text[$0.range].characters) == "let x = 1" && $0.font != nil }, "Fenced code font")

        let table = "| A | B |\n|---|---|\n| one | **two** |"
        let tableResult = ChatReplyMarkdown.parse(table)
        expect(tableResult.visibleText == table, "Unsupported table layout remains legible verbatim")
        expect(!hasLink(tableResult), "Table fallback never creates a link")

        for (source, reason) in [
            ("![alt](https://example.org/image.png)", ChatReplyMarkdown.Fallback.image),
            ("<img src='https://example.org/image.png'>", .rawHTML),
            ("^[x](custom:danger)", .extendedAttribute),
            ("[bad](javascript:alert(1))", .unsafeLink),
            ("[file](file:///tmp/private)", .unsafeLink),
            ("[relative](../document)", .unsafeLink),
            ("```\nunclosed code", .unclosedFence),
            ("```swift [hidden](file:///tmp/private)\ncode\n```", .invalidMarkdown),
            (String(repeating: "A", count: ChatReplyMarkdown.maximumUTF8Bytes + 1), .tooLarge),
            (String(repeating: "x\n", count: ChatReplyMarkdown.maximumLines + 1), .tooLarge)
        ] {
            let result = ChatReplyMarkdown.parse(source)
            expect(result.mode == .verbatim(reason), "Unsupported syntax has an explicit fallback")
            expect(result.visibleText == source, "Fallback keeps exact source visible")
            expect(!hasLink(result), "Fallback never produces actionable links")
        }

        let partial = "# 標題\n\n**粗體"
        expect(ChatReplyMarkdown.parse(partial, streaming: true).visibleText == "標題\n\n**粗體", "Incomplete inline syntax stays visible while streaming")
        expect(partial == "# 標題\n\n**粗體", "Display does not modify a partial reply")
        let streamBound = String(repeating: "a", count: 4_096) + "\n"
            + String(repeating: "b", count: 4_096)
        expect(ChatReplyMarkdown.parse(streamBound, streaming: true).mode == .verbatim(.tooLarge), "Streaming parse cost stays bounded")
        expect(ChatReplyMarkdown.parse(streamBound).mode == .formatted, "Completed answer can format beyond preview bound")
        print("PASS chat reply markdown: inline=5 blocks=5 safeLinks=1 fallbacks=10 streaming=2")
    }
}
