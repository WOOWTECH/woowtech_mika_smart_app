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
    case profile, routeTitle, websiteKnowledgeCount, routeCount, websitesAndRoutes
    case routesHelp, webLogins, webLoginsHelp, storedData
    case clearAll, clearSubtitle, clearDetails
    case emptyMemory, memoryNotFound, addMemory, emptyPending, pendingNotFound
    case pendingProcedure, pendingSkills, pendingSearchHint
    case manualSource, conversationSource, pinned, originalContent
    case accept, reject, edit, unpin, pin, delete
    case kindAbout, kindPreferences, kindProcedures
    case emptySkills, skillsScope, mineSkills, importSkill, importHint, importSafety
    case getSkills, catalog, pdfRead, agentWrite, transcript, builtInHelp, builtInTools
    case draftImported, draftPending, draftUpdate, changedLines
    case acceptTrial, editDraft, fullText, viewFullText, skillSuspended, skillTrial, skillEnabled
    case enableReference, share, restorePrevious
    case skillDeleteTitle, skillDeleteMessage, confirmSkillDelete
    case useMemory, useMemorySub, autoRemember, autoRememberSub
    case learnSkills, learnSkillsSub, preferenceScope, learningLimit, learningProgress, switches
    case preferenceSaveFailed, preferenceStillOn, preferenceStillOff
    case memoryEditorKind, memoryEditorContent, memoryEditorKeywords, memoryEditorProcedureHelp
    case memoryEditorAddTitle, memoryEditorEditTitle, cancel, save, clearContent, doneTyping
    case skillEditorImportHelp, skillEditorEditHelp, skillEditorImportTitle, skillEditorEditTitle
    case importAction, approveAction, clearFullText, done
    case clearStageOne, clearStageTwo, clearWarning, continueClear, confirmClear, clearTitle

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
        case .profile: return ("個人檔案", "Profile")
        case .routeTitle: return ("記住的操作路線", "Saved routes")
        case .websiteKnowledgeCount: return ("網站知識 %lld 篇", "%lld website notes")
        case .routeCount: return ("%lld 條", "%lld routes")
        case .websitesAndRoutes: return ("網站知識與路線（%lld／%lld）", "Website notes and routes (%lld/%lld)")
        case .routesHelp: return ("網頁路線以實際讀取與完成判定建立；目前只支援公開網站的導覽與核對。", "Web routes are saved after actual reading and outcome review. Only navigation and verification on public sites are supported.")
        case .webLogins: return ("網站登入", "Website sign-ins")
        case .webLoginsHelp: return ("網站登入資料由 WebKit 儲存，可在瀏覽器的網站頁面查看與清除。", "WebKit stores website login data. View or clear it from the browser's Websites page.")
        case .storedData: return ("儲存的資料", "Saved data")
        case .clearAll: return ("全部清除", "Clear all")
        case .clearSubtitle: return ("刪掉所有記憶和學到的技能", "Delete all memory and learned skills")
        case .clearDetails: return ("需要兩次確認，並包含個人檔案。模型設定、模型金鑰與 MCP 端點不會被清除。", "Requires two confirmations and includes your profile. Model settings, keys, and MCP endpoints are kept.")
        case .emptyMemory: return ("還沒有記住的事", "Nothing remembered yet")
        case .memoryNotFound: return ("沒有找到", "Nothing found")
        case .addMemory: return ("手寫一條", "Write one yourself")
        case .emptyPending: return ("沒有等你確認的東西", "Nothing to review")
        case .pendingNotFound: return ("沒有找到", "Nothing found")
        case .pendingProcedure: return ("等你批准的記憶", "Memory waiting for your OK")
        case .pendingSkills: return ("新技能草稿，收下後先試用", "New skill drafts · trial after approval")
        case .pendingSearchHint: return ("搜尋僅篩選記憶；技能草稿會全部列出。", "Search filters memories only; all skill drafts remain listed.")
        case .manualSource: return ("你手動填寫的", "Written by you")
        case .conversationSource: return ("來自你的對話 · %@", "From your conversation · %@")
        case .pinned: return ("已置頂", "Pinned")
        case .originalContent: return ("原來:%@", "Was: %@")
        case .accept: return ("好", "OK")
        case .reject: return ("不要", "No thanks")
        case .edit: return ("改一改", "Edit")
        case .unpin: return ("取消置頂", "Unpin")
        case .pin: return ("置頂", "Pin")
        case .delete: return ("刪除", "Delete")
        case .kindAbout: return ("關於你", "About you")
        case .kindPreferences: return ("偏好", "Preferences")
        case .kindProcedures: return ("做法", "Procedures")
        case .emptySkills: return ("尚未核准任何 Skills。", "No approved skills yet.")
        case .skillsScope: return ("核准並啟用的 Skills 可作為模型對話的文字參考，不會執行程式、控制其他 App 或授予工具權限。試用中不代表已驗證成功。", "Approved, enabled skills are text references for model conversations. They cannot run code, control other apps, or grant tools. Trial does not mean verified.")
        case .mineSkills: return ("我的技能", "My skills")
        case .importSkill: return ("匯入技能", "Import a skill")
        case .importHint: return ("貼上別人分享的技能全文", "Paste a shared skill's full text")
        case .importSafety: return ("貼上 SKILL.md；匯入後先進入待確認，不會立即啟用。", "Paste SKILL.md. Imported skills wait for review and are not enabled immediately.")
        case .getSkills: return ("取得技能", "Get skills")
        case .catalog: return ("Mika 內建技能目錄（6）", "Mika built-in skill catalog (6)")
        case .pdfRead: return ("選取 PDF 並擷取文字", "Select a PDF and extract text")
        case .agentWrite: return ("請模型協助編寫技能", "Ask the model to draft a skill")
        case .transcript: return ("整理文字稿與字幕", "Organize transcripts and subtitles")
        case .builtInHelp: return ("閱讀完整原文與授權，或選取文件執行處理；每個執行步驟仍需核准。", "Read the full source and license, or select a document to process. Each execution step still needs approval.")
        case .builtInTools: return ("內建工具", "Built-in tools")
        case .draftImported: return ("由你匯入 · 尚未核准", "Imported by you · awaiting approval")
        case .draftPending: return ("待你核准", "Awaiting your approval")
        case .draftUpdate: return ("更新草稿；核准前仍保留目前版本。", "Update draft. The current version stays in use until approval.")
        case .changedLines: return ("改了這幾行：", "Changed lines:")
        case .acceptTrial: return ("收下試用", "Accept for trial")
        case .editDraft: return ("改一改", "Edit first")
        case .fullText: return ("看全文", "Full text")
        case .viewFullText: return ("查看全文", "View full text")
        case .skillSuspended: return ("已停用", "Disabled")
        case .skillTrial: return ("試用中 · 尚未驗證", "Trial · not verified")
        case .skillEnabled: return ("已啟用", "Enabled")
        case .enableReference: return ("啟用文字參考", "Enable text reference")
        case .share: return ("分享", "Share")
        case .restorePrevious: return ("還原上一版", "Restore previous version")
        case .skillDeleteTitle: return ("刪除技能？", "Delete skill?")
        case .skillDeleteMessage: return ("將「%@」從我的技能移除，後續對話不再參考。", "Remove “%@” from My Skills? Future conversations will no longer refer to it.")
        case .confirmSkillDelete: return ("確認刪除", "Confirm deletion")
        case .useMemory: return ("使用記憶", "Use memory")
        case .useMemorySub: return ("關掉後不讀也不記", "Off means do not read or save memories")
        case .preferenceSaveFailed: return ("設定未儲存", "Setting not saved")
        case .preferenceStillOn: return ("「%@」畫面仍顯示開啟。請稍後重試；若資料已在其他位置變更，請重新讀取後再試。", "“%@” still shows as on. Try again later; if data changed elsewhere, reload it first.")
        case .preferenceStillOff: return ("「%@」畫面仍顯示關閉。請稍後重試；若資料已在其他位置變更，請重新讀取後再試。", "“%@” still shows as off. Try again later; if data changed elsewhere, reload it first.")
        case .autoRemember: return ("自動記住我說過的事", "Remember what I say automatically")
        case .autoRememberSub: return ("任務結束後從你的原話整理", "Organize your words after a task")
        case .learnSkills: return ("從做過的事裡學（技能和網站知識）", "Learn from completed tasks (skills and website notes)")
        case .learnSkillsSub: return ("學到的內容要你收下才會用", "Learned content is used only after your approval")
        case .preferenceScope: return ("使用記憶不影響已核准技能；技能請用各自開關停用。學習技能開關只控制起草，不影響匯入或使用已核准技能。", "Turning off memory does not disable approved skills; use each skill's switch. The learning switch controls drafting only, not importing or using approved skills.")
        case .learningLimit: return ("網站研究達到學習條件後會提出技能草稿，需核准才會使用。一般模型對話不會直接被當成技能驗證成功。", "Website research may propose a skill draft after meeting learning conditions. It needs approval; a normal model reply does not verify it.")
        case .learningProgress: return ("正在整理對話記憶…", "Organizing conversation memories…")
        case .switches: return ("開關", "Switches")
        case .memoryEditorKind: return ("種類", "Type")
        case .memoryEditorContent: return ("記憶內容（最多 200 個 UTF-16 字元）", "Memory content (up to 200 UTF-16 units)")
        case .memoryEditorKeywords: return ("關鍵字，以空白分隔", "Keywords, separated by spaces")
        case .memoryEditorProcedureHelp: return ("做法會先進入待確認，核准後才可供對話參考；不會自動執行操作。", "Procedures wait for your approval before use in conversations. They do not run automatically.")
        case .memoryEditorAddTitle: return ("新增記憶", "Add memory")
        case .memoryEditorEditTitle: return ("編輯記憶", "Edit memory")
        case .cancel: return ("取消", "Cancel")
        case .save: return ("儲存", "Save")
        case .clearContent: return ("清空內容", "Clear content")
        case .doneTyping: return ("完成輸入", "Done typing")
        case .skillEditorImportHelp: return ("貼上完整 SKILL.md。有效內容會進入待確認，不會立即啟用。", "Paste the full SKILL.md. Valid content waits for review and is not enabled immediately.")
        case .skillEditorEditHelp: return ("檢查全文後核准試用；不會執行程式或授予工具權限。", "Review the full text before approving a trial. It cannot run code or grant tool access.")
        case .skillEditorImportTitle: return ("匯入 Skill", "Import skill")
        case .skillEditorEditTitle: return ("編輯後核准", "Edit and approve")
        case .importAction: return ("匯入", "Import")
        case .approveAction: return ("核准", "Approve")
        case .clearFullText: return ("清空全文", "Clear full text")
        case .done: return ("完成", "Done")
        case .clearStageOne: return ("第一步：確認清除範圍", "Step 1: Review what will be cleared")
        case .clearStageTwo: return ("第二步：最後確認", "Step 2: Final confirmation")
        case .clearWarning: return ("將清除所有記憶、Skills、待確認草稿、網站知識、路線與版本紀錄。模型設定、模型金鑰與 MCP 端點會保留。此操作無法復原。", "This clears all memories, skills, pending drafts, website notes, routes, and version history. Model settings, keys, and MCP endpoints remain. This cannot be undone.")
        case .continueClear: return ("繼續", "Continue")
        case .confirmClear: return ("確認全部清除", "Confirm clear all")
        case .clearTitle: return ("清除資料", "Clear data")
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
