# 本機文件產生：第一階段

工作分支：`feature/documents-ios-android-20261120`，基底 `1d986032f294613cf7ecce6833a6e2be44052ab3`。

## 範圍與入口

從已完成的助理回答建立 HTML、PDF、CSV，預覽後透過系統介面儲存或分享。使用者選定的原始回答會先複製成快照，後續對話更新不會改變這次文件。長按回答的文件入口不使用複製功能的去格式純文字，以保留表格結構。

另提供保守的完整句子辨識，例如 `export the previous answer as PDF`、`把剛才的分析整理成 PDF`。只有明確指向前一則回答、沒有等待中的附件或引用時才開啟本機文件操作頁；不直接儲存或分享，也不把一般 PDF 問題攔截成命令。不支援任意自然語言產檔代理或新內容生成。其餘需求仍可先讓模型產生回答，再由使用者選定匯出。

本輪不包含 Excel/Word、網站發布、雲端產檔、跨 App 控制、文件歷史庫或自動傳送。原有 iPhone 舊對話卡死、MCP 工具錯誤及玻璃輸入區實機驗收仍為獨立未完成項。

## 實作選擇

| 層次 | iOS | Android |
| --- | --- | --- |
| 模型、Markdown 子集、HTML、CSV | 新的 `AssistantDocuments` Swift 模組 | `core/.../document` Kotlin 模組 |
| PDF | Core Text 分行、UIGraphicsPDFRenderer 分頁 | Android PdfDocument 與原生文字排版、小型字碼區分字型 |
| HTML 預覽 | WKWebView，非持久資料庫、關閉 JavaScript、阻擋導覽 | 靜態 WebView，限制腳本、網路與檔案存取 |
| PDF 預覽 | PDFKit | 沿用檔案檢視器的 PDF 呈現 |
| 儲存 | UIDocumentPicker 匯出副本 | Storage Access Framework CreateDocument |
| 分享 | UIActivityViewController + 暫存 URL | 系統分享 + FileProvider 讀取授權 |

不新增大型文件產生套件，也不新增伺服器或權限。兩個原生專案共用語意規則與測試輸入，並不強迫共用語言程式碼。系統 API 參考：[Apple PDF renderer](https://developer.apple.com/documentation/uikit/uigraphicspdfrenderer)、[Apple WebKit JavaScript 控制](https://developer.apple.com/documentation/webkit/wkwebpagepreferences/allowscontentjavascript)、[Apple 分享完成回呼](https://developer.apple.com/documentation/uikit/uiactivityviewcontroller)、[Android 文件儲存](https://developer.android.com/training/data-storage/shared/documents-files)、[Android 安全檔案分享](https://developer.android.com/training/secure-file-sharing)。

## 文件內容與限制

- 支援標題、段落、基本清單及 Markdown 管線表格。未支援的內嵌格式與 HTML 留作文字；不執行、不下載、不嵌入附件或圖片。
- CSV 只輸出明確選定的一張表；多表時要求選擇，不合併或猜測。
- UTF-8 BOM、CRLF 記錄、引號跳脫；疑似公式的欄位在原值前加單引號，包含標頭。介面揭露影響，預覽顯示處理後的值。試算表仍可能自行轉換日期、數字或前導零。
- 來源上限 1 MiB；單表至多 64 欄、5,000 資料列；全文件至多 50,000 儲存格（含標頭）、64 張表；輸出上限 16 MiB。超限或欄數不一致會失敗，不產生空檔或截掉資料後報成功。
- iOS PDF 最多 256 頁；寬表按可閱讀欄數拆成連續區段，長儲存格可跨頁，續頁重列標頭。複雜版面與嵌入圖像不在首版保證範圍。
- 預設檔名由標題產生，去除路徑、控制及不適合的字元，限制字元數與 UTF-8 位元組數；每次產生使用獨立目錄，避免覆寫。
- 介面的來源摘要與大型 CSV 預覽有顯示上限，完整輸出內容不因此截斷。

## 結果與檔案生命週期

「已產生」、「系統分享介面已開啟」、「系統回報活動完成」、「已匯出」、「取消」、「失敗」分別處理。系統活動完成不代表接收者收到；儲存介面取消不報成功。分享不自動寄信、不聯絡外部接收者。

暫存檔在交付期間保持可讀，關閉頁面不立即刪除，防止接收端尚未讀取。iOS 產檔時清理超過 24 小時且未被使用中的文件，暫存總額 100 MiB；上限不足時明確失敗。這是下次操作時清理，並非背景定時刪除保證。檔案排除備份；沒有紀錄文件內容、金鑰或完整工具資料。

## 驗證與尚未完成項

以下為 2026-11-20 `/Users/woowtech` 本輪真實輸出，原始 log、來源前後雜湊、receipt、xcresult、JUnit XML 與 PDF 保存在 `Documents/WOOWTECH-iOS-validation/documents-20261120`。合成內容、模擬器與單元測試均不代表商用／實機驗收。

| 實際執行 | 來源 | 結果與範圍 |
| --- | --- | --- |
| Swift 文件核心原先回歸 | `20ad338b`，期間只有文件提交 | 23/23、0 skip；不可套用為新版本整體通過 |
| `native-2` | 乾淨 `d0019f5f`，runtime `b9662745` | 建置成功；29 項 26 通過、3 失敗、0 skip；393.71 秒、exit 1 |
| `android-1` | 乾淨 `d0019f5f` | JUnit 18/18、0 failure/error/skip；core14、app4；497.58 秒、exit 0；兩品牌 Kotlin／AndroidTest 編譯通過，這一輪沒有執行儀器測試 |
| `native-4` PDF／UI 回歸 | `197af506` | PDF 文字與跨頁、PDF 對話命令 UI 通過；CSV UI 的查詢識別錯誤，合計 2 通過、1 失敗 |
| `native-6` CSV／HTML UI | `40f9c9cf` | 精確案例 1/1、0 skip；226.88 秒、exit 0；真 CSV 預覽、公式防護、Files 取消與靜態 HTML WKWebView |
| `native-7` 舊持久化案例 | `40f9c9cf` | MemoryTool 手動更新後重啟、BrowserSearch 設定／歷史重啟 2/2、0 skip；392.73 秒、exit 0；iOS27 模擬器，未證明舊 iOS18/26 間歇失敗的根因已修 |
| Android 第一次儀器測試 | `40f9c9cf` | API36 模擬器 4 項：3 通過、1 失敗、0 skip；失敗為長表格 PDF 的中文字碼 |
| Android PDF 修補回歸 | `e5f970aa` | API36 原生儀器 3/3、0 skip；159.07 秒、exit 0；原失敗完整字串、跨頁末端、一般／粗體中英與部首；來源前後相同 |

`native-2` 的失敗不是 Info.plist：兩個 UI 案例在文件畫面之前崩潰，兩份對齊時間／UUID 的 `.ips` 指向隔離 Keychain reset。本機 driver 原為不簽章，已改與官方 CI 相同的模擬器 ad-hoc 簽章，原 reset 與斷言均保留；後續 UI 實際通過。

iOS PDF 原始 8 頁的結尾文字視覺完整，但系統 UI 字型讓 PDFKit 把下劃線移到字尾。Core Text／PDFKit 單變量對照後，`197af506` 改用 Helvetica 文件字型，保留中文 fallback，原完整字串斷言通過；修補後 9 頁 PDF 與截圖已保留。沒有以放寬斷言或正規化文字掩蓋缺漏。

兩項 iOS UI 測試修正：`a2ba7a27` 查詢實際 `document.preview.content`；`40f9c9cf` 在 Files 開啟子資料夾、沒有 Cancel 按鈕時，執行真實下滑關閉，再確認「已取消操作」，不直接呼叫取消 callback。CSV／HTML 實際畫面已匯出檢查。原生 UI 的模型回答仍為 fixture，不能當成真實模型服務驗收。

Android 原始 PDF 的「文 U+6587」被寫成可擷取的「⽂ U+2F42」。原生 sans-serif／serif／monospace 對照均重現，ToUnicode 表亦吻合；不是表格末端遭裁切。`e5f970aa` 新增 165,380 bytes 的 **Apporo Document Aliases** 文件字型：來自固定來源 Noto Sans TC，867 個共用字形字碼各用不同 glyph ID，未覆蓋字元仍用系統 fallback。SIL OFL 1.1／版權／來源 SHA／重建工具保留在 `app/src/main/assets/fonts` 與 `tools/build_document_alias_font.py`；重建使用 fonttools 4.60.2，不是 App 或 Gradle 執行依賴。不正規化／改寫原文字碼，也不引入 PDF 引擎或隱藏 API。修補後長表格為 11 頁，已檢視第 5 頁與末頁，標頭、列號、中文末端及第 5–6 欄完整；不同字型度量改變頁數，未承諾與舊版逐頁相同。覆蓋範圍外仍受平台字型影響。

原 CI [44699145821](https://github.com/WOOWTECH/woowtech_mika_smart_app/actions/runs/44699145821) 的 `b9662745` 原始 log 已取得：可攜式 **253/253**、腳本 **337/337**，原生 UI **4/5**；唯一失敗為同一 CSV selector，不能以舊 `06a4b812` 結果混算。修補後限定 CI [44708429933](https://github.com/WOOWTECH/woowtech_mika_smart_app/actions/runs/44708429933) 綁定 `40f9c9cf`，目前仍執行原生測試；未重跑或中止正常隊列。Android 字型修補不在該 iOS CI head 內。

Android 原生安全預覽、FileProvider 讀取／禁止寫入、分享 Intent 權限、取消狀態等在 `40f9c9cf` 的兩個案例已通過。Intent 或元件狀態不是接收端收到檔案；Android 實際文件畫面完整流程仍待驗。API35 以下文字擷取案例會明示 skip，不算通過。

共用 `test-fixtures/documents/parity-v1.json` 由兩平台測試讀取，核對相同表格資料、精確 CSV 位元內容與 HTML 轉義。

建置與測試應在取得時段後序列執行：

```sh
swift test --package-path ios --jobs 2 --filter AssistantDocumentsTests
# XcodeGen 2.44.1 依 ios/project.yml 產生專案後，使用 WoowAssistant scheme：
# AssistantDocumentsTests
# AssistantBrowserIntegrationTests/DocumentExportIntegrationTests
# WoowAssistantUITests/DocumentExportUITests

./gradlew --offline --no-daemon --max-workers=1 \
  :core:test --tests 'com.wangzan101.mika.core.document.*' \
  :app:testUpstreamDebugUnitTest --tests 'com.wangzan101.mika.document.*' \
  :app:compileApporoDebugKotlin :app:compileWoowtechDebugKotlin \
  :app:compileUpstreamDebugAndroidTestKotlin
```

以上命令仍須包在 `heavy.sh` 與磁碟監控內，本案逐次設定 `HEAVY_OWNER_DISK_FLOOR_GIB=0`，不修改共用預設。Android 使用 JDK 17 與本機 SDK 36；依專案既有規則，單元／儀器測試在 upstream flavor 執行，品牌版本另外編譯驗證。MacBook 的 `bounded.py`、`native.py` 與快取清理紀錄保留在前述證據目錄；持續記錄用量，實際檔案系統／建置錯誤仍須如實處理。

本工作區的原生測試與共用測試均使用去識別的合成文件；模型 fixture 只能證明本機串接，不能當成商用模型或真實業務驗收。

需要保留的驗證證據：Swift/Kotlin 測試退出碼、iOS/Android 編譯結果、PDF 頁數與末端文字、HTML 靜態內容、CSV 引號與公式防護、系統儲存/分享取消與實際接收端開啟。執行結果保存在 MacBook `Documents/WOOWTECH-iOS-validation/documents-20261120`，未執行的項目不得列為通過。

仍需兩平台實機驗證：中文/長表格閱讀、深淺色與大字體、背景返回、低儲存空間、實際文件提供者、外部接收端可讀性、取消與重試。另需用目標試算表檢查 CSV 中文、公式防護、日期與前導零的實際呈現。

本輪不操作原 iPhone 對話或附件，也不修改原工作區的 `UserProfileChatFlow.swift` 與 `UserProfileChatFlowTests.swift` 未提交內容。
