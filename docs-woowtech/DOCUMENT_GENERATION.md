# 本機文件產生：第一階段

工作分支：`feature/documents-ios-android-20261120`，基底 `1d986032f294613cf7ecce6833a6e2be44052ab3`。

## 範圍與入口

從已完成的助理回答建立 HTML、PDF、CSV，預覽後透過系統介面儲存或分享。使用者選定的原始回答會先複製成快照，後續對話更新不會改變這次文件。長按回答的文件入口不使用複製功能的去格式純文字，以保留表格結構。

另提供保守的完整句子辨識，例如 `export the previous answer as PDF`、`把剛才的分析整理成 PDF`。只有明確指向前一則回答、沒有等待中的附件或引用時才開啟本機文件操作頁；不直接儲存或分享，也不把一般 PDF 問題攔截成命令。不支援任意自然語言產檔代理或新內容生成。其餘需求仍可先讓模型產生回答，再由使用者選定匯出。**2026-11-25 起此句子辨識已移除**，改由模型的 file_create 處理任何說法的產檔要求；長按回答的匯出不變，見[下方](#2026-11-25-助理建立檔案file_create)。

本輪不包含 Excel/Word、網站發布、雲端產檔、跨 App 控制、文件歷史庫或自動傳送。（Word、Excel、PowerPoint、ZIP 由 2026-11-25 的 file_create 補上，仍不含網站發布、雲端產檔與自動傳送。）原有 iPhone 舊對話卡死、MCP 工具錯誤及玻璃輸入區實機驗收仍為獨立未完成項。

iPad 後續的版面修補、受控卡死重現、267 安裝來源、實機結果與剩餘限制，另見 [iPad 版面與視覺回歸](IPAD_VISUAL_VALIDATION.md)。iPad 結果不取代原 iPhone A31 對話或跨平台商用驗收。

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

以下為 2026-11-20／21 `/Users/woowtech` 本輪真實輸出，原始 log、來源前後雜湊、receipt、xcresult、JUnit XML 與 PDF 保存在 `Documents/WOOWTECH-iOS-validation/documents-20261120`。合成內容、模擬器與單元測試均不代表商用／實機驗收。

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
| Android 真正觸控 UI | `eaeee5ed` | `android-device-9-touch-regression` 1/1、0 skip；87.01 秒、exit 0；CSV 選擇／產檔／精確 bytes／FileViewer 預覽，前景視窗與實際截圖通過，沒有新 ANR 事件 |
| iOS Files 空白頁診斷 | `eaeee5ed` | `native-9`／`native-10` 各 0/1、0 skip、exit 1；228.77／279.45 秒；均已產生／預覽 CSV，系統儲存頁沒有導覽列，尚未修復 |
| iOS Files 後續時段對照 | `012a5065`，僅比 `eaeee5ed` 多文件紀錄 | `native-11` 1/1、0 skip、exit 0；237.85 秒；同一案例與等待時間，CSV／Files 真取消／HTML 全流程通過，兩張畫面已檢查；不代表前兩次空白頁根因已修 |

`native-2` 的失敗不是 Info.plist：兩個 UI 案例在文件畫面之前崩潰，兩份對齊時間／UUID 的 `.ips` 指向隔離 Keychain reset。本機 driver 原為不簽章，已改與官方 CI 相同的模擬器 ad-hoc 簽章，原 reset 與斷言均保留；後續 UI 實際通過。

iOS PDF 原始 8 頁的結尾文字視覺完整，但系統 UI 字型讓 PDFKit 把下劃線移到字尾。Core Text／PDFKit 單變量對照後，`197af506` 改用 Helvetica 文件字型，保留中文 fallback，原完整字串斷言通過；修補後 9 頁 PDF 與截圖已保留。沒有以放寬斷言或正規化文字掩蓋缺漏。

兩項 iOS UI 測試修正：`a2ba7a27` 查詢實際 `document.preview.content`；`40f9c9cf` 在 Files 開啟子資料夾、沒有 Cancel 按鈕時，執行真實下滑關閉，再確認「已取消操作」，不直接呼叫取消 callback。CSV／HTML 實際畫面已匯出檢查。原生 UI 的模型回答仍為 fixture，不能當成真實模型服務驗收。

Android 原始 PDF 的「文 U+6587」被寫成可擷取的「⽂ U+2F42」。原生 sans-serif／serif／monospace 對照均重現，ToUnicode 表亦吻合；不是表格末端遭裁切。`e5f970aa` 新增 165,380 bytes 的 **Apporo Document Aliases** 文件字型：來自固定來源 Noto Sans TC，867 個共用字形字碼各用不同 glyph ID，未覆蓋字元仍用系統 fallback。SIL OFL 1.1／版權／來源 SHA／重建工具保留在 `app/src/main/assets/fonts` 與 `tools/build_document_alias_font.py`；重建使用 fonttools 4.60.2，不是 App 或 Gradle 執行依賴。不正規化／改寫原文字碼，也不引入 PDF 引擎或隱藏 API。修補後長表格為 11 頁，已檢視第 5 頁與末頁，標頭、列號、中文末端及第 5–6 欄完整；不同字型度量改變頁數，未承諾與舊版逐頁相同。覆蓋範圍外仍受平台字型影響。

原 CI [44699145821](https://github.com/WOOWTECH/woowtech_mika_smart_app/actions/runs/44699145821) 的 `b9662745` 原始 log 已取得：可攜式 **253/253**、腳本 **337/337**，原生 UI **4/5**；唯一失敗為同一 CSV selector，不能以舊 `06a4b812` 結果混算。限定 CI [44708429933](https://github.com/WOOWTECH/woowtech_mika_smart_app/actions/runs/44708429933) 的 `40f9c9cf` 為 4/5、0 skip。已取得該失敗的原始畫面／AX：iOS26.2 Files 的「儲存」按鈕沒有 `DOCPicker.actionButton` 識別碼；`eaeee5ed` 在真實 Files 導覽列內同時辨識可見標籤與識別碼，保留真實取消及狀態斷言。artifact `14618267598` 只取需要的 ZIP entries，逐項 CRC 與 SHA-256 已核；沒有宣稱已驗整包 SHA。修補後 CI [44715367632](https://github.com/WOOWTECH/woowtech_mika_smart_app/actions/runs/44715367632) 綁定 `eaeee5ed66458a1a10a21098c5ef087bdaffe8f5`：原始 log、xcresult summary 與逐案完成檢查均為 **5/5、0 skip**，兩個文件案例通過；整體 job 仍為 failure，因模擬器準備、測試與收尾共用的 20 分鐘步驟超時，不能把 job 說成成功。`5c7c88cb` 將準備拆成獨立、上限 10 分鐘的步驟；原測試時限、逐案上限、5 個 selector、斷言、錯誤處理與 job 70 分鐘上限不變。YAML／bash 語法、workflow 生成同步與既有範圍保護 4 項檢查通過。新 CI [44721012515](https://github.com/WOOWTECH/woowtech_mika_smart_app/actions/runs/44721012515) 僅驗這項流程修補，來源 `5c7c88cb5aedd8720f33c0a53d1e8dcec02a5667`，整體成功；原始 log 與逐案完成 gate 均為 **5/5、0 fail、0 skip**（3 個附件、2 個文件 UI 案例）。模型仍為 fixture，不算真實供應商驗收；正常既有隊列未重觸發或中止。

Android 原生安全預覽、FileProvider 讀取／禁止寫入、分享 Intent 權限、取消狀態等在 `40f9c9cf` 的兩個案例已通過。Intent 或元件狀態不是接收端收到檔案；Android 真實 CSV 對話框產檔與 FileViewer 預覽已通過；HTML／PDF 的完整畫面操作、系統儲存／取消／分享與接收端仍待驗。API35 以下文字擷取案例會明示 skip，不算通過。

兩個新的驗收缺口已保留，不以舊通過結果掩蓋：

- Android `b11a5e31` 原 UI 斷言雖為 2/2，但實際截圖被 System UI ANR 對話框遮擋，**不列為 UI 驗收通過**。已補真正的觸控事件與 App 前景視窗檢查；測試自動化初次連線會暫時沒有視窗資料，先建立連線後有界等待資料，任何其他前景視窗仍立即失敗。隔離模擬器只將 GPU 從 SwiftShader 改為 host，未修改其他工作區。`eaeee5ed` 再跑真正觸控案例 1/1，截圖無遮擋、事件日誌無新 ANR。原 System UI ANR 的 DropBox 日誌與當時高 CPU 壓力另有保存。
- iOS27 `native-9`／`native-10` 的空白頁是另一個現象，不能歸因為 CI 識別碼差異。第 10 輪已擷取 471 KB Document／FileProvider 日誌：DocumentManager 擴充服務在 18:16:05 記錄未於約兩秒內收到 host handshake，列出非預期啟動或 CPU 競用的可能性；18:16:08 隨後仍收到 extension request，18:16:11 開始建立 scene，故不是已證明永久斷線；18:16:14 的連線失效發生在測試終止 App 之後，不能倒果為因。沒有找到相符服務崩潰檔；日誌不能證明唯一根因。兩輪皆觀察到其他工作區的建置或模擬器在本案取得 heavy lock 後重疊，已保存 PID／時間線並保留其工作；其他模擬器結束後，`native-11` 在相同程式與斷言下通過，沒有加長 timeout、預先暖機 Files 或清除原使用者資料。有效資源採樣涵蓋 18:28:45–18:30:13 的產檔／Files／HTML 階段，28 次均未見外部重型工作；較早的主採樣因 macOS 截短 comm 欄位而無效，已標註，不能宣稱整輪完全隔離。Files 不再出現該握手警告；這支持啟動時序值得追查，仍不足以證明唯一根因或實機可靠性。兩個測試容器已恢復，僅本案 Android AVD 已刪除，證據保留。

`native-7` 與後續 CSV 案例另出現 SwiftUI「Invalid frame dimension」警告；唯讀核對發現前者發生於 `settings.baseURL` 取得焦點，尚未進入 MemoryEditor，後者發生於 `chat.draft` 輸入、早於文件匯出。xcresult 沒有來源位置或實際 proposal 數值；設定 chip layout／聊天麥克風僅有理論上的非法尺寸輸入候選，共同鍵盤 toolbar 路徑亦待觀測。沒有據此修改無法重現的程式，也未宣稱與舊手機 A31 高 CPU 卡死相關。

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

2026-11-21 實機先從 248 升級到 249，後續修補已安裝 **0.1.0 (251)**，USB iPad 第 9 代／iPadOS 26.6.1，未卸載、重置或清除原資料。使用者完成 XCTest 授權後，已執行真實 UI 與已設定模型的請求，未使用模型 fixture。先前 Touch ID 阻礙已解除；`ipad-04` 起的操作紀錄可證，不應再以舊阻礙回報等待。

248 的實測發現 HTML／PDF 會將來源的首個 H1 與推定文件標題各顯示一次。`b2fbb9dc85aeca4a11c9813613776a0fd503ef83` 同步修正 Swift／Kotlin：只合併與文件標題完全相同的第一個 H1；保留來源資料、後續同名標題、不同標題與 H2。iOS 文件核心與實際 PDFKit 整合 **25/25、0 skip**；Android 文件測試 **19/19、0 failure/error/skip**，兩品牌 Kotlin／AndroidTest 編譯通過，此輪沒有執行 Android 儀器測試。兩輪來源前後一致，原始結果為 `native-12-title`、`android-title`。

249 為該乾淨提交的 MacBook Release／arm64 產物，134.79 秒、exit 0；9 個 framework 與 App 嚴格簽章驗證通過，描述檔含本 iPad。IPA SHA-256：`3cd2a132b924a91144f2b5e02d3c67b19d013fdde8ab3ea19be171a008cccbcd`；binary UUID：`21BB7F98-C724-3E93-BD7B-A82EE2BFE733`。包內來源、版本、SHA 與安裝後 249 回讀均已核對；不是 GitHub 產物。`device-249-artifact.json`、安裝 receipt 與來源 manifest 保留。

| iPad 實際執行 | 版本 | 可證明結果 |
| --- | --- | --- |
| 真模型產生中文表格 → CSV／HTML／PDF | 248 | 預覽可讀；CSV 有 BOM、CRLF、前導零 `00123`、公式保護字元；HTML 的 script 字串為文字，未執行 |
| Files 取消 → 儲存 | 248 | 取消顯示取消；實際保存 CSV、PDF，CSV 回讀 bytes 完全一致 |
| 系統分享面板 → 取消 | 248 | iPad popover 正常，取消未誤報成功；未送給外部接收端 |
| 100 列中文長報告 → PDF | 248／249 | 均為 5 頁，100 個列尾標記與結尾完整；249 PDF、HTML 畫面及檔案均只含一次文件標題 |
| PDF 匯入新對話 → 真模型讀取 | 248 | 沒有原報告上下文的新對話正確回覆 `100`、`END_100`、`FINAL_LONG_IPAD248`；重啟後從歷史重開，附件仍可預覽 |
| 損壞 PDF | 248 | 80 bytes 無效 PDF 的真模型回覆明確表示不能讀取，未編造內容；UI 流程 99.7 秒，中途有自動化等待，不據此斷言 App 卡死 |
| 201 MiB 附件 → 拒收 → 正常 CSV | 249 | 真 Files 匯入顯示 200 MB 上限提示，沒有加入附件；隨後同一對話成功讀取較小 CSV，保留 `00123` 與 `'=1+1` |
| 淺色／深色、橫向鍵盤、背景返回 | 248／249 部分 | 所保存畫面中輸入區、附件／錯誤提示可讀；背景返回草稿仍在；尚未完成大字體／降低透明度的完整矩陣 |

詳細逐項結果與畫面位於 `ipad-248-commercial-partial-results.json`、`ipad-249-commercial-partial-results.json`；真 UI 步驟 receipt 與模型回覆分開核對，沒有把自動化傳輸 exit 0 當成功。原 248 的 `ipad-remote-01` 因結果區在折疊外而查找失敗；`ipad-remote-16` 使用錯誤移除按鈕標籤而失敗，均保留為工具操作失敗，後續使用實際畫面／識別碼操作。實機不使用測試 namespace、重設旗標或模擬模型。

新發現限制：終止 App 後回到新對話，未送出草稿未恢復；目前 `ChatDraft` 只存在記憶體。保存的對話與附件另已確認可從歷史重開，不能把兩者混為資料遺失或宣稱草稿保存通過。原 iPhone A31 高 CPU 對話未在本機重現／修復，iPad 的成功不能替代它。

需要保留的驗證證據：Swift/Kotlin 測試退出碼、iOS/Android 編譯結果、PDF 頁數與末端文字、HTML 靜態內容、CSV 引號與公式防護、系統儲存/分享取消與實際接收端開啟。執行結果保存在 MacBook `Documents/WOOWTECH-iOS-validation/documents-20261120`，未執行的項目不得列為通過。

249 的 Google 實測發現另一個真實缺陷：結果已載入，卻顯示整頁導覽失敗。真 WebKit 子框架導覽在原程式重現，`native-13-browser-repro` 的原斷言 0/1；`b4b0a117cb3fc958f447295650cd294d4e153dd3` 保留阻擋政策，只讓主框架拒絕導覽影響整頁錯誤。`native-14-browser-fix` 導覽／搜尋回歸 9/9、0 skip。250 實機同一 Google 查詢正常；安全分類日誌確認 4 次 `frame=subframe scheme=about` 仍被拒絕，畫面不再出現假整頁錯誤。日誌 binary UUID 與安裝包相符；沒有記錄網址、查詢內容或憑證。

250 的來源是 `b4b0a117`，IPA SHA-256 `95e6c3a95f392f6bbd9849a4fd2108ca9b3e0474468211258a71f70ae78a3e6c`，UUID `9CA54B84-FA3B-3741-9246-1A9104CC4A00`。第一次本機建置在 XcodeGen 取得使用者名稱時結束，尚未編譯；helper 改從目前 uid 設定 USER／LOGNAME，第二次 74.54 秒成功，沒有因此修改 App 程式。

| 後續實機案例 | 版本 | 實際結果與邊界 |
| --- | --- | --- |
| 手動記憶 → 真模型更新 → 重啟 | 249 | 同一記憶 ID 從茉莉茶改為咖啡，保留「不加糖」與中文關鍵字；沒有新增重複列。之後刪除本輪測試記憶 |
| 待確認做法 → 核准 → 中文回想 | 249 | 一筆待確認，核准後獨立讀取證明待確認清空、保存一筆做法；新對話真模型回想「先核對欄位，再輸出 CSV」。核准那輪最後 AX 讀取逾時，receipt 仍為失敗；後續狀態證據不改寫原結果，也不代表所有技能建立／檢索已驗完 |
| 真技能建立 → 重啟 → 中文搜尋／讀取 | 251 | 真模型保存一份 `ipad251-export-check`；重啟後技能列、全文與中文別名存在，待確認沒有重複項。全新對話只給「文件匯出驗收」中文名稱，實際進入檢視技能步驟，按序回答兩個測試步驟；App 記錄試用轉正式。已刪除自己的測試技能，待確認仍空。只證明精確中文別名檢索，不代表任意語意改寫都能找回 |
| 自訂搜尋／歷史重啟、內嵌 PDF | 249／250 | 搜尋設定與歷史實機重啟後仍在；W3C PDF 真實顯示。這是內嵌閱讀，產品仍明確拒絕瀏覽器下載，不宣稱已完成下載功能 |
| Wi-Fi 斷線 → 同對話恢復 | 250 | Wi-Fi 與行動網路皆關閉時，真模型請求顯示網路連線失敗；恢復 Wi-Fi 後重新提交的請求正常回答 `5`。沒有盲重送；不是靜默伺服器逾時測試 |
| 減少透明度、深／淺色與鍵盤 | 250 | 系統值確認 0→1→0；中文草稿、按鈕與既有錯誤提示可讀。早期只點到標籤、開關仍為 0 的操作不算通過；串流／各種附件全部組合仍未覆蓋 |
| 最大輔助字體 | 250→251 | 250 對話固定字級、輸入框與錯誤提示會放大，差異已重現。251 中文對話、表格、程式碼隨字體放大；系統 slider 實測 100%，輸入→送出→真模型「大字體成功」→收鍵盤，28.3 秒完整通過 |

字體修補 `e7fd5dcd9def2149b1a307918c4dbeb8925e4ba5` 使用 SwiftUI `ScaledMetric`，保留一般字體大小及表格水平捲動。251 MacBook Release 建置 53.22 秒、exit 0、來源前後相同，9 個 framework 與 App 簽章驗證通過；IPA SHA-256 `3b62cb54f457a604e0190c610fa46ea587768ddfbc3c1242986032c87a2fbb33`，UUID `6AB5D803-8F03-338E-9F15-D56AACC566E7`，安裝後版本回讀為 251。編譯與實機目標回歸已做，未將舊單元／官方 CI 結果套到此新提交。250 最大字體的自動化曾在 152 秒逾時，獨立 CPU 取樣當時為 0%；未證明唯一根因，不能把字體修補說成解決該逾時或原 iPhone A31 卡死。

251 後已還原原深色、一般字級 slider 50%、更大輔助字體關閉、減少透明度關閉及 Wi-Fi 連線；兩個暫停建置用測試容器均已恢復。版本、原始 UI receipt／AX／畫面與未通過結果見 `ipad-250-commercial-partial-results.json`、`ipad-251-commercial-partial-results.json`。

仍需完成：Android 實機文件／SAF／分享完整流程、完整 VoiceOver 與全部附件／串流外觀組合、相機實拍及相簿選取、低儲存空間與外部文件提供者、外部接收端可讀性、多供應商／靜默逾時／登入跳轉、技能任意語意改寫與其餘生命週期、原 MCP 工具錯誤及舊 iPhone 卡死。iPad 的 MCP 伺服器清單為空，需要使用者在 App 內設定既有授權連線，不能憑空補憑證或把新機的結果當原 iPhone 回歸。iPad 沒有已安裝的 Numbers／Books 可供接收端對照；CSV 仍需目標試算表驗證中文、公式防護、日期與前導零的實際呈現。Android USB ADB 現已可讀，但當下另一工作區正在使用同一套件；本輪沒有覆蓋其安裝，也未新增 Android 實機通過宣稱。

清理以本輪建立的精確 ID／路徑為界：已經由 App UI 刪除 11 個獨立測試對話（包含最後的技能建立與檢索兩個對話），前後 AX 清單核對，原清單中的其他 13 個對話 ID 都保留；捲動清單另露出 3 個既有對話，不能要求整份可見清單完全相等。兩筆測試記憶、一份測試技能與自訂搜尋引擎已刪除；5 個測試 Documents 檔案、7 個本輪產檔暫存目錄已移除，Documents 原有 9 個項目保留。Mac 端的驗收檔案／雜湊／畫面保留。原購物對話內誤加入的兩筆短文件測試訊息，以及 Google／PDF 測試瀏覽歷史仍在：介面沒有單筆刪除入口，因此沒有為清理測試而刪掉原對話或清空原歷史。精確清理證據為 `ipad-owned-files-cleanup.json`、`ipad-own-conversation-cleanup-verification.json`。

本輪不操作原 iPhone 對話或附件，也不修改原工作區的 `UserProfileChatFlow.swift` 與 `UserProfileChatFlowTests.swift` 未提交內容。

## 2026-11-22 文件錯誤處理與預覽修補

此批變更在已發佈的271之後整合，**不包含於271**。受測來源為 `9f62a017a964968ca42d39950bfb41e3346f9088` 加九份文件相關修改；精確檔案SHA見外部 `native-289-document-followup-source-before.json`，manifest SHA256 `1ffa1cb6dc1de6d33bb930b1c7e57161de2a01bd6f2ad1456c3dcc94ad5568b8`。前後manifest完全相同，原回尾／分頁修補未被覆寫。

修補涵蓋：無效來源的說明不因切換格式或改標題而消失；取消解析可在同一狀態重試，舊解析結果不能覆蓋較新的結果；CSV預覽於64KiB截點退至完整UTF-8字元邊界，完整儲存／分享資料不截斷；100MiB邏輯暫存額度改用獨立錯誤，與真正Cocoa／POSIX磁碟空間不足分開。100MiB、24小時、使用中檔案保護及到期清理時機均未更動，沒有新增套件。

原生 `native-289-document-followup` 在既有iPhone17／iOS27 Simulator執行，**40/40 PASS，failure0、skip0，外層466.34秒、exit0**：

| 範圍 | 實際執行與界線 |
| --- | --- |
| 文件核心24項 | parser／HTML／CSV／公式保護／資料上限與雙平台共同fixture；不是商用模型結果 |
| 原生匯出整合13項 | 含新增8項：真parser取消及可控交錯、無效來源終態、UTF-8邊界、完整輸出bytes、實際暫存IO／配額恢復、錯誤domain及雙語文案；另保留中文跨頁PDF等既有案 |
| 實際UI三項 | 本機PDF匯出；無效來源格式／標題變動後說明仍存在，關閉後第二個有效來源可產CSV；CSV預覽／儲存取消及靜態HTML腳本文字不執行。模型回覆為隔離fixture |

Python資源／精確scope檢查另有15/15 PASS；inventory144是登錄數，不是此次執行144案。單元、整合、UI分開計，不把合成資料或Simulator列為實機商用驗收。

證據根目錄仍為 `Documents/WOOWTECH-iOS-validation/documents-20261120`：`Documents-289-document-followup.xcresult`、`native-289-summary.json`、同名wrapper／log／source／容器恢復收據；`testflight-20261122/document-followup-native289-evidence.json`彙整bytes與SHA。`native-289-chinese-pdf/`保留實際PDF與文字擷取，`native-289-document-images/`保留畫面。已目視核對有效來源的CSV產生畫面；無效來源改標題時的截圖有鍵盤遮住較下方說明，錯誤持續存在的證據來自AX／disabled／未產檔斷言，**不主張該截圖已完整顯示錯誤**。

**警告尚未定位**：PDF預覽開啟時出現一次 `Publishing changes from within view updates`；全部UI結束後的hosted App啟動出現一次 `ChatTranscriptViewportPreferenceKey` 每frame多次更新。測試PASS不消除這兩個警告，也未證明來源是PDFKit、新狀態物件或原A31故障。一次受控Simulator取樣超過15秒上限而中止，沒有完整profile，保留失敗不作根因結論。

配額案以隔離sparse file測真100MiB邏輯用量及到期恢復，沒有填滿實機磁碟。外部接收App、實機ENOSPC、外部文件提供者、實際分享生命週期及SwiftUI快速關閉／重開時的取消行為仍須各別驗收。後續TestFlight與原iPhone結果分別見[271發佈紀錄](TESTFLIGHT_271_RELEASE.md)及[驗收缺口](ACCEPTANCE_GAPS_20261122.md)。

### Android 對應修補與限定驗證（2026-11-22）

Android同步修正兩個來源可證的問題：來源解析錯誤在切換格式／修改無關標題後仍保留，編輯來源後可重試；生成CSV的64KiB預覽退至完整UTF-8字元邊界，完整匯出／儲存／分享資料不截斷。可由標題修復的標題驗證及總bytes限制仍允許重驗；格式相關writer錯誤不被固化成來源錯誤。保留Android可編輯來源的既有流程，未宣稱兩平台UI完全對齊。

`android-290-document-followup` 的真JUnit XML確認 **8/8 PASS，failure0、error0、skip0**：`DocumentExportSessionTest` 6項（3個新測試＋3個舊回歸），`DocumentCsvPreviewTextTest` 2項新測試，共 **5新＋3舊**。新測試涵蓋錯誤保留及正確失效、可修復的標題／總bytes限制、writer錯誤分類，以及真CSV writer輸出的2／3／4-byte字元截點、cap+1讀取與完整bytes保留；舊案覆蓋畸形表格修正重試、多表選擇及產生中禁止編輯。單元測試使用upstream debug；Apporo與WOOWTECH兩品牌Kotlin編譯成功。整個序列48.65秒、exit0，source前後一致。

受測來源為 `9f62a017a964968ca42d39950bfb41e3346f9088` 加當時未提交修改；精確身份見證據根目錄的 `android-290-document-followup-source-before.json`／`-source-after.json`，兩者SHA256同為 `daa35ed8c4e2c36e9ffc1f6318a1d3022a224f5d1692dd8718ab5a3bcef7aaeb`。原始JUnit XML及彙整收據位於 `testflight-20261122/android-document-followup-candidate/execution290/`；`result.json` SHA256為 `925a86b99c357a46145cac7d3e0ba5a66da13640da94c46853aa45ddf18d01be`，其中列出兩份已核對XML的SHA256與完整case清單。

Android原有 **64MiB／32檔** logical cache與獨立`CacheFull`說明維持，與iOS的100MiB額度不同；取消仍重拋`CancellationException`，本批未引入iOS的初始化架構。**290只執行JVM單元測試與品牌編譯，沒有執行instrumentation或真機測試**；不能據此宣稱實際FileViewer畫面、SAF／外部分享接收、實體磁碟ENOSPC或完整UI驗收通過。

診斷追加：native291／292的單一PDF案例各1/1 PASS，警告仍出現，但擷取分別未建立target／附加失敗；293僅為隔離Simulator附加及安全卸離檢查。294實際附加成功，卻在PDF之前的chat.draft AX讀取逾時，0/1、exit1；只捕獲WebKit啟動及XCTAutomationSupport predicate兩個無關fault，已成功detach。此批診斷沒有取得目標警告的stack、沒有根據它修改runtime；完整失敗與界線見外部 `pdf-preview-warning-candidate/diagnostic-disposition.json`。不得把294併成40/40，亦不把原40案正常測試改寫為失敗。

## 2026-11-25 助理建立檔案（file_create）

owner 2026-11-25 決定：助理要能**建立** PDF、ZIP、Word（.docx）、Excel（.xlsx）、PowerPoint（.pptx）。實作在分支 `feature/ios-next-files-20261125`（基於送審中的 291 `103c596c`），**不在 291**。全部在裝置上原生產生，不移植 Android 在 App 內執行程式的 Linux 沙盒。瀏覽器下載同日恢復，規格見[瀏覽器下載](BROWSER_DOWNLOADS.md)。

### 格式與內容

| 格式 | 模型提供 | 產生方式 |
| --- | --- | --- |
| PDF | `markdown` | 沿用匯出的 `DocumentReport` 解析與 `DocumentPDFRenderer`；建立的 PDF 另畫斜體與程式碼字型（`Marks.boldItalicCode`），匯出仍只畫粗體，不改變既有匯出結果 |
| Word | `markdown` | `WordDocumentWriter`：標題、H1–H6（Word 內建樣式名，進導覽窗格）、段落與換行、粗體／斜體／程式碼、項目清單與每張各自從 1 起算的編號清單、表格（粗體標頭、跨頁重複、格線）、程式碼區塊；A4 |
| Excel | `sheets`：每張 `name` 與 `rows` | `SpreadsheetWriter`：數字寫成數字、文字寫成共用字串（`=1+1` 也是文字，不會成為公式）、`null` 為空格；第一列粗體並凍結；欄寬依內容；工作表名稱依 Excel 規則清理、去重 |
| PowerPoint | `slides`：每頁 `title` 與 `bullets` | `PresentationWriter`：固定的母片、「標題及內容」版面與佈景主題，16:9；字多的投影片自動縮小字級（Quick Look 不會像 PowerPoint 自動縮小） |
| ZIP | `entries`：每個 `name` 加 `text`，或 `file`（本對話先前建立的檔名） | `DocumentZipWriter`：本機標頭、中央目錄、CRC-32、Compression framework 的 raw deflate，壓不小就以 stored 存；UTF-8 檔名旗標；三種 Office 格式共用此寫入器 |

不放圖片與連結；多層清單、合併儲存格、公式、圖表不在本版。Mac 上的 Quick Look 對照後改了三處：每張編號清單各自一個定義（Quick Look 不讀重新起算的覆寫）、表格直接帶框線（Quick Look 不畫樣式的框線）、true／false 寫成文字 TRUE／FALSE（Quick Look 不顯示 Excel 布林格）。

### 工具與觸發

- 指令：`{"action":"file_create","arguments":{"format":…,"file_name":…,"title":可省略,…各格式內容}}`。說明文字在 `DocumentCreationPrompts`，要求使用者要檔案時一律用 file_create，不要把內容貼進回答；只有 ok 的結果才算建立；沒按存到檔案或分享前不能說已存或已寄出。
- 一般對話、記憶對話與 MCP 步驟都提供 file_create，跟技能工具同一套 JSON 指令機制（不是供應商原生 function calling）：技能工具步驟（`ChatSkillToolRun`）新增 App 自己的 host tool（`ChatHostTool`），Play 的技能工具名稱不變；`UserProfileChatFlow` 把 `file_create` 交給同一步驟；MCP 步驟的 host tools 加入 file_create。以 file_create 開頭的請求即使開著 MCP 也在技能工具步驟執行（MCP 步驟對單一指令有 4096 個 JSON 值、單一字串 128 KiB 的上限）。
- 參數錯誤以 `{"ok":false,"error":…,"message":…}` 回給模型修正，不會把原始 JSON 當成回答顯示給使用者。
- 固定句子辨識（`DocumentExportRequest`）、其單元測試與對應 UI 測試已移除；長按回答的「產生文件」照舊。

### 限制

| 項目 | 值 |
| --- | --- |
| 一個指令 | 256 KiB（與對話其他指令相同） |
| 檔案大小 | 16 MiB（與匯出相同）；PDF 最多 256 頁 |
| 檔名 | 1–120 字，清理後最多 80 個 Unicode 純量、240 UTF-8 位元組，去除路徑與保留字，副檔名依格式 |
| 標題 | 一行，最多 200 字 |
| Excel | 16 張工作表、每張 5,000 列、每列 64 格、全活頁簿 50,000 格、每格 32,767 字 |
| PowerPoint | 50 頁、每頁 12 點、每段 500 字 |
| ZIP | 32 個項目、壓縮前合計 64 MiB；同名自動加「(2)」 |
| 每個請求 | 最多 8 個檔案 |
| App 裡的建立檔案合計 | 100 MiB |

### 使用者確認

- 檔案先寫進 `Library/Caches/CreatedFiles/<UUID>/`，不備份、權限 0700、首次解鎖前受保護。回覆完成後，回覆下方出現檔案卡：Quick Look 縮圖、檔名、種類與大小，點卡片以 Quick Look 預覽。
- 只有按「存到檔案」（系統檔案面板，選好位置才算）或「分享」（系統分享面板，回報完成才算）檔案才離開 App；取消則不變。沒有任何自動儲存或傳送。
- 存到檔案或移除（×）後立即刪除 App 裡的副本，卡片顯示「已存到檔案，App 裡的副本已刪除」或「已移除，App 裡的副本已刪除」。分享完成後 30 秒刪除，卡片顯示「已分享，App 裡的副本稍後會刪除」；刪除時間先寫進檔案資料夾的 `.delete-after`，App 在這之前被系統結束時，下次啟動就刪除，卡片不會再出現。
- 卡片記錄所屬回覆，App 重新啟動後打開同一對話仍看得到（分享過的除外）；沒等到回覆的請求所建檔案在下次啟動刪除，已過刪除時間的分享檔不看 24 小時直接刪除，其餘建立檔案在建立一天後的下次啟動刪除；已被刪除的檔案點下去會顯示「這個檔案已經不在了」。

### 驗證與尚待確認

本機已執行（2026-11-25，`/usr/bin/lockf -k /tmp/woow-swiftc.lock`）：

- `check_document_creation.py`：以 Mac Catalyst 編譯 AssistantDocuments 與 App 的 `DocumentPDFRenderer.swift`（UIKit 在本機實際執行），Debug／Release 各 **100** 項 Swift 檢查、8 個樣本檔；`validate_created_files.py` 以 uv 執行 zipfile（逐項 CRC、檔名、stored／deflated）、ElementTree（每個 XML 部件格式正確）、python-docx、openpyxl、python-pptx、pypdf 開檔，各 **848** 項全過；另 iOS 17 typecheck 與 Swift 6 typecheck。樣本含中文、XML 特殊字元、CRLF、空內容、未配對記號與各上限。
- macOS Quick Look 實際產生四種格式縮圖並目視檢查（編號重起、表格框線、TRUE／FALSE、整頁投影片縮字後在頁內）。
- 既有檢查：`check_chat_skill_tools.py` 101、`check_profile_chat_app.py` Debug 978／Release 914、`check_task_notifications.py`、`check_ai_safety_and_reports.py`（12 個請求點）、`check_chat_attachment_reader.py`、`check_model_attachments.py` 全過；App target 對 iOS 17 SDK typecheck 通過。

沒有執行 xcodebuild、模擬器或真機，也沒有用真模型。完整建置後要確認：真模型在各種說法下會用 file_create（含記憶對話與開著 MCP）；卡片、縮圖、Quick Look、存到檔案與分享的完成／取消；30 秒刪除對分享接收端是否足夠；重啟後卡片回來；iPad 與大字體；Word、Excel、PowerPoint、Numbers、Pages、Keynote 實際開啟（本機只以 Python 函式庫與 Quick Look 驗證）。
