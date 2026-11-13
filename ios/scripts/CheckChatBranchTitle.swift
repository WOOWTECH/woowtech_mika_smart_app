import Foundation

@main
enum CheckChatBranchTitle {
    static func main() {
        var assertions = 0
        func expect(_ condition: @autoclosure () -> Bool, line: UInt = #line) {
            precondition(condition(), "CheckChatBranchTitle line \(line)")
            assertions += 1
        }
        // ConversationArchive.normalizedTitle: one trimmed line, no control or
        // format characters, at most 120 characters and 512 UTF-8 bytes.
        func archiveAccepts(_ title: String) -> Bool {
            title == title.trimmingCharacters(in: .whitespacesAndNewlines) && !title.isEmpty
                && title.count <= 120 && title.utf8.count <= 512
                && !title.unicodeScalars.contains(where: CharacterSet.controlCharacters.union(.newlines).contains)
        }
        func make(_ base: String, suffix: String = " · 分支", fallback: String = "新對話") -> String {
            let title = ChatBranchTitle.make(base: base, suffix: suffix, fallback: fallback)
            expect(archiveAccepts(title))
            return title
        }

        // Android ChatCopy.branchTitle: the source title, then the suffix.
        expect(make("幫我整理會議記錄") == "幫我整理會議記錄 · 分支")
        expect(make("Plan the trip", suffix: " · branch", fallback: "New chat") == "Plan the trip · branch")
        // 24 characters in all: the title is cut to 19, never the suffix.
        let long = make(String(repeating: "長", count: 40))
        expect(long == String(repeating: "長", count: 19) + " · 分支" && long.count == 24)
        // A space left at the cut is trimmed, like trimEnd().
        expect(make("abcdefghijklmnopqr stuvwxyz") == "abcdefghijklmnopqr · 分支")
        // A branch of a branch keeps one more suffix within the limit.
        expect(make("報告 · 分支") == "報告 · 分支 · 分支")
        // Only the first line with text; control and format characters go.
        expect(make("\n  \n第一行\n第二行") == "第一行 · 分支")
        expect(make("A\u{0007}B\u{200D}C\u{2028}D") == "ABC · 分支")
        // Characters are never cut in half: 19 whole flags.
        let flags = make(String(repeating: "🇹🇼", count: 30))
        expect(flags == String(repeating: "🇹🇼", count: 19) + " · 分支" && flags.count == 24)
        // Blank titles fall back to the new-chat name; nothing at all keeps the suffix.
        expect(make(" \n\t") == "新對話 · 分支")
        expect(make("", fallback: "") == "· 分支")
        // A title whose characters overflow the byte limit falls back too.
        expect(make("a" + String(repeating: "\u{0301}", count: 600) + "bc") == "新對話 · 分支")

        print("{\"assertions\":\(assertions)}")
    }
}
