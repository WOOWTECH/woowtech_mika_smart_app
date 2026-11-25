import AssistantDocuments
import Foundation

/// Makes a sample of every format the assistant creates, with the shipped
/// writers and the App's PDF renderer, and checks file_create's parsing and
/// limits. scripts/validate_created_files.py then opens the samples with
/// zipfile, python-docx, openpyxl, python-pptx and pypdf; the expected values
/// in manifest.json are written here by hand, never read back from the writers.
@main
enum CheckDocumentCreation {
    static var assertions = 0

    static func expect(_ condition: @autoclosure () throws -> Bool, _ label: String, line: Int = #line) {
        do {
            guard try condition() else { fail(label, line: line) }
        } catch { fail(label + " threw \(error)", line: line) }
        assertions += 1
    }

    static func expectError(_ expected: DocumentCreationError, _ label: String, line: Int = #line, _ body: () throws -> Void) {
        do {
            try body()
            fail(label + ": no error", line: line)
        } catch let error as DocumentCreationError {
            guard error == expected else { fail(label + ": \(error)", line: line) }
        } catch { fail(label + ": \(error)", line: line) }
        assertions += 1
    }

    static func fail(_ label: String, line: Int) -> Never {
        FileHandle.standardError.write(Data("FAIL line \(line): \(label)\n".utf8))
        exit(1)
    }

    static let modified = Date(timeIntervalSince1970: 1_795_000_000)

    static func main() throws {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.count == 2 else { fail("usage: CheckDocumentCreation <output folder>", line: #line) }
        let folder = URL(fileURLWithPath: arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var manifest: [[String: Any]] = []
        var made: [String: Data] = [:]

        func command(_ arguments: [String: Any]) throws -> DocumentCreationCommand {
            let data = try JSONSerialization.data(withJSONObject: ["action": "file_create", "arguments": arguments])
            return try DocumentCreationCommand.parse(String(decoding: data, as: UTF8.self))
        }
        func create(_ arguments: [String: Any], expected: [String: Any], line: Int = #line) throws {
            let parsed: DocumentCreationCommand, data: Data
            do {
                parsed = try command(arguments)
                data = try DocumentCreation.make(parsed, language: "zh-Hant", modified: modified,
                    pdf: { try DocumentPDFRenderer.render($0, marks: .boldItalicCode) }, file: { made[$0] })
            } catch { fail("making the sample: \(error)", line: line) }
            made[parsed.fileName] = data
            try data.write(to: folder.appendingPathComponent(parsed.fileName))
            var entry = expected
            entry["path"] = parsed.fileName
            entry["format"] = parsed.format.rawValue
            entry["title"] = parsed.title
            manifest.append(entry)
            expect(data.count <= DocumentCreationLimits.maximumOutputBytes, parsed.fileName + " within the output limit")
        }

        // Word: headings, bold and italic, lists that each count from 1, a table,
        // XML's special characters, Chinese, CRLF, a code fence and a lone mark.
        let markdown = "# 季度報告\r\n\r\n這是 **粗體** 與 *斜體*，還有 ***兩者***、`code` 與 snake_case_name。\r\n"
            + "特殊字元 & < > \" ' 都要保留。\n\n## 待辦\n\n- 第一項\n- **第二項**\n\n1. 步驟一\n2. 步驟二\n\n"
            + "### 另一張清單\n\n1. 重新開始\n2. 第二步\n\n| 名稱 | 數量 |\n| --- | ---: |\n| 蘋果 & 梨 | 3 |\n| <b>標籤</b> | 00123 |\n\n"
            + "```swift\nlet a = 1 < 2\n```\n\n5 * 3 = 15，未配對的 *星號"
        try create(["format": "docx", "file_name": "季度報告.pdf", "title": "季度報告 & <總覽>", "markdown": markdown], expected: [
            "kind": "docx",
            "paragraphs": [
                ["text": "季度報告 & <總覽>", "style": "Title"],
                ["text": "季度報告", "style": "Heading 1"],
                // Two lines of one paragraph: a line break, CRLF included.
                ["text": "這是 粗體 與 斜體，還有 兩者、code 與 snake_case_name。\n特殊字元 & < > \" ' 都要保留。",
                 "bold": ["粗體", "兩者"], "italic": ["斜體", "兩者"], "code": ["code"]],
                ["text": "待辦", "style": "Heading 2"],
                ["text": "第一項", "style": "List Paragraph", "numbering": "bullet"],
                ["text": "第二項", "style": "List Paragraph", "numbering": "bullet", "bold": ["第二項"]],
                ["text": "步驟一", "style": "List Paragraph", "numbering": "decimal", "list": 1],
                ["text": "步驟二", "style": "List Paragraph", "numbering": "decimal", "list": 1],
                ["text": "另一張清單", "style": "Heading 3"],
                ["text": "重新開始", "style": "List Paragraph", "numbering": "decimal", "list": 2],
                ["text": "第二步", "style": "List Paragraph", "numbering": "decimal", "list": 2],
                ["text": "let a = 1 < 2", "style": "Code"],
                ["text": "5 * 3 = 15，未配對的 *星號"],
            ],
            "tables": [[["名稱", "數量"], ["蘋果 & 梨", "3"], ["<b>標籤</b>", "00123"]]],
        ])
        try create(["format": "docx", "file_name": "  ../one/line?.docx ", "markdown": "Just one line."], expected: [
            "kind": "docx", "paragraphs": [["text": "oneline", "style": "Title"], ["text": "Just one line."]], "tables": [Any](),
        ])

        // Excel: numbers as numbers, text as text (a formula-looking cell stays
        // text), booleans, empty cells, names Excel would refuse, and an empty sheet.
        let rows: [[Any]] = [
            ["品名", "數量", "單價", "備註", "啟用"],
            ["蘋果 & <梨>", 3, 12.5, "=1+1", true],
            ["香蕉", -2, 0.1, "00123", false],
            ["空白", NSNull(), 1e21, "第一行\n第二行", NSNull()],
            ["emoji 😀", 1234567, -0.25, "\"引號\" 'single'", true],
        ]
        try create(["format": "xlsx", "file_name": "銷售/統計", "title": "銷售 & 統計",
                    "sheets": [["name": "一月:[銷售]*", "rows": rows], ["name": "一月:[銷售]*", "rows": [["x"]]],
                               ["name": "History", "rows": [Any]()], ["rows": [["only"]]]]], expected: [
            "kind": "xlsx",
            // true and false are written as the text TRUE and FALSE.
            "sheets": [["name": "一月銷售", "rows": rows.map { $0.map { value in type(of: value) == Bool.self ? ((value as! Bool) ? "TRUE" : "FALSE") : value } }],
                       ["name": "一月銷售 (2)", "rows": [["x"]]], ["name": "Sheet3", "rows": [Any]()],
                       ["name": "Sheet4", "rows": [["only"]]]],
            "header_bold": true,
        ])
        // The cell limit exactly: 5,000 rows of 10 cells, short enough for the 256 KiB command.
        let big = (0..<5_000).map { row in (0..<10).map { column in column == 0 ? "列" as Any : (row + column) % 10 as Any } }
        try create(["format": "xlsx", "file_name": "limit-cells", "sheets": [["name": "大表", "rows": big]]], expected: [
            "kind": "xlsx", "sheets": [["name": "大表", "rows_count": 5_000, "first": big[0], "last": big[4_999]]],
        ])

        // PowerPoint: titles and bullets with special characters, a slide
        // without bullets, a line break inside a bullet, and the slide limits.
        let slides: [[String: Any]] = [
            ["title": "第一頁 & <開場>", "bullets": ["重點一", "重點 \"二\"", "第一行\n第二行"]],
            ["title": "只有標題"],
            ["title": "English slide", "bullets": ["a < b", "c & d"]],
        ]
        try create(["format": "pptx", "file_name": "簡報", "title": "我的簡報", "slides": slides], expected: [
            "kind": "pptx", "slides": slides.map { ["title": $0["title"]!, "bullets": $0["bullets"] ?? [String]()] },
        ])
        let fullSlides = (1...DocumentCreationLimits.maximumSlides).map { number in
            ["title": "第 \(number) 頁", "bullets": (1...DocumentCreationLimits.maximumBullets).map { "第 \($0) 點：" + String(repeating: "字", count: 40) }]
        }
        // A full slide's bullets are set smaller to fit; a short one keeps the theme's 24 pt.
        try create(["format": "pptx", "file_name": "limit-slides", "slides": fullSlides], expected: [
            "kind": "pptx", "slides": fullSlides.map { $0.merging(["bullet_points_at_most": 16]) { $1 } },
        ])

        // PDF through the App's renderer, italic and code included.
        try create(["format": "pdf", "file_name": "報告", "title": "PDF 報告",
                    "markdown": "## 摘要\n\n**重點**與*說明* & <符號>，END_OF_PDF_SAMPLE。\n\n| 項目 | 金額 |\n| --- | --- |\n| 合計 | 1,234 |"],
                   expected: ["kind": "pdf", "text": ["PDF 報告", "摘要", "重點", "說明", "& <符號>", "END_OF_PDF_SAMPLE", "合計", "1,234"]])

        // ZIP: text files and the files made above; one stored (incompressible), one deflated, one empty.
        let noise = randomData(4_096)
        made["noise.bin"] = noise
        try create(["format": "zip", "file_name": "全部檔案", "entries": [
            ["name": "說明.txt", "text": "這是說明 & <內容>\n" + String(repeating: "重複的行。\n", count: 200)],
            ["name": "說明.txt", "text": "同名的第二個檔案"],
            ["name": "../空的.md", "text": ""],
            ["name": "季度報告.docx", "file": "季度報告.docx"],
            ["name": "銷售統計.xlsx", "file": "銷售統計.xlsx"],
            ["name": "報告.pdf", "file": "報告.pdf"],
            ["name": "noise.bin", "file": "noise.bin"],
        ]], expected: [
            "kind": "zip",
            "entries": [
                ["name": "說明.txt", "text": "這是說明 & <內容>\n" + String(repeating: "重複的行。\n", count: 200)],
                ["name": "說明 (2).txt", "text": "同名的第二個檔案"],
                ["name": "空的.md", "text": ""],
                ["name": "季度報告.docx", "same_as": "季度報告.docx"],
                ["name": "銷售統計.xlsx", "same_as": "銷售統計.xlsx"],
                ["name": "報告.pdf", "same_as": "報告.pdf"],
                ["name": "noise.bin", "sha256_of": "noise.bin"],
            ],
            "stored": ["noise.bin", "空的.md"], "deflated": ["說明.txt"],
        ])
        try noise.write(to: folder.appendingPathComponent("noise.bin"))

        parsing()
        limits(made: made)
        inline()
        prompts()
        let data = try JSONSerialization.data(withJSONObject: ["files": manifest], options: [.prettyPrinted, .sortedKeys])
        try data.write(to: folder.appendingPathComponent("manifest.json"))
        print("{\"assertions\":\(assertions),\"files\":\(manifest.count)}")
    }

    /// Bytes deflate cannot shrink, so their entries are stored.
    static func randomData(_ count: Int) -> Data {
        var data = Data(count: count)
        data.withUnsafeMutableBytes { arc4random_buf($0.baseAddress, count) }
        return data
    }

    static func parse(_ arguments: [String: Any], action: String = "file_create") throws -> DocumentCreationCommand {
        let data = try JSONSerialization.data(withJSONObject: ["action": action, "arguments": arguments])
        return try DocumentCreationCommand.parse(String(decoding: data, as: UTF8.self))
    }

    static func parsing() {
        let markdown = ["format": "PDF", "file_name": "a", "markdown": "x"] as [String: Any]
        expect(try parse(markdown).format == .pdf && parse(markdown).fileName == "a.pdf", "format is case-insensitive")
        expect(try parse(markdown).title == "a", "the title defaults to the file name")
        expect(try DocumentCreationCommand.parse("```json\n{\"action\":\"file_create\",\"arguments\":{\"format\":\"docx\",\"file_name\":\"a\",\"markdown\":\"x\"}}\n```").format == .docx,
               "one code fence is tolerated")
        expectError(.invalidCommand, "another action") { _ = try parse(markdown, action: "skill_read") }
        expectError(.invalidCommand, "extra top-level key") {
            _ = try DocumentCreationCommand.parse(#"{"action":"file_create","arguments":{"format":"pdf","file_name":"a","markdown":"x"},"extra":1}"#)
        }
        expectError(.invalidCommand, "not JSON") { _ = try DocumentCreationCommand.parse("make a pdf please") }
        expectError(.invalidCommand, "two objects") {
            _ = try DocumentCreationCommand.parse(#"{"action":"file_create"} {"action":"file_create"}"#)
        }
        expectError(.invalidFormat, "unknown format") { _ = try parse(["format": "rtf", "file_name": "a", "markdown": "x"]) }
        expectError(.invalidCommand, "another format's content") { _ = try parse(["format": "xlsx", "file_name": "a", "markdown": "x"]) }
        expectError(.invalidCommand, "unknown argument") { _ = try parse(["format": "pdf", "file_name": "a", "markdown": "x", "path": "/tmp"]) }
        expectError(.invalidCommand, "content missing") { _ = try parse(["format": "pptx", "file_name": "a"]) }
        expectError(.invalidCommand, "wrong type") { _ = try parse(["format": "pdf", "file_name": "a", "markdown": ["x"]]) }
        expectError(.invalidFileName, "blank file name") { _ = try parse(["format": "pdf", "file_name": "  ", "markdown": "x"]) }
        expectError(.invalidFileName, "long file name") { _ = try parse(["format": "pdf", "file_name": String(repeating: "a", count: 121), "markdown": "x"]) }
        expectError(.invalidTitle, "title with a line break") { _ = try parse(["format": "pdf", "file_name": "a", "title": "a\nb", "markdown": "x"]) }
        expectError(.emptyContent, "blank markdown") { _ = try parse(["format": "docx", "file_name": "a", "markdown": " \n "]) }
        expectError(.emptyContent, "no sheets") { _ = try parse(["format": "xlsx", "file_name": "a", "sheets": [Any]()]) }
        expectError(.invalidCommand, "a sheet's unknown key") { _ = try parse(["format": "xlsx", "file_name": "a", "sheets": [["rows": [["x"]], "style": "bold"]]]) }
        expectError(.invalidCommand, "a cell that is an object") { _ = try parse(["format": "xlsx", "file_name": "a", "sheets": [["rows": [[["x": 1]]]]]]) }
        expectError(.invalidText, "a control character in a cell") { _ = try parse(["format": "xlsx", "file_name": "a", "sheets": [["rows": [["a\u{1}b"]]]]]) }
        expectError(.invalidCommand, "a slide without a title") { _ = try parse(["format": "pptx", "file_name": "a", "slides": [["bullets": ["x"]]]]) }
        expectError(.invalidCommand, "a blank bullet") { _ = try parse(["format": "pptx", "file_name": "a", "slides": [["title": "t", "bullets": [" "]]]]) }
        expectError(.invalidText, "a control character on a slide") { _ = try parse(["format": "pptx", "file_name": "a", "slides": [["title": "t\u{7}"]]]) }
        expectError(.invalidCommand, "an entry with text and file") {
            _ = try parse(["format": "zip", "file_name": "a", "entries": [["name": "x", "text": "a", "file": "b"]]])
        }
        expectError(.invalidEntryName, "an entry without a name") { _ = try parse(["format": "zip", "file_name": "a", "entries": [["name": " ", "text": "a"]]]) }

        // File names: one component, the format's extension, Windows' reserved names.
        let names: [(String, DocumentCreationFormat, String)] = [
            ("報告.pdf", .pdf, "報告.pdf"), ("報告.docx", .pdf, "報告.pdf"), ("v1.2", .xlsx, "v1.2.xlsx"),
            ("a/b\\c:d*e?f\"g<h>i|j", .docx, "abcdefghij.docx"), ("..", .zip, "document.zip"), ("CON", .pptx, "_CON.pptx"),
            ("lpt1.final", .pdf, "_lpt1.final.pdf"), ("tab\there\u{200B}", .pdf, "tabhere.pdf"),
            (String(repeating: "長", count: 100), .docx, String(repeating: "長", count: 80) + ".docx"),
        ]
        for (raw, format, expected) in names {
            expect(DocumentFileName.sanitized(raw, extension: format.rawValue) == expected, "file name " + raw)
        }
        expect(DocumentFileName.sanitized("../a/b.TXT", extension: nil) == "ab.TXT", "an entry keeps its own extension")
        expect(DocumentFileName.unique("a.txt", taken: ["a.txt", "a (2).txt"]) == "a (3).txt", "a taken name is numbered")

        // What the model reads back.
        let created = DocumentCreationResult.created(fileName: "報告.pdf", format: .pdf, bytes: 1234)
        expect(created.hasPrefix(#"{"bytes":1234,"file_name":"報告.pdf","format":"pdf","note":"#) && created.hasSuffix(#""ok":true}"#), "created result")
        let failed = DocumentCreationResult.failed(DocumentCreationError.tooManySheets)
        expect(failed.contains(#""error":"too_many_sheets""#) && failed.contains(#""ok":false"#) && failed.contains("16"), "failure names the limit")
        expect(DocumentCreationResult.failed(DocumentCreationError.content(.invalidTable)).contains(#""error":"invalid_table""#), "table failure")
        expect(DocumentCreationResult.failed(CancellationError()).contains(#""error":"failed""#), "other failures")
    }

    static func limits(made: [String: Data]) {
        func make(_ arguments: [String: Any], file: (String) -> Data? = { _ in nil }) throws {
            _ = try DocumentCreation.make(try parse(arguments), language: "en", modified: modified,
                                          pdf: { _ in Data("%PDF".utf8) }, file: file)
        }
        let row = (0..<10).map { $0 as Any }
        expectError(.tooManySheets, "17 sheets") {
            _ = try parse(["format": "xlsx", "file_name": "a", "sheets": (0..<17).map { _ in ["rows": [row]] }])
        }
        expect(try parse(["format": "xlsx", "file_name": "a", "sheets": (0..<16).map { _ in ["rows": [row]] }]).fileName == "a.xlsx", "16 sheets")
        expectError(.tooManyRows, "5,001 rows") {
            _ = try parse(["format": "xlsx", "file_name": "a", "sheets": [["rows": (0..<5_001).map { _ in ["x"] }]]])
        }
        expectError(.tooManyColumns, "65 cells in a row") {
            _ = try parse(["format": "xlsx", "file_name": "a", "sheets": [["rows": [(0..<65).map { $0 }]]]])
        }
        expectError(.tooManyCells, "50,001 cells across sheets") {
            _ = try parse(["format": "xlsx", "file_name": "a", "sheets": [["rows": (0..<5_000).map { _ in row }], ["rows": [["one more"]]]]])
        }
        expectError(.cellTooLong, "a cell over Excel's limit") {
            _ = try parse(["format": "xlsx", "file_name": "a", "sheets": [["rows": [[String(repeating: "x", count: 32_768)]]]]])
        }
        expectError(.tooManySlides, "51 slides") {
            _ = try parse(["format": "pptx", "file_name": "a", "slides": (0..<51).map { _ in ["title": "t"] }])
        }
        expectError(.tooManyBullets, "13 bullets") {
            _ = try parse(["format": "pptx", "file_name": "a", "slides": [["title": "t", "bullets": (0..<13).map { "b\($0)" }]]])
        }
        expectError(.slideTextTooLong, "a 501-character bullet") {
            _ = try parse(["format": "pptx", "file_name": "a", "slides": [["title": "t", "bullets": [String(repeating: "b", count: 501)]]]])
        }
        expectError(.tooManyEntries, "33 entries") {
            _ = try parse(["format": "zip", "file_name": "a", "entries": (0..<33).map { ["name": "f\($0).txt", "text": "x"] }])
        }
        expectError(.invalidCommand, "a command over 256 KiB") {
            _ = try parse(["format": "pdf", "file_name": "a", "markdown": String(repeating: "x", count: 262_144)])
        }
        expectError(.unknownFile, "a ZIP entry naming no made file") {
            try make(["format": "zip", "file_name": "a", "entries": [["name": "x.pdf", "file": "missing.pdf"]]])
        }
        let large = Data(count: 9 * 1_048_576)
        expectError(.tooLarge, "a ZIP over 16 MiB") {
            let noise = randomData(9 * 1_048_576)
            try make(["format": "zip", "file_name": "a", "entries": [["name": "a.bin", "file": "a"], ["name": "b.bin", "file": "a"]]],
                     file: { _ in noise })
        }
        expectError(.tooLarge, "ZIP input over 64 MiB") {
            try make(["format": "zip", "file_name": "a", "entries": (0..<8).map { ["name": "f\($0).bin", "file": "big"] }],
                     file: { _ in large })
        }
        expectError(.content(.invalidTable), "a table row with a missing cell") {
            try make(["format": "docx", "file_name": "a", "markdown": "| a | b |\n| --- | --- |\n| 1 |"])
        }
        expect(made["銷售統計.xlsx"] != nil, "the sheet name's slash left the file name")

        // The ZIP writer itself.
        var writer = DocumentZipWriter(modified: modified)
        expectError(.invalidEntryName, "an absolute name") { try writer.add("/etc/passwd", Data()) }
        expectError(.invalidEntryName, "a parent folder") { try writer.add("a/../b", Data()) }
        expectError(.invalidEntryName, "a backslash") { try writer.add("a\\b", Data()) }
        expect((try? writer.add("same.txt", Data("1".utf8))) != nil, "a name")
        expectError(.duplicateEntryName, "the same name twice") { try writer.add("same.txt", Data("2".utf8)) }
        // End record, local header, central header, the name twice and one stored byte.
        let expectedSize: Int = 22 + 30 + 46 + 2 * 8 + 1
        expect((try? writer.archive().count) == expectedSize, "one stored entry's size")
    }

    static func inline() {
        typealias Run = DocumentInlineStyle.Run
        let cases: [(String, [Run])] = [
            ("a **b** c", [Run(text: "a "), Run(text: "b", bold: true), Run(text: " c")]),
            ("*i* and _j_", [Run(text: "i", italic: true), Run(text: " and "), Run(text: "j", italic: true)]),
            ("***both***", [Run(text: "both", bold: true, italic: true)]),
            ("**a *b* c**", [Run(text: "a ", bold: true), Run(text: "b", bold: true, italic: true), Run(text: " c", bold: true)]),
            ("snake_case_name", [Run(text: "snake_case_name")]),
            ("5 * 3 * 2", [Run(text: "5 * 3 * 2")]),
            ("**open only", [Run(text: "**open only")]),
            ("\\*not italic\\*", [Run(text: "*not italic*")]),
            ("`a *b*` c", [Run(text: "a *b*", code: true), Run(text: " c")]),
            ("``unclosed", [Run(text: "``unclosed")]),
            ("中文*斜體*文字", [Run(text: "中文"), Run(text: "斜體", italic: true), Run(text: "文字")]),
            ("**計費期間**：2026", [Run(text: "計費期間", bold: true), Run(text: "：2026")]),
            ("```\n**x**\n```", [Run(text: "```\n**x**\n```", code: true)]),
            ("", [Run(text: "")]),
        ]
        for (text, expected) in cases { expect(DocumentInlineStyle.runs(text) == expected, "inline: " + text) }
        // Unpaired marks stay linear.
        let marks = String(repeating: "*a ", count: 20_000)
        let started = Date()
        expect(DocumentInlineStyle.runs(marks).map(\.text).joined() == marks, "a long line of unpaired marks is kept")
        expect(Date().timeIntervalSince(started) < 5, "unpaired marks are handled in bounded time")
    }

    static func prompts() {
        let offer = DocumentCreationPrompts.offer
        expect(offer.hasPrefix(DocumentCreationPrompts.lead), "the offer starts with its lead")
        for format in DocumentCreationFormat.allCases {
            expect(offer.contains("\"format\":\"\(format.rawValue)\"") || (format == .docx && offer.contains("pdf or docx")), "the offer shows " + format.rawValue)
        }
        expect(offer.contains("存到檔案") && offer.contains("分享"), "the offer names the card's buttons")
        expect(DocumentCreationPrompts.inStep.contains("file_create") && !DocumentCreationPrompts.inStep.hasPrefix(DocumentCreationPrompts.lead),
               "the in-step wording")
        for example in DocumentCreationPrompts.offer.components(separatedBy: "\n") where example.hasPrefix("{") {
            expect((try? DocumentCreationCommand.parse(example.replacingOccurrences(of: "\"file\":\"Report.pdf\"", with: "\"text\":\"x\""))) != nil,
                   "the offer's example parses: " + example)
        }
    }
}
