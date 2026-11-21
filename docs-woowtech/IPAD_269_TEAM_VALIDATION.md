# iPad 269／長歷史／MCP 團隊回歸（2026-11-21）

目前正式 iPad 已安裝 **269**。本輪修補與有限範圍的實機驗證已完成；**不是完整商用驗收，也未證明原 iPhone A31 故障已修復**。

## 版本、環境與證據位置

- 工作分支：`feature/documents-ios-android-20261120`。起始 `d83d4181`／正式版 267。
- `1f1b2a00b6ab4481a6033f0fbd9e6c320dfb4807`：長歷史分頁、MCP 分類與鍵盤工具列修補。
- `84e012a495ef65cecd6ae8f30ce524d93a266463`：長歷史頁不再顯示會蓋住回覆的重複浮動按鈕；補上較舊頁面送出被阻擋的回歸。
- `b81ff349981fb9c4807aa3c09282e9ebe6427df0`：僅修正 MCP UI 測試的 Return／Done 操作順序；269 建置來源。相較前一提交，正式 runtime 未變。
- MacBook 本機 Xcode 27／SDK 27；iPad 9、iPadOS 26.6.1。原生 UI 使用本案獨立 iPhone 17／iOS 27 模擬器。
- 原始證據根目錄（以下簡稱 R）：`/Users/woowtech/Documents/WOOWTECH-iOS-validation/documents-20261120`。保留日誌、source-before/after SHA、xcresult、截圖、堆疊及已簽章 IPA；未把秘密或業務工具資料加入提交。
- 所有重型執行經既有 `heavy.sh` 序列化；本輪兩次裝置建置、274／275 與最後檢查皆 `source_changed_during_command=false`。只暫停授權的兩個測試容器，完成後恢復。

正式 269：本機 Release 建置 120.29 秒，簽章驗證成功，覆蓋安裝後回讀 bundle version 269。IPA SHA-256：`a906a663b58c57760a7878acb4a195c44232a82e2165e260551b228e69ed671a`；binary SHA-256：`b3b0122f11d08655640ef1440e535de145fba2897e5734673ae894296aef6f95`；UUID `D2034017-C76E-32D8-9FD3-E4B8A960F048`。證據 `device-269-artifact.json`、`ipad-269-install.json`、`ipad-269-installed-version.json`。artifact 檔的 `installed:false` 是建置當下狀態，安裝結果以後兩份紀錄為準。

隔離 QA 269：相同來源、Release 最佳化但啟用 DEBUG 合成 fixture，獨立 `io.woowtech.assistant.perfqa` bundle／Keychain，不註冊正式版 URL schemes。建置 70.07 秒；IPA SHA-256 `27b45f8022345931da88d94ba9dcba73481f07666b5a09f435de5723021384ba`。未讀取或修改正式版對話；測完已移除此 QA App。

## 實作與原因

### 長歷史

原 999 輪／1,998 訊息一次建立完整 SwiftUI／AX 樹，原生測試在查詢階段超過 300 秒；sample 主執行緒 107/107 在 XCTest／AX，其中 70 涉及 children 排序，當時 footprint 約 3.4 GiB。這證明該測試條件下的負荷，不能反推原 A31 的唯一起因或無自動化時也同樣 busy loop。

現在一次呈現最多 80 則訊息，使用原訊息索引與 ID；可切最早、較早、較新及最新頁。完整 session／加密存檔保留，頁面切換不累加節點。幾何回報帶 conversation／page revision，舊頁回報不能改變新頁追隨狀態。閱讀較早頁會保留位置；接受送出或按最新才切回尾端。長歷史頁頂端已有「最新訊息」，移除重複的浮動按鈕以免遮住回覆。

此處只限制呈現，不增加模型上下文：既有 32 則／64 KiB 傳送政策未變。原本 1,000 輪存檔上限亦未變；超過上限顯示未保存提示，保留原存檔，不假裝第 1,001 輪已持久化。較舊頁面沒有模型時，阻擋提示必須在輸入區可見並能前往設定，不藏在未呈現的最新訊息卡。

### MCP

Host 產生安全的 category／數值 code／outcomeUnknown metadata，不從不可信工具文字猜分類。區分 HTTP、RPC、工具錯誤、傳輸／逾時／取消與協定錯誤；結果截短後 metadata 仍保留。工具回傳不能偽造 host 分類。未知結果或工具錯誤仍保留「變更是否套用未知」及不要盲重送的保護。

cached session 初始化亦檢查取消。結果 UI 說明只屬於本次送出、下次清除、不隨對話保存；舊 nil metadata 不補造分類。統計改為「嘗試呼叫／結果紀錄／異常」，不把本機產生的紀錄數當作服務端收到請求的次數。沒有新增 token、完整端點或工具 payload 日誌。

### 鍵盤與 SwiftUI 警告

受控 A/B：原鍵盤工具列有 3 次 Invalid-frame；只合併 ToolbarItem 仍有 3 次，已撤回。LLDB 比對實際 runtime UUID／指令後觀察到 SwiftUI InputAccessoryBar 傳入無限寬度，沒有任意 clamp App frame。改為共用隨焦點顯示的 Done 區：聊天放在既有底部容器，其餘表單用 safeAreaInset，保留原 Clear／導覽。按鈕至少 44 pt，支援動態字級與減少透明度。

## 原生執行結果（不可當外部商用實測）

| 執行／來源 | 實際結果 | 範圍與限制 |
| --- | --- | --- |
| native-268-team-first／當時來源快照 | 9 PASS、1 FAIL | MCP 對照通過；無分頁的 999 輪 AX 查詢超過 300 秒。 |
| native-268-warning／當時來源快照 | 1 FAIL | 診斷 setup 的 memory toggle 未通過，未執行到串流；保留失敗。 |
| native-272-team-window／來源快照 | 8 PASS、2 FAIL | 一項千分位測試預期不符；一項 HTTP fixture 只送標頭導致 timeout，尚未到大小拒收。 |
| native-273-keyboard-page／來源快照 | 7 PASS、0 skip，715.99 秒 | 999／1000 輪、附件面板、一般／XXXL Done、串流、大小拒收。fixture 加一主體位元組後大小拒收 29ms；正式 5 秒期限未改。 |
| native-274-forms-and-results／84e012a4 | 13 PASS、1 FAIL、0 skip，934.04 秒 | 五個 TCP/HTTP MCP、兩個 MCP UI、附件邊界、999 舊頁阻擋提示、四個表單通過；MCP 表單測試先按 Return 收鍵盤又要求鍵盤存在而失敗。 |
| native-275-long-history-delay／b81ff349 | 2 PASS、0 FAIL、0 skip，331.75 秒 | 1000 上限／保存案 111.974 秒；MCP 表單 137.042 秒，三處 Done、HTTPS/token 驗證及重啟 Keychain 保存皆通過。僅重跑必要兩項。 |
| final-policy-and-resources／b81ff349 | PASS，6.36 秒 | 1,070 keys／2 語系產物一致；11 項資源測試、3 項捲動規則／mutation checks。非 UI／商用結果。 |

273、274、275 各自完整 App stderr 的 Invalid-frame 都為 0，行數分別約 212 萬、249 萬、72.7 萬；xcresult runtimeWarnings 亦為 0。未關閉日誌來取得此結果。275 原始 stderr 另保留可回解、已核 SHA 的 gzip。273 初版 teardown 的 `succeeded:false` 與附件名稱是測試當下狀態讀取問題；最後兩個長歷史判定依 xcresult PASS，未改寫原始失敗樣貌。

MCP TCP/HTTP 是真本機 loopback，包括 HTTP／RPC／toolError、期限、斷線、取消、後續唯讀恢復、不重送及分類不能被工具內容覆寫；另有 URLProtocol session tests。全部都不能代替真 Apporo 服務的歷史兩筆錯誤。證據 `team-mcp-diagnostics-20261121/FINAL-COMBINED-MCP-HANDOFF.txt`。

275 本次輸入 1.134 秒、送出至 fixture 回覆 9.118 秒、cold launch 12.643 秒，未重現 273 輸入 47.214 秒或 274 cold launch 52.961 秒。兩次在 active phase 開始的 3 秒採樣，seed 23/28 主執行緒樣本為 XCTest／AX，reopen 106/203 等待、68/203 XCTest／AX。這些短樣本含剖析擾動，且命令結束含符號處理，不能等同精準 CPU 比例，也沒有確立之前間歇延遲或 A31 根因。詳見 `team-long-history-20261121/native275-delay-analysis.txt`。

## iPad 實測

- QA 268：999→1000 輪中文送出、重啟存檔保留；1000→1001 顯示未保存提示，重啟仍為原 1000 輪。保留早期自動化重啟黑畫面／半尺寸 AX 失敗：透過正常 terminate→Home→fresh launch 回復，未清存檔，沒有證明產品崩潰原因。999 立即截圖尚未穩定、回覆不在畫面內；後續穩定畫面才驗可見。1000 CPU 最初僅 33 samples、末值 64.53，不能當成回到 idle；監控缺 PID snapshot 不等於 App 退出。
- **QA 269**：沿用真正相同合成 1000 輪存檔，最早／最新、中文輸入→送出→可見回覆、收鍵盤、選單操作，27.7 秒通過。最新回覆完整在鍵盤上方，沒有重複浮動按鈕遮擋。90 秒監控 173 筆，其中 172 筆有效 CPU、1 筆 nil；峰值 100.625%，末 20 筆有效值最大 0.0212%，末值 0%。該窗 footprint 最大 141,182,872 bytes。這是該次合成實機流程的結果，非 A31 或無剖析的效能基準。證據 `ipad-269qa-safe-results.json`、CPU JSONL、`ipad-269qa-1000-cycle`。
- **正式 269**：既有模型實際回覆 `IPAD269完成。`，無 fixture；21.6 秒操作序列包含送出、顯示、收鍵盤及選單。未使用任何業務工具。深色直向、淺色直／橫向鍵盤、收鍵盤與附件選單皆有實際檢視的截圖；沒有把 AX 存在當作可見。
- 減少透明度已核系統 switch=1，穩定後 Done frame `(687,710,66,44)`；按鈕可操作。立即截圖曾落在鍵盤動畫中，另等 3 秒驗證穩定狀態。初次點到設定列／AssistiveTouch 未改 switch，這些序列不算啟用成功；`08-reduced-ui`／`10-reduced-verified` 目錄名稱只是原計畫條件，receipt 已明示 switch 未啟用。真正啟用證據是 `13-move-and-toggle`／`18-reduced-steady-setup`，畫面為 `14-reduced-on`／`19-reduced-steady`。
- 兩次自動化選錯 ID（`chat.new`、`drawer.tools`）失敗原樣保留，依實際元素改用 `chat.newConversation`、`navigation.tools` 後成功；不是產品功能通過紀錄。低階 HID drag 因裝置低於 iOS27 被工具拒絕，改用既有 XCTest drag，沒有重裝系統或要求新權限。
- 正式 269 工具頁仍明示「尚未設定 MCP／還沒有 MCP 伺服器」。頁面可用不能當作 Apporo 訂單查詢成功。

全部畫面摘要：`ipad-269-visual-evidence-index.json`；真模型紀錄：`ipad-269-03-real-model-corrected`；MCP 現況：`ipad-269-10-reduced-verified`。

## Android 對照及未完成項

另團隊 Play-channel runtime `c9fbb5d8`：POCO C85／Android15 已安裝 WOOWTECH `0.1.37-play.3 (3)`、Apporo `0.1.37-play.1 (1)`，實際讀取兩個 APK hash 與部署證據吻合；六份 QA HTML／PDF／CSV 儲存副本大小與 hash 也吻合。現有真機 instrumentation 為 WOOWTECH 13/14 後修 browser fixture 單項 1/1、Apporo 14/14，0 skip。未重新執行這些已過項。一般模型產檔／預覽／儲存，與合成分享檔被外部 test-process 讀取分開記錄，沒有對外聯絡人投遞。

本輪新增 Android 視覺導覽因畫面被其他操作者切至另一品牌 App／非空草稿而停止，沒有干擾其資料，也不宣稱兩平台新的外觀完整一致。證據 `team-android-comparison-20261121`。

針對 Android `c9fbb5d8` 的實際來源比較：iOS 是 80 則分頁，Android 是連續 LazyColumn，兩者導覽不同，不能據此評定效能高低。iOS 本次新增 category／code／outcomeUnknown metadata；Android MCP contract 的 text／isError／costUnits 尚無同等欄位或未知寫入提示，保存工具文字也不等於保存分類。iOS 聊天與 MCP 表單有顯式 Done，Android 聊天使用點外部／拖曳解除焦點；其 MCP dialog 沒有同樣的共用關閉機制，實際平台鍵盤行為仍需配對實測，不能由讀碼稱為缺陷。完整來源行號與 hash：`team-android-comparison-20261121/ios269-limited-parity/LIMITED-COMPARISON.txt`。

以下仍未商用驗收：

1. **原 iPhone A31**：該手機與原完整對話／附件目前不在這台 Mac 可用裝置內；需原手機接到這台 Mac 並解鎖，才能對原資料做輸入→送出→CPU／互動→唯讀 MCP 全鏈回歸。原資料未刪改。
2. **真 Apporo 兩筆 tool_errors／unknown**：這台 iPad 沒有 MCP 連線。需使用者在 App 內設定原有唯讀服務與有效授權（不要在對話貼 token），或提供可授權讀取的既有遮罩請求紀錄，才可對齊 request／server 證據。不得盲重送未知寫入。
3. **間歇長歷史延遲**：本次改善有 UI／實機證據，但舊 47／53 秒尖峰未完整歸因。原 A31 同縮圖／完整歷史對照仍缺原裝置。
4. **Android 新版同步視覺比較、實際接收端相容性、多供應商真網路斷線／逾時、登入跳轉下載與完整文件異常矩陣**：不由本輪 loopback、模型短答或舊測試直接宣稱完成。
5. **外接鍵盤、浮動／分離鍵盤切換**：共用 Done 的程式審查完成，本輪沒有實體鍵盤裝置驗證。最大字級原生測試通過，本輪正式 269 沒有重跑整套最大字級實機矩陣。

舊 BrowserSearch／MemoryTool 的既有回歸資料保留，未把本輪表單 PASS 重新包裝成那些舊 CI 間歇失敗的唯一根因。

## 清理與交接

升級前後、清理後皆核對原 16 個對話 ID 完全一致。只由 App 個別刪除本輪新建的 `IPAD269` 測試對話；移除本輪獨立 QA bundle。恢復深色、直向、減少透明度關，字級與粗體本輪未修改；AssistiveTouch 持續開啟，為操作開關暫移位置後復位。Mac 原始證據保留。紀錄 `ipad-269-final-restoration.json`、`ipad-269-21-final-state`、`ipad-269qa-uninstall.json`。

本輪由原三個代理分別接續長歷史、SwiftUI／表單、MCP／Android 證據；未重複派全套建置。沒有變更 session runner／model／workspace，沒有改動或搬走原 `/Users/elmolin` 的兩個 UserProfileChatFlow 未提交檔。
