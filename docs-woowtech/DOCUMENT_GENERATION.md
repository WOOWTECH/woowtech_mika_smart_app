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

2026-11-21 實機已從 248 升級到 **0.1.0 (249)**，USB iPad 第 9 代／iPadOS 26.6.1，未卸載、重置或清除原資料。使用者完成 XCTest 授權後，已執行真實 UI 與已設定模型的請求，未使用模型 fixture。先前 Touch ID 阻礙已解除；`ipad-04` 起的操作紀錄可證，不應再以舊阻礙回報等待。

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

仍需完成：Android 實機文件／SAF／分享完整流程、iPad 大字體／降低透明度、相機實拍及相簿選取、低儲存空間與外部文件提供者、外部接收端可讀性、多供應商與網路中斷／逾時、原 MCP 錯誤與舊 iPhone 卡死。iPad 沒有已安裝的 Numbers／Books 可供接收端對照；CSV 仍需目標試算表驗證中文、公式防護、日期與前導零的實際呈現。

本輪不操作原 iPhone 對話或附件，也不修改原工作區的 `UserProfileChatFlow.swift` 與 `UserProfileChatFlowTests.swift` 未提交內容。
