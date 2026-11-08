# 渥屋助理（woowtech agent）fork 說明

上游：[wangzan101/Mika](https://github.com/wangzan101/Mika)（Apache-2.0）。這份文件記錄 WOOWTECH 版跟上游的每一處刻意差異、為什麼這樣改，以及怎麼跟上游同步。改 fork 時，這份文件要一起更新。

## 基準

| 項目 | 值 |
|---|---|
| 切出點 | 上游 `v0.1.37`（`2c4563bc`，2026-11-05） |
| 合併 owner 建的 README commit | `e0108381`（`--allow-unrelated-histories`） |
| applicationId | `io.woowtech.agent`（Kotlin package 維持上游的 `com.wangzan101.mika`） |
| 版本 | `<上游版本>-woow.<N>`；versionCode＝上游 × 100 + N（`app/brand.gradle.kts` 的 `woowtechRevision`） |
| 發佈 | 只發 APK，放本 repo 的 GitHub Releases；不上 Google Play |

## 品牌層怎麼運作

Apporo 共用分支的補充：`BrandValues.capsuleDefaultFraction` 讀取可選 `capsule.default.fraction`，`FeatureFlags` 僅在沒有儲存位置時採用它；渥屋未設定，仍為0。`ui/components/Logo.kt` 可依 `brand_monochrome_logo` 使用 App 主題的標誌顏色，渥屋／上游預設false，原圖不變。Apporo 為0.5與true；理由與裝置驗證見 `docs-apporo/EMULATOR-WAVE2-20261108.zh-TW.md`。

Apporo 對齊 woow.4：共用同意通知金額與分類改名修正；`app/src/apporo/AndroidManifest.xml` 為直接安裝 APK 加上相同準時提醒權限分流，`apporo/tools/check.py` 與 `check-apk.py` 核對來源及成品。Apporo 繁中權限錯誤指引也覆蓋為實際「應用程式存取」頁名。版本為 apporo.2；詳細範圍見 `docs-apporo/PARITY-WOOW4-20261108.zh-TW.md`。這不代表 Google Play 權限資格已核准。

Apporo 實測後的共用介面補強（apporo.3；裝置結果見 `docs-apporo/EMULATOR-WAVE5-20261108.zh-TW.md`）：

- `ScreenAccessibility.expandedSystemPanel` 與 `core/capsule/SystemPanelPolicy` 偵測預設螢幕的大型 SystemUI 視窗：通常須取得輸入焦點；若 App 自己的輸入浮層仍持有焦點，則另要求沒有應用程式視窗可見，才視為系統面板遮住底下畫面；通知／快速設定展開時暫時收起膠囊，保留未送出草稿、附件與對話，視窗收合後恢復。SystemUI 內容事件使用獨立、合併的訊號；首次讀不到視窗或套件時只有限次延後重讀，服務替換會取消舊讀取，不用空值猜測 SystemUI。可選 MikaPanel 診斷僅記幾何、焦點與固定 owner 類別，不記畫面文字。不同 OEM 若不提供相同視窗資訊仍可能漏判，待實機補驗。
- `OverlayHost` 的尺寸回呼延後至排版完成後合併執行，再向 WindowManager 更新視窗，即使位置沒變也重送尺寸；處理空視窗展開後仍沿用零寬高、卡片偏出螢幕的情況。關閉視窗會撤銷待執行回呼。
- 需要使用者處理的卡片按鈕及回答選項啟用 `MikaButton.wrapLabel`，讓大字體下的「Allow this once」等完整顯示、按鈕高度隨內容增加（最小 48dp），其他按鈕維持原樣。
- 聊天摘要改為「Activity／執行摘要」＋耗時，不再把合併／過濾後的顯示列數稱為已完成步數；詳細時間軸的步數保持原值。
- `ui/MarkdownText.kt` 只在表格超出可見寬度時顯示左右滑動提示，避免價格等右側欄位被誤認為缺失；各語言的提示放在 `strings_markdown.xml`。
- Apporo 的 USB 操作說明補上 App 更新後要重跑目前啟動指令並確認 Ready。舊小幫手仍依原本 `StaleApk` 驗證退出，沒有放寬 APK、簽章、Binder 或口令驗證。
- Apporo 購物提示要求區分組合數量、規格、列表價與優惠條件；未觀察到的數量須明說未知，不能只憑重複型號推定。這是模型指引，仍須以來源核對回答。

- `app/brand.gradle.kts`＋`app/build.gradle.kts` 結尾：flavor 維度 `brand`。`upstream` 就是上游原樣，上游的單元測試、金樣測試、儀器測試都跑在它上面；`woowtech` 是發行用的版本（`assembleWoowtechRelease`）。
- 品牌值只有一個來源：`app/src/woowtech/resources/brand.properties`，由 `core/.../brand/Brand.kt` 讀取。沒有這個檔時，所有值都退回上游原值。
- 介面字串：Gradle 設定時，把 `src/main/res`（英文、繁中）裡提到 Mika 或上游 repo 的字串，自動換成品牌名和本 repo，產生到 `app/.gradle/woowtech-brand-res`（不進 git）。`app/src/woowtech/res` 裡人工寫的 key 不會被覆蓋。上游新增或修改字串，下次建置會自動跟上。上游繁中翻譯的錯字和大陸用語（隻、早上好、重啟、運行、獲取、自定義、應用訪問、退出登入……）在 `app/src/woowtech/res/values-b+zh+Hant/strings_woowtech_wording.xml` 人工覆蓋；瀏覽器寫 Google（跟 `search.url` 一致）、OpenRouter Key 名稱寫 woowtech agent，在 `strings_woowtech.xml`。`BrandStringsTest` 核對每個人工覆蓋的 key 上游還在、佔位符一樣；上游改了原文的意思，同步時要自己看
- 說明文件連結：字串裡指向上游 `docs/<檔名>.md` 的連結，如果 `docs-woowtech/` 有同名檔，就改指 WOOWTECH 自己的版本（目前有 `agent-quickstart`、`mcp` 的繁中與英文版，套件名是 `io.woowtech.agent`）。沒有同名檔的連結照舊指本 repo 的 `docs/`（上游原文）。
- 程式碼依 flavor 分：`app/src/upstream/java` 和 `app/src/woowtech/java` 各放一份同名類別（目前只有授權頁的 `BrandLicenses`），上游版的行為跟上游一模一樣。
- 給模型看的內部文字（工具結果、系統說明）維持「Mika」。人設段（`prompts/system/identity.md`）開頭換成品牌名，並補一段說明：內部說的 Mika 就是它自己，對使用者一律自稱渥屋助理。使用者讀得到的角色輸出（技能草稿、記憶、停下後的總結、App 知識）由 `brand.properties` 的 `prompt.append.roles/*.md` 要求用台灣繁體中文，使用者寫英文時仍用英文；技能草稿的五個小節標題照上游簡體，`SkillDrafter` 靠它們核對格式（`BrandValuesTest` 會檢查）
- 語言：woowtech 版的介面只有英文和繁中（`resourceConfigurations`、`res/xml/locales_config.xml`、`ui.languages` 三處一致）。`resourceConfigurations` 另外留 `zh-rTW`，那是 AndroidX、Material、Play 服務的繁中譯文，不是另一種介面語言，香港、澳門的手機也用它；`zh-rHK` 不收（Compose UI 那份是粵語口語）。系統語言是 zh-TW 時，`state_on`／`state_off` 用 Compose UI 的譯文（已開啟／已關閉），和上游一樣

## 上游檔案的改動（都標了 `WOOWTECH fork` 註解，或在 `Brand.*` 呼叫處）

| 檔案 | 改什麼 | 原因 |
|---|---|---|
| `app/build.gradle.kts` | 結尾一段：`apply(from = "brand.gradle.kts")`，再加 flavor、woowtech 資源目錄、要打包的語言（`en`、`b+zh+Hant`，另加 `zh-rTW` 收 AndroidX／Material／Play 服務的繁中譯文）、選用的簽章、測試開關（套用的腳本看不到 Android 外掛的型別，所以接線放這裡） | 品牌層入口；少了 `zh-rTW`，讀螢幕軟體在繁中介面念英文（Close navigation menu） |
| `.github/workflows/ci.yml` | app 工作只跑 upstream flavor（`testUpstreamDebugUnitTest`、`assembleUpstreamDebug`） | 兩個 flavor 一起編會超過 2 GB 編譯記憶體；woowtech 版由 `woowtech.yml` 建 |
| `core/.../prompt/Prompts.kt` | `read()` 經過 `Brand.prompt()` | 人設改名 |
| `core/.../chatgpt/ChatGptAuth.kt`、`core/.../oauth/OpenRouterAuth.kt` | 給 OpenAI、OpenRouter 看的 App 名稱 | 第三方同意頁顯示正確產品名 |
| `core/.../mcp/McpRpc.kt`、`core/.../cap/mcp/{McpOAuth,HttpMcpClient,LegacySseMcpClient,StdioMcpClient}.kt`、`app/.../settings/McpServerStore.kt` | MCP 伺服器與用戶端的名稱、說明、登入結果頁 | 電腦端和外部 MCP 伺服器看得到 |
| `core/.../mcp/McpTaskTools.kt`、`core/.../remote/{RemoteTasks,RemoteTaskService}.kt`、`app/.../task/RemoteTaskHub.kt` | MCP 工具說明、任務狀態提示（`note`）、錯誤訊息裡的產品名經 `Brand.text`（含 CLI 任務 API 原樣交出的「要在手機上處理」，以及任務開不起來的原因）；任務內容（使用者的話、模型的回答）不動 | 外部 AI 會照這些字稱呼 App |
| `tools/mika/scripts/mika_cli.py`、`tools/mika/SKILL.md` | CLI 經 ADB 先找 `io.woowtech.agent`，沒有才用上游套件名（`MIKA_ANDROID_PACKAGE` 可指定）；ADB 認不出套件時（`--url`、自訂套件）看手機回報的 `server_version`，結尾是 `-woow.<N>` 就是品牌版；手機回應前（例如 `--url` 連不上）和 `--help` 都稱 woowtech agent，認出上游 Mika 才稱 Mika；Skill 說明補一段品牌版說明 | 電腦端 CLI 用 USB 才連得到品牌版；Wi-Fi、VPN、遠端閘道的錯誤訊息也要寫對名字 |
| `.github/ISSUE_TEMPLATE/device-report.yml` | 改成繁中＋英文、品牌名；檔名和欄位 id 不變 | App 的「去 GitHub 回報」開這個範本 |
| `.github/CONTRIBUTING.md`、`.github/CONTRIBUTING.zh-CN.md` | 開頭加一段 WOOWTECH 說明，下面保留上游原文 | 回報管道換成本 repo；上游文件連到這兩份的錨點不能壞 |
| `core/.../shell/HelperHandoff.kt`、`core/.../mcp/McpUsb.kt` | USB 腳本印給使用者的訊息 | 使用者看得到 |
| `core/.../selfcheck/SelfCheckReport.kt`、`app/.../about/Diagnostics.kt` | 自檢報告、診斷資訊的標題與內文 | 使用者會貼到 issue |
| `core/.../agent/StopRules.kt` | 「模型不支援工具」的提示 | 使用者看得到 |
| `app/.../about/MikaLinks.kt` | repo、Releases、issue、更新 API 改讀 `Brand` | 更新來源與回報管道換成本 repo |
| `app/.../MikaApp.kt`、`app/.../about/UpdateChecker.kt`、`app/.../about/ApkUpdater.kt` | User-Agent、下載通知標題 | 第三方與使用者看得到 |
| `app/.../ui/{ChatCopy,ChatDrawer,AboutScreen}.kt`、`app/.../task/TaskService.kt`、`app/.../capsule/{CapsuleContent,CapsuleCardModel,CapsuleCardContent}.kt` | 寫死的「Mika」改用 `R.string.app_name` | 介面標題、通知、膠囊 |
| `app/.../cap/sandbox/ShareExporter.kt` | 匯出資料夾 `Download/woowtech agent/` | 使用者看得到 |
| `app/.../cap/phone/shell/adb/AndroidAdb.kt` | ADB 金鑰名稱 `woowtech-agent@<機型>` | 顯示在「無線偵錯 › 已配對的裝置」 |
| `app/.../ui/theme/Colors.kt` | accent 改讀品牌色（淺色 `#4069FB`、深色 `#6183FC`） | 品牌色；白字對比 4.53:1 |
| `app/.../browser/AddressInput.kt` | 預設搜尋改 Google | 台灣使用習慣 |
| `app/.../ui/SettingsSubPages.kt` | 語言清單只列品牌支援的語言 | 跟出貨語言一致 |
| `app/.../ui/LicensesScreen.kt` | 第三方清單經 `BrandLicenses`（依 flavor 各一份） | woowtech 版列出上游 Mika 署名、補 ML Kit，並跟著介面語言顯示英文或繁中（上游寫死簡體中文） |
| `core/.../gate/IrreversibleDetector.kt`（台灣用語）、`core/.../uistate/Hant.kt` | 付款關卡認台灣的結帳用語（匯款、下訂單、送出訂單、確認訂單、確認送出、加值、超商代碼、ATM轉帳、取貨付款等），繁簡對照補「紀匯簽遊」 | 台灣 App 和網站的付款、下單要先問（6f650f7f，woow.1 起） |
| `app/.../ui/RelaySection.kt`、`app/src/main/res/values/strings_relay.xml` | 遠端閘道位址的示例改成不翻譯的字串 `relay_gateway_hint`（上游的值不變），woowtech 版覆蓋成 `https://gateway.example.com` | 品牌版畫面上不出現 mika |
| `core/.../memory/SensitiveFilter.kt`、`core/src/test/.../memory/SensitiveFilterTest.kt` | 敏感關鍵詞也認繁體：密碼、驗證碼、校驗碼、動態碼、安全碼、安全問題，以及「為」「用戶的／使用者的」 | 繁體寫的記憶、技能草稿、App 知識也要攔住密碼；這是上游的漏洞，可以回報上游 |
| `app/.../ui/RunTimelineViewModel.kt`、`app/.../ui/ChatViewModel.kt`（`where` 改成 internal） | 運行過程頁的步驟對象改用對話步驟同一套說法：「网站 域名」只留域名，命令只留命令 | 每個網頁步驟都寫「開啟網頁 · 网站 127.0.0.1」 |
| `app/.../ui/ChatViewModel.kt`（`noteText`）、`app/src/main/res/values*/strings_memory.xml`（`memory_note_*`） | 回答下方的記憶小字改用字串資源；簡體逐字同 core 的 `MemoryNote.text` | 上游直接用 core 寫死的簡體「记住了:…」（K2） |
| `core/.../model/{ModelError,ModelAccessErrors,ModelHttp,OpenAiCompatModel,AnthropicModel,ResponsesModel}.kt` | `BadResponse` 多帶 HTTP 狀態碼和服務端原話（`BadResponse.http`、串流錯誤幀），`message` 不變；`detail`／`jsonDetail` 拆開閘道（LiteLLM）包在原話裡的 JSON；新增 `shownDetail` | 介面只引原話，不貼整段報文 |
| `app/.../ui/ModelErrorCopy.kt`（新）、`app/.../ui/ModelSetupViewModel.kt`、`app/.../ui/VoiceHold.kt`、`app/src/main/res/values*/strings_setup.xml`（`model_error_*`、`list_error_*`） | 模型設定頁（測試並儲存、選模型、重新測試、試轉語音）和語音輸入的錯誤原因跟著介面語言；簡體逐字同 core | 英文介面也顯示「模型返回了无法解析的内容: HTTP 400 {…}」 |
| `core/.../brand/Brand.kt`、`app/src/woowtech/resources/brand.properties`、`app/.../about/Diagnostics.kt`、`core/.../selfcheck/SelfCheckReport.kt` | 新品牌值 `diagnostics.header`、`issue.title.prefix`（沒設時同上游）：woowtech 診斷資訊抬頭「渥屋助理診斷資訊 / woowtech agent diagnostics」、自檢回報標題前綴「[相容性]」 | 簡體的「诊断信息」（K3）、「[兼容性]」（K8） |
| `.github/ISSUE_TEMPLATE/device-report.yml` | title 改成「[相容性] 」，要和 `issue.title.prefix` 一致（檔頭註解有寫） | App 預填的標題和範本一致（K8） |
| 13 個工具的宣告：`core/.../general/{ViewPastScreens,ViewUserScreen,MemoryTools,ProfileEdit,HistoryRead,ScheduleTask,SpawnAgent}.kt`、`core/.../cap/phone/OpenLink.kt`、`core/.../cap/web/{WebScriptTool,Interact}.kt`、`core/.../uistate/tools/VisionTools.kt`；`app/src/main/res/values*/strings_tools.xml` | 補上 `label`（上游沒有），10 個語系都有譯文 | 運行過程、步驟露出 phone_find_visually、web_script 等工具名 |
| `app/.../ui/ChatViewModel.kt`（`ToolLabels`）、`app/.../ui/SourceViewModel.kt`、`app/src/main/res/values*/strings_chat.xml`（`source_command`） | `do_steps` 有說法；新增 `ToolLabels.shared`、`place()`、`command()`：命令這類地方（`run_command「…」`、`root_run_command`、`search_files`、`run_bundled_script`）的工具名，在來源標籤換成說法，在步驟對象只留命令 | 「do_steps · …」「來源 · run_command「…」」 |
| `app/.../task/TaskService.kt`（`describe`） | 進行中通知的步驟說明，工具名換成工具的說法 | 「第 2 步:phone_set_alarm」 |
| `app/.../i18n/AppLanguage.kt`、`app/.../MikaApp.kt`（新增 `onConfigurationChanged`） | 安卓 13 起，啟動、程序設定變更、App 內換語言時，把程序的預設語言設回 App 語言（跟隨系統時不動） | 無障礙服務連上後，系統把程序設定換回系統語言（AOSP `WindowProcessController.onServiceStarted`），排版按 en-US，繁中全形標點靠左下 |
| `app/.../task/TaskService.kt`、`app/.../confirm/ConfirmationNotifier.kt` | 通知上的字（接管標題、提問、各按鈕、Reply、確認通知的按鈕和鎖屏提示）和「回答太晚」Toast 改用 `tr()`；測試 `NotificationTextsTest` 確保發通知的程式不用 `getString` 取介面文字 | 服務的 `getString` 可能是系統語言：App 選繁中、系統是英文時，通知寫成〔Needs you: Payment〕〔Reply〕（上游問題） |
| `core/.../agent/UserExchange.kt`、`core/src/main/resources/prompts/feedback/loop.md`、`app/.../ui/RunTimelineViewModel.kt` | 不在手機上發起的任務（電腦交辦）申報同意時，自動拒絕改用自己的錯誤碼 `confirmation_remote`、給模型的說明（新鍵 `confirmation_remote`）、執行過程的標籤和出錯說明；同一任務再申報也一樣 | 原本和使用者拒絕共用 `confirmation_declined`：執行過程寫〔要你同意〕〔出錯:你沒有同意〕，回答說「你未核准」，其實沒有人被問過（上游問題） |
| `app/.../task/TaskRun.kt`、`app/.../task/TaskService.kt` | 電腦端取消它交辦的任務時記下（`cancel(fromComputer = true)`、`stoppedFromComputer`），結果通知寫〔電腦端停止了這個任務〕；手機上先按停止的照舊 | 原本寫〔你停止了這個任務〕（上游問題） |
| `app/.../cap/phone/setup/{PairingNotifier,PairingCoordinator}.kt`、`app/.../ui/PhoneSetupScreen.kt` | 填碼通知被系統丟掉（沒允許通知、配對頻道關著）時記下；通知變得發得出去時補發一次 | 引導頁到配對一步才請使用者允許通知，先發的填碼通知被丟掉、之後不會補發；「跳過無障礙」時找不到填碼的地方（上游問題） |
| `app/.../task/TaskService.kt`、`app/.../task/TriggerRuntime.kt` | 結果、進度、提問／接管、提醒通知的文字經 `notificationText()` 去掉 Markdown（沿用 `MarkdownModel.toPlainText`，表格格子用「 · 」隔開） | 通知不渲染 Markdown，原本露出 `**`、`#`、反引號和表格直線（上游問題） |
| `app/.../task/TriggerRuntime.kt` | 定時任務自己的通知（到點提醒、沒能開始、結果待確認）和準時鬧鐘引導放進結果組 `com.wangzan101.mika.results`（有摘要）；拿掉 woow.2 沒有摘要的 `com.wangzan101.mika.schedule` 組；提醒照樣標 `CATEGORY_REMINDER` | woow.2 的提醒有響、有跳出，約 3 秒後系統把它併進 `g:Aggregate_AlertingSection`、標成 SILENT，橫幅提早收掉（s10-lang 18-notif-full-4／8）（上游問題；取代原本 `com.wangzan101.mika.schedule` 那一列） |
| `app/src/main/res/values*/strings_timeline.xml`、`app/src/main/res/values*/strings_task.xml`（10 種語言） | 新字串 `tag_remote_declined`、`err_confirm_remote`、`task_stopped_remote_body`（英文檔裡標了 WOOWTECH fork 註解） | 上面第 2、3 列用到；繁中為「從電腦交辦的任務不能付款或下單」「不能從電腦付款」「電腦端停止了這個任務」 |
| `app/src/test/.../i18n/NotificationTextsTest.kt`、`app/src/test/.../task/TaskNotificationCopyTest.kt`（新增） | 確保發通知的程式不用 `getString`；電腦端停止的說法、通知去 Markdown | 守著上面幾項；既有的 AgentLoopGateTest、RunTimelineViewModelTest、PairingNoticeTest 補了案例，金樣 `feedback-loop.txt`、`sizes.txt` 一併更新 |
| `core/.../gate/IrreversibleDetector.kt` | 付款方式介紹（「支持／支援…付款」）先整句去掉：可跨空格，到最後一個付款／支付為止，遇到句讀或「立即、確認」一類動作字就停；輸入框同一行、緊挨著它的通用確認（價格區間、跳頁）只算套用框裡的值，不按下單判（框是密碼框、或那一行寫著金額時照舊）；網頁上有應付金額、又有付款／下單／提交按鍵時，輸入欄裡按 Enter 按點那個按鍵判；新增 `tapActions`（這個畫面點得到的不可逆動作） | 11/07 模擬器實測：momo 價格區間的「確認」被當成下單擋下；測試商店商品頁「支援 LINE Pay、街口支付付款」會被當成付款；P8 在優惠碼欄按 Enter 會不經同意就下單 |
| `core/.../gate/ConfirmationGate.kt` | `declare` 先拿關卡自己的判定核對申報：剛在同一個 App 被擋下的那一步是付款，或（沒被擋過時）申報當下這個畫面點得到的不可逆動作有付款、沒有申報的那一種，就回 `Unsupported`，模型收到 `payment_requires_takeover` 改交給使用者；新增 `noteRefused`，打字以外的寫操作和 `reset` 會清掉 | P5（立即加值）、P10（選 ATM轉帳）模型把付款申報成提交、下單，出了按了也沒用的〔允許這一次〕 |
| `core/.../action/ConfirmDecision.kt` | 因為沒有可用的同意而擋下的一步（單步、do_steps、網頁腳本都算）交給關卡記著 | 同上；P10 是在 do_steps 裡被擋 |
| `core/.../general/RequestConfirmation.kt`、`core/.../tool/Tools.kt`（`Outcome.Confirm.screenActions`）、`core/.../agent/UserExchange.kt` | 申報同意時帶上這個畫面點得到的不可逆動作，交給 `ConfirmationGate.declare` 判 | 同上；P5 是沒先點就申報 |
| `core/src/test/.../gate/{IrreversibleDetectorTest,ConfirmationGateTest,AgentLoopGateTest}.kt` | 只新增測試，沒改原有斷言 | 守住上面三項關卡修正 |
| `app/.../ui/ChatViewModel.kt`、`app/.../ui/AgentPip.kt` | 開始等你處理時小畫面不自動展開，展開著的也收起（上游是接管一開始就展開）；等你處理時從下方的角挪到同側上方，回到執行時挪回原來的角（使用者拖過就不再挪） | 小畫面蓋住同意卡、接手卡的按鈕；展開時連遮罩一起蓋住〔跳過〕〔我來處理〕〔取消任務〕（2026-11-07 模擬器測試問題 5） |
| `app/.../ui/ChatScreen.kt`（提問卡）、`app/.../task/TaskService.kt`（提問通知的按鈕） | 有選項的〔需要你回答〕卡最下面加〔取消任務〕小字（和接管卡一樣）；提問通知改成「回覆」＋第一個選項＋〔取消任務〕，其餘選項在「回覆」的快捷選項裡 | 有選項時卡片和通知都取消不了任務（問題 6） |
| `app/.../ui/{MessageMenu,McpScreen,SelfCheckScreen,DiagnosticsSheet,AccountSignIn,PhoneSetupScreen,RunMetricsUi,BrowserScreen}.kt` | 複製一律改走新增的 `app/.../ui/ClipboardCopy.kt` 的 `copyToClipboard()`：安卓 13 起不再跳「已複製」Toast，複製失敗的提示照舊 | 系統自己有剪貼簿浮層，Toast 疊在上面、字被蓋住（小問題表） |
| `app/.../ui/ModelSetupViewModel.kt`、`app/.../ui/ModelSetupScreen.kt`（`ModelSetupCopy.refusal`）、`app/src/main/res/values*/strings_setup.xml`（新 key `model_reason_refused`，10 種語言） | 「測試並儲存」試呼叫遇到服務商拒絕（HTTP 4xx、認不出原因）或額度用完，和 5xx 一樣接著試下一個；都不通過時照舊不存，另外列出試了哪些、自動展開模型名一欄；錯誤只留服務商那一句話的摘要（例：HTTP 400: Your credit balance is too low…） | 閘道（LiteLLM）第一條線路沒額度就整個失敗，錯誤顯示截斷的原始 JSON（小問題表、S2） |
| `app/src/test/.../ui/{ChatViewModelTest,ModelSetupViewModelTest,ModelSetupNetworkTest}.kt`、`app/src/androidTest/.../ui/ChatScreenDeviceTest.kt` | 上游的 `pipAutoExpandsWhenNeedsUser` 改寫成 `pipStaysCollapsedWhileItNeedsYou`；真機測試接管時不再先收起小窗；新增閘道線路被拒、額度用完、全部被拒、錯誤摘要的測試 | 跟著上面的行為改動；同步上游時這幾處要對照 |
| `app/.../task/AlertGroup.kt`（新） | 會響鈴、跳出的通知放進 App 自己的通知組，組裡一定有摘要：先發通知，再發（或更新）摘要；摘要和它同一個頻道、用 `GROUP_ALERT_CHILDREN`，從不響、不跳出；一組只放一條的組撤通知時連摘要一起撤，摘要也跟著那一條的自動消失時間；結果組的摘要交給系統（最後一則被滑掉或點開時一起撤） | 安卓 16 把同一區段裡 App 沒分組的通知（滿 2 則，`config_autoGroupAtCount`）疊進系統的 `g:Aggregate_AlertingSection` 並加上 `FLAG_SILENT`（16 正式版）；分了組卻沒有摘要的，發出 3 秒後被強制併組、加 `FLAG_SILENT`（16 QPR1、17 仍會）。有摘要的組不會被併，除非同一區段有 6 個以上只有 1～2 則的組（這裡最多 5 組）（上游問題） |
| `app/.../task/TaskService.kt`（`refreshNotifications`、`attentionNotification`、任務結束時撤通知、`notifyDelivery`）、`app/.../confirm/ConfirmationNotifier.kt`（`build` 多一個 `group` 參數，不給時照上游） | 接管、提問、要你同意的通知每個任務一組（`com.wangzan101.mika.attention.<槽位>`），和摘要一起發、一起撤；懸浮膠囊顯示時改在組裡用 `GROUP_ALERT_SUMMARY` 靜音，不再用沒有摘要的 `com.wangzan101.mika.quiet` 組；結果、提示放進 `com.wangzan101.mika.results`；`setOnlyAlertOnce` 照舊 | 11/07 模擬器：App 在背景時〔要你同意〕通知 flags=`ONLY_ALERT_ONCE\|SILENT`（originalFlags 沒有 SILENT）、groupKey 是 `g:Aggregate_AlertingSection`，不響也不跳出；只要通知欄裡還有上一則〔任務完成〕就會這樣（上游問題） |
| `app/.../cap/phone/setup/PairingNotifier.kt` | 配對通知每一則都放進 `com.wangzan101.mika.pairing`（有摘要，摘要跟著填碼通知 10 分鐘、配對成功 8 秒自動消失），`cancel` 連摘要一起撤；靜靜備好的填碼通知改在組裡用 `GROUP_ALERT_SUMMARY` 靜音，拿掉 `pairing_quiet` 組 | 通知欄裡還有別的渥屋助理通知時，填碼通知同樣會被併組、靜音，配對視窗上方不跳出來（同上機制推得，沒實測） |
| `app/src/test/.../task/AlertGroupTest.kt`（新） | 組的提醒方式、各組名稱不重複、只有一組一條的摘要跟著自動消失、組數低於系統的 6 組門檻；掃原始碼確認「需要你」和結果頻道只在 TaskService、TriggerRuntime 建通知，TaskService、TriggerRuntime、PairingNotifier 裡直接 notify／cancel 的只剩進度和留頁通知 | 同步上游時這幾行容易被改回直接 `nm.notify` |
| `app/.../cap/phone/shell/HelperProcess.kt`（`onAppDied`、新 `checkApp`、`signedAsPinned` 拆出 `pinState`）、`core/.../shell/HelperAppCheck.kt`（新） | App 程序結束後（死亡通知之後、重新交接之前），手機操作小幫手當下查一次，再隔 1、2、4、8 秒、之後每 10 秒查一次套件還是不是啟動時那個 App（uid 和簽章憑證都對上）；確定已解除安裝，或同名套件換成別的 App（uid 或憑證不同），就撤掉改動結束；查不清時照舊等；App 連著時不查 | 解除安裝時系統先結束 App、隨後才刪套件，小幫手只在死亡通知當下查一次、之後不再查，會一直跑到手機重開機（2026-11-07 模擬器實測 S10C-07；上游問題） |
| `app/.../cap/phone/shell/HelperProcess.kt`（`maybeRestore`） | 拉起 App 之前先核對套件的 uid 和簽章憑證，對不上就結束，不寫回無障礙服務 | 原本先寫 `enabled_accessibility_services`、交接時才核對：App 解除安裝後 8 秒內裝上同名的別的 App，系統可能替那個 App 綁定同名的無障礙服務（上游問題） |
| `core/src/test/.../shell/HelperAppCheckTest.kt`（新增） | 判定（同一個、不在、換了人、查不清）和複查間隔；不管 App 死後多久才被解除安裝，10 秒內都會查到 | 守住上面兩列 |
| `core/.../record/RunEvent.kt`（`Confirmation.step`）、`core/.../action/{ActionRecorder,ActionExecutor}.kt`、`core/.../agent/UserExchange.kt`、`app/.../ui/RunTimelineViewModel.kt` | 確認事件多記 `step`：申報同意、或被確認關卡擋下的那一次呼叫所在的一步（經驗回放是 0；舊紀錄沒有）。執行過程按它把〔要你同意〕〔你沒同意〕〔你同意了〕〔從電腦交辦的任務不能付款或下單〕掛在那一步，那一步還沒有別的紀錄（還在等你回答）時先開出這一行；沒有 `step` 的舊紀錄照舊掛在前一步 | 那一步的回覆和結果要等執行完（問完人）才記，確認事件排在它們前面，原本被掛到前一步：P8 填好優惠碼的第 9 步同時標綠色「生效」和〔你沒同意〕，看起來像被拒絕的下單生效了；電腦交辦被擋、do_steps 第一個動作就被擋也一樣（woow.3 問題 4，上游問題） |
| `core/src/test/.../action/ActionExecutorOriginsTest.kt`、`core/src/test/.../gate/AgentLoopGateTest.kt`、`app/src/test/.../ui/RunTimelineViewModelTest.kt` | 上游的 `paymentIsRefusedTheSameWay` 預期的確認事件多帶 `step`（＝來源的步號）；woow.2 的 `remoteRefusalIsNotShownAsTheUsersDecision` 改成標籤在申報那一步；新增確認事件帶步號（等你回答時就有）、標籤掛在申報或被擋的那一步、等你回答時先開出那一行、舊紀錄照舊的測試 | 守著上一列；同步上游時這幾處要對照 |
| `core/.../gate/ConfirmationGate.kt` | `permits` 核對動作種類時，下單和提交互相放得過（新增 `covers`）：同意下單也放行結帳頁的提交鍵（「確認送出」），同意提交也放行下單鍵（「送出訂單」）；App、對象、金額照樣核對（兩種互換時金額一律要核），也只放行緊接著的一次；付款照舊永遠不放行，發送、刪除、其他仍要同一種；拒絕、電腦交辦、無人在場的路徑不變 | 11/07 模擬器實測 P1：同意「下單」後點「確認送出」被擋成「和你同意的內容對不上」，要再同意一次「提交」才送出（woow.2 已知問題：結帳有時要同意兩次） |
| `core/src/test/.../gate/{ConfirmationGateTest,AgentLoopGateTest}.kt` | 新增下單↔提交互相放行、只放行一次、對象／金額／App 對不上不放行、付款不放行的測試；原有斷言沒改，`lighterDeclarationOfAPaymentGoesToTakeover` 只改一行註解 | 守住上面一項 |
| `app/.../confirm/ConfirmationNotifier.kt`（新增 `ConfirmationCopy.notificationTitle`、`notificationBody`、`TITLE_AMOUNT_MAX`；`fields` 多一個預設 false 的 `amountFirst`；`build` 的可見版本改用它們）、`app/src/main/res/values*/strings_confirm.xml`（新 key `confirm_title_amount`，10 種語言，各自接在自己的 `confirm_title` 後面） | 〔要你同意〕通知的標題有金額時帶上金額（「要你同意:下單 NT$590」，金額超過 30 字截斷加「…」），收起的一行（橫幅、折疊的通知）金額排最前（「金額:NT$590 · 在 … · 目標:… · 內容:…」），其餘欄位順序不變，沒有金額時和原來一樣；金額照模型寫的字當純文字清理（`plain()`）。鎖屏的公開版本、展開的大字（`detail`）、App 內的確認卡、進度通知（仍用 `body()`）、〔同意〕〔不同意〕按鈕和關卡都不動 | 11/07 模擬器（woow.3 複測）：橫幅只露出「在 127.0.0.1 · 目標:… · 內容:渥…」，金額被截掉，橫幅上的〔同意〕卻一點就生效（上游問題） |
| `app/src/test/.../confirm/ConfirmationNotificationCopyTest.kt`（新增）、`app/src/androidTest/.../confirm/ConfirmationDeviceTest.kt` | 新測試：金額排最前、沒有金額照舊、長金額截斷（不劈代理對、省略號前不留空格）、金額裡的分隔符和冒號清理、繁中／英文讀法、10 種語言的 `confirm_title_amount`（佔位符與來源）、鎖屏公開版本仍不帶金額（讀原始碼確認）；真機測試的標題、收起的一行斷言跟著改，並加上公開版本的標題沒有金額 | 守著上一列；上游的 `ConfirmationCopyTest` 沒動（案例都沒有金額、`body()` 沒變）；同步上游時 `ConfirmationDeviceTest` 要對照 |
| `app/src/woowtech/AndroidManifest.xml`（新） | woowtech flavor 多宣告 `USE_EXACT_ALARM`（Android 13 起的一般權限，安裝即授權、使用者撤不掉），並把 `src/main` 的 `SCHEDULE_EXACT_ALARM` 在這個 flavor 限到 `maxSdkVersion="32"`（同名元素合併，只多一個屬性；留給沒有 `USE_EXACT_ALARM` 的 Android 12／12L，裝好就有）。`src/main` 清單沒動，upstream flavor 沒有自己的清單，合併結果跟上游一模一樣 | 沒有權限時 `canScheduleExactAlarms()` 是 false（Android 14 起新裝的 App 預設拒絕 `SCHEDULE_EXACT_ALARM`），`TriggerRuntime.arm` 只能用 `setAndAllowWhileIdle`，系統可把鬧鐘最多延後剩餘等待的 3/4、上限一小時：「一分鐘後」的提醒晚約 42 秒（woow.3 模擬器 N2-a/b）；不精確鬧鐘的廣播也沒有「背景啟動前景服務」的豁免，定時任務可能起不來（AOSP 讀碼推得，未實測）。AOSP 文件要求兩個權限一台裝置只要一個，所以 `SCHEDULE_EXACT_ALARM` 加上限。**只發 APK、不上 Google Play**：Play 政策只准鬧鐘、計時器、日曆類 App 宣告 `USE_EXACT_ALARM`；日後要上 Play，先刪掉這個檔案，回到使用者授權流程（`ExactAlarmGuide`、定時任務頁的提示） |
| `woowtech/tools/brand-check.sh`（`apk` 模式） | 用 `aapt2 dump permissions` 檢查 woowtech APK：`USE_EXACT_ALARM` 要有、且不能帶 `maxSdkVersion`；`SCHEDULE_EXACT_ALARM` 要帶 `maxSdkVersion='32'` | 系統會略過超過 `maxSdkVersion` 的權限，少了任一行，Android 14 起的提醒又會不準時；發佈步驟 3 本來就對兩個 release APK 跑這支，`woowtech.yml` 不用改 |
| `core/src/test/.../brand/WoowtechManifestTest.kt`（新增） | 讀 `app/src/woowtech/AndroidManifest.xml` 和 `app/src/main/AndroidManifest.xml`：woowtech 清單有 `USE_EXACT_ALARM`（無上限）、`SCHEDULE_EXACT_ALARM` 限 32、沒有別的權限和 `package`；main 清單仍是無上限的 `SCHEDULE_EXACT_ALARM`、沒有 `USE_EXACT_ALARM`；`app/src/upstream` 沒有自己的清單 | 守住上面兩列，不讓 upstream flavor 被連帶改到；上游的 `ManifestProvidersTest` 只讀 provider、service、activity、feature，不讀權限，不受影響 |
| `app/.../task/ChannelNames.kt`（新）、`app/.../MikaApp.kt`（`onCreate`、`onConfigurationChanged`）、`app/.../i18n/AppLanguage.kt`（`set` 兩個分支）、`app/.../cap/sandbox/SandboxForeground.kt`（`CHANNEL` 改 `internal`、新增 `CHANNEL_NAME`，建頻道也改用它） | App 啟動、系統語言變更、App 內換語言時，把系統裡已經存在的「配對」「背景準備」頻道（`pairing_code`、`pairing_alert`、`runtime_prepare`）和任務的三個頻道（`task_progress`、`task_result_v2`、`task_attention`）改成當下語言的名字：取出頻道、只改名字、原樣交回 `createNotificationChannel`（官方：已存在的頻道會更新名字與說明，分組只在原本沒有時設，重要程度只會調低、而且只在使用者沒動過設定時，其餘忽略）；不建不存在的頻道，不動重要程度、聲音、振動與使用者的設定；名字已經對了就只讀不寫；`TaskService` 新增 `channelNames()`（任務三個頻道的名字只在這一處定），`ensureChannels` 和這支都用它；建頻道的地方和重要程度照舊 | 安卓在建頻道時存下名字、換語言不會跟著換。這兩個頻道是用到才建的、建好後沒人再碰，繁中介面下系統〔應用程式通知〕頁出現「Pairing」「Background setup」，任務的三個頻道只在起任務、定時任務、電腦接入時才重建，換語言後到下次起任務前也是舊語言（woow.3 複測 s12-notify 的 dumpsys；上游問題）。安卓 12 以前語言只記在本機、系統不會通知；安卓 13 起程序裡有無障碍服務時，系統也不會為 App 語言變更通知程序（`WindowProcessController.onServiceStarted`），所以 `AppLanguage.set` 要自己呼叫 |
| `app/src/test/.../task/ChannelNamesTest.kt`（新增） | 判斷（只改存在且名字不同的、不建頻道、別的頻道不碰、空名字不用、按文字比）、名字跟著語言（英文、簡中、繁中）、原始碼檢查（建頻道的只有原來三處、`ChannelNames.kt` 不碰頻道設定、`MikaApp`／`AppLanguage` 的四個呼叫點都在） | 守住上一列；同步上游時呼叫點容易被改掉 |
| `NOTICE` | 加 WOOWTECH 段落 | Apache-2.0 §4(d) |

新增的檔案：`core/.../brand/Brand.kt`、`core/src/test/.../brand/BrandValuesTest.kt`、`app/brand.gradle.kts`、`app/src/woowtech/**`（含 `java/.../woowtech/BrandLicenses.kt`、`res/values*/strings_woowtech_licenses.xml`）、`app/src/upstream/java/.../woowtech/BrandLicenses.kt`、`tools/mika/tests/test_woowtech_package.py`、`core/src/test/.../brand/BrandStringsTest.kt`、`app/src/woowtech/res/values-b+zh+Hant/strings_woowtech_wording.xml`、`app/.../ui/ModelErrorCopy.kt`（＋`ModelErrorCopyTest.kt`）、`app/.../ui/ClipboardCopy.kt`（＋`ClipboardCopyTest.kt`）、`app/src/test/.../task/{ProgressNoteTest,TaskNotificationCopyTest}.kt`、`app/src/test/.../i18n/NotificationTextsTest.kt`、`app/.../task/AlertGroup.kt`（＋`AlertGroupTest.kt`）、`core/.../shell/HelperAppCheck.kt`（＋`HelperAppCheckTest.kt`）、`.github/README.md`（repo 首頁）、`.github/workflows/woowtech.yml`、`docs-woowtech/**`、`woowtech/tools/**`、`app/src/woowtech/AndroidManifest.xml`（woowtech flavor 的清單）、`core/src/test/.../brand/WoowtechManifestTest.kt`、`app/.../task/ChannelNames.kt`（＋`ChannelNamesTest.kt`）、`app/src/test/.../confirm/ConfirmationNotificationCopyTest.kt`。

## 刻意不改的

- Kotlin package、類別名稱、Keystore alias、SharedPreferences 名稱、虛擬螢幕名稱、OTel 屬性：使用者看不到，改了只會增加同步衝突。
- 沙盒裡的 `mika` 指令、MCP 工具名（`mika_run_task` 等）、relay 協定識別字：屬於介面，改了電腦端工具會壞。
- 根目錄 `README.md`、`docs/`：上游原文，上游測試會檢查它們。WOOWTECH 的說明放 `.github/README.md` 和 `docs-woowtech/`。
- 高風險功能（存 PIN 遠端解鎖、root、xAI 帳號登入、自主模式）：owner 2026-11-06 決定保留。

## 已知缺口（之後處理）

- 電腦端的本機任務面板（`mika ui`，`tools/mika/scripts/mika_desk/`）介面仍寫 Mika、用上游圖示；連線已會找到品牌版。
- `docs/` 裡其他上游文件（安裝、模型、常見問題等）沒有 WOOWTECH 版；App 內只連到已有 WOOWTECH 版的兩份。
- `tools/mika/tests/phone_task_recovery.py`（真機手動測試腳本，不在 CI 裡）仍寫死上游套件名。
- 聊天裡任務失敗的原因（core `StopRules.userReason`）仍是寫死的簡體；要先在 core 加結構化的失敗代碼，App 才能翻譯。
- 付款關卡：用 `phone_*` 操作 Chrome 結帳頁時按 Enter 還沒涵蓋（這版只涵蓋內建瀏覽器 `web_*`）；申報被改判成付款時，要模型自己呼叫 `hand_to_user(reason=payment)` 才會出接手卡。
- 無障礙服務連上後，服務與浮層的 Resources 仍可能是系統語言（服務內的 `getString`、浮層的 `stringResource`）；這版已把程序預設語言設回 App 語言。
- 診斷資訊會寫出自訂服務商的完整主機名；自主模式一點就開、沒有確認（owner 決定保留功能）。
- 繁中用詞還沒整批統一：重置、禁用、這臺／這台、半形標點。
- 進度通知（通知欄靜音區那條，只有〔停止〕鈕）的收合那行還是舊順序，金額在最後；只有〔要你同意〕通知改成金額在最前（`body()` 留給進度通知用，上游測試斷言兩者相等）。
- 要你同意通知的標題在窄螢幕上可能把尾端的金額截在「NT$5…」附近（英文、西文等前綴較長的語言更容易）；收合那行金額在最前面，不受影響。
- 宣告 `USE_EXACT_ALARM` 的前提是只發 APK、不上 Google Play；日後要上 Play，必須刪掉 `app/src/woowtech/AndroidManifest.xml` 並回到使用者授權流程。
- 通知冷卻（Android 15 起，16 預設開著）：同一個 App 短時間內連續提醒會被系統降低音量或靜音，這是系統設定，App 管不到。
- 同意時把「下單」和「提交」算同一類（`ConfirmationGate.covers`，woow.3）；拒絕仍按種類記，所以拒絕「下單」後改申報「提交」會再問一次。上游 `docs/dev/architecture.md` 仍寫「同類動作」。

## 發佈

1. 要發的內容都已合進 `main`，`main` 上的 CI（`ci.yml`、`woowtech.yml`）全綠。
2. 在 `main` 上手動跑 `woowtech.yml`（`gh workflow run woowtech.yml --ref main`）。同一次會建 APK（`woowtech APK`），也會做 GPL 原始碼包（`GPL sources tarball`，只有手動執行才跑）。
3. 下載這次的產物，核對 `SHA256SUMS.txt`，再用 `woowtech/tools/brand-check.sh apk` 檢查兩個 release APK。
4. 在發佈機上用 apksigner 簽章（APK Signature Scheme v3），金鑰不進 repo、不進 CI。簽章憑證的 SHA-256 必須是 `806b3db808ecbb4d2d032b34624baa7e193802f17a07afbde2a03e78da9474c8`。檔名：`woowtech-agent-v<版本>-arm64.apk`（arm64 專用）、`woowtech-agent-v<版本>.apk`（通用）。App 的檢查更新靠 `-arm64.apk` 結尾挑檔，檔名格式不能改。
5. 建 GitHub Release 草稿：tag `v<版本>` 指向步驟 2 的 commit，附上兩個 APK、`mika-<版本>-gpl-sources.tar.gz`、`SHA256SUMS.txt`。核對每個附件的大小和 SHA-256 後再公開。不要標成 prerelease：App 只看 `releases/latest`。
6. 在下面的發佈紀錄寫一行。下一次在同一個上游版本上再發，要先把 `app/brand.gradle.kts` 的 `woowtechRevision` 加 1；同步到新的上游版本後，改回 1。

| 版本 | 日期 | commit | 說明 |
|---|---|---|---|
| `v0.1.37-woow.1` | 2026-11-06 | `b8f79503` | 第一版：品牌層、拿掉中國系服務、台灣知識、電腦端連線說明、授權頁繁中／英文 |
| `v0.1.37-woow.2` | 2026-11-07 | `7b8f3e54` | 修 11/07 模擬器實測找到的問題（品牌與繁中字串、寫死的簡體字、通知與電腦端用詞、付款關卡、對話介面；PR #5）。補測 46 個案例全過，「允許這一次」只送出一次；已知問題記在發佈說明，排 woow.3 |
| `v0.1.37-woow.3` | 2026-11-07 | `8e35a305` | 修 woow.2 的五項已知問題（通知被系統靜音、提醒被靜音、解除安裝後小幫手還在跑、被拒絕步驟標「生效」、結帳要同意兩次；PR #7）。模擬器實測 40 項通過，每項經獨立核對；付款仍只能接手。沒測到：App 死很久才解除安裝、助手由 App 自己配對啟動、換簽章蓋掉、ATM 同意一次。GPL 原始碼包那一步第一次因 samba.org 暫時連不上失敗，重跑成功 |

## 跟上游同步

1. 每週一次：`git fetch upstream --tags`，看這週的上游 tag。
2. 先審 `git diff <上次基準>..<新 tag>`：新權限、新端點、可疑的下載或執行、動到上表檔案的地方。上游大量由 AI 撰寫，網路上也有惡意的山寨 fork，**沒審過不合併**。
3. 開分支 `woowtech/sync-<tag>`，合併上游 tag，解衝突（大多在上表檔案）。
4. 跑 CI：上游測試（upstream flavor）、`BrandValuesTest`、`woowtech/tools/brand-check.sh`、`woowtech/tools/check-no-cn-services.sh`，以及 woowtech release 建置。
5. 在下面的同步紀錄寫一行：基準、拿了什麼、刻意沒拿什麼。

## 同步紀錄

| 日期 | 上游基準 | 說明 |
|---|---|---|
| 2026-11-06 | `v0.1.37` | 初版品牌層 |
