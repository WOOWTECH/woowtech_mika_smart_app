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

後續驗收與限制（含本輪補測狀態）：

- POCO 目前未透過 ADB 連線；不能把模擬器當成 POCO 實機驗收。
- WOOWTECH 原先 debug 簽章不符的障礙已解決：以既有正式憑證重簽本機驗收包後，`install -r` 覆蓋成功，主畫面啟動 Status: ok，firstInstallTime 保留。僅為模擬器 Debug 驗收包，不能當公開更新包。未證明所有使用者資料逐項保留。
- Numbers 開啟實際 CSV 遇 macOS「node 控制 Numbers」權限提示並逾時（-1712），待使用者在系統視窗允許，不能宣稱試算表相容性通過。
- 系統另存與跨 App 接收已補驗 CSV：從預覽按另存、系統 SAVE 寫入下載資料夾，再重新開檔讀回比對；分享則從真實系統選單選擇獨立測試接收 Activity，由另一套件讀取 URI 並回報 bytes，逐位元相同。這不代表 LINE、郵件或所有第三方 App 均已驗收；HTML/PDF 已在後續補測同一系統另存與分享接收流程，見下方紀錄。
- 真實模型對話 → 產檔 → 附件 → 預覽的整段真人操作、背景/程序重建、目標手機不常見字形，仍須驗收。
- 商店渠道、Play AAB 與 iOS 不在本輪驗證範圍。共用測試可引用；各渠道的平台差異驗證仍須由整合方完成。

尚未合併 main 或公開發布。測試 APK 是開發驗證用途，不是使用者正式更新包。

## 補充驗收與修正（2026-11-20）

- 新增 `saveCopyWritesExactBytes` 與 `shareReceiverReadsGrantedAttachment`：修正後同輪 **OK (2 tests)**，`build/document-acceptance/delivery-e2e-fixed.log`，30.889 秒。此前 7 個平台案例加本次 2 個，共 9 個案例各有通過紀錄。
- 實際另存觸發 Compose instrumentation 的無 Looper Toast 錯誤，現將另存 callback coroutine 明確指定 `Dispatchers.Main.immediate`，資料複製仍在 IO 執行。此錯誤是在測試環境重現，不宣稱先前已在真人裝置重現。
- 接收 Activity 僅在 `androidTest`，使用 Java 可於獨立測試 APK 程序執行，接受檔案 MIME 後讀取系統授予的 URI；不發送到聯絡人，不進產品 APK。測試原本宣告單一 CSV MIME 沒有出現在選單，改為一般檔案接收器後通過。
- 模擬器冷啟動後發生 System UI ANR，以 UI hierarchy 確認後按 Wait 再執行本輪。首次失敗保留於 `delivery-e2e.log`、`share-e2e-recheck.log`，沒有刪除失敗證據。
- 修正後 `assembleApporoDebug`、`assembleApporoDebugAndroidTest`、`assembleWoowtechDebug` 全部成功（3m41s，`/tmp/document-delivery-fixed-build.log`）。核心未改，不重複執行先前 62 項共用測試。
- WOOWTECH 最新修正驗收包再次同簽章覆蓋並啟動；證據 `woowtech-signature.txt`、`woowtech-update.txt`、`woowtech-launch.txt/png`。正式憑證 SHA-256 符合既有發布規格；未更改 Gradle、CI、包名、版本序列或金鑰。
- Numbers 再次因 macOS 自動化權限未完成而逾時；已請使用者處理。POCO 仍無 ADB，已請使用者接線解鎖。此兩項不算通過。

### 三種格式補測與 GitHub 交付

- HTML、PDF、CSV 分別執行 SAF 另存後讀回與真實分享選單 → 獨立套件接收，六個案例均有通過紀錄；與原有七項合計十三個不同平台案例各有通過紀錄。
- `delivery-all-formats.log` 第一輪 3/6（前三項受 System UI ANR 對話框遮擋，active package=android）；排除遮擋後其餘三項通過。只重跑受遮擋的 PDF 分享、HTML 另存、CSV 分享，`delivery-formats-recheck.log` **OK (3 tests)**，48.955 秒。不宣稱單輪全綠或真機通過。
- 測試樣本由共用 Document／DocumentPdf 產生，獨立接收端以實際 URI 授權讀取後比對 bytes；系統另存檔另行開啟讀取比對 bytes。產物本身不變；此次只擴充 androidTest。
- 分支已推送 `origin/feature/document-export`；Draft PR：<https://github.com/WOOWTECH/woowtech_mika_smart_app/pull/45>。
- PR 的部分 CI 在 `.github/scripts/prepare-compiler-repository.py` 下載官方 Kotlin 編譯器 asset 的 GET 階段收到 HTTP403，尚未到程式編譯。來源為 GitHub JetBrains 官方 asset API `598635327`；已交接建置配置負責對話，未擅改 CI。品牌來源與 WOOW release plan 檢查曾通過，不能視為整體 CI 通過。
- 仍未合併 main／公開發布：POCO、Numbers 授權、真實模型端到端與生命週期等界線仍依前文；Debug 驗收包不作正式下載包。


## CI recovery (2026-11-20)

- `0216f899` / `8f6b5974`: compiler asset API requests now use the step-scoped GitHub token via curl stdin config. The existing HTTPS, deadline, pinned size/SHA256/SHA1 and atomic publication checks remain. Tokens are absent from command arguments and receipts. The first revision rejected the runner token alphabet; the follow-up accepts standard Bearer syntax and tests header-injection rejection.
- Actual GitHub run `44712565160` and brand runs `44712565001`, `44712565010`, `44712564995`: all seven compiler preparation steps succeeded. Saved CLI log shows JAR/POM HTTP 200 and `repository_ready`. Prior 403 logs lack response diagnostics, so anonymous rate limiting is not established as the definitive cause.
- Local `.github/scripts` regression suite: 19 tests passed; translation check: 1980 resources / 10 languages. Added create_document labels fixed the previously failing Android ToolLabelsTest; the complete Android job passed on `8f6b5974`.
- Full core CI uncovered 10 remaining failures among 3026 cases: missing document tool prompt resource, stale entry lists/snapshots, and changed compaction indices after the new schema. The description now loads from `prompts/tools/create_document.md` with the same text and channel-specific delivery placeholder. No production compression algorithm change. At the fixed 80K test window, OpenAI-compatible/Responses/Anthropic fixtures compact at 12/21/30; Gemini stays 12/22. Existing cache-prefix/share assertions remain.
- Updated only the reviewed tool-list/size snapshots and expected tool/compaction lists. Local targeted suite: 59 cases passed again without `-PupdateSnapshots` (`/tmp/document-ci-regressions-verify.log`). Full GitHub verification of this follow-up is pending at commit time.
- Raw download evidence: `build/document-acceptance/ci-8f6b5974/cli.log`; original core CI failure XML: sibling `core/` directory. These build artifacts remain local.


## Latest direct-brand emulator revalidation (2026-11-20)

Product source baseline: `3ac6e042`. Rebuilt both direct debug APKs, then both Android test APKs. Only the test opt-in and preview assertions/evidence capture changed after that baseline; no product behavior, package, signing configuration or version sequence changed.

- Added `-PdocumentAcceptanceTests` to enable branded Android test APKs for both direct WOOWTECH and Apporo. Existing `-PapporoAlignmentTests` remains supported. Ordinary branded builds still omit instrumentation.
- Added actual format-specific preview assertions and synthetic sample screenshots before each SAF save. Reviewed all six captured previews: Chinese/table HTML, paginated PDF view and CSV text are readable in both brands.
- AVD `woow_relay_contract`, Android 16 / API 36 arm64. A cold-boot System UI ANR was dismissed with Wait before starting tests; its screenshot is preserved as `ready.png`.
- Apporo (`com.apporo.assistant`): **OK (13 tests)**, single run, **150.789s**. The three formats each passed system save/readback and real chooser/independent test-APK URI access; PDF multipage/overflow, MediaStore exports, existing viewers and save cancellation also passed.
- WOOWTECH (`io.woowtech.agent`): first run **12/13**. Two installed test APKs advertised the same receiver label; PDF sharing selected a receiver that did not report to the WOOWTECH test. After disabling only the Apporo test package, CSV/HTML sharing passed, and the isolated PDF sharing rerun was **OK (1 test)** in **15.268s**. All 13 distinct WOOWTECH cases have passing evidence, not a single all-green run. Preserve both logs.
- WOOWTECH main and test APKs were locally signed with the existing WOOWTECH certificate and installed with `-r`; no product uninstall/data clear. These are debug acceptance artifacts, not public release APKs. Both product manifests exclude DocumentShareReceiverActivity.
- Cleanup restored the pre-existing Apporo test package to enabled and removed only the newly installed WOOWTECH test package to avoid duplicate chooser targets. Product packages/data remain installed.
- Evidence: `build/document-acceptance/latest-3ac6e042/`: `artifacts.json` (four APK hashes), `apporo-instrumentation.log`, `woowtech-instrumentation.log`, `woowtech-share-pdf-recheck.log`, `{apporo,woowtech}-preview-{html,pdf,csv}.png`. Build logs: `/tmp/document-latest-platform-build.log`, `/tmp/document-both-brand-tests-build.log`.

Reproduction:

```sh
./gradlew :app:assembleApporoDebug :app:assembleWoowtechDebug :app:assembleApporoDebugAndroidTest :app:assembleWoowtechDebugAndroidTest -PdocumentAcceptanceTests --max-workers=1 -Pkotlin.compiler.execution.strategy=in-process
adb -s emulator-5554 shell am instrument -w -r -e class com.wangzan101.mika.document.DocumentPdfTest,com.wangzan101.mika.cap.sandbox.DocumentExportDeviceTest,com.wangzan101.mika.ui.viewer.FileViewerScreenTest com.apporo.assistant.test/androidx.test.runner.AndroidJUnitRunner
# For WOOWTECH use io.woowtech.agent.test; install main+test with matching certificates.
# Keep only the target brand's test receiver enabled during chooser tests, then restore test-package state.
```

### POCO and store-channel boundary

- POCO still absent from USB/ADB. Apporo relay initialize returned HTTP 200 and `0.1.37-apporo.10`, but this version label does not identify the new document commit.
- A bounded read-only relay task attempted installed-package/version preflight. It terminated with `gaveup`: system commands reported `no_app_open`, and opening Settings reported `phone_unavailable`. Only a partial package list was returned, not verified version codes/device identity. No packages were installed/removed and no settings changed on the phone. This is NOT document acceptance.
- Requested USB debugging connection/authorization. Latest direct APKs have not been deployed to the physical POCO in this round.
- Store coordination worktree `assistant-store-documents-20261120` remained clean at `9ec745e0`, without the shared document engine/store adapter. Requested the integrated store commit/artifacts through its coordination file and user; cannot use direct APK evidence for store packages/AABs.
- These instrumented cases exercise generation/export components and real preview/save/share UI. They do not establish a real-model natural-language conversation through tool selection and attachment navigation. Third-party spreadsheet behavior, store delivery and physical-device acceptance remain separate pending items.
