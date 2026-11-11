# Android 渥屋助理對照工作項目

使用者要求除手機控制、操作其他 App 與螢幕錄影外，Android 渥屋助理的畫面、功能和操作均納入 iOS 對照。此清單記錄靜態來源檢查發現的主要差距，**不是完整功能認證**；每項仍需在對應版本的 iPhone／iPad 實測。

來源：Android `de5be358c4e24b7eed46a95e46edf35a86881bff`；iOS `11646634cc580b0844c20993f83de8961e04c221`；Craft Anything 檢查的公開 APK 是另一版本 `v0.1.37-woow.7`（tag `da8e578`）。版本與方法見 [介面對照基準](ANDROID_UI_REFERENCE.md)。

| 範圍 | 已觀察到的現況與待辦 | 主要來源 |
| --- | --- | --- |
| 聊天首屏及抽屜 | 已有品牌頂欄、抽屜、問候、對話歷史與置頂；頂欄狀態、首屏資訊位置及返回抽屜行為仍有差異。需同尺寸、語言、外觀及資料狀態比較截圖。 | `app/src/main/java/com/wangzan101/mika/ui/ChatScreen.kt`、`ios/Sources/App/ContentView.swift` |
| 訊息操作 | iOS 可選取文字並支援部分 Markdown；Android 的引用、回合分支、符合條件時重試等操作未見對等入口，須核對附件及未完成回合的限制。 | `app/src/main/java/com/wangzan101/mika/ui/ChatScreen.kt`、`ios/Sources/App/ChatReplyMarkdown.swift` |
| 語音輸入 | Android 有按住說話、辨識後填入草稿及語音模型設定；iOS 尚缺 App 內對應流程。需驗證權限、取消、辨識失敗與草稿保留。 | `app/src/main/java/com/wangzan101/mika/ui/SpeechModelScreen.kt`、`ios/Sources/App/ContentView.swift` |
| 圖片及一般附件 | iOS 有受限的文字型 PDF 流程；Android 有相機、相簿、檔案與多附件。需實作實際資料傳遞與錯誤處理，並依模型支援能力顯示結果。 | `app/src/main/java/com/wangzan101/mika/ui/ChatAttachments.kt`、`ios/README.md` |
| 模型與用量 | iOS 有 URL、模型及金鑰設定與 OpenAI-compatible 對話；Android 的首次引導、多服務商、角色、連線測試及用量仍需逐項對照，不能只補外觀。 | `app/src/main/java/com/wangzan101/mika/ui/ModelSetupScreen.kt`、`ios/Sources/App/MikaAlignedSettingsView.swift`、[runtime 差異](ANDROID_MIKA_RUNTIME_BASELINE.md) |
| 定時任務 | Android 有排程頁與啟停、立即執行等操作；iOS 現有通知不等於排程。需分開驗證 iOS 實際背景執行條件，並準確呈現可提供的行為。 | `app/src/main/java/com/wangzan101/mika/ui/PlansScreen.kt`、`ios/docs/TASK_NOTIFICATIONS.md` |
| 瀏覽器 | iOS 已有分頁、書籤、搜尋、下載及研究等能力，登入、頁面互動、區域網路等仍須逐流程比對。 | `app/src/main/java/com/wangzan101/mika/ui/BrowserScreen.kt`、`ios/README.md` |
| 記憶、技能及 MCP | 各有實作；原版技能執行環境、MCP 傳輸／認證及真實模型整合仍有差距或驗收待完成。 | [記憶與技能](MEMORY_SKILLS_PARITY.md)、[runtime 差異](ANDROID_MIKA_RUNTIME_BASELINE.md) |
| 設定、語言與關於 | 語言、外觀、通知及版本頁已部分實作；聊天區固定文案、關於頁的說明、授權與更新入口尚需逐項對照。 | `app/src/main/java/com/wangzan101/mika/ui/AboutScreen.kt`、`ios/Sources/App/MikaAboutView.swift` |

Android 檔案及 APK 字串只提供功能線索。驗收必須記錄來源版本、可操作步驟、結果和裝置／模擬器；僅能做到平台替代行為時，也需明示差別。

## 關於頁後續對照

Craft Anything 讀取 `v0.1.37-woow.7` 的繁中字串，可見檢查更新、更新記錄、回報問題、複製診斷資訊、儲存庫、使用說明與授權等項目；Android `AboutScreen.kt` 也有對應操作。iOS `d462653` 補上開源專案、專案說明、問題回報及授權連結，連結及三語文字經本機檢查，原生畫面和點擊尚待測。檢查更新、更新記錄、診斷資訊及 iOS 專用使用說明仍待實作或驗證；不能以 Android APK 下載更新代替 iOS 的發行流程。以上四個連結未代表關於頁已完全對齊。
