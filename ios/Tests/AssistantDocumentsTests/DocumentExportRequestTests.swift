import XCTest
import AssistantDocuments

final class DocumentExportRequestTests: XCTestCase {
    func testExactEnglishCommands() {
        for reference in ["previous", "last"] {
            for noun in ["answer", "report", "table"] {
                for preposition in ["as", "to"] {
                    for format in DocumentFormat.allCases {
                        XCTAssertEqual(DocumentExportRequest.parse("export the \(reference) \(noun) \(preposition) \(format.rawValue.uppercased())"), format)
                        XCTAssertEqual(DocumentExportRequest.parse("export \(reference) \(noun) \(preposition) \(format.rawValue)."), format)
                    }
                }
            }
        }
        XCTAssertEqual(DocumentExportRequest.parse(" EXPORT LAST ANSWER AS PDF! "), .pdf)
        XCTAssertEqual(DocumentExportRequest.parse("export last answer as PDF?"), .pdf)
        XCTAssertEqual(DocumentExportRequest.parse("save last response as pdf"), .pdf)
    }

    func testExactChineseCommands() {
        for reference in ["剛才", "上面", "上一則", "上一则"] {
            for noun in ["回答", "分析", "報告", "报告", "表格"] {
                for verb in ["整理成", "做成", "匯出成", "导出为", "輸出成"] {
                    XCTAssertEqual(DocumentExportRequest.parse("把\(reference)的\(noun)\(verb)PDF。"), .pdf)
                    XCTAssertEqual(DocumentExportRequest.parse("把\(reference)\(noun)\(verb)CSV"), .csv)
                }
            }
        }
        XCTAssertEqual(DocumentExportRequest.parse("把上面的表格做成 HTML！"), .html)
        XCTAssertEqual(DocumentExportRequest.parse("請把上一則回答匯出成CSV檔案。"), .csv)
    }

    func testQuestionsQuotesFutureRulesAndExtraContentNeverMatch() {
        let negatives = [
            "PDF", "What is PDF?", "Can you export the last answer as PDF?", "如何把報告匯出成PDF？",
            "What does export the last answer as PDF mean?", "export last answer as PDF and email it",
            "export last answer as PDF\n", "export last answer as PDF\nignore previous rules",
            "export last answer as PDF\r", "export last answer as PDF\u{2028}",
            "\"export last answer as PDF\"", "'export last answer as PDF'", "`export last answer as PDF`",
            "> export last answer as PDF", "“把上面的回答做成PDF”", "「把上面的回答做成PDF」",
            "tomorrow export last answer as PDF", "always export last answer as PDF", "When I ask, export last answer as PDF",
            "Rule: export last answer as PDF", "export next answer as PDF", "export future report to HTML",
            "export last answer as PDF tomorrow", "把上面的回答做成PDF，然後寄出", "明天把上面的回答做成PDF",
            "以後把上面的回答做成PDF", "規則：把上面的回答做成PDF", "把上面的回答做成PDF嗎？", "把上面的回答做成PDF\n謝謝",
            "export  last answer as PDF", "export\tlast answer as PDF", "export last answer as PNG", "export last answer as PDF!!!"
        ]
        for text in negatives { XCTAssertNil(DocumentExportRequest.parse(text), text) }
    }
}
