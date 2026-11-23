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
        expect(inline.text.runs.contains { String(inline.text[$0.range].characters) == "code" && $0.backgroundColor != nil },
               "Inline code has a fill, so it shows in a CJK sentence")
        expect(inline.text.runs.contains { String(inline.text[$0.range].characters) == "italic" && $0.underlineStyle != nil },
               "Emphasis has a dotted underline, since Chinese has no italic")
        // LaTeX shows as Unicode; prices, inline code and the source stay as written.
        func shown(_ source: String) -> String { String(ChatReplyMarkdown.parse(source).text.characters) }
        expect(shown("行內數學 $E=mc^2$") == "行內數學 E=mc²", "Inline math")
        expect(shown("$$\\int_0^1 x^2\\,dx=\\frac{1}{3}$$") == "∫₀¹ x² dx=1/3", "One-line display math")
        expect(shown("$$\n\\sum_{i=1}^{n} i = \\frac{n(n+1)}{2}\n$$") == "∑ᵢ₌₁ⁿ i = (n(n+1))/(2)", "A display block on its own lines")
        expect(shown("\\(\\alpha+\\beta \\le 90^\\circ\\)") == "α+β ≤ 90°", "Greek, ≤ and degrees")
        expect(shown("特價 $4,990，濾網約 $807") == "特價 $4,990，濾網約 $807", "Prices are not math")
        expect(shown("用 `$x^2$` 表示") == "用 $x^2$ 表示", "Inline code keeps its dollars")
        expect(shown("$\\sqrt{x_1}$ 與 $a_{ij}$") == "√x₁ 與 aᵢⱼ", "Roots and indices")
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
        expect(tableResult.visibleText == table, "The accessible text keeps the table verbatim")
        expect(!hasLink(tableResult), "Table fallback never creates a link")
        // Like Android, the bubble lays a table out as a grid and code in a box.
        expect(tableResult.hasRichBlocks && tableResult.blocks.count == 1, "A table is its own block")
        if case .table(let header, let rows)? = tableResult.blocks.first {
            expect(header.map { String($0.characters) } == ["A", "B"], "Table header cells without pipes")
            expect(rows.map { $0.map { String($0.characters) } } == [["one", "two"]], "Table rows keep inline text, skip the rule line")
            expect(rows[0][1].runs.contains { $0.inlinePresentationIntent != nil }, "A cell keeps its bold")
        } else { expect(false, "Table block") }
        let ragged = ChatReplyMarkdown.parse("| A | B |\n|---|---|\n| only |\n| x | y | z |\nAfter")
        if case .table(_, let rows)? = ragged.blocks.first {
            expect(rows.map(\.count) == [2, 2], "Short and long rows fit the header")
        } else { expect(false, "Ragged table block") }
        expect(ragged.blocks.count == 2, "Text after a table is its own block")
        let fenced = ChatReplyMarkdown.parse("Intro\n\n```swift\nlet x = 1\n  let y = 2\n```\nAfter")
        expect(fenced.blocks.count == 3, "Text, code and text blocks in order")
        if case .code(let lines)? = fenced.blocks.dropFirst().first {
            expect(lines == ["let x = 1", "  let y = 2"], "Code keeps its exact lines")
        } else { expect(false, "Code block") }
        expect(!ChatReplyMarkdown.parse("plain **text**\n- item").hasRichBlocks, "Plain replies stay one Text")

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
