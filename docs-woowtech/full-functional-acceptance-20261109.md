# 全功能驗收工作表（進行中）

範圍：渥屋助理目前版本公開功能、POCO C85 / Android 15、同機與 Mika 並存。依功能驗收，不以對話數量當完成條件。跨裝置、跨模型、外部服務及真人感官結果另列證據，不能以單元測試代替實機通過。

## 狀態與原則

- 原 50 案與證據：[基線報告](qa50-poco-20261109.md)。本輪修正版尚未完成驗收，不能沿用基線通過數宣稱全功能通過。
- 每項分別記錄程式回歸、實機正常路徑、錯誤恢復及尚缺條件。
- 不以關閉 Play Protect、取消確認關卡、刪掉功能或跳過失敗測試達成「全過」。
- 所有測試只處理明確標記的合成資料；真實付款與對外訊息需具體對象及授權。
- 私人證據目錄：`~/.local/share/woowtech-mika/test-evidence/full-functional-20261109/`。

## 最新驗收摘要（2026-11-10，仍未全數通過）

- 真實 POCO 已完成 F01–F28 中有證據的正常／錯誤路徑；逐案限制見下文。2026-11-10已透過MCP操作Chrome下載候選版、ADB保留資料安裝；安裝後雜湊核對、50筆任務保存及受控鎖屏／MCP解鎖通過。
- 完整核心最近一輪 2969 項，0 失敗、3 略過；Android JVM 1502 項全過。之後新增滾輪回歸，相關核心42項全過，Android JVM1502項再次全過；全核心數字仍是新增2案之前的完整執行結果。
- 儀器逐案最新收集結果 587 通過、11 項前提不符、1 項人工解鎖程序未執行。另保留 1 個舊執行器類別參數錯誤及 1 個已拆分案例，不計為通過。這是跨批次最新案例彙整，不是單次全套執行，也不是所有產品功能覆蓋率。
- final-v5 的滾輪4項、設定連結、任務服務可執行案例、確認通知5項通過。滾輪0→40維持20–24次門檻；最初整組319.174秒，補正模數距離為零卻仍步進的問題後，最新整組39.68秒全過；不存在值單案12.493秒（含測試前置），不強迫到達錯值。
- 強制終止恢復已由主機實際執行兩階段測試：建立雙任務檢查點→force-stop→重新啟動驗證音訊／虛擬螢幕恢復→刪除恢復紀錄。第二階段9.392秒通過；第一階段Process crashed是主機刻意終止，不能誤報產品崩潰。
- `instrumentation-latest.csv` 與各組原始日誌保留所有前次失敗；以最後一次針對相同案例的結果判定，略過不當通過。

### 尚不能宣告通過的驗收項目

| 項目 | 缺少的證據或條件 |
|---|---|
| GitHub APK 一般安裝 / Play Protect | 使用者已明確排除本輪驗收；未修復、不列通過 |
| 最新候選版 POCO 完整流程 | 已更新並驗證資料保留、MCP任務、檔案分享、真人語音；其餘按項驗收 |
| 實機語音與通知聲音 | 新版真人語音回填、取消後追加、手動送出及回覆已通過；通知聲音正在獨立驗收 |
| 鎖屏喚醒與解鎖 | 已完成受控循環，系統鎖定狀態獨立確認，期間無實體觸控事件；不代表外網喚醒 |
| 遠端外網中繼、實體重啟恢復 | 本地回歸不能代替外網服務與實體重啟 |
| 新模型／網站帳號登入 | 現有帳號流程可保留；新增登入需測試帳號及驗證步驟 |
| Root、分身與特定系統能力 | 當前非Root／無分身；硬連結建立經實測被系統拒絕，相關案例前提不成立 |
| 長時間穩定性與慢速錯誤路徑 | 滾輪慢速錯誤路徑已改善並重測；長時間背景與偶發時序問題仍須實機穩定性補驗 |
| 實際付款／對外訊息 | 已驗證確認關卡與舊通知隔離；尚無具體測試交易／收件目標，未執行真實交易 |

## 起始功能追蹤（後續結果以最新摘要及逐次紀錄為準）

| 功能 | 基線／本輪狀態 | 尚須完成的驗收 |
|---|---|---|
| 安裝、簽章、保留資料更新 | 基線 ADB 覆蓋通過；Files 安裝被 Play Protect 擋 | 修正版簽章與資料保留；一般下載安裝需解除分類後重測 |
| 無障礙與手機助手 | 基線 POCO 可用 | 更新、背景、重開機後恢復；引導入口 |
| App 身分與兩品牌並存 | 基線誤開 Mika | 已加入實際套件提示；待修正版實測 |
| 純文字、格式、計算、翻譯 | 基線通過 | 修正版抽驗與整套回歸 |
| 對話歷史、追問、插話、取消 | 基線早期控制通過 | 長工具執行、錯誤與恢復、背景切回 |
| 語音輸入 | 基線真人流程通過 | 修正版、取消／追加／重試、真人確認 |
| 記憶新增、搜尋、刪除、撤銷 | F05/F06 新增、搜尋、限定刪除及其他資料保留實機通過；撤銷核心回歸通過 | 撤銷 UI 正常路徑補驗 |
| 個人技能與知識 | F11–F13 建立、讀取套用、停用隔離與 UI 刪除通過 | 匯入、修改版本、知識／技能成效追蹤 |
| 排程與條件任務 | 遠端 API 刻意不提供排程工具 | 手機 UI 建立、暫停、恢復、觸發、清理；條件為真／假 |
| 通知與聲音 | 未完整實測 | 實際提醒、通知入口、分類設定、切語言、真人聲音確認 |
| 手機啟動與恢復 | 基線有重複讀屏 | 已補失敗恢復提示；重跑錯誤前景情境 |
| 點選、輸入、捲動、計算機 | 基線部分通過 | 修正版正常路徑與不存在元素 |
| 虛擬螢幕、並行與 App 互斥 | 未完整實測 | 不同 App 並行、同 App 等待、取消釋放 |
| 浮動膠囊、接管、目前畫面 | 未完整實測 | 顯示、暫停／恢復、截圖詢問、權限拒絕 |
| 內建瀏覽器 | 表單、分頁、上傳、靜態／動態 Blob 下載、分享及實際內容比對通過 | 來源卡、錯誤恢復、接管；儀器整套仍執行中 |
| 網站登入與模型登入 | 使用現有設定 | 不動既有登入；登入新增需對應測試帳號與使用者完成驗證 |
| 附件、圖片、PDF | F19 真實選檔、拒絕照片權限、PDF/CSV/圖片解析及來源通過 | 遺失與格式錯誤恢復補驗 |
| 沙箱、程式與檔案 | 基線通過 | 工作區隔離、長命令取消、離線限制、成果保留與清理 |
| 來源、過程與用量 | F19 開來源、過程、匯出用量及UI總數核對通過 | 詳細Trace為debug功能，release另按限制驗證 |
| USB、Wi-Fi、CLI、MCP | USB/Wi-Fi任務、MCP握手／工具、CLI、錯誤權杖、邏輯重連通過 | 實體重啟後恢復補驗 |
| 遠端中繼與喚醒 | 未完整實測 | 本地整合回歸與實際服務連線；不可把模擬測試當外網通過 |
| 語言、主題與設定保存 | 中英／外觀切換、覆蓋更新持久化、通知分類使用者設定保留通過 | 長時間背景與其他設定補驗 |
| 模型斷線、重試與串流 | 未完整實測 | 回歸測試、具體斷線路徑與成果保留 |
| 付款、對外傳送確認 | 僅草稿界線測過 | 可用測試目標驗證關卡；實際交易須另有具體授權 |
| Root 附加能力 | 本機非 Root，未驗證 | 核心權限回歸；Root 實機需要相應裝置，不算通過 |

## 本輪發現與變更

### 記憶管理

新增 `memory_forget`：指定搜尋所得 ID 與完整內容，內容已變更時不刪除；引文須來自當次使用者訊息。只動自己的單筆記憶，可使用既有撤銷機制，唯讀／子任務／無人值守執行不提供此寫入工具。刪除任務不再自動重新提取記憶，既有對話提示隨刪除清理。

任務身分提示帶入真實執行套件，避免將 Mika 與渥屋的記憶或設定混為一談。仍保留禁止操作自身 App 畫面的既有防護，透過專用記憶工具完成授權工作。

### 啟動後錯誤前景

補充 `phone_launch_app` 提示：啟動失敗且前景仍是別的 App 時，不反覆交替觀察與列元素；依錯誤採一次合理恢復，仍失敗則回報障礙。此為提示修正，必須實機重跑才可判定改善。

### 排程入口

F01 經 USB API 回報沒有 schedule_task，核對 TaskRun 的排程配置僅給 RunOrigin.Ui。未建立任何排程。後續改從手機對話送出 FQA-SCHEDULE，驗證實際產品入口。

## 外部依賴

Play Protect 複核草稿已備妥；已向使用者詢問公開 APK 上傳 VirusTotal 及向 Google 送件的授權／聯絡信箱，尚待回覆。即使送件，分類改判仍須外部結果及相同 APK 實機重驗，不能預先列通過。

## 回歸與實機補驗進度

- 核心 2,968 項：0 失敗、3 略過（兩項紀錄重評工具需指定資料；一項 USB helper hangup 測試要求 Linux 主機）。Android JVM 1,501 項全部通過。
- 新工具造成清單／提示快照變動，已核對並更新，沒有移除既有斷言。
- 補齊七種其他語系缺少的安裝引導／語音錯誤文案與刪除記憶標籤；資源一致性測試通過，尚未真人審校所有翻譯。
- `9d46d758` 正式簽章 release 與 lint 成功並已保留資料覆蓋安裝。APK SHA-256：5a0e9836b4ed0b641c1a2d7ba949e499a6fed694ad05e036e72660c4623f3f7f。
- F02 從手機 UI 建立、暫停與恢復排程。16:04:47 尚無精確提醒通知，16:05:05 已有獨立提醒，對話亦有固定提醒結果；App 在背景。聲音待真人確認。觸發後排程自動移除，後續列出為空；這不代替尚未觸發排程的刪除測試。
- F03 瀏覽器表單／新分頁／切回通過，伺服器收到 Submitted FQA-Iris quantity 7，第二分頁 token 正確。
- F04 HTTP 本機檔案下載被 blocked_address 拒絕，維持既有私有位址防護，改以 Blob 下載測試正常路徑。上傳連續 ref_expired，沒有上傳成功。
- 上傳根因：Upload 未套用穩定編號到 WebPort 編號的轉換。新增回歸先重現失敗，再補 withPortRef；相關工具／編號／風險測試通過。修正提交 `982111e0`，等待實機重驗。
- F05 在修正版實測新增 DELETE 與 KEEP 兩筆，只刪 DELETE；手機記憶頁獨立確認只剩 KEEP。F06 以新工具清理 KEEP 並搜尋兩筆皆不存在，沒有操作 Mika。
- 中英通知分類：系統設定中手動把 task_result_v2 震動由 false 改為 true；切英文後，五個分類名稱均更新，除名稱以外所有欄位與手動修改後完全一致。待切回原語言與恢復震動。
- 模擬器正在執行 326 項介面／瀏覽器儀器測試，不能提前列通過。

### 16:40 補驗紀錄（仍在進行）

- `982111e0` 正式簽章 APK 已覆蓋安裝；SHA-256 `76134c0228127b455425231fec9ca79210c506eb10c7a37693c89112f182e7e0`。仍是本機驗收版，尚未發布 GitHub。
- F07 上傳實機成功，伺服器獨立收到 `UPLOAD upload.txt: FQA-UPLOAD-824`。
- F08 靜態 Blob 下載、F10 動態 Blob 下載均已下載／讀取／分享，從手機 Download 取回後逐位元組等於 `FQA-DOWNLOAD-713\n`（17 bytes）。F07/F09 的動態下載失敗是測試頁 inline handler 中 URL 被解析為 document.URL；伺服器記錄 TypeError，改明確 window.URL 後通過，未改 App 下載防護。
- 通知分類手動改震動後，切英文、覆蓋更新、切回跟隨系統，五分類除名稱外完全一致。語言與外觀已恢復跟隨系統、震動已恢復 false；只有 Android 的 userLockedFields 留下使用者操作標記，沒有刪除分類消除此紀錄。
- F11 個人技能儲存與讀回、F12 讀取套用排序去重、F13 停用後搜尋與讀取不可用均通過。手機 UI 已恢復後刪除唯一測試技能，列表確認空；未動其他技能。試用成效計數未因此宣稱驗證通過。
- MCP initialize／initialized／tools/list／mika_list_tasks 均成功；不存在工具回 JSON-RPC 錯誤。缺少與錯誤權杖均 HTTP 401。CLI doctor 回 connection ok、helper_available/user_unlocked/ready true；模型配置仍標 unverified。
- 模擬器 WebFilesTest 7 項全過。ChatScreenDeviceTest 補齊首次導覽前置後，檔案卡開啟、附件入口、並行對話切換三項通過；任務流程尚有語音入口文案斷言待重驗。
- ChatScreen 非同步 Toast 明確切 Main 執行緒，分支兩案例已不再出現 Looper 錯誤。
- 整套 47 組介面／瀏覽器儀器測試改逐組執行保留結果；若干組仍發生 Compose measure/layout 時序錯誤，正在驗證測試 dispatcher，尚未列全過。

### 後續驗收進度

- F14 實際長命令取消：先確認 libmikarun/proot/sh 三個程序存在，取消 API 202 後原 PID 均消失。F15 進度檔兩次相隔五秒皆 252 bytes、最後 tick 85、沒有 DONE。F15 結束標為 failed 是測試操作誤把下一個排程提示插入這個遠端任務；檔案讀回結果保留，沒有把它當作完整成功任務。
- F16 重新由 UI 新對話送排程，建立 11/16、改到 11/17、刪除；排程頁獨立確認進行中 0／已停用 0，截圖階層已保存。
- F17 條件算術任務均未執行：模型額外要求沙箱算術命令，但條件階段只有唯讀工具。補強 schedule_task 提示不把命令／腳本／寫入列為條件前置；ScheduleTaskTest 明確驗證可讀／搜尋檔案，不能 run_command/run_bundled_script/write_file/share_file。F18 以實際檔案條件重測中。
- CLI 56 項回歸全過。Wi-Fi 能連到同機服務，但 USB 專用權杖 HTTP 401；程式確認 loopbackToken 刻意僅供回環，這是預期隔離，Wi-Fi 正常權杖路徑尚待測。
- Compose 布局錯誤定位到測試清理協程時 Activity 尚未關閉。先關閉 Activity 後 BrowserScreenTest 10/10 通過，套用共通 CloseComposeActivity 內層規則；新的逐組回歸截至目前 About/AccessibilityInstallHelp/AgentPipCorner/AgentPipWebFrame/AppAccess/BackgroundLandscapePreview/Browser/ChatAttachments/ChatDeleteAndSelect 全組通過。不能據此宣稱剩餘組通過。
- 模型設定頁原測試同案呼叫兩次 setContent，拆成兩個案例保留兩側斷言；待新版測試 APK 重跑。

### 17:20 後補驗

- F18 檔案條件：同一檔案 price=100，A 條件 price=100 成立並交付 FQA-FILE-TRUE-713；B 條件 price=50 不成立，沒有交付 FQA-FILE-FALSE-824。實際 read_file 結果、兩次條件判斷、通知與對話均有證據。
- Wi-Fi 使用正常權杖後 CLI doctor 成功，實際任務精確回覆 FQA-WIFI-713；測試用權杖檔已刪除。USB forward 移除時拒絕連線，恢復後 HTTP 200；這是邏輯連線恢復，不是實體拔插或重開機。
- F19 經 Android 文件選擇器選取三個合成附件，拒絕照片全面存取後仍能使用指定檔案。PDF 品項 7×17=119、CSV 兩筆合計152、圖片標題與3個藍方塊／2個橘圓皆答對。來源卡與執行過程可開啟。
- F19 用量匯出到 Download，取回 JSONL 10列均可解析。7次任務模型回覆共107052 Token，符合畫面10.7萬；全部呼叫摘要另含意圖判斷，為8次呼叫。不能把逐次紀錄與摘要重複加總。
- F20 不存在設定項目重測40.5秒結束，只搜尋一次，沒有反覆讀取。此回啟動設定成功，尚未重現原啟動失敗分支。
- 持續變動網頁點擊耗時測試單獨重跑仍失敗（3731ms，門檻3500ms），保留失敗，正在拆解點擊與等待耗時。

### 撤銷與儀器補驗

- F21/F22 遠端任務新增與刪除 FQA-UNDO-935 成功，但遠端來源不執行 learnAfter，沒有結果卡撤銷入口；未把它算作 UI 撤銷通過。F23 改用手機 UI 新增後刪除 FQA-UNDO-946，背景整理完成後出現撤銷；點刪除的撤銷恢復完整內容，再點新增的撤銷清除。獨立記憶頁確認空，相關階層存檔。
- 連線設定、模型設定21案、時間軸、PageScript、完整 WebStack 接管、FileViewer 重跑通過。RunTrace 返回路徑補上「高級與其他」後主案例通過；release 專屬案例在 debug 依條件略過。
- SteerEditing UI 測試缺少主模型設定；補上僅在尚無模型時使用的本地合成配置，測後刪除。撤回、編輯引用、遠端插話不可編輯三案均已跑過且成功。
- 網頁耗時拆解：開始4815038，等待開始4815734，等待結束4818783，操作結束4819171毫秒。3秒上限屬DOM等待，不含之前696ms與之後388ms。改以 waitStable 驗證3500ms門檻，真實點擊仍以10秒整體上限驗證成功與可讀畫面；另補 withTimeoutOrNull 使慢 JavaScript 回應也受等待上限限制，尚待新APK重跑。

### 最新回歸狀態

- WebActionsTest 在加入等待截止保護後18項全數通過。上一批合併重跑16項只有修正前的耗時斷言失敗；RunTrace 主案例、SteerEditing三案、WebTakeover十案全部成功，release 專屬Trace案例略過。
- 完整核心2969項，1項快照大小失敗、3略過；差異僅 schedule_task 補充329 bytes（44247→44576），已核對更新並另跑提示／排程／等待策略回歸。不能將這次全套原始失敗抹除。
- 原介面／瀏覽器清單48組之外，再盤點出55組儀器測試；LiveRun/Eval需指定真實評測配置，另外53組納入擴充測試，包含沙箱、手機控制、虛擬螢幕、確認、任務恢復。進行中，未提前列通過。
- F17 UI 顯示其中一筆為「檢查失敗」，另筆為「條件未變化」；兩筆皆未交付目標。F18 的假條件排程也保留為已停用，並非所有一次性排程均自動移除。已開始逐筆刪除這三筆合成排程。

### 新版覆蓋安裝

- 提交 f211ac60，正式憑證SHA-256仍為806b3db808ecbb4d2d032b34624baa7e193802f17a07afbde2a03e78da9474c8。APK SHA-256為95fe1e719144cf95ab1b5d3520e50f58784740f967cd2a078ed1e89f767f7e57。已ADB保留資料更新POCO，尚未公開發布。
- F25 在新版Python計算、寫檔、讀回、分享成功；從手機Download獨立取回31bytes：FQA-UPDATE-957及17*7+11*3 = 152。
- 更新後CLI doctor連線成功、helper_available/user_unlocked/ready為true；無障礙服務仍啟用，ACCESS_RESTRICTED_SETTINGS仍allow；輸入法仍為原Google LatinIME。
- F24 三筆F17/F18停用排程均經UI確認後刪除，最終進行中0、已停用0；階層證據已保存。
- Android JVM1501項全過；核心針對PromptLayout/ScheduleTask/SettlePolicy共27項全過。完整核心前次2969項唯一快照失敗已於這批修正重驗。
- 浮動卡片30案的第一輪在第23案被測試執行器240秒總限中止（exit124），無斷言失敗；調整執行器上限後整組重新執行。原中斷紀錄保留，不算產品通過。

### 18:05 補驗與修正

- F26/F27 新版背景實機任務同時送出，依目前設定排隊。系統設定實際讀到 POCO C85 / Android 15 AP3A.240905.015.A2；接續計算機真實按鍵17×7+11×3，畫面結果152，兩任務皆done。這不是同時並行的通過證據。
- F28 遠端喚醒成功，鎖屏仍在；兩次解鎖在輸入前回unsupported_keyguard，attempt_blocked=false。XML只核對SystemUI PIN欄位結構，不輸出密碼。找到KeyguardFields的歧義：stock PasswordTextView若editable且未宣告TYPE_CLASS_NUMBER，可同時匹配Pin和Password，singleOrNull將它拒絕。新增回歸先失敗，再令Password分類排除已識別pinView。
- 修正後Android JVM1502項全過，正式簽章候選APK SHA-256：76c41facb92e4a1a28545b4427b64e9cc4a27ec5ea5c51e6e8417c6b27629612，已覆蓋安裝POCO。F28 API回unlocked，keyguard_showing/device_locked=false、ready=true。此前已請使用者手動解鎖但未收到回覆；需重新建立一次鎖屏循環，排除人工同時介入的可能。之後USB裝置從adb清單消失，後續實機驗收待重連。
- 本輪首次完整lint實際失敗32 errors/182 warnings；之前的成功打包不能代替完整lint。修正API31守衛、受限制常數的使用、Settings StateFlow訂閱及BOM字元；Compose produceState誤報對應Google issue368420773（https://developer.android.com/studio/releases/fixed-bugs/studio/2024.2.2），升AGP8.8.2，沿用Gradle8.11.1/JDK17。完整lint、release、1502項JVM回歸在同一串行建置成功。未關閉檢查或新增baseline。
- 曾同時啟動兩個同工作目錄Gradle建置，造成knowledgeIndex class在編譯產出變動時找不到；保留失敗log，改串行後成功，非產品驗收通過證據。後續禁止同目錄Gradle並行。
- 擴充測試的助手重啟案例會讓USB啟動的helper停止；這種模式需要重跑USB命令，後續依賴測試曾受污染。執行器改每組啟動instrumentation後補起helper。原helper_missing失敗保留、需重跑，不能當產品故障或通過。部分系統設定頁斷言只認原手機WLAN版面，尚待適配測試前置；未跳過宣稱通過。


### 擴充驗收第二輪（18:45，尚未完成）

- 正式手機 USB 仍未出現在 adb 清單；沒有新增真人語音、聲音或獨立鎖屏循環通過證據。所有此輪 Debug APK 僅安裝 emulator-5554。
- 擴充裝置測試新增已完成的組：手機 OCR、浮窗拖曳、畫面擷取、VirtualDisplayWindowing；原始逐案日誌保存在 full-functional-20261109/instrument-remaining。LegacyPhone 等受 API 前提限制的案例獨立列為 assumption，不能算實測通過。
- 部分舊測試只辨識小米設定首頁 WLAN；改辨識實際網路入口、AOSP Network & internet 詳細頁及可點擊父列內的文字。虛擬螢幕隔離、點擊結果、舊 ref 失效、視覺模型呼叫次數等斷言保留。尚待新版重跑的修正不列通過。
- Shell 音訊恢復現有規格將未設值 default 還原為 allow；改對照實際有效模式，明確 ignore/deny 仍須保留，非法模式輸入仍要求原始值完全不變。連結策略已允許 tel 交由 App 開啟，舊拒絕案例改測真正禁止的 javascript 協定，未改生產政策。
- USB 模式助手死亡後需明確執行 USB 啟動命令；死亡測試先觀察 UsbHelperStopped，再由測試主機角色執行命令，確認新 Binder 及可用畫面。無線模式不使用此補啟動。不能把 USB 恢復當作無線自動恢復證據。
- 沙箱 MikarunDeviceTest 整組已通過：TCP on 使用真實本地 TCP server 驗證，不再依賴 1.1.1.1:80 是否回 HTTP。SandboxTaskDeviceTest 明確設定 ACT 意圖後整組通過。
- InstallDeviceTest 的 Python/Node/CLI 與斷網拒絕通過，稽核僅剩 host /proc 不可讀檔案；修正稽核前提時逐筆對照 Alpine installed 資料庫，只有未被套件擁有的 /proc 讀取錯誤可排除，套件檔案讀取失敗仍失敗。待重測。
- SkillScriptsDeviceTest 的真實 PDF 解析通過；拒絕未提供的授權腳本已回 script_unavailable，測試仍比對舊中文提示，修正為檢查錯誤、不可恢復及腳本名稱。待重測。
- 舊批次 ParallelDeviceTest 在模型模擬前提仍未更新時發生等待逾時，已中止並保留 interrupted.txt；新批次會完整重跑，不沿用中止結果。
- 逐案例清單與來源日誌在私有證據目錄 instrumentation-latest.csv；統計只表示已收集日誌，尚有舊案例改名、拆分與啟動器錯誤需要對照，不能等同產品缺陷數量。

- 18:53 完整核心重新執行2969項：0失敗、3略過，串行Gradle成功（8m22s），XML保存在core-tests-final。原快照失敗已由這次完整重跑確認修復。ShellParity46項、ShellDestroy清理與USB明確恢復、A11yOnDisplay、StaleNodeId均在第二輪通過。


### 19:03 獨立重測

- 第二輪滾輪4案耗時348.85秒，無效值有返回、3案通過；0→40雖到達正確值卻52次操作，原20–24次效率要求失敗。曾用JDWP短暫暫停取得執行緒堆疊並立即resume/exit，因此本輪耗時包含診斷介入，不能當純效能基準。模擬器當時有約1GB swap使用，已重啟保留資料；需隔離負載再次測量。
- 重啟後單獨網頁剪貼簿還原、AgentDisplay.releaseClearsFrames通過；尚不能只憑一次成功宣稱前次偶發因素完全消失。
- AuthSpill根因為Android16拒絕shell更改其他套件元件狀態，pm enable實際拋SecurityException。改run-as測試套件自己的UID切換，並檢查命令成功；系統AccountManager的獨立dumpsys確認認證器由4增加為5，測後關回。完整登入頁保留主屏案例通過，未更改產品登入處理防護。
- InstallDeviceTest、SkillScriptsDeviceTest、LocateDeviceTest、BitmapImageOpsTest、TakeoverTest完整組均通過。
- ScreenAccuracy無障礙不重要文字案例穩定失敗；點擊後再讀仍為0，尚需截圖分辨實際畫面未變或節點快取陳舊。此前對使用者說「按鈕沒有真正改變內容」僅根據讀屏，須以獨立畫面核對，不能提前定論。


### 確認通知修正與後續驗證

- 發現同一筆確認通知重建會以FLAG_CANCEL_CURRENT作廢既有按鈕。新增rebuildingSameRequestKeepsExistingApprovalButtonUsable先穩定重現舊／新PendingIntent不相等；修正為FLAG_UPDATE_CURRENT，保留每次請求不同的data URI及請求編號核對。模擬器ConfirmationDeviceTest五項全通過，包含同意、拒絕、評測拒絕、舊通知不能核准新請求及重建後原按鈕仍可使用。沒有實際下單或付款。
- 修正後Android JVM1502項全過；目前只裝模擬器，POCO USB仍不在線，正式手機尚未套用這項新增修正。
- ScreenAccuracy全組與AndroidScreen13案已通過。啟動測試Activity補-W等待；設定首頁前提明確cold啟動。前次讀屏只見0不能證明按鈕無效果：診斷的啟動前截圖尚為空白，後續取得截圖後該案通過；未修改產品的畫面變更判斷，也未因此宣布不存在時序風險。
- 滾輪原「鎖住」前提只擋焦點，Android16仍可能接受SET_TEXT，曾走text而非預期actions。測試頁改實際停用內部EditText，保留NumberPicker滾動。此時穩定到40但81次嘗試／24.879秒，效率要求失敗；產品已加入每個接受的無障礙步驟後等待動畫，待新APK實測，未降低原20–24次門檻。
- 並行與快速取消的ScriptedModel改按ModelSession固定分配，避免背景對話標題提早取走下一個任務的模型。強制終止恢復案例改由externalKillTest參數控制，主機二階段腳本已備妥，尚待實際執行。


### 19:37 最後補驗與交接

- 滾輪延遲修正保留20–24次原門檻；新增核心missingValueDoesNotKeepSteppingPastItsModuloEquivalent先實際失敗，再修正零距離未匹配時回not_reached，不再強制至少一步或退到拖曳。非零起點101–160到141也通過；沒有將數值域武斷視為0起點。
- 最新裝置完整4案39.68秒全通過；不存在值12.493秒（TestRunner 19:35:52.195→19:36:04.688，含前置），前次整組319.174秒。證據instrument-wheel-confirmed與wheel-runner-timestamps.log。
- 中間一次剛更新APK後helper以固定2秒啟動過早，首案UsbHelperStopped失敗；保留instrument-wheel-final原始紀錄。最後執行器改等instrumentation報告案例開始才啟動helper，完整組重跑成功，沒有跳過首案。
- WebDevtools強制helper代連已等到helper，仍因系統拒絕socket連接而列assumption；Route.None的降級斷言通過，不宣稱代連功能可用。這與對外遠端中繼是不同測試。
- 正式簽章候選檔位於本機artifacts/fullqa-20261109/woowtech-agent-woow4-fullqa-candidate-arm64.apk，SHA-256：95634d65e639c891086492b3f8f1edbc0f01d4ba9e568185ba996ac97f38a6cd；憑證806b3db808ecbb4d2d032b34624baa7e193802f17a07afbde2a03e78da9474c8，與正式版一致。尚未發布、未裝POCO；版本仍0.1.37-woow.4/3804，僅供保留資料驗收，不能冒充公開更新版本。
- 最終正式release與完整lint串行成功（3m11s），0 errors、182 warnings、3 information；未新增baseline或關閉規則。警告仍保留在lint-final.xml，不以建置成功宣稱警告清零。


## 2026-11-10 MCP 遠端部署補驗（進行中）

- 使用者明確排除Play Protect一般下載安裝攔截；標記為「本輪排除，未修復」，不再作為其餘功能驗收的停止條件。
- 使用者要求上傳候選檔，透過MCP在POCO下載部署驗證。已將cfec696e來源分支推送GitHub，發布獨立prerelease：v0.1.37-woow.4-qa.20261110。原穩定latest經API核對仍是v0.1.37-woow.4。
- 候選APK公開下載：https://github.com/WOOWTECH/woowtech_mika_smart_app/releases/download/v0.1.37-woow.4-qa.20261110/woowtech-agent-woow4-qa20261110-arm64.apk ，77,183,103 bytes，SHA-256 95634d65e639c891086492b3f8f1edbc0f01d4ba9e568185ba996ac97f38a6cd。
- POCO USB重新可見，起初RUNNING_LOCKED，使用者首次解鎖後恢復RUNNING_UNLOCKED。重開機的USB MCP權杖按設計失效，重新啟動USB服務與forward後，MCP device state回helper_available/user_unlocked/ready=true。這次MCP走USB轉送，不能稱為外網中繼成功。
- 第一個MCP下載任務6081e817失敗：手機沙箱腳本聯網未開啟且curl不存在。另核對產品明確禁止share_file匯出APK，因此不更改限制、不以改副檔名繞過，改送MCP任務6bf1442e由Chrome正常下載指定公開APK。
- 更新前安裝檔仍是76c41fac…629612（163bcff7候選）；firstInstallTime=2026-11-09 13:12:33。已保存無障礙服務、輸入法與任務歷史供更新後比對。實際安裝與新版驗收尚未完成。
- 私人證據：~/.local/share/woowtech-mika/test-evidence/mcp-deploy-20261110/，下載／部署結果將接續補記。


### MCP下載與安裝完成，鎖屏循環通過

- Chrome下載任務6bf1442e完成；主機在POCO /sdcard/Download獨立確認77,183,103 bytes與候選SHA-256相符。使用此手機已下載檔案，複製到暫存安裝位置後執行ADB `pm install -r`成功。並非用MCP遠端核准安裝，亦非電腦重傳另一份APK。
- 安裝後base APK SHA-256再次等於95634d65…f38a6cd；lastUpdateTime=2026-11-10 12:47:25，firstInstallTime保持2026-11-09 13:12:33。暫存APK已移除；Download候選檔保留供使用者使用。
- 更新後MCP重新連線正常，既有50筆任務ID全部保留，無障礙服務列表與Google輸入法設定完全一致。
- 受控鎖屏：主機KEYCODE_SLEEP→MCP確認device_locked=true→mika_wake_device回awake且仍鎖定→mika_unlock_device回unlocked→MCP ready=true。獨立dumpsys trust確認deviceLocked=0；期間getevent未記錄ABS_MT_TRACKING_ID實體觸控，沒有讀出或回傳解鎖憑證，僅使用手機既有授權設定。這是USB轉送MCP測試，不是外網喚醒證據。
- 新版MCP任務9c897b3e實際Python運算152、寫檔、讀回及share_file成功。主機獨立讀取手機Download內deploy-check.txt，逐位元組等於QA-20261110=152加換行（16 bytes）。
- 已向使用者請求新版真人語音句「今天更新驗收，一二三四五」，鬆手不送出，尚待實際回填核對。通知音訊目前系統靜音（STREAM_NOTIFICATION Muted=true、zen_mode=0），尚不能把無聲歸因App。


### 2026-11-10 17:06 新版真人語音回填核對

- 使用者在渥屋助理完成指定語音後，實機UI套件確認為io.woowtech.agent，輸入框為「今天更新驗收一二三四五」，與指定句內容一致（未自動加入逗號）。既有對話未新增此訊息，文字仍為草稿，沒有自動送出。
- 隨後主機長按輸入框2秒、向上移動再鬆手；取消後草稿逐字不變，既有對話顯示文字亦不變。這證明本次操作後草稿保留；取消後重新真人收音追加仍待下一次操作。
- 證據voice-human-result.xml、voice-human-after-cancel.xml、voice-human-verification.json，位於mcp-deploy-20261110私人證據目錄。未將本輪結果外推為通知聲音或外網中繼通過。

### 2026-11-10 17:08 取消後真人追加通過

- 使用者再次說「第二段完成」後，io.woowtech.agent輸入框實際為「今天更新驗收一二三四五第二段完成」。第一段完整保留，第二段正確追加一次；既有對話顯示文字不變，仍未送出。
- 本候選版已驗證真人語音回填、取消操作後草稿保留、再次收音追加與未自動送出。最新候選版此草稿的傳送／模型回覆尚未執行，不沿用舊版結果宣稱本輪完成。證據voice-human-appended.xml、voice-append-verification.json。

### 2026-11-10 新版真人語音完整流程通過

- 使用者確認手動按傳送後，實機io.woowtech.agent對話顯示已送出的「今天更新驗收一二三四五第二段完成」，助理已回覆確認收到，輸入框清空。證據voice-human-sent.xml及voice-send-verification.json。
- 此候選版在POCO完成真人收音→文字回填→取消保留草稿→重新收音追加→手動送出→模型回覆的完整流程。此結論限本輪實測情境；通知聲音、外網中繼及其他未測功能仍須分別驗收，不宣稱全功能通過。

### 2026-11-10 背景通知、響鈴紀錄與入口驗收

- 開始時 POCO 靜音模式開啟；透過系統設定暫時關閉，實測通知音量8/15、Muted=false，未更改勿擾或通知分類。
- 手機UI建立唯一一次性提醒「渥屋通知驗收 N1710」，App退到背景。建立結果通知與到時提醒均送達；提醒建立時間1794302003053（17:13:23.053），系統mLastAudiblyAlertedMs=1794302003729（17:13:23.729），mIntercept=false。這是系統響鈴紀錄，真人是否聽見仍待回覆，不能等同實體喇叭聽覺驗證。
- 展開通知群組後點擊提醒，實際回到io.woowtech.agent原始對話。定時任務UI確認進行中0／已停用0，沒有殘留測試提醒。
- 五個通知分類設定前後完全一致；測後已恢復原靜音模式，確認Muted=true、音量索引仍8。
- 外網連線頁實查尚未配對閘道，位址與配對碼空白；真正外網中繼驗收缺少可信HTTPS閘道。未更改網路／遠端權限。
- UI階層擷取期間App曾顯示無障礙暫停；結束後dumpsys確認渥屋助理已Bound、Crashed services為空，MCP device state ready=true，未將此當作產品崩潰。
- 證據位於mcp-deploy-20261110：notification-watch.jsonl、notification-shade.xml、notification-conversation.xml、notification-schedules-after.xml、notification-verification.json、remote-settings.xml。
