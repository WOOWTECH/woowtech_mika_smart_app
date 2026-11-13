import AssistantSkills
import Foundation

/// Generate synthetic inputs using the same exporter as the iOS ShareLink.
@main
enum GenerateAndroidSkillShareFixtures {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else { fatalError("Expected an empty fixture directory") }
        let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        guard try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty else {
            fatalError("Fixture directory must be empty")
        }
        let simplified = ["入口", "步骤", "容易出错的地方", "怎样算办成", "什么时候停下交给用户"]
        let traditional = ["入口", "步驟", "容易出錯的地方", "怎樣算辦成", "什麼時候停下交給使用者"]
        let english = ["Entry", "Steps", "Pitfalls", "Success criteria", "When to stop"]
        func markdown(name: String, headings: [String], delimiter: String = "---") -> String {
            """
            ---
            name: \(name)
            display: Synthetic share
            description: Organize a synthetic note
            aliases: ["note, summary", guide]
            license: CC0-1.0
            source: user
            learned_from: synthetic-run
            updates: previous-synthetic
            \(delimiter)
            ## \(headings[0])
            ENTRY_BODY_KEEP
            ## \(headings[1])
            STEPS_BODY_KEEP
            ## \(headings[2])
            PITFALL_BODY_KEEP
            ## \(headings[3])
            SUCCESS_BODY_KEEP
            ## \(headings[4])
            STOP_BODY_KEEP
            """
        }
        func make(_ label: String, _ text: String) throws {
            var state = SkillsState()
            let pending = try state.importMarkdown(text, availableToolNames: [])
            let installed = try state.approveDraft(id: pending.id, availableToolNames: [])
            let before = state
            let shared = try state.exportMarkdown(name: installed.name)
            // The approved fixture has exactly one local source field. Verify every
            // other byte, including the raw body and its surrounding whitespace.
            let expected = installed.markdown.replacingOccurrences(of: "\nsource: imported\n", with: "\n")
            guard expected != installed.markdown, Data(shared.utf8) == Data(expected.utf8) else {
                fatalError("Exporter changed more than the local field in \(label)")
            }
            let parsed = try SkillDocument.parse(shared, availableToolNames: [])
            guard Data(parsed.body.utf8) == Data(installed.document.body.utf8) else {
                fatalError("Exporter changed the body of \(label)")
            }
            guard state == before else { fatalError("Export changed the source state") }
            try installed.markdown.write(to: directory.appendingPathComponent(label + ".installed.md"), atomically: true, encoding: .utf8)
            try shared.write(to: directory.appendingPathComponent(label + ".shared.md"), atomically: true, encoding: .utf8)
            print("generated \(label): shared UTF-8=\(shared.utf8.count)")
        }
        let anchors = "\n[Jump](#steps)\n## Stepsister\nSTEPSISTER_KEEP"
        try make("simplified", markdown(name: "cross-share-simplified", headings: simplified) + "\n## Steps\nLINK_TARGET_KEEP" + anchors)
        try make("hant", markdown(name: "cross-share-hant", headings: traditional))
        try make("english", markdown(name: "cross-share-english", headings: english) + anchors)
        try make("indented", markdown(name: "cross-share-indented", headings: simplified, delimiter: "  ---  "))
        try make("html", markdown(name: "cross-share-html", headings: simplified) + "\n<pre>\n## Steps\nHTML_BODY_KEEP\n</pre>")
        let canonicalInFence = simplified.map { "## \($0)\nCANONICAL_BODY_KEEP" }.joined(separator: "\n")
        try make("fenced", markdown(name: "cross-share-fenced", headings: english) + "\n~~~text\n" + canonicalInFence + "\n~~~")
        try make("invalid-fence", markdown(name: "cross-share-invalid", headings: simplified) + "\n``` invalid` info\n## Steps\n```")
    }
}
