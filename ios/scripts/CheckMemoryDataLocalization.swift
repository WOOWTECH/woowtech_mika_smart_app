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
        // Play 964d7bec (woowtech) memory and skills wording.
        precondition(traditional.text(.skillTrial) == "試用中，還沒用它辦成過事")
        precondition(traditional.text(.manualSource) == "你手寫的")
        precondition(traditional.text(.saidSource, "11 月 14 日", "我喜歡烏龍茶") == "你在 11 月 14 日說：『我喜歡烏龍茶』")
        precondition(english.text(.saidSource, "Nov 14", "I like oolong") == "You said on Nov 14: “I like oolong”")
        precondition(traditional.text(.skillEditorImportTitle) == "匯入技能" && traditional.text(.skillEditorEditTitle) == "改一改再試用")
        precondition(traditional.text(.restorePrevious) == "恢復上一版" && traditional.text(.share) == "分享技能")
        precondition(traditional.text(.routeCountDetail, Int64(2)) == "2 條 · 做過的事下次照著做，更快")
        // No English "Skill(s)" and no half-width ,:;( inside Traditional Chinese sentences.
        let han = { (c: Character) in c.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) } }
        for key in keys {
            let text = traditional.text(key)
            precondition(!text.contains("Skill"), "English Skill in \(key)")
            let characters = Array(text)
            for (index, character) in characters.enumerated() where ",:;(".contains(character) {
                let before = index > 0 ? characters[index - 1] : " "
                let after = index + 1 < characters.count ? characters[index + 1] : " "
                precondition(!han(before) && !han(after), "half-width punctuation in \(key)")
            }
        }
        precondition(traditional.text(.selected) == "已選取")
        precondition(traditional.text(.fullText) == "看全文")
        precondition(traditional.text(.memoryEditorContent) == "內容")
        precondition(traditional.text(.clearStageOne) == "第一步：確認清除範圍")
        precondition(traditional.text(.confirmClear) == "確認全部清除")
        precondition(traditional.text(.routeCount, Int64(2)) == "2 條")
        precondition(simplifiedSystem.text(.tabPendingCount, Int64(4)) == "待確認 4")
        precondition(english.text(.tabPendingCount, Int64(4)) == "To review 4")
        precondition(english.text(.routeCount, Int64(2)) == "2 routes")
        precondition(english.text(.signInsSignedOut, "example.com").hasPrefix("Signed out of example.com.")
                     && traditional.text(.signInsSignedOut, "example.com").hasPrefix("已登出 example.com。"))
        precondition(english.text(.conversationSource, "Nov 11") == "From your conversation · Nov 11")
        precondition(english.text(.memoryEditorAddTitle) == "Write one yourself")
        precondition(simplifiedSystem.text(.memoryEditorAddTitle) == "手寫一條")
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
