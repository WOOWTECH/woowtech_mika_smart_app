import Foundation

@main
enum CheckSkillDeletionCopy {
    static func main() {
        let cases: [(AppDisplayLanguage, String, String, String)] = [
            (.traditionalChinese, "刪除技能？", "確認刪除", "將「notes-test」從我的技能移除"),
            // A Simplified Chinese system shows the Traditional Chinese copy.
            (AppLanguage.system.resolve(preferredLanguages: ["zh-Hans-CN"]), "刪除技能？", "確認刪除", "將「notes-test」從我的技能移除"),
            (.english, "Delete skill?", "Confirm deletion", "Remove “notes-test” from My Skills")
        ]
        for (language, title, confirmation, message) in cases {
            let copy = MemoryDataCopy(language: language)
            precondition(copy.text(.skillDeleteTitle) == title)
            precondition(copy.text(.confirmSkillDelete) == confirmation)
            precondition(copy.text(.skillDeleteMessage, "notes-test").contains(message))
            precondition(copy.text(.cancel) != confirmation)
        }
        print("PASS skill deletion confirmation copy: Traditional Chinese, English, and a Simplified Chinese system")
    }
}
