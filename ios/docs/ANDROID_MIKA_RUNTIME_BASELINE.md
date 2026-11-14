# Android／Mika 行為基準與 iOS 維運

本文件只追蹤**功能與安全契約**。介面對照另見 [Android UI 基準](ANDROID_UI_REFERENCE.md)；iOS 實際支援與驗收仍以 [架構](ARCHITECTURE.md)及 [驗證紀錄](VERIFICATION.md)為準。Android 程式碼、APK、Kotlin `:core` 和 Android `:app` 都不是 iOS 可直接連結的函式庫。追蹤某項原理不表示 iOS 已有相同工具或同等驗收。

## 此次核對的版本（2026-11-11）

| 角色 | 固定版本 | 說明 |
|---|---|---|
| iOS 的產品行為基準 | [WOOWTECH Android `de5be358c4e24b7eed46a95e46edf35a86881bff`](https://github.com/WOOWTECH/woowtech_mika_smart_app/tree/de5be358c4e24b7eed46a95e46edf35a86881bff) | 目前審閱的 fork 主線原始碼；`app/build.gradle.kts` 的上游版號是 `0.1.37`、`app/brand.gradle.kts` 的 `woowtechRevision` 是 8，故**這份原始碼的建置版號**為 `0.1.37-woow.8`；不能據此宣稱已發行。實際 APK／畫面版本另見 UI 基準。 |
| 原理與安全變更的來源 | [Mika `753467f6e141274b4ef6075905e58784193da487`](https://github.com/wangzan101/Mika/tree/753467f6e141274b4ef6075905e58784193da487) | 上游當日快照；不是 iOS 的直接產品規格，也不是已同步到 fork 的保證。 |
| iOS 程式碼 | `a1bf53f0a6a5490f6d969cc36bdce64851160ffc` | 此文件的本地核對基點；後續 iOS 提交須按實際驗收更新結論。 |
| iOS 內嵌 Mika 內容 | `0c172724f3f0c96f7345262588072f6e95db1138` | [NOTICE](../NOTICE) 與 `MikaBundledSkills.json` 的來源版；獨立於上述最新上游。 |

fork 的 [差異與同步紀錄](https://github.com/WOOWTECH/woowtech_mika_smart_app/blob/de5be358c4e24b7eed46a95e46edf35a86881bff/docs-woowtech/FORK.md) 說明切出點是上游 `v0.1.37`／`2c4563bcd8bad7b4b4e3c6de39a3e3f19be7ff98`，另合併 owner 建的 README commit。實際 Git merge-base 也是該提交；兩端之後各有提交（此次 `git rev-list --left-right --count fork...upstream` 為 270／185）。因此不能把 fork 當成上游最新 `main`，也不能只依 GitHub 的「fork」標記判斷血緣。fork 的根 `README.md` 按其文件刻意保留上游原文，品牌說明應讀 `.github/README.md` 與 `docs-woowtech/`。

## 架構與可共用邊界

[Mika 架構](https://github.com/wangzan101/Mika/blob/753467f6e141274b4ef6075905e58784193da487/docs/dev/architecture.md) 把 `:core` 定為純 Kotlin/JVM 任務迴圈、工具分派與能力契約，`:app` 接 Android 前景服務、虛擬螢幕、無障礙、WebView、沙箱和資料儲存。[fork 的 `TaskRun`](https://github.com/WOOWTECH/woowtech_mika_smart_app/blob/de5be358c4e24b7eed46a95e46edf35a86881bff/app/src/main/java/com/wangzan101/mika/task/TaskRun.kt) 依本輪設定裝配模型、記憶、技能、MCP、網頁與沙箱；[`RunAssembler`](https://github.com/WOOWTECH/woowtech_mika_smart_app/blob/de5be358c4e24b7eed46a95e46edf35a86881bff/core/src/main/kotlin/com/wangzan101/mika/core/assembly/RunAssembler.kt) 依 `RunSpec.capabilities` 過濾提供者與工具。iOS 則以 Swift 的 `AssistantModels`、`AssistantMCP`、`AssistantSkills`、`AssistantBrowser`、`AssistantPersistence` 及 App 層分開實作。兩端可共用的是**審閱過的需求、內容與測試向量**，不是 Android 的執行器、作業系統權限或持久化格式。

| 範圍 | Android fork 中的原理／能力 | 目前 iOS 對應與明確差距 | 可共用的審查單位 |
|---|---|---|---|
| 模型 | `core/model` 的 `ChatModel`、OpenAI-compatible、Responses、Anthropic、Gemini 客戶端及 `ModelCatalog`；`TaskRun` 裝入 `AgentLoop`，可分派工具。 | [`HTTPChatModelClient`](../Sources/AssistantModels/HTTPChatModelClient.swift) 僅向設定的 HTTPS `/chat/completions` 發送，普通文字可串流；結構化流程仍讀完整回應並做自己的驗證。沒有等同 Android 多協定模型目錄或統一 AgentLoop。 | 訊息角色、上下文上限、停止／取消、錯誤類別、實際模型測例；不要共用 Kotlin HTTP client 或供應商 SDK。 |
| MCP | `core/cap/mcp` 有 Streamable HTTP、OAuth、stdio、legacy SSE；`core/mcp` 還有可供外部呼叫的伺服器／遠端任務。 | [`MCPClient`](../Sources/AssistantMCP/MCPClient.swift) 是**出站** Streamable HTTP 客戶端；[`MCPConversationRunner`](../Sources/AssistantMCP/MCPConversationRunner.swift) 用已選工具（照 Play 版不逐次核准，2026-11-13 起）、12 次模型決策／6 次遠端執行／180 秒上限；照 Play 版支援手動 Bearer 存取權杖、記住工具選擇（預設全部）、對話自動連線（2026-11-14 起）。OAuth、stdio、legacy SSE、多個伺服器、Android 裝置 MCP server 不在目前 iOS 產品路徑。 | MCP JSON-RPC／協定測例、工具名稱及參數、重複操作規則；伺服器文字或 Markdown 不得擴大工具選取。 |
| 技能與文件 | 六份內建 `SKILL.md`、`GuideCatalog`、個人技能試用／學習；Android 沙箱可依工具能力執行受控腳本。 | iOS 內建原文是釘選且驗雜湊的**資料**，不在 App 內執行；照 Play 版，iOS 的 PDF 擷取／問答／組頁、技能目錄與寫技能畫面已移除（2026-11-14），iOS 不執行任意本機 Shell／Python。 | 原始技能內容／來源 SHA、manifest、逐步依賴、輸入輸出與拒絕案例；執行能力必須由 iOS host 另行授予。 |
| 記憶／個人資料 | `MemoryStore`、`MemoryContext`、`RunLearning` 在 Android 任務結束後整理；開關關閉時不檢索或提取。 | [`LearningStore`](../Sources/App/LearningStore.swift) 透過裝置 Keychain 與加密儲存、明確審閱／提交處理；[`LearningRunContext`](../Sources/App/LearningRunContext.swift) 在開始時擷取有界參考並對刪除、主開關與取消設撤銷。並未共用 Android 資料庫或自動學習的每個時機。 | 開關、來源優先順序、引用、撤銷、已提交資料與失敗後回執；以黑箱行為測例對齊，不直接複製記憶檔。 |
| 瀏覽器／研究 | Android `UserBrowser` 和 `WebStack` 可借用頁面、建工具專用網頁環境與工作區；Web 能力由 TaskRun 裝配。 | [`BrowserSession`](../Sources/App/BrowserSession.swift) 用 App 自己的 WKWebView；手動瀏覽、來源發現、單／多站研究和路線重播有各自的邊界與核准。研究仍限實際觀察的頁面／連結，不把發現結果直接當已讀引文；沒有 Android 的跨 App WebView／CDP 全功能等價。 | URL／來源與引文政策、使用者核准、讀取帳本、取消與導覽失效測例；不能共用 Android DOM adapter、Cookie 儲存或網頁腳本。 |

這次逐位元組核對 fork `de5be358`、上游 `753467f6` 和 iOS 所釘選的 Mika `0c172724`：六份 `core/src/main/resources/skills/*/SKILL.md`，以及 `documents/scripts/extract_pdf.py`、其 manifest 和逐字稿格式參考，三者的 SHA-256 各自相同。另核對 iOS `MikaBundledSkills.json` 的六份原文與三份資產：內容與宣告雜湊都和釘選來源一致。這只證明**這九個內容檔**在指定版本一致，未證明其他原始碼一致，也未授予 iOS 執行原版工具的權限。具體檔案與雜湊由 [runtime 來源清單](android-runtime-reference.json) 追蹤。

## 授權與平台邊界

fork 與 upstream 根目錄均有 `LICENSE`（Apache-2.0）和 `NOTICE`；fork 的 [NOTICE](https://github.com/WOOWTECH/woowtech_mika_smart_app/blob/de5be358c4e24b7eed46a95e46edf35a86881bff/NOTICE) 保留 Mika 出處並標示 WOOW TECH 修改。上游另有獨立 PRoot／talloc 的 [第三方授權與原始碼交付說明](https://github.com/wangzan101/Mika/blob/753467f6e141274b4ef6075905e58784193da487/docs/disclaimer.en.md)，不能把整個 APK 的組件一概稱為只有 Apache-2.0。iOS 有 [NOTICE](../NOTICE) 和 `licenses/Mika-Apache-2.0.txt`，目前**沒有根目錄 LICENSE**；該上游授權副本不自動宣告所有 WOOWTECH Swift 程式的授權。發行或移植更多原文前，應由權利人明確決定 iOS 自有程式授權、檢查各組件授權／NOTICE 與分發物，不推定品牌名稱授權。參照 [Apache-2.0 §4](https://www.apache.org/licenses/LICENSE-2.0) 的保留授權／NOTICE 條件。

Apple 的 [App Review Guidelines §2.5.2／§2.5.6](https://developer.apple.com/app-store/review/guidelines/) 對容器外資料、下載執行會改變功能的程式碼與瀏覽器引擎設限；[文件選取器文件](https://developer.apple.com/documentation/uikit/providing-access-to-directories.md) 說明使用者選取、安全範圍 URL 與 file coordination。iOS 因此維持使用者選檔、原生 PDFKit、App 自己的 WebKit 與顯式核准；不移植 Android 無障礙／虛擬螢幕／ADB、任意本機腳本或其他 App 控制。選用外部隔離 worker 是另一項需審查與部署的服務能力，不能算本機已可用。

## 每週更新與發行判定

1. **記錄三個基點**：fork 的產品 commit／實際發行 tag，上游新 tag／commit，iOS 的候選 commit。fork 先依其 [同步程序](https://github.com/WOOWTECH/woowtech_mika_smart_app/blob/de5be358c4e24b7eed46a95e46edf35a86881bff/docs-woowtech/FORK.md#跟上游同步)審閱上游差異；iOS 不自動跟上游合併。每週及每次 fork 發行時做一次。對改動權限、網路預設、模型端點、執行／下載與資料流的提交即時加做安全審查。
2. **檢出並比較**：以當次記錄的 commit 取得 fork／upstream；先跑下面的釘選檔案檢查，再以 `git diff --name-status <上次審閱的-fork-commit>..<候選-fork-commit>` 掃全部新舊路徑，並用 `git diff <上次審閱的-upstream-commit>..<候選-upstream-commit>` 看上游新原理。清單外新增檔案、Gradle、Manifest、權限、依賴與 generated resources 必須人工查；雜湊檢查不會找到它們。
3. **每一差異填決策**：記來源 commit／實際檔案、受影響能力及目前 iOS 路徑，判為「iOS 要求並實作」、「Android 專用／明確排除」或「待外部服務／裝置」；附安全／授權影響和可執行測例。模型輸出、網站內容與技能文字僅能作資料，不得自動取得工具權限。
4. **分平台驗收後才升基準**：fork 依 upstream flavor、WOOWTECH flavor 的建置／品牌／授權／服務檢查；iOS 依 Swift core、實際 App、iOS 17+ 原生 UI 和適用的真模型／MCP／worker 測例逐層留證。檔案一致或可編譯都不是功能通過。把通過／失敗／跳過／未執行與來源 commit 分開記錄；審閱通過才更新此表與 JSON 基準。

在 iOS repo 執行既有檢查器；`--android-repo` 指向要比較的 fork checkout，**不會更新基準**：

```sh
python3 scripts/check_android_ui_reference.py \
  --android-repo /path/to/woowtech_mika_smart_app \
  --baseline docs/android-runtime-reference.json
```

本次已確認的一個必審實例：fork [`SandboxState.kt:49`](https://github.com/WOOWTECH/woowtech_mika_smart_app/blob/de5be358c4e24b7eed46a95e46edf35a86881bff/app/src/main/java/com/wangzan101/mika/cap/sandbox/SandboxState.kt#L49) 對缺少設定時的 `networkAllowed` 預設 `false`；上游 [`753467f6` 同一行](https://github.com/wangzan101/Mika/blob/753467f6e141274b4ef6075905e58784193da487/app/src/main/java/com/wangzan101/mika/cap/sandbox/SandboxState.kt#L49) 已改為 `true`。這是需由 Android fork 擁有者判斷的行為／風險變動；iOS 沒有該 Android 沙箱，不應照搬任一實作。更新基準時也要重新核對九個技能內容檔，避免把「原文雜湊未變」誤當能力已對齊。

此次為來源與授權文件的靜態審閱及釘選檔案檢查；沒有執行 Android／iOS 建置、原生 UI、真模型或外部服務驗收。
