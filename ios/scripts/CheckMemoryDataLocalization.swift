import Foundation

@main
enum CheckMemoryDataLocalization {
    static func main() {
        let keys = MemoryDataKey.allCases
        precondition(Set(keys.map(\.key)).count == keys.count)
        precondition(keys.allSatisfy { $0.key.hasPrefix("memoryData.") })
        for language in AppDisplayLanguage.allCases {
            let copy = MemoryDataCopy(language: language)
            precondition(keys.allSatisfy { !copy.text($0).isEmpty })
            precondition(copy.text(.title) != copy.text(.tabMemory))
        }

        let traditional = MemoryDataCopy(language: .traditionalChinese)
        let english = MemoryDataCopy(language: .english)
        precondition(normalizedMemorySearch(" \t\n\u{00a0}").isEmpty)
        precondition(normalizedMemorySearch(" \t tea \n") == "tea")
        precondition(emptyMemoryMessage(for: " \t\n\u{00a0}", pending: false) == .emptyMemory)
        precondition(emptyMemoryMessage(for: " \t\n\u{00a0}", pending: true) == .emptyPending)
        precondition(emptyMemoryMessage(for: " tea ", pending: false) == .memoryNotFound)
        precondition(emptyMemoryMessage(for: " tea ", pending: true) == .pendingNotFound)
        // No Simplified Chinese column (2026-11-13): a Simplified Chinese system reads the Traditional one.
        let simplifiedSystem = MemoryDataCopy(language: AppLanguage.system.resolve(preferredLanguages: ["zh-Hans-CN"]))
        precondition(simplifiedSystem.language == .traditionalChinese)
        precondition(keys.allSatisfy { key in
            !english.text(key).unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) }
        })
        precondition(traditional.text(.emptyMemory) == "還沒有記住的事")
        precondition(traditional.text(.emptyPending) == "沒有等你確認的東西")
        precondition(traditional.text(.skillTrial) == "試用中 · 尚未驗證")
        precondition(traditional.text(.selected) == "已選取")
        precondition(traditional.text(.fullText) == "看全文")
        precondition(traditional.text(.viewFullText) == "查看全文")
        precondition(traditional.text(.memoryEditorContent) == "記憶內容（最多 200 個 UTF-16 字元）")
        precondition(traditional.text(.clearStageOne) == "第一步：確認清除範圍")
        precondition(traditional.text(.confirmClear) == "確認全部清除")
        precondition(traditional.text(.websitesAndRoutes, Int64(2), Int64(1)) == "網站知識與路線（2／1）")
        precondition(simplifiedSystem.text(.tabPendingCount, Int64(4)) == "待確認 4")
        precondition(english.text(.tabPendingCount, Int64(4)) == "To review 4")
        precondition(english.text(.websitesAndRoutes, Int64(2), Int64(1)) == "Website notes and routes (2/1)")
        precondition(english.text(.conversationSource, "Nov 11") == "From your conversation · Nov 11")
        precondition(english.text(.memoryEditorAddTitle) == "Add memory")
        precondition(simplifiedSystem.text(.memoryEditorAddTitle) == "新增記憶")
        precondition(english.text(.clearTitle) == "Clear data")
        precondition(traditional.text(.title) != english.text(.title))
        precondition(simplifiedSystem.text(.title) == traditional.text(.title))
        for copy in [traditional, english] {
            let name = copy.text(.useMemory)
            let on = copy.text(.preferenceStillOn, name), off = copy.text(.preferenceStillOff, name)
            precondition(!copy.text(.preferenceSaveFailed).isEmpty && on.contains(name) && off.contains(name) && on != off)
        }
        precondition(traditional.text(.preferenceStillOn, traditional.text(.useMemory)).contains("仍顯示開啟"))
        precondition(traditional.text(.preferenceStillOn, traditional.text(.useMemory)).contains("稍後重試"))
        precondition(traditional.text(.preferenceStillOff, traditional.text(.useMemory)).contains("仍顯示關閉"))
        precondition(english.text(.preferenceStillOn, english.text(.useMemory)).contains("still shows as on"))

        print("PASS memoryData keys=\(keys.count) languages=\(AppDisplayLanguage.allCases.count) preferenceFailure=on/off")
    }
}
