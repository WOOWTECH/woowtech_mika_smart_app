import Foundation

/// Use the same query for filtering and choosing the empty-state message.
func normalizedMemorySearch(_ query: String) -> String {
    query.trimmingCharacters(in: .whitespacesAndNewlines)
}

func emptyMemoryMessage(for query: String, pending: Bool) -> MemoryDataKey {
    if normalizedMemorySearch(query).isEmpty { return pending ? .emptyPending : .emptyMemory }
    return pending ? .pendingNotFound : .memoryNotFound
}

// Closed, memory-specific display keys. Keep this table separate from the
// generated shared AppText catalog so independent UI work does not reorder it.
enum MemoryDataKey: String, CaseIterable {
    case title, tabMemory, tabSkills, tabPending, tabPendingCount
    case selected, unselected, search, unavailable, reload, dismissNotice
    case routeTitle, routeCount, webLogins, storedData
    case signInsNone, signInsNoneDetail, signInsManage, signInsVisited, signInsSignOutSite, signInsSignedOut
    case signInsAllTitle, signInsAllQuestion, signInsAllBody, signInsAll, signInsAllDone, signInsNote
    case routesSaved, routesClearAll, routesClearTitle, routesClearBody, clear
    case clearAll, clearSubtitle, clearDetails
    case emptyMemory, memoryNotFound, addMemory, emptyPending, pendingNotFound
    case pendingProcedure, pendingSkills, pendingSearchHint
    case manualSource, conversationSource, pinned, originalContent
    case accept, reject, edit, unpin, pin, delete
    case kindAbout, kindPreferences, kindProcedures
    case emptySkills, skillsScope, mineSkills, importSkill, importHint, importSafety
    case getSkills
    case draftImported, draftPending, draftUpdate, changedLines
    case acceptTrial, editDraft, fullText, skillSuspended, skillTrial
    case enableReference, share, restorePrevious
    case skillUserCreated
    case skillDeleteTitle, skillDeleteMessage, confirmSkillDelete
    case useMemory, useMemorySub, autoRemember, autoRememberSub
    case learnSkills, learnSkillsSub, preferenceScope, learningProgress, switches
    case preferenceSaveFailed, preferenceStillOn, preferenceStillOff
    case memoryEditorKind, memoryEditorContent, memoryEditorKeywords, memoryEditorProcedureHelp
    case memoryEditorAddTitle, memoryEditorEditTitle, cancel, save, clearContent, doneTyping
    case skillEditorImportHelp, skillEditorEditHelp, skillEditorImportTitle, skillEditorEditTitle
    case importAction, clearFullText, done
    case clearStageOne, clearStageTwo, clearWarning, continueClear, confirmClear, clearTitle
    case saidSource, sourceDayFormat, kindFact, skillImported, routeCountDetail

    var key: String { "memoryData." + rawValue }

    var translations: (hant: String, en: String) {
        switch self {
        case .title: return ("記憶與資料", "Memory & Data")
        case .tabMemory: return ("記憶", "Memory")
        case .tabSkills: return ("技能", "Skills")
        case .tabPending: return ("待確認", "To review")
        case .tabPendingCount: return ("待確認 %lld", "To review %lld")
        case .selected: return ("已選取", "Selected")
        case .unselected: return ("未選取", "Not selected")
        case .search: return ("搜尋", "Search")
        case .unavailable: return ("記憶資料目前無法讀取；不會以空白資料覆寫原檔。", "Memory data is unavailable. The original file will not be overwritten with empty data.")
        case .reload: return ("重新讀取", "Reload")
        case .dismissNotice: return ("關閉提示", "Dismiss")
        case .routeTitle: return ("記住的操作路線", "Saved routes")
        case .routeCount: return ("%lld 條", "%lld routes")
        case .webLogins: return ("網站登入", "Website sign-ins")
        case .storedData: return ("儲存的資料", "Saved data")
        // Play's WebSitesSection (web_*) and RoutesScreen (routes_*), with the app name.
        case .signInsNone: return ("還沒有造訪過的網站", "No sites visited yet")
        case .signInsNoneDetail: return ("渥屋助理在網頁上辦過事、或你在這裡登入過之後會列在這裡",
                                         "Sites appear here after woowtech agent works on them or you sign in here")
        case .signInsManage: return ("管理", "Manage")
        case .signInsVisited: return ("渥屋助理造訪過這個網站。", "woowtech agent has visited this site.")
        case .signInsSignOutSite: return ("登出這個網站", "Sign out of this site")
        case .signInsSignedOut: return ("已登出 %@。個別網站的登入可能仍在，如需徹底清除請用「全部登出」。",
                                        "Signed out of %@. Some sign-ins may remain; use “Sign out of all” to clear everything.")
        case .signInsAllTitle: return ("全部登出並清除網頁資料", "Sign out of all and clear web data")
        case .signInsAllQuestion: return ("全部登出並清除網頁資料？", "Sign out of all and clear web data?")
        case .signInsAllBody: return ("會登出內建瀏覽器裡的所有網站，並清除它們存在渥屋助理裡的網頁資料。之後渥屋助理用網頁辦事時要重新登入。",
                                      "Signs out of every site in the built-in browser and clears their web data stored in woowtech agent. woowtech agent will need to sign in again when it uses those sites.")
        case .signInsAll: return ("全部登出", "Sign out of all")
        case .signInsAllDone: return ("已全部登出並清除網頁資料。", "Signed out of all and cleared web data.")
        case .signInsNote: return ("網站的登入資料只存在這臺裝置上渥屋助理的私有空間，沒有另行加密，和系統瀏覽器的保護程度相同。",
                                   "Website sign-in data is stored only in woowtech agent’s private storage on this device, without extra encryption — the same protection as the system browser.")
        case .routesSaved: return ("已記住的操作路線", "Saved routes")
        case .routesClearAll: return ("全部清除", "Clear all")
        case .routesClearTitle: return ("清除全部已記住的操作路線？", "Clear all saved routes?")
        case .routesClearBody: return ("清除後，做過的事下次會重新一步步來做，不影響別的設定。",
                                       "After clearing, woowtech agent works things out step by step again next time. Other settings aren’t affected.")
        case .clear: return ("清除", "Clear")
        case .clearAll: return ("全部清除", "Clear all")
        case .clearSubtitle: return ("刪掉所有記憶和學到的技能", "Delete all memory and learned skills")
        case .clearDetails: return ("需要兩次確認，並包含渥屋助理記下的個人檔案及其修改紀錄。模型設定、模型金鑰與 MCP 端點不會被清除。", "Requires two confirmations and includes the profile woowtech agent keeps about you and its edit history. Model settings, keys, and MCP endpoints are kept.")
        case .emptyMemory: return ("還沒有記住的事", "Nothing remembered yet")
        case .memoryNotFound: return ("沒有找到", "Nothing found")
        case .addMemory: return ("手寫一條", "Write one yourself")
        case .emptyPending: return ("沒有等你確認的東西", "Nothing to review")
        case .pendingNotFound: return ("沒有找到", "Nothing found")
        case .pendingProcedure: return ("等你批准的記憶", "Memory waiting for your OK")
        case .pendingSkills: return ("新技能草稿，收下後先試用", "New skill drafts — tried out after you accept")
        case .pendingSearchHint: return ("搜尋僅篩選記憶；技能草稿會全部列出。", "Search filters memories only; all skill drafts remain listed.")
        // Play memory_manual and memory_said (date_pattern_md): the user's own words.
        case .manualSource: return ("你手寫的", "Written by you")
        case .conversationSource: return ("來自你的對話 · %@", "From your conversation · %@")
        case .pinned: return ("已置頂", "Pinned")
        case .originalContent: return ("原來：%@", "Was: %@")
        case .accept: return ("好", "OK")
        case .reject: return ("不要", "No thanks")
        case .edit: return ("改一改", "Edit")
        case .unpin: return ("取消置頂", "Unpin")
        case .pin: return ("置頂", "Pin")
        case .delete: return ("刪除", "Delete")
        case .kindAbout: return ("關於你", "About you")
        case .kindPreferences: return ("偏好", "Preferences")
        case .kindProcedures: return ("做法", "How-tos")
        case .emptySkills: return ("還沒有學到的技能", "No learned skills yet")
        case .skillsScope: return ("收下並啟用的技能只是對話時參考的文字，不會執行程式、控制其他 App 或授予工具權限。", "Accepted, enabled skills are only text the model refers to in chat. They can’t run code, control other apps, or grant tools.")
        case .mineSkills: return ("我的技能", "My skills")
        case .importSkill: return ("匯入技能", "Import a skill")
        case .importHint: return ("貼上別人分享的技能全文", "Paste a skill someone shared with you")
        case .importSafety: return ("貼上 SKILL.md；匯入後先進入待確認，不會立即啟用。", "Paste SKILL.md. Imported skills wait for review and are not enabled immediately.")
        case .getSkills: return ("取得技能", "Get skills")
        case .draftImported: return ("由你匯入 · 尚未核准", "Imported by you · awaiting approval")
        case .draftPending: return ("待你核准", "Awaiting your approval")
        case .draftUpdate: return ("更新草稿；核准前仍保留目前版本。", "Update draft. The current version stays in use until approval.")
        case .changedLines: return ("改了這幾行：", "Changed lines:")
        case .acceptTrial: return ("收下試用", "Accept and try")
        case .editDraft: return ("改一改", "Edit")
        case .fullText: return ("看全文", "View full text")
        // Play skills_suspended and skills_trial; a skill in use has no state line.
        case .skillSuspended: return ("已停用", "Paused")
        case .skillTrial: return ("試用中，還沒用它辦成過事", "On trial, no task done with it yet")
        case .enableReference: return ("啟用文字參考", "Enable text reference")
        case .share: return ("分享技能", "Share skill")
        case .restorePrevious: return ("恢復上一版", "Restore previous version")
        case .skillUserCreated: return ("按你的要求寫下", "Written at your request")
        case .skillDeleteTitle: return ("刪除技能？", "Delete skill?")
        case .skillDeleteMessage: return ("將「%@」從我的技能移除，後續對話不再參考。", "Remove “%@” from My Skills? Future conversations will no longer refer to it.")
        case .confirmSkillDelete: return ("確認刪除", "Confirm deletion")
        case .useMemory: return ("使用記憶", "Use memory")
        case .useMemorySub: return ("關掉後不讀也不記", "When off, woowtech agent neither reads nor saves memory")
        case .preferenceSaveFailed: return ("設定未儲存", "Setting not saved")
        case .preferenceStillOn: return ("「%@」畫面仍顯示開啟。請稍後重試；若資料已在其他位置變更，請重新讀取後再試。", "“%@” still shows as on. Try again later; if data changed elsewhere, reload it first.")
        case .preferenceStillOff: return ("「%@」畫面仍顯示關閉。請稍後重試；若資料已在其他位置變更，請重新讀取後再試。", "“%@” still shows as off. Try again later; if data changed elsewhere, reload it first.")
        case .autoRemember: return ("自動記住我說過的事", "Remember what I say")
        case .autoRememberSub: return ("任務結束後從你的原話裡整理", "Organized from your own words after each task")
        case .learnSkills: return ("從做過的事裡學（技能和操作路線）", "Learn from past tasks (skills and routes)")
        case .learnSkillsSub: return ("學到的內容要你收下才會用", "What woowtech agent learns is used only after you accept it")
        case .preferenceScope: return ("使用記憶不影響已核准技能；技能請用各自開關停用。學習技能開關只控制起草，不影響匯入或使用已核准技能。", "Turning off memory does not disable approved skills; use each skill's switch. The learning switch controls drafting only, not importing or using approved skills.")
        case .learningProgress: return ("正在整理對話記憶…", "Organizing conversation memories…")
        case .switches: return ("開關", "Switches")
        case .memoryEditorKind: return ("種類", "Type")
        // Play's EditDialog: memory_add or edit_it, memory_content and memory_keywords.
        case .memoryEditorContent: return ("內容", "Content")
        case .memoryEditorKeywords: return ("檢索詞（空格分開）", "Keywords (separated by spaces)")
        case .memoryEditorProcedureHelp: return ("做法會先放進「待確認」，你批准後才會用；不會自動執行操作。", "How-tos go to “To review” first and are used only after you approve them. They don’t run anything automatically.")
        case .memoryEditorAddTitle: return ("手寫一條", "Write one yourself")
        case .memoryEditorEditTitle: return ("改一改", "Edit")
        case .cancel: return ("取消", "Cancel")
        case .save: return ("儲存", "Save")
        case .clearContent: return ("清空內容", "Clear content")
        case .doneTyping: return ("完成輸入", "Done typing")
        // Play skills_import with skills_import_hint, and skills_edit_title.
        case .skillEditorImportHelp: return ("會先放進「待確認」，你看過、收下後才會用。", "It goes to “To review” first and isn’t used until you read it and accept it.")
        case .skillEditorEditHelp: return ("看過全文再收下試用；不會執行程式或授予工具權限。", "Read the full text, then accept it for a trial. It can’t run code or grant tool access.")
        case .skillEditorImportTitle: return ("匯入技能", "Import a skill")
        case .skillEditorEditTitle: return ("改一改再試用", "Edit, then try")
        case .importAction: return ("匯入", "Import")
        case .clearFullText: return ("清空全文", "Clear full text")
        case .done: return ("完成", "Done")
        case .clearStageOne: return ("第一步：確認清除範圍", "Step 1: Review what will be cleared")
        case .clearStageTwo: return ("第二步：最後確認", "Step 2: Final confirmation")
        case .clearWarning: return ("將清除所有記憶、技能、待確認草稿、渥屋助理記下的個人檔案及其修改紀錄、路線與版本紀錄。模型設定、模型金鑰與 MCP 端點會保留。此操作無法復原。", "This clears all memories, skills, pending drafts, the profile woowtech agent keeps about you and its edit history, routes, and version history. Model settings, keys, and MCP endpoints remain. This cannot be undone.")
        case .continueClear: return ("繼續", "Continue")
        case .confirmClear: return ("確認全部清除", "Confirm clear all")
        case .clearTitle: return ("清除資料", "Clear data")
        case .saidSource: return ("你在 %@說：『%@』", "You said on %@: “%@”")
        // A date format, not text: Play's date_pattern_md.
        case .sourceDayFormat: return ("M 月 d 日", "MMM d")
        // The add dialog's kinds are 事實／偏好／做法; the list headers say 關於你.
        case .kindFact: return ("事實", "Facts")
        case .skillImported: return ("匯入的", "Imported")
        // Play routes_count on the routes page; the memory page row shows routeCount.
        case .routeCountDetail: return ("%lld 條 · 做過的事下次照著做，更快", "%lld routes · repeats what worked before, faster")
        }
    }
}

struct MemoryDataCopy {
    let language: AppDisplayLanguage

    func text(_ key: MemoryDataKey, _ arguments: CVarArg...) -> String {
        let translations = key.translations
        let format: String
        switch language {
        case .traditionalChinese: format = translations.hant
        case .english: format = translations.en
        }
        guard !arguments.isEmpty else { return format }
        return String(format: format, locale: Locale(identifier: language.rawValue), arguments: arguments)
    }
}
