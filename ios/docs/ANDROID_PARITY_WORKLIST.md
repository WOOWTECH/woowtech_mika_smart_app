# Android 渥屋助理對照工作項目

使用者要求除**手機控制及操作其他 App**外，Android 渥屋助理的功能、介面與操作都納入 iOS 逐項對照。這是尚未完成的工作清單，**不是完整功能或視覺驗收**。涉及 Android 特定執行環境、背景能力或平台政策的項目仍須列出實際差異和可行替代，不以空入口或名稱相同冒充能力。

## 基準與證據用法

- Android 來源基準 `de5be358c4e24b7eed46a95e46edf35a86881bff`；以下 `A:` 路徑均相對於該 Android 倉庫根目錄。此來源的建置版號是 woow.8，**不等於**下列已檢查的發行 APK。
- 本次靜態核對的 iOS 主線基準 `272c702`；以下 `I:` 路徑相對於本倉庫的 `ios/`。過去清單使用的 `1164663` 已不是本次基準。本文件不推定主線後續提交或其他 worktree 已合併。
- 已取得 Craft Anything graph 與繁中資源，對象是官方 APK `v0.1.37-woow.7`、tag `da8e578`，APK SHA-256 `39f36725c7bac06f91d318cdabdb4c91b90e25af1ce13d413a6f579e2c3b1ea4`。graph 顯示 Kotlin／WebView 提示、四個 DEX 與 arm64；其 manifest 元件未解碼，不能當完整頁面圖。
- 本次使用 `/tmp/woow-craft-android-graph-woow7.json`、`/tmp/woow-craft-zh-hant-woow7.json`、`/tmp/woow-craft-zh-hant-woow7-page2.json`、`/tmp/woow-craft-zh-tw-woow7.json`；這些是本機暫存證據，**不是倉庫內長期保存的 artifact**。兩頁 `b+zh+Hant` 分別回傳 1,000／970 筆，`zh-rTW` 131 筆；包含 Android／依賴框架字串。下表 APK 鍵僅作查找線索：排除框架資源及手機控制／操作其他 App 項目，並以 Android 來源核對；字串數量、graph 節點和存在某個 Kotlin 類別都不代表可操作功能數或 iOS 通過。
- 上述四份暫存 JSON 的 SHA-256，依 graph、繁中第一頁、繁中第二頁、zh-rTW 順順序：`be3c9dbbd01ec9f18659227830b8fea363fd3a6b0f7e47e6580275bd9a96e90a`、`ae9ad46242afbc578d5d68b058f13ef673262b94f7e6bcad0098cf33b9445daf`、`ffbe041f1d791150ec04ae7112385c4b84c6387b4df93703527a59b3db3246dd`、`c6bc3bb0582ed51e6d311266b6e4b8480af4bdf8733cf09511fcaaa46d6df8ab`。
- 原始 APK、版本和介面方法見 [介面對照基準](ANDROID_UI_REFERENCE.md)；已有詳細對照見 [runtime 差異](ANDROID_MIKA_RUNTIME_BASELINE.md)、[記憶與技能](MEMORY_SKILLS_PARITY.md)、[聊天差異](ANDROID_CHAT_UI_GAPS.md) 及下列各專題。此表只補原九個粗分類未具體列出的驗收項／索引，**不重做或覆蓋既有專題的測試結果**。

狀態僅描述指定 iOS 基準的靜態證據：**部分**＝看到相關實作但未證明等價；**缺入口／缺同等入口**＝本次在所列產品路徑未見相應入口；**待確認**＝需更深入驗證，不能當作缺失或已完成。不同 worktree 的候選分開標示。每項驗收仍需固定 Android APK、iOS commit、裝置、語言、外觀和資料狀態，記錄操作與結果；含平台限制的項目需逐一說明。

## 設定、模型與語音

| 原清單未細列的行為／驗收 | Android 來源與 APK 線索 | iOS 基準及待辦 |
| --- | --- | --- |
| 服務商管理：新增、刪除、更新金鑰、列出／篩選模型、選模型前試呼叫與狀態。 | A:`app/src/main/java/com/wangzan101/mika/ui/ModelsScreen.kt`、`app/src/main/java/com/wangzan101/mika/ui/ModelSetupViewModel.kt`；`models_add_provider`、`models_list_failed`、`models_delete_used`。 | **部分**：I:`Sources/App/MikaAlignedSettingsView.swift` 是單組 URL／模型／金鑰及已存設定連線測試；依 [runtime 差異](ANDROID_MIKA_RUNTIME_BASELINE.md) 逐一驗證多服務商與協定，包含刪除正在使用的設定。 |
| 帳戶式供應商登入／登出、登入中斷、刪除或變更帳戶後模型角色失效。 | A:`app/src/main/java/com/wangzan101/mika/ui/AccountSignIn.kt`、`app/src/main/java/com/wangzan101/mika/settings/ChatGptSignIns.kt`；`models_roles`。 | **待確認**：I:`Sources/App/MikaAlignedSettingsView.swift` 的 API Key 設定不等同帳戶登入；需查供應商協定、授權及失敗恢復。 |
| 主模型、看圖、輕量和語音角色；推理強度、上下文長度及壓縮觸發設定。 | A:`app/src/main/java/com/wangzan101/mika/ui/ModelSetupScreen.kt`、`app/src/main/java/com/wangzan101/mika/ui/ModelsScreen.kt`；`role_main`、`role_vision`、`role_light`、`role_speech`、`model_context_trigger`。 | **部分**：iOS 設定畫面顯示主模型，尚須核對其他角色與實際模型行為；同名選項不能替代有效執行。 |
| 首次引導：選服務商、測試／略過、錯誤後續操作。 | A:`app/src/main/java/com/wangzan101/mika/ui/Onboarding.kt`、`app/src/main/java/com/wangzan101/mika/ui/ModelSetupScreen.kt`；`welcome_start`、`models_untested_note`。 | **待確認**：I:`Sources/App/MikaAlignedSettingsView.swift` 有設定與測試；首次啟動、返回和已配置使用者路徑須按版本實測。 |
| Token 用量：時間區間、自訂日期、按服務商／模型與趨勢、快取及輸入／輸出。 | A:`app/src/main/java/com/wangzan101/mika/ui/UsageScreen.kt`；`usage_24h`、`usage_by_provider`、`usage_cached`。 | **缺入口**：本次未見同等使用量頁；需先確認服務回傳資料可用、儲存和刪除規則，再做可驗收入口。 |
| 語言範圍及外觀：Android 除中、英還提供阿拉伯、日、韓、西、葡、俄、印尼語及系統語言。 | A:`app/src/main/java/com/wangzan101/mika/i18n/AppLanguage.kt`、`app/src/main/java/com/wangzan101/mika/ui/SettingsSubPages.kt`；`language_title`。 | **部分**：I:`Sources/App/AppLanguage.swift` 只有系統、繁中、簡中、英文。增加語系須覆蓋實際畫面與錯誤文案；阿拉伯語另驗 RTL、數字及語音語系。 |
| 語音模型設定：系統辨識／停用／服務商模型、可用性與試轉、線上／離線說明。 | A:`app/src/main/java/com/wangzan101/mika/ui/SpeechModelScreen.kt`、`app/src/main/java/com/wangzan101/mika/voice/SpeechResolver.kt`；`speech_system`、`speech_pick_failed`、`speech_off_note`。 | **缺入口**：`272c702` 無該設定頁；語音 UI 候選 `c6e549c` 不是主線，且音訊所有權與 VoiceOver 取消仍有審查阻擋。需分別驗麥克風權限、音訊資源、設定變更與錯誤。 |
| 按住說話、上滑取消、辨識結果填草稿；任務進行中對目標插話。 | A:`app/src/main/java/com/wangzan101/mika/ui/VoiceHold.kt`、`app/src/main/java/com/wangzan101/mika/voice/HoldToTalk.kt`、`app/src/main/java/com/wangzan101/mika/ui/ChatScreen.kt`；`voice_slide_cancel`、`voice_release_fill`、`voice_steer_to`。 | **缺入口**：需測一般草稿與任務中插話兩種上下文、舊結果和取消；不可將手機控制的浮動操作當作必要前提。 |
| 進階：網路代理設定及不同連線範圍／不支援提示。 | A:`app/src/main/java/com/wangzan101/mika/ui/SettingsScreen.kt`、`app/src/main/java/com/wangzan101/mika/ui/NetProxySettings.kt`；`net_proxy`、`net_proxy_browser_unsupported`。 | **部分**：I:`Sources/App/MikaAlignedSettingsView.swift` 已有進階→MCP 導覽，但沒有宣稱代理已可用；需逐項查模型、MCP、WebKit 的實際設定及平台邊界。 |
| 計算環境、每工作區用量／清理；診斷的瀏覽器及環境自檢。 | A:`app/src/main/java/com/wangzan101/mika/ui/AdvancedSection.kt`、`app/src/main/java/com/wangzan101/mika/ui/SelfCheckScreen.kt`；`settings_sandbox`、`selfcheck_check_browser`。 | **待確認／能力有差距**：I:`Sources/App/SkillWorkerSettings.swift` 為外部 worker 設定，不能等同 Android 沙箱；見 [技能執行範圍](SKILL_RUNTIME.md)。自檢僅追蹤瀏覽器、環境等非手機控制項。 |
| 任務執行設定中與非手機控制相關的步數上限、自行配置權限及變更後行為。 | A:`app/src/main/java/com/wangzan101/mika/ui/SettingsSubPages.kt`、`core/src/main/kotlin/com/wangzan101/mika/core/settings/SelfConfig.kt`；`settings_step_limit`、`settings_self_config`。 | **部分**：I:`Sources/App/SelfConfigurationView.swift` 與 `Sources/AssistantSkills/SelfConfigurationStore.swift` 有有界自行配置；需按項比較允許／撤銷與真實任務效果，手機操控節奏、靜音等不列。 |
| 通知分類與可行動的狀態指引、任務與授權提醒。 | A:`app/src/main/java/com/wangzan101/mika/ui/SettingsSubPages.kt`、`app/src/main/java/com/wangzan101/mika/settings/NotificationOverview.kt`；`settings_notif_master`、`settings_task_notifs`。 | **部分**：I:`Sources/App/TaskNotificationSettingsView.swift`；依 [任務通知](TASK_NOTIFICATIONS.md) 比對允許／拒絕、各種提醒及導向，通知不等於任務執行。 |
| 關於：版本、版本變更、授權、指南、意見回饋及更新檢查。 | A:`app/src/main/java/com/wangzan101/mika/ui/AboutScreen.kt`、`app/src/main/java/com/wangzan101/mika/ui/LicensesScreen.kt`；`about_changelog`、`about_feedback`、`about_check`。 | **部分**：I:`Sources/App/MikaAboutView.swift`；逐入口比較可讀內容與平台發行方式，Android APK 下載安裝流程需依 iOS 發行機制另設對應。 |

## 對話與定時任務

| 原清單未細列的行為／驗收 | Android 來源與 APK 線索 | iOS 基準及待辦 |
| --- | --- | --- |
| 聊天首屏、頂欄狀態、抽屜歷史／置頂及返回；保存範圍說明。 | A:`app/src/main/java/com/wangzan101/mika/ui/ChatScreen.kt`、`app/src/main/java/com/wangzan101/mika/ui/ChatDrawer.kt`；`drawer_recent`、`drawer_pinned`。 | **部分**：I:`Sources/App/ContentView.swift`、`Sources/App/ConversationArchiveStore.swift`；保留 [聊天差異](ANDROID_CHAT_UI_GAPS.md) 的既有對照，按相同狀態與尺寸驗證。 |
| 任務中插話及狀態；**只對仍未被取用且符合條件的本機插話**提供編輯／撤回，非任意歷史訊息。 | A:`app/src/main/java/com/wangzan101/mika/ui/ChatViewModel.kt`、`app/src/main/java/com/wangzan101/mika/ui/ChatScreen.kt`、`app/src/main/java/com/wangzan101/mika/ui/MessageMenu.kt`；`chat_edit_message`、`chat_withdraw_message`。 | **缺入口**：I:`Sources/App/ChatSession.swift` 的一般提交中狀態與 Android 插話流程不同；需涵蓋消費競態、已撤回／已取用與取消。 |
| 執行中等待使用者輸入、允許一次／拒絕、排隊、暫停、繼續、取消及狀態保留。 | A:`app/src/main/java/com/wangzan101/mika/ui/ChatScreen.kt`、`app/src/main/java/com/wangzan101/mika/ui/ChatViewModel.kt`；`chat_allow_once`、`chat_continue`。 | **部分**：iOS 有特定 MCP／技能核准與取消流程，需比對一般任務狀態、回合和不同目的地；排除控制其他 App 的接手流程。 |
| 引用、分支／重新問的可用條件、附件與不完整回合；執行摘要與來源入口。 | A:`app/src/main/java/com/wangzan101/mika/ui/MessageMenu.kt`、`app/src/main/java/com/wangzan101/mika/ui/ChatBranch.kt`、`app/src/main/java/com/wangzan101/mika/chat/ConversationBrancher.kt`；`chat_branch_attachments_readd`、`chat_view_source`。 | **部分**：I:`Sources/App/ChatSession.swift`、`Sources/App/ConversationArchiveStore.swift` 已有引用及分支核心；需逐一確認 UI 是否接線和來源／附件結果，不能以核心存在認證整個操作。 |
| 執行過程：步驟、結果、耗時、模型呼叫、使用的記憶及 Token 用量 JSONL 匯出。 | A:`app/src/main/java/com/wangzan101/mika/ui/RunTimelineScreen.kt`、`app/src/main/java/com/wangzan101/mika/ui/RunTraceSection.kt`；`timeline_export`、`timeline_memory_used`。 | **缺同等入口**：需確認 iOS 可提供的實際記錄、資料保留和匯出範圍；與上列 Token 用量頁分開驗收。 |
| 相機／相簿／檔案、多附件、傳送前移除、拒收原因與重新加入。 | A:`app/src/main/java/com/wangzan101/mika/ui/ChatAttachments.kt`、`app/src/main/java/com/wangzan101/mika/ui/AttachmentMessage.kt`；`chat_attach_rejected`。 | **部分**：I:`Sources/App/ChatPDFAttachment.swift` 為受限 PDF 流程；一般圖片／附件與各模型實際資料通路須逐種驗證。 |
| 定時任務清單：進行中／已停用、建立對話、啟停、改時間及預覽、立即執行、刪除、上次結果及待確認。 | A:`app/src/main/java/com/wangzan101/mika/ui/PlansScreen.kt`、`app/src/main/java/com/wangzan101/mika/task/TriggerRuntime.kt`；`plans_run_now`、`plans_result_pending`、`trigger_interrupted_body`。 | **缺入口**：主線沒有排程頁。獨立候選 `19947ab`／`e18a37d` 僅提供加密儲存、排程計算及注入式前景 runner，未接真實執行器／UI；不確定 claim 的調解未完成。iOS 背景執行不保證準時，不能把通知或預覽當作已執行。 |

## 瀏覽器、記憶、技能及 MCP

| 原清單未細列的行為／驗收 | Android 來源與 APK 線索 | iOS 基準及待辦 |
| --- | --- | --- |
| 網頁內提問：選取文字、另起或繼續對話、展開／收合、頁面切換、暫停與交還。 | A:`app/src/main/java/com/wangzan101/mika/ui/BrowserPageAsk.kt`、`app/src/main/java/com/wangzan101/mika/browser/PageAskModel.kt`；`browser_ask_selection`、`browser_ask_open_chat`、`browser_ask_paused`。 | **部分**：I:`Sources/App/BrowserSession.swift` 有受限研究／互動；依 [多來源研究](MULTI_SOURCE_RESEARCH.md) 與既有瀏覽器專題核對，尤其頁面／對話身分及授權撤銷。 |
| 首頁常用網站整理、近期瀏覽清除，頁面複製連結、桌面／行動切換與頁面對話框。 | A:`app/src/main/java/com/wangzan101/mika/ui/BrowserStart.kt`、`app/src/main/java/com/wangzan101/mika/ui/BrowserScreen.kt`；`browser_edit_favorites`、`browser_desktop`。 | **部分**：I:`Sources/App/BrowserStartPageView.swift`、`Sources/App/BrowserWorkspace.swift`；逐項比對入口、切換及真實網頁效果，不重做既有 [搜尋](MANUAL_BROWSER_SEARCH.md) 與 [站點模式](MANUAL_BROWSER_SITE_MODES.md) 對照。 |
| 分頁新增／切換／關閉、下載及選擇檔案，上傳失敗與下載管理。 | A:`app/src/main/java/com/wangzan101/mika/ui/BrowserScreen.kt`、`app/src/main/java/com/wangzan101/mika/browser/UserBrowser.kt`；`browser_close_page`。 | **部分**：I:`Sources/App/BrowserWorkspace.swift`、`Sources/App/BrowserDownloadsView.swift`；沿用既有瀏覽器驗證與 [下載 PDF](BROWSER_DOWNLOADED_PDF_BRIDGE.md)，分開核對選檔器、實際檔案與多分頁。 |
| 網站登入管理：清單、個別登出／清資料、全部登出及部分清除說明。 | A:`app/src/main/java/com/wangzan101/mika/ui/WebSitesSection.kt`；`web_sign_out_site`、`web_logout_partial`。 | **部分**：I:`Sources/App/BrowserWorkspace.swift` 有網站資料清除；需驗實際 cookie、登入狀態、其他站點隔離及清除後的呈現。 |
| 區網頁面：使用者授權、導址與其他分頁、歷史／書籤／研究隔離。 | A:`app/src/main/java/com/wangzan101/mika/ui/BrowserScreen.kt`、`app/src/main/java/com/wangzan101/mika/browser/UserBrowser.kt`；頁面行為另需實測。 | **未完成**：主線有 [政策](BROWSER_MANUAL_LAN_POLICY.md)，接線候選與 iOS 17 ATS／WebKit 尚需原生驗證；頂層導覽防護不等於子資源和跨 origin 的網路隔離。 |
| 記憶的搜尋、類別、手寫、編輯／置頂／刪除、待確認與三個獨立開關、兩次確認清除。 | A:`app/src/main/java/com/wangzan101/mika/ui/MemoryScreen.kt`、`core/src/main/kotlin/com/wangzan101/mika/core/memory/MemoryStore.kt`；`memory_auto`、`memory_pending`、`memory_clear_sure`。 | **部分**：I:`Sources/App/MemoryDataView.swift`、`Sources/App/LearningStore.swift`；詳細規則及已知證據以 [記憶與技能](MEMORY_SKILLS_PARITY.md) 為準，另補三語 UI 與原生狀態驗收。 |
| 個人技能匯入、待確認全文／編輯／批准／拒絕、試用／停用、分享、還原前一版。 | A:`app/src/main/java/com/wangzan101/mika/ui/SkillsSection.kt`、`core/src/main/kotlin/com/wangzan101/mika/core/skills/SkillImport.kt`；`skills_restore_prev`、`skills_share`、`skills_trial`。 | **部分**：I:`Sources/App/MemoryDataView.swift`、`Sources/App/SkillCatalogView.swift`；逐操作引用 [記憶與技能](MEMORY_SKILLS_PARITY.md) 及 [技能執行範圍](SKILL_RUNTIME.md)，須區分原文、個人技能與實際工具執行。只用於操作其他 App 的知識不納入。 |
| 開發者選項中的非手機控制項：結構化上下文壓縮、任務追蹤、儲存上限與匯出。 | A:`app/src/main/java/com/wangzan101/mika/ui/DeveloperOptionsScreen.kt`、`app/src/main/java/com/wangzan101/mika/ui/RunTraceSection.kt`；`trace_switch`、`trace_storage_limit`。 | **待確認**：需逐一區分可由 iOS 真實執行的追蹤／壓縮與僅依賴 Android 手機控制的選項，不以開關取代底層能力。 |
| MCP 出站伺服器清單、增刪改、單筆測試／全部重新整理、工具允許清單、憑證、OAuth 與 HTTP／SSE／stdio。 | A:`app/src/main/java/com/wangzan101/mika/ui/McpServersScreen.kt`、`core/src/main/kotlin/com/wangzan101/mika/core/cap/mcp/`；`mcp_servers_save_test`、`mcp_servers_use_oauth`、`mcp_servers_transport_sse`。 | **部分**：I:`Sources/AssistantMCP/MCPClient.swift`、`Sources/App/MCPSettings.swift`；依 [runtime 差異](ANDROID_MIKA_RUNTIME_BASELINE.md) 分項驗證傳輸與授權，不把出站 client 當作同時提供其他能力。stdio 等平台方案須標記實際可行性。 |
| 外部 MCP client 連入渥屋助理：連線／授權、任務工具及請求狀態；排除裝置操作工具。 | A:`app/src/main/java/com/wangzan101/mika/ui/McpScreen.kt`、`app/src/main/java/com/wangzan101/mika/mcp/McpService.kt`、`core/src/main/kotlin/com/wangzan101/mika/core/mcp/McpTaskTools.kt`；`mcp_last_request`、`mcp_network_enable`。 | **缺同等入口**：目前 [runtime 差異](ANDROID_MIKA_RUNTIME_BASELINE.md) 明列 iOS 為出站 client；是否可提供安全可撤銷的非手機控制任務服務仍待實作與驗收，不能把出站設定算成入站 server。 |

## 優先驗收次序

1. 對話任務狀態／插話及訊息操作、語音權限與取消、附件實際送達；這些直接影響首輪對話操作。
2. 模型與語音設定、Android 額外語言及 Token 用量；先補資料與失敗路徑，再對照介面。
3. 排程持久化／執行及不確定結果處理；區網與網頁提問的真實邊界。
4. 依既有專題完成記憶、技能、MCP、設定進階項和瀏覽器其餘逐流程驗證；全程保留尚未驗證和平台差異標記。

## 關於頁後續對照

Craft Anything 讀取 `v0.1.37-woow.7` 的繁中字串，可見檢查更新、更新記錄、回報問題、複製診斷資訊、儲存庫、使用說明與授權等項目；Android `AboutScreen.kt` 也有對應操作。iOS `d462653` 補上開源專案、專案說明、問題回報及授權連結，連結及三語文字經本機檢查，原生畫面和點擊尚待測。檢查更新、更新記錄、診斷資訊及 iOS 專用使用說明仍待實作或驗證；不能以 Android APK 下載更新代替 iOS 的發行流程。以上四個連結未代表關於頁已完全對齊。

瀏覽器逐項來源、Android 網頁工具與目前待驗證差異另見 [瀏覽器對照](ANDROID_BROWSER_PARITY_AUDIT.md)。

## 語音後續進度

iOS 開發分支 `55edf2c` 已加入按住說話及取消、辨識結果併入草稿的語音輸入流程。原候選在 iPad 模擬器使用假辨識 driver 的五個介面案例通過；`55edf2c` 合併後的 iOS 原生建置與介面、真人收音和辨識、音訊中斷及 VoiceOver 操作仍待驗證。Android 的語音模型設定亦需另行對照；不能把 Apple Speech 流程當成兩者已完全一致。

## 記憶頁畫面與網站登入入口

使用者提供的 Android 深色畫面中，「記憶與資料」有三個分段、三項開關及獨立的「網站登入」列，該列顯示網站數量。iOS `55edf2c` 的 `MemoryDataView.swift` 已有三個分段與偏好設定，但「網站登入」列目前會切換到瀏覽器，未直接開啟等價的登入清單，也未提供相同的登入數量；同頁另有個人資料列與網站知識／路線合併列，與參考圖排列不同。WebKit 網站資料筆數不必然等於已登入網站數量，不可直接拿來充當該數字。以上為截圖與程式碼對照，仍需在相同資料與畫面條件下實測。手機及其他 App 操作路線維持排除；瀏覽器自身的網站知識仍在範圍內。

本獨立候選將記憶頁「網站登入」改為直接開啟瀏覽器既有的 WebKit 網站資料管理，關閉後回到原記憶頁；沿用逐站清除確認和實際資料清除，沒有將網站資料筆數顯示為登入數。資料列舉期間顯示載入，避免把尚未收到的結果當成空清單。Android 仍有登入／驗證狀態、開啟登入及全部登出等不同操作；iOS 的資料記錄不證明登入狀態，逐站清除資料也不等於網站伺服器端登出。畫面、三語、真實 cookie 與回程的原生測試已加入，仍待 iOS 執行與視覺驗收。

逐站清除確認會顯示選中的網站名稱，並說明不保證伺服器端登出。清除期間進入瀏覽器時，成功清除後才恢復目前分頁；如果使用者已離開則不在背景載入。受控延遲清除的真實 WebKit 測試涵蓋兩種情況與重入，但 iOS 原生執行、對話框視覺和 VoiceOver 呈現仍需驗證；重新載入網站也可能建立新的本機資料。
