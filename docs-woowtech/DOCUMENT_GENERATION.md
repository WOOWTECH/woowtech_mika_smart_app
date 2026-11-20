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
| PDF | Core Text 分行、UIGraphicsPDFRenderer 分頁 | Android PdfDocument 與原生文字排版 |
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

2026-11-20 本輪已在 MacBook 實際完成 Swift 可攜式編譯。首輪 23 項文件測試為 22 通過、1 失敗（退出碼 1，111.04 秒）：共用 CSV 測試預期值經 Foundation JSON 字串轉換後失去前導 BOM；輸出 CSV 有 BOM。提交 `5850870f` 改以完整 UTF-8 位元組比較後，已實際回歸 **23／23 通過、0 skip、退出碼 0**（增量編譯與執行共 6.48 秒，測試 0.342 秒）。回歸起始來源為 `20ad338b`，期間只有說明文件提交 `1d29554f`，文件程式與測試來源未變。兩輪前後來源及原始日誌已保存。

另已通過 60 項 CI 清單／啟動診斷腳本測試、1053 個文案鍵的雙語資源一致性檢查、42 處 UI 啟動語言檢查、`git diff --check`、字串／XML／共用 JSON 格式檢查。修正了新測試未登錄 CI 清單、文件文案未進入產生器及診斷白名單缺漏；這些腳本測試不代表原生或商用驗收。

CI [44697157866](https://github.com/WOOWTECH/woowtech_mika_smart_app/actions/runs/44697157866)（來源 `06a4b812`）已取得原始證據：253 項可攜式測試全過，337 項腳本測試有 1 項失敗，原生 UI 未執行。失敗是新增文件 WKWebView 尚未納入音訊用途盤點；`b9662745` 已依靜態、已轉義內容與禁止媒體的 CSP 完成盤點，並明確限制自動／行內／AirPlay 播放，該案例針對性回歸通過。證據 artifact `14612031954` SHA-256 `fadb310288f0a67dd26695f6c9840f76927118c365414dab476eae59417699af` 已核對。新的限定 CI [44699145821](https://github.com/WOOWTECH/woowtech_mika_smart_app/actions/runs/44699145821) 來源 `b9662745`，包含 HTML 原生預覽斷言，已通過可攜式／腳本／語言檢查與建置，正執行原生測試，最終結果待取得。

MacBook 原生建置第 1 輪（`b9662745`）的相對 Info.plist 路徑問題已修正。第 2 輪 `native-2` 在乾淨 `d0019f5f`（執行程式仍為 `b9662745`）建置成功並實際執行 **29 項：26 通過、3 失敗、0 skip**，393.71 秒、退出碼 1；前後來源完全相同。其中 23 項文件核心全過、3 項真實檔案 IO／生命週期通過。失敗為兩個文件 UI 啟動案例，以及中文跨頁 PDF 的英文結尾文字擷取。

- UI：兩份相符裝置／時間／App UUID 的崩潰紀錄停在 `UITestModelFixture.repository` 的隔離資料 reset，而非文件畫面。發現本機 driver 使用 `CODE_SIGNING_ALLOWED=NO`，與官方 CI 的 `CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES` 不同；已對齊官方模擬器臨時簽章，保留原 reset 旗標、案例與斷言，待原生回歸。失敗時新增截圖、前景 App 元素階層與狀態附件。
- PDF：第 3 輪只重跑該失敗案例，304.62 秒、退出碼 1，來源無變，保存實際 8 頁 PDF 與擷取文字。頁面上的三個結尾均完整，但 PDFKit 將下劃線移到文字後方。Mac Core Text／PDFKit 單變量控制重現：系統 UI 字型的 `DOCUMENT_END_MARKER` 擷取錯序，Helvetica、Arial、Times、Courier 均完整；ActualText 標記無法解決該擷取現象。採最小的 Helvetica 文件字型修補，Core Text 保留中文後備字形；原來的完整字串斷言未放寬，iOS 回歸待取得。第 3 輪測試結束後，僅中止額外的 `simctl diagnose` 收集（原設定最長 600 秒）；未中斷測試，xcresult 與兩份附件完整匯出。

Android `android-1` 同樣綁定乾淨 `d0019f5f`，前後來源相同，497.58 秒、退出碼 0。JUnit 原始 XML 為 **18 項通過、0 failure／error／skip**：core 14、app upstream 4。Apporo／Woowtech Debug Kotlin 與 upstream AndroidTest Kotlin 編譯通過，Gradle 為 84 項工作實際執行。**儀器測試未執行**，編譯成功不等於裝置驗收；這輪不重跑已成功的 Android 工作。

仍待原生文件 UI 完整操作、修補後 PDF 回歸，以及 Android 裝置上的 4 項原生測試。API 35+ 的 Android PDF 文字擷取案例在較舊系統會明示 skip；skip 不代表該平台內容完整性已驗證。

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
