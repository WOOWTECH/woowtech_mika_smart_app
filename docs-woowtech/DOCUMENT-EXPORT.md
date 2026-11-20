# 非上架 Android 文件產生功能

範圍：woowtech／Apporo 共用核心。此變更不包含 iOS、新增商店發布流程、XLSX 或 DOCX。

## 使用流程

1. 在對話要求將已知內容製成 HTML、PDF 或 CSV。
2. 模型呼叫 `create_document`，傳入明確內容。來源或多表格指涉不明時先詢問。
3. 工具在目前對話工作區的 `documents/` 新建文件，重名另編序號，不覆寫舊文件。
4. 模型呼叫既有 `share_file`，以 MediaStore 寫入品牌的下載資料夾，對話顯示附件卡片。
5. 點附件預覽；預覽頂欄可另存副本、開啟系統分享或使用其他 App 開啟。

產檔本身在本機完成；對話模型是否需要網路依既有設定。`share_file` 是儲存下載附件，沒有自動傳送給聯絡人。系統分享面板的開啟不代表收件者收到。

## 技術與依賴

- `core/document/Document.kt`：共用資料模型、欄位驗證、HTML 轉義、CSV 序列化及安全檔名。
- `CreateDocument`／`SandboxTools.createDocument`：模型工具註冊、工作區安全寫入、儲存額度與錯誤回報。
- `SandboxPort.renderDocumentPdf`：平台介面；未實作的平台明確回報不支援。
- `core/document/DocumentToolDefinition.kt`：單一工具 schema，渠道轉接提供各自的交付說明。
- Android `app/.../document/DocumentPdf.kt`：使用系統 PdfDocument、StaticLayout 與字型 fallback 分頁；不下載字型、不建立 WebView、不載入外部資源。
- 沿用 WebView HTML 預覽、PdfRenderer PDF 預覽、文字 CSV 預覽、MediaStore 匯出及系統分享。
- 新增 Storage Access Framework 的 CreateDocument「另存副本」。只在寫入成功後回報儲存成功；取消另行提示。
- 沒有新增第三方依賴、廣泛儲存權限或外部產檔服務。

平台參考：[PdfDocument](https://developer.android.com/reference/android/graphics/pdf/PdfDocument)、[系統文件選擇器](https://developer.android.com/training/data-storage/shared/documents-files)。

## 文件契約

```json
{
  "format": "html",
  "document": {
    "title": "中文報告",
    "sections": [
      {"type": "heading", "level": 1, "text": "摘要"},
      {"type": "paragraph", "text": "報告內容"},
      {"type": "bulletList", "items": ["項目一", "項目二"]},
      {"type": "table", "columns": ["項目", "數量"], "rows": [["A", "10"], ["B", "20"]]}
    ]
  }
}
```

也支援 `orderedList`。CSV 多表格時必須指定零起算的 `tableIndex`；不任意合併資料。

## 限制與資料處理

- 文件 JSON 上限 250,000 字元；標題 200 字元；區段 200 個；表格 12 欄、1,000 列；PDF 200 頁；輸出 20 MiB。
- HTML 是靜態文件，文字轉義並帶 CSP，禁止腳本及外部資源。不提供公開網址。
- CSV 為 UTF-8 BOM、CRLF、所有欄位加引號；雙引號加倍。疑似公式欄位加前置單引號，工具回應與技能指引要求告知使用者。試算表仍可能自行轉換日期、前導零等資料。
- PDF 表格使用格線與跨頁重複標題列；過長的欄名超過 200pt 時，改採逐列「欄名：內容」版面，避免標題佔滿頁面而無法交付。中文使用裝置系統字型；Emoji 與不常見字形仍需目標手機驗收。
- 工作區文件沿用對話工作區生命週期；下載附件為持久副本，使用者可從下載資料夾刪除；另存或傳送的副本不由 App 自動清除。
- 工具沿用既有沙箱能力提供條件；首次環境準備仍可能等待。非 Android 平台不宣稱 PDF 支援。
- 當前 UI 使用既有檔案卡片，沒有新增文件歷史庫或對話範圍選取編輯器。

## 測試與交付狀態

2026-11-20 驗證紀錄：

- 共用提交 `4d4cf8ec`；直裝接線提交 `655fa978`。後續僅修正既有 viewer 測試寫死簡體中文的斷言，改用目前語系資源。
- 62 項核心測試通過：DocumentTest 5、ToolDispatcherSandboxTest 25、ToolRiskTest 6、PromptSurfaceTest 6、SystemPromptTest 20。最後一次沒有更新 snapshots。
- `assembleWoowtechDebug`、`assembleApporoDebug`、`assembleApporoDebugAndroidTest` 成功。兩品牌正式來源均未再修改；測試 APK 在語系斷言修正後另行重建成功。
- Android 16 arm64 AVD `woow_relay_contract`，Apporo package `com.apporo.assistant`：PDF 分頁與超量拒絕 2 項、HTML/CSV/PDF 經實際 AndroidFdSys/MediaStore 匯出並逐位元讀回 1 項、文字/Markdown/不支援格式預覽 3 項、系統另存 picker 開啟及取消 1 項，合計 7 個案例均有通過紀錄，並非單輪全部通過。
- 首輪 6/7，舊測試硬編簡體中文，Apporo 實際文案為英文。改用字串資源後三項預覽通過；該輪另存遭模擬器 System UI ANR 對話框遮擋，從 UI hierarchy 確認並按 Wait 後，單獨重跑另存案例通過。保留失敗日誌，不視為產品無異常證明。
- APK 產生的 9 頁 PDF 再經 macOS PDFKit 讀取：NFKC 正規化後標題、300/300 段落、200/200 表格重複文字、最後 END-OF-DOCUMENT 均存在；表格核對排除重複表頭與頁碼。首尾頁 PNG 已人工視覺檢查，中文/格線/末列可讀。
- 十種既有語系的四個另存提示字串皆存在且不重複；未新增第三方套件。

可重現命令（JAVA_HOME 使用本機 JDK17、ANDROID_HOME 使用本機 Android SDK）：

```sh
./gradlew :core:test --tests '*DocumentTest' --tests '*ToolDispatcherSandboxTest' --tests '*ToolRiskTest' --tests '*PromptSurfaceTest' --tests '*SystemPromptTest' :app:assembleWoowtechDebug :app:assembleApporoDebug :app:assembleApporoDebugAndroidTest -PapporoAlignmentTests --max-workers=1 -Pkotlin.compiler.execution.strategy=in-process --console=plain
adb -s emulator-5554 shell am instrument -w -r -e class com.wangzan101.mika.document.DocumentPdfTest,com.wangzan101.mika.cap.sandbox.DocumentExportDeviceTest,com.wangzan101.mika.ui.viewer.FileViewerScreenTest com.apporo.assistant.test/androidx.test.runner.AndroidJUnitRunner
```

本機證據在本工作樹 `build/document-acceptance/`：`instrumentation.log`（首輪）、`viewer-locale-final.log`（語系修正後）、`save-picker-after-systemui.log`（排除系統 ANR 後）、`document-acceptance.pdf/html/csv`、PDFKit 抽字與首尾頁 PNG、建置日誌。核心 XML 在 `core/build/test-results/test/`。`build/` 不進 Git；整合方可直接讀取共享工作區。

尚未通過／未驗收：

- POCO 目前未透過 ADB 連線；不能把模擬器當成 POCO 實機驗收。
- WOOWTECH APK 已建置，但此 AVD 已有不同簽章的 `io.woowtech.agent`；覆蓋安裝遭 UPDATE_INCOMPATIBLE 拒絕。未解除安裝或清除舊資料；品牌自身安裝/啟動 smoke 待隔離裝置或對應簽章包。
- Numbers 開啟實際 CSV 遇 macOS「node 控制 Numbers」權限提示並逾時（-1712），待使用者在系統視窗允許，不能宣稱試算表相容性通過。
- 系統另存的「完成寫入並重開」與外部分享接收端尚未做 UI 端到端驗收；已通過的是 MediaStore 附件讀回與 picker 取消。
- 真實模型對話 → 產檔 → 附件 → 預覽的整段真人操作、背景/程序重建、目標手機不常見字形，仍須驗收。
- 商店渠道、Play AAB 與 iOS 不在本輪驗證範圍。共用測試可引用；各渠道的平台差異驗證仍須由整合方完成。

尚未合併 main 或公開發布。測試 APK 是開發驗證用途，不是使用者正式更新包。
