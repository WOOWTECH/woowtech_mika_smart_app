import Foundation

/// Only a complete, explicit reference to a previous answer can open the export preview.
/// This is intent recognition, never authorization to save, share, or execute content.
public enum DocumentExportRequest {
    public static func parse(_ text: String) -> DocumentFormat? {
        guard text.utf8.count <= 256,
              !text.unicodeScalars.contains(where: { CharacterSet.newlines.contains($0) || $0.value < 32 }) else {
            return nil
        }
        let text = text.trimmingCharacters(in: CharacterSet(charactersIn: " "))
        let patterns = [
            #"\A(?:export|save) (?:the )?(?:previous|last) (?:answer|response|report|table) (?:as|to) (pdf|html|csv)[.!?。！？]?\z"#,
            #"\A(?:請)?把(?:剛才|上面|上一則|上一则|上個)的?(?:回答|回覆|分析|報告|报告|表格)(?:整理成|做成|匯出成|导出为|輸出成|轉成) ?(pdf|html|csv)(?: ?(?:檔案|檔))?[.!?。！？]?\z"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                  let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let range = Range(match.range(at: 1), in: text) else { continue }
            return DocumentFormat(rawValue: text[range].lowercased())
        }
        return nil
    }
}
