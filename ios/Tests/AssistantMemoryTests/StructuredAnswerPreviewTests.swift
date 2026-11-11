import Foundation
#if !STRUCTURED_ANSWER_PREVIEW_STANDALONE
import XCTest
@testable import AssistantMemory
#endif

private enum StructuredAnswerPreviewChecks {
    struct Failure: Error { let name: String }
    struct Assertions {
        var count = 0
        mutating func check(_ condition: @autoclosure () -> Bool, _ name: String) throws {
            guard condition() else { throw Failure(name: name) }
            count += 1
        }
    }

    static func finishOnly() throws -> Int {
        var c = Assertions(), preview = StructuredAnswerPreview()
        try c.check(preview.append(" \n{ \"action\" : \"fin") == nil, "split action hidden")
        try c.check(preview.append("ish\" , \"answer\" : \"") == nil, "empty answer hidden")
        try c.check(preview.append("Hello ") == "Hello ", "first decoded answer")
        try c.check(preview.append("世界") == "Hello 世界", "Unicode answer")
        try c.check(preview.append("\"}") == nil && preview.current == "Hello 世界" && !preview.isRejected,
                    "closing envelope adds no raw syntax")
        for raw in [
            #"{"action":"profile_edit","arguments":{"quote":"SECRET"}}"#,
            #"{"action":"memory_search","arguments":{"query":"SECRET"}}"#,
            #"{"action":"memory_save","arguments":{"content":"SECRET"}}"#,
            #"{"action":"memory_edit","arguments":{"content":"SECRET"}}"#,
            #"{"answer":"SECRET","action":"finish"}"#,
            #"{"\u0061ction":"finish","answer":"SECRET"}"#,
            #"[{"action":"finish","answer":"SECRET"}]"#
        ] {
            var hidden = StructuredAnswerPreview()
            for byte in raw.utf8 {
                try c.check(hidden.append(String(decoding: [byte], as: UTF8.self)) == nil, "unrecognized byte hidden")
            }
            try c.check(hidden.current == nil, "unrecognized envelope cannot preview")
        }
        return c.count
    }

    static func escapes() throws -> Int {
        var c = Assertions(), preview = StructuredAnswerPreview()
        try c.check(preview.append(#"{"action":"finish","answer":"Hi \"#) == "Hi ", "literal before split escape")
        try c.check(preview.append(#"u4E16\u754C "#) == "Hi 世界 ", "escaped Unicode decoded")
        try c.check(preview.append(#"\uD83C"#) == nil && preview.current == "Hi 世界 ", "incomplete surrogate hidden")
        try c.check(preview.append(#"\uDFE1"#) == "Hi 世界 🏡", "surrogate pair decoded")
        try c.check(preview.append(#"\nQuote: \""#) == "Hi 世界 🏡\nQuote: \"", "escaped control and quote decoded")
        try c.check(preview.append(#" \\ end"}"#) == "Hi 世界 🏡\nQuote: \" \\ end", "backslash decoded")
        return c.count
    }

    static func malformed() throws -> Int {
        var c = Assertions()
        for suffix in [#"\q"#, #"\uD800X"#, #"\uDC00"#, "\nraw"] {
            var preview = StructuredAnswerPreview()
            try c.check(preview.append(#"{"action":"finish","answer":"safe"#) == "safe", "safe prefix")
            try c.check(preview.append(suffix) == nil && preview.isRejected && preview.current == nil,
                        "invalid escape or control clears preview")
            try c.check(preview.append(#"","arguments":{"secret":"SECRET"}}"#) == nil && preview.current == nil,
                        "rejected parser cannot resume")
        }
        for suffix in [#", "action":"profile_edit"}"#, #", "extra":1}"#, #"}TRAILING"#] {
            var preview = StructuredAnswerPreview()
            try c.check(preview.append(#"{"action":"finish","answer":"tentative""#) == "tentative",
                        "answer remains provisional before object close")
            try c.check(preview.append(suffix) == nil && preview.isRejected && preview.current == nil,
                        "invalid suffix retracts decoded preview as soon as it arrives")
        }
        return c.count
    }
}

#if STRUCTURED_ANSWER_PREVIEW_STANDALONE
@main private enum StructuredAnswerPreviewMain {
    static func main() {
        do {
            let groups = try [StructuredAnswerPreviewChecks.finishOnly(), StructuredAnswerPreviewChecks.escapes(),
                              StructuredAnswerPreviewChecks.malformed()]
            print("{\"groups\":3,\"assertions\":\(groups.reduce(0, +)),\"group_counts\":\(groups)}")
        } catch { print("PREVIEW_FAILURE: \(error)"); exit(1) }
    }
}
#else
final class StructuredAnswerPreviewTests: XCTestCase {
    func testFinishOnly() throws { XCTAssertGreaterThan(try StructuredAnswerPreviewChecks.finishOnly(), 0) }
    func testEscapes() throws { XCTAssertGreaterThan(try StructuredAnswerPreviewChecks.escapes(), 0) }
    func testMalformed() throws { XCTAssertGreaterThan(try StructuredAnswerPreviewChecks.malformed(), 0) }
}
#endif
