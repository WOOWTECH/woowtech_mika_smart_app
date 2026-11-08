# Apporo Assistant Wave6 模擬器驗收（已收尾，保留限制）

## 最終總表（2026-11-08 17:33；runner文件凍結）

最後受測 **48785409 / 0.1.37-apporo.3 / 3803 / About f7b08b0**，SHA-256 `4952f5e1e24c5e6a83d2b7813d5db0acf090881a168bcc45be8f16c8d907860c`，測試憑證775149…，不是正式發佈APK。雜湊、覆蓋安裝及About均實際核對。487與699產品相同，只加入官方asset API＋SHA的CI下載bootstrap；Apporo／WOOW及4個cloud startup成功由parent提供，shared Kotlin依賴下載504仍不能寫全部CI成功。最後兩項排版完成後已移除本輪安裝並正常釋放時段。

這份報告是多版本、逐狀態驗收；不同版本的通過不冒稱全部在487重跑，也不以矩陣空缺清單為空宣稱所有實際服務／能力全面通過。

| 項目 | 目前結果與證據範圍 |
|---|---|
| 通知定向／旋轉 | 82 提問與接手、8b 原始確認通知精確流程實測通過；不同通知不互相替代 |
| W6-01／03 手機引導 | 原始 Step3 英繁明暗預設／極大8格在573完成，ea步驟數字修復；ZD正常下段4–6/footer於5105補齊 |
| W6-02 模型列／provider metadata | ea模型列與33連線資訊定向格通過；不推論角色選單能力標籤同時通過 |
| W6-04／05 MCP | f923清單、自主選對stdio及受控offline/recovery有實呼叫與獨立log；HTTP無誤呼叫，不代表任意外部MCP可用 |
| F04本地驗證 | 573英繁錯誤翻譯、改欄／transport清舊error、取消保留通過 |
| W6-07固定欄位標籤 | bd英繁明暗預設／極大靜態四格，EL及ZD實際IME／輸入／返回丟棄通過。鍵盤彈出時dialog標題會被平移至狀態列部分裁切，收鍵盤恢復；不稱所有文字無裁切 |
| W6-08／09代理、通知排版 | 5105英繁明暗預設／極大四格已目視；代理未儲存，通知系統入口抽驗未改頻道 |
| W6-10連接電腦 | 5105 selectors/copy按鈕、正常四格及極大抽驗通過；實際複製核對後清空未送。英文長字拆行與工具列省略保留限制 |
| ManualModel | bd EL/ZD語音及主模型手填欄預設／極大、點提示下段聚焦／輸入／Back未Use通過；ZL語音靜態已補。ED語音極大下段、ED/ZL角色正常／極大靜態於17:24在bd補齊；視覺／輕量未各自重跑，僅共用元件來源 |
| U09 API type | bd英繁明暗預設／極大四格完整目視；EL/ZL切換種類後取消，未新增服務商；不把周邊單行placeholder裁切也宣稱修好 |
| fresh U02／F01 | bd全新安裝，繁中明暗模型頁底部完整；首次通知拒絕後 granted=false，再由App要求授權並Allow後 granted=true，畫面狀態一致 |
| U21初始／離線 | 離線首次啟動到模型設定，未觀察到計算環境 Preparing/Broken；恢復網路完成模型設定後可見已就緒、122.6MB及0B工作區。此分支PARTIAL，不當離線準備完成證據 |
| 其餘UI／F01–08 | 逐格依matrix-summary及各收據；F06僅更新失敗／空記錄／回報入口，不是正式更新成功 |
| 487角色能力／語音狀態 | 英繁明暗normal/extreme四格目視PASS：完整unconfirmed／未確認，語音說明與Available／可用上下排列。僅排版，不當模型工具能力或語音辨識準確度驗證 |
| 收尾 | 17:32:07 DONE、17:32:09 emulator停止；holder／slot exit0，review healthy、heavy free，兩review demo running。Apporo／ADB Keyboard／helper／fixture移除，smart Debug保留 |

最後slot：release-apporo-wave6b-1108，15:58:22開始、17:32:09正常結束，未用滿180分鐘上限。最終收據 `cleanup-final/FINAL-RECEIPT.json`；前一slot恢復只算turnover。多版本結果均保留實際來源，歷史待驗段落由本表與較新收據取代。平台AccessDenied、蝦皮登入／驗證、外部OAuth、正式更新與實機聲音保持限制；cloud API30/32/35/36只計安裝啟動smoke。

## 歷史執行紀錄（以下舊待驗狀態可能已被上述較新結果取代）

2026-11-08，唯一UI runner，依WAVE6-REMAINING-PLAN續測。Wave5已完成裝置及時段清理（13:07 review healthy、exit0、heavy free），不沿用殘留PIN/helper。初始APK83734282，82e84d35 已於13:18覆蓋安裝成功（SHA a7f66916c0abc0a470658b112dc86c051c1828a50d6c7ad63d41a9b8b1a0874c）；提問通知旋轉及跨對話、付款接手跨對話已實測；原始確認通知 View→Settings→旋轉保留到最後 APK 精確重驗。8b6fbe0f 已於13:41覆蓋安裝、USB helper重啟；SHA 8d5a028dbd219241632eed0ce6f7ec585fbad90d5340ea7d8d5a4352ccd0c026，artifact標示build f8b9e68（About畫面尚待核對）。

證據：`~/.local/share/apporo-assistant/test-evidence/wave6-20261108/`；監控`monitor-status.json`。cap180正常slot，不改產品碼、不commit/push。舊證據依`prior-theme-review.json`引用，註明為獨立reviewer目視，不假稱本runner重看全部。

## 本輪結果

U01歡迎四格已目視通過；U02模型初始頁英文淺深通過，繁中淺／深底部說明覆蓋不完整均列PARTIAL；U03b手機操作初始引導繁中淺深通過，英文淺深長按鈕文字省略列PARTIAL（W6-01，尚未驗配對功能）。837初始設定後私下設定授權模型 apporo/gpt-6.1-sol，Connected 54 models，看圖沿用主模型。82覆蓋後保留設定。EL/ED/ZL/ZD分別英文淺/深、繁中淺/深，預設font1/density420直向；各子頁獨立收據，不以主頁替代。


82 通知實測：提問通知本文→完整問題卡→設定→橫向→直向，兩次仍留設定；再次點通知可重開，沒有代答。另實際由膠囊建立新B，Recents回到已停止A，點B通知正確開Red/Blue卡。收據82-question-rotation-receipt.json、82-question-A-to-B-receipt.json。接手通知另實測 B 停止畫面→C 本機錢包通知→正確 C 接手卡，取消後 FINAL 仍為0（82-takeover-target-receipt.json），不由提問結果推論。


13:40 前補齊82英文：主／輕量角色選單上半部、ED看圖上半部（未掃54模型，均PARTIAL）；ED context；EL Token 24h/7d/30d/90d及自訂日期取消；EL/ED語音設定與膠囊設定；ED記憶待確認／網站登入／操作路線、進階、計算已就緒用量、MCP清單說明與HTTP/SSE/stdio空表單。F03非法代理停用Save、合法格式可用、取消重開仍空；F04空白／非法URL均拒絕儲存，退出仍0server。各自結果在results.jsonl，不把設定頁Available當語音辨識通過。

W6-02：自訂服務商目前模型列三個角色徽章擠壓名稱，預設字級只顯示appo…；EL/ED均重現，已回報，尚未修復驗證。8b確認通知第一次直開checkout/cvs遇空車退回，Assistant如實停止；屬測試前置未備，不計通知PASS，已改完整本機商品流程。


8b 原始確認通知回歸已完成（8b-confirmation-rotation-receipt.json）：完整P1流程取得NT590卡，View→Settings→橫向→直向都停在Settings；再次View正確重開卡，未自動核准；Refuse後終態明確沒有送單／付款，FINAL=0。實際來源8b6fbe0f，截圖8b-09/11/13/14/15/16/17/19。USB第一次升級後立即重跑回already running，不等於恢復；稍後Settings顯示Stopped，再重跑目前腳本才啟動成功，8b-20畫面On/Ready已目視。


W6-01證據校正：ED/EL-U03-8b-off-default.png 再次目視確為Step 3，兩個原始長按鈕完整，僅預設字級畫面通過。guide-8b-bottom與extreme-3/buttons顯示Step 4，不算原按鈕的極大字體驗收；uiautomator暫停無障礙時的XML也不算。最後全新設定批次仍補穩定Step 3英／繁預設／極大字體。W6-03另列極大字體步驟5/6圓形數字裁切，parent準備修正。繁中記憶子頁補圖時，主題切換會回預設記憶分頁，拍錯分頁的檔案排除；correct後綴與results.jsonl列明的畫面才列入驗收。

HTTP outbound MCP已在8b實測PASS：儲存測試成功→受控503錯誤→恢復成功，清單重開仍可用1工具；新對話要求echo一次，10.9秒完成，日誌第11行唯一tools/call成功，回答JSON含echo與固定witness一致。mcp/http-receipt.json列來源與限制；不是僅連線測試，也不是斷網測試。stdio仍待實測，測試伺服器清理待收尾。

stdio在Android沙箱實際呼叫通過但需人工辨識同名工具：原7132字fixture被4000上限正確拒絕；相同原碼壓縮封裝3587字後設定成功。Assistant看到兩個相同描述echo，先詢問而未亂呼叫；依已知HTTP工具ID選另一個stdio後完成。來源頁MCP-stdio-source.png實際顯示echo與同對話file_read原始log，唯一tools/call、witness一致；不是以模型摘要代替日誌。mcp/stdio-receipt.json列限制。W6-04長命令清單全文造成多屏；W6-05多伺服器同名工具缺來源辨識，均已回報，未稱完整全自主通過。


14:20 ea080d56 覆蓋安裝完成、SHA核對一致。W6-02模型列英／繁、淺／深、font1/density420與font2/density540的provider preview和All models目前模型列皆實圖可讀；英繁淺色點模型可開角色選單並取消，未改選擇。詳ea-model-badge-receipt.json。ZL-U08-ea-provider.png實為U07主模型選擇頁上半，排除於此修復證據。極大字體工具列標題仍省略，與模型ID修復分別列。ea的Apporo/WOOW/App測試通過，但shared core仍有一項navigationWhileRunningIsStopped失敗，未稱CI全過。步驟badge與MCP後續仍待驗。

14:24 W6-03在ea英／繁、淺／深、font2/density540下5/6圓圈數字完整，四張stable圖已目視，見ea-model-badge-receipt.json；W6-01原Step3極大字體仍獨立待補。ea USB啟動回starting，ZD-U12-ea-ready及ED-U12-ea-ready實圖On/Ready，與dump暫停時Not running分開。

14:30 f923e797新對話MCP自主辨識PASS：只給W6 stdio echo與stdio/Local process，不提供opaqueID，17秒完成一次echo。Source頁原始結果與同workspace日誌唯一tools/call/witness一致；HTTP只多initialize/initialized/list，0新增tools/call。清單兩行preview實圖PASS，editor3587字與測試命令完全相同。mcp/f923-receipt.json列原始證據。f923 sharedcore另有CdpSession.closed race失敗，不列全部CI通過。

### f923 stdio 同對話受控恢復（14:35）

PASS。親眼核對 Source 原始工具結果與讀檔紀錄：新增 tools/call 恰為一次 offline、一次 ok，恢復回傳 W6 recovered 與 fixture witness。原先自主呼叫的成功紀錄保留，沒有當成本次重複呼叫。HTTP 累積 tools/call 仍為 1，沒有轉用另一台。成功恢復表示同 workspace 的離線旗標於呼叫時已不存在；這是受控 fixture 故障測試，不代表真實網路斷線。收據：`mcp/f923-recovery-receipt.json`，原始畫面：`ui/f923-recovery-source.png`。

### 英文功能補格（f923，14:40）

F01 三類通知實際往返系統設定 PASS，未改提醒方式；F05 重置確認取消 PASS，工作區用量保留。F06 實際檢查更新回覆 Can’t reach GitHub，更新記錄顯示尚無資料；回報選單可開啟關閉，沒有送出 issue。此項為錯誤／空狀態覆蓋，不算下載成功。ED About 親眼確認 0.1.37-apporo.3、Beta、Build 8c4010a 與頁尾完整。詳見 EN-F01-F05-F06-receipt.json。

### 繁中設定與驗證補格（f923，14:45）

F03 代理非法格式被擋、合法格式未存即取消，重開空值 PASS；F05 重置確認取消且工作區保留 PASS。U20/U21 淺深兩格完整目視；ZD U06 底部補齊。F04 空名、無效 URL、空 stdio 命令均無法儲存，Back 後仍只有原兩 fixture；但錯誤直接顯示英文 name is required／invalid URL／command is required，語系 FAIL。HTTP invalid URL 切 stdio 後也暫留舊錯誤直到再次儲存，保留前證據。詳見 ZH-F03-F04-F05-receipt.json。

### 繁中模型設定補格（f923，14:49）

ZL/ZD 新增服務商預設與自訂空表單可達、返回未建立資料；ZD 步數上限實際對話框完整並取消。Token 用量完成繁中明暗、24h/7d/30d/90d、自訂日期取消與服務商篩選還原；圖表模型名稱仍省略，不把 ModelRow 修正推及圖表。收據 ZH-U09-U10-U13-receipt.json。ZL-U06-bottom-f923 實際仍是設定上段，底部完整性不採該圖。

### 33efe79b provider 連線資訊修正回歸（14:54）

APK 雜湊與指定值一致，覆蓋安裝 Success，USB current command 回 starting。英繁／明暗四格均在 font1/density420 與 font2/density540 親眼確認 API type／介面、URL／網址標籤與值完整，長網址兩行不裁切，PASS。沒有顯示 Key 或改動模型。收據 33-provider-metadata-receipt.json；ZD-U08-33-metadata 實際為主模型選單，明確排除。原 ModelRow 不重跑。

### 15:04 補齊模型選單下端與新增服務商收據（33efe79b）

英文淺色三個角色選單最底部、繁中深色三個角色選單上／下段均實際目視：手動模型欄、新增服務商與頁尾說明可讀，返回後沒有改選模型。這不是54個模型逐一能力驗證。英文淺色預設／Custom與深色Custom空表單已補收據，未新增服務商。索引：`33-role-bottom-receipt.json`。

### 15:06 繁中草稿、鍵盤與語音取消（33efe79b）

明暗兩主題的實際Gboard證據為 `ZL-U04-33-ime-open.png`／`ZD-U04-33-ime.png`，較早以keyboard命名但沒有鍵盤的圖僅證草稿。麥克風先拒絕、再授予使用期間權限，長按後上滑出現紅色「放開 取消」，放開回原草稿、沒有送出。未驗音訊辨識準確度。完整限制與系統偏好還原項在 `ZH-F02-33-receipt.json`。

### 15:11 MCP F04 修復回歸（573b8f93）

英文與繁中空名稱、非法網址、空命令都顯示對應語言錯誤；改名稱／命令立即清掉錯誤，HTTP網址錯誤切本機程式也消失。取消後仍僅兩個原fixture，未儲存新伺服器、未執行命令。`573-F04-receipt.json`列實圖；英文第一張transport-clear捕捉在切換前，改以transport-stable為準。本輪未重做已通過MCP實呼叫。


### 15:21 — 573 授權頁與 About 補格

573 的 EL/ZL/ZD About（a157998）、EN 用量篩選控制與 ZH F06 錯誤／記錄／回報入口見 `573-about-F06-receipt.json`；F06 維持 PARTIAL，不當正式更新成功。授權頁繁中明暗已逐屏目視，淺色以 dump 後穩定截圖 `ZL-U27-573-top`、`stable-01..29` 連續重疊掃至頁尾；30 之後重複頁尾。Mika 排第一、86 元件、PRoot/talloc、ML Kit、Alpine 與頁尾均可讀；英文授權原文及上游名稱不當漏翻。`ZL-U27-573-header.png` 名稱誤植、實際為頁尾，真正頁首採 `-top.png`。詳見 `573-licenses-receipt.json`。


### 15:27 — 搜尋與排程管理

U17 英／繁搜尋 `W6-no-match-20261108` 顯示沒有結果，收起搜尋清除條件並回原空記憶狀態，沒有刪資料。F07 由 Assistant 建立單筆 90 分鐘後（16:53）的 W6 無害提醒，獨立核對列數／時間；英文取消刪除保留、停用後重開仍 Paused；繁中明暗可讀，取消刪除後再確認刪除，最終進行中／已停用均 0。首次讀時間工具失敗但模型自行恢復，不把所有步驟寫成首次成功。沒有重測到點投遞。收據 `573-U17-search-receipt.json`、`573-F07-receipt.json`。


### 15:33 — 英文複製／語音取消與起始頁

EN F08 CLI 412 字、MCP 306 字貼回與資源全文一致（含8765埠與docs-apporo），未送出、草稿清空，電腦存取始終關閉。EN F02 實際Gboard／短按打字、拒絕再授麥克風、Listening 上滑 Let go to cancel，放開完整保留53字原草稿且沒有任務；之後清除測試草稿。未驗音訊辨識準確度。ED/ZL/ZD 瀏覽器起始頁及 ZL 真正空白無草稿聊天頁已目視。收據 `EN-F08-573-copy-receipt.json`、`EN-F02-573-receipt.json` 與 results.jsonl。


15:39 補格（573）：已目視 App 存取 EL/ZL/ZD 下段至最後一列，未動任何開關；EL 全空白 stdio 新增表單完整可讀，返回後仍只有原兩個 fixture；系統 App 語言選單已目視，未更改語言。收據 `573-ui-gap-receipt.json`。早期名稱含 bottom 但實為頂部／中段的圖不作底部證據。


15:40 新缺陷 W6-07（573、英文淺色、font2/density540）：MCP 新增 HTTP／stdio 表單下段被裁，Allowed tools 與信任說明不可完整讀取；表單內上滑後畫面未移動。Local process 顯示成 Local。Save 按鈕仍可見，但不能據此算整張表單可用。未填資料／未儲存。三張圖已目視，詳 `573-extreme-MCP-defect.json`。

15:42 新缺陷 W6-08（573、英／繁淺色、font2/density540）：網路代理說明末段被裁，輸入欄被壓縮，英文表單內滑動無法移動。取消可用，未設定代理。圖片均已目視，詳 `573-extreme-proxy-defect.json`。

15:45 W6-09：通知頁繁中極大字體 font2/density540，任務進度左側說明被右側狀態擠成單字直排，跨一屏，閱讀性不合格；頁面仍能捲到底，非通知功能失效。詳 `573-extreme-notifications-defect.json`。U21 計算環境四格極大字體可捲至完整頁尾，英標題省略及工作區短名另列限制，未執行重置或清空（`573-U21-extreme-receipt.json`）。

15:49 W6-10：連接電腦 ZL 極大字體下 USB（建議）只見USB、Wi-Fi / VPN只見Wi-Fi /，複製膠囊按鈕文字底部被固定高度裁切。CLI USB正文與命令可捲動完整看到，未啟用電腦存取。詳 `573-extreme-connect-defect.json`。

15:54 W6-01 原始 Step3 最終視覺回歸：573 的英／繁、明／暗、預設與 font2/density540，Skip 與受限制設定原長按鈕均可完整換行並捲讀，已目視列入收據的每張圖。起初只關無障礙會被運行中的 helper 自動恢復，舊 off 命名圖排除；實際從 App 解除本輪配對、停止 helper 後再關無障礙取得穩定 Step3。未重新做無線配對。詳 `573-original-Step3-receipt.json`。模型及兩個 MCP fixture 設定仍保留。


### 16:04 正常續時段與補格

前時段15:58正常done、holder exit0、review host healthy、SLOT_EXIT=0；heavy free後再檢查AC、磁碟21GiB、容器可回應，新時段release-apporo-wave6b-1108於15:58:22啟動，180分鐘上限。收據slot/holder-turnover.last與slot2/release.log。

573版U28四格實際Gboard鍵盤、輸入、清除與Back完成；未送出搜尋。證據573-U28-keyboard-receipt.json。U11 ED極大字完整開頭已補，底部placeholder仍只顯示e.g.，保留PARTIAL，未觸發語音服務，見573-U11-ED-followup-receipt.json。U25 EN初始下段12項Waiting已補，未重跑自檢。


### 16:27 — 5105 排版回歸進度（仍在測試）

5105／預期 About 2fda398 已實際安裝；本段只涵蓋指定排版，不代表重跑 AI 功能。W6-08 網路代理、W6-09 通知頁的英文／繁中、亮／暗四格，預設與 font=2/density=540 均已目視：代理說明及欄位可滾動抵達、取消不儲存；通知狀態改列於說明下方後可讀，系統頻道入口抽驗正確。收據 `5105-proxy-notification-ED-receipt.json`、`5105-ZL-regression-receipt.json`、`5105-ZD-regression-receipt.json`、`5105-EL-regression-receipt.json`。

W6-10 連接電腦的繁中安裝指引及 MCP USB 命令已實際複製到未送出的草稿，核對原字串／命令相符後清空；英文選項切換及大字按鈕可讀。極端英文長字仍會拆字、頁標題會省略，並非宣稱完全無截斷。剩餘定向格繼續補。W6-07 MCP 編輯器滾動有效，但聚焦 command 的浮動標籤仍與 transport 重疊，保持 PARTIAL，待 bd0915 合併修正版一併驗 ManualModel、API type chips 和固定欄位標籤；不重跑已過 MCP 實呼叫。


16:36：5105 W6-10剩餘正常格及極大copy／設定說明可達性補齊，見`5105-connect-followup-receipt.json`。U03 ZD正常第4–6步及footer補齊，見`5105-U03-ZD-lower-receipt.json`。U26回報與空更新記錄面板英繁明暗font2/density540四格均親眼檢視，文字與按鈕可讀，Back正常；未點GitHub、未複製診斷、未重送更新請求。收據`5105-U26-extreme-receipt.json`。恢復font1/density420，等bd0915最後三項回歸，再fresh與最終清理。


### bd0915f7 MCP 固定標籤定向回歸（16:46）
英亮／繁暗正常與極大字體：原命令標籤與 transport 重疊已修，欄位可聚焦輸入、底部可捲動，返回取消後重開為空。詳見 `bd-MCP-EL-receipt.json`、`bd-MCP-ZD-receipt.json`。**殘留限制：極大字體＋鍵盤會把 Add server／新增伺服器標題平移至狀態列而部分裁切；收鍵盤後標題完整恢復，不能稱整畫面所有文字無裁切。** 未儲存或測試新增伺服器。


### 17:14 — bd 定向收據與 fresh 完成

bd-MCP-{EL,ZD,ED-static,ZL-static}-receipt.json 分列四格正常／極大靜態證據，EL、ZD另外完成輸入與退出丟棄；不把ED/ZL靜態圖當各自IME操作。固定標籤不再與transport重疊，但鍵盤出現時對話框標題仍可能被平移裁掉，收鍵盤後恢復。`bd-U09-fourcell-receipt.json` 支持API type四格正常／極大可讀；EL/ZL切換後取消，沒有建立新服務商。`bd-ManualModel-receipt.json` 支持EL/ZD語音與主角色手填欄聚焦、輸入、Back未Use，ZL語音靜態另補；角色能力標籤與語音狀態擠壓另等699/487，不混為手填欄失敗。

先核對無helper／無障礙與舊私有連線，再移除本輪Apporo並重新安裝bd。關閉Wi-Fi/data後第一次網路dump仍顯示過渡中的active WIFI，明確排除；等待`fresh/offline-connectivity-stable.txt`為Active default network:none後，清除尚未輸入資料的新安裝並重新啟動。離線可達歡迎與模型上手；繁中淺／深底部全角色與說明已目視。離線儲存服務商未讓主模型前置完成，故沒有觀察到計算環境Preparing/Broken/離線Ready，不能因內建runtime原碼就記PASS。之後恢復Wi-Fi/data、私下設定原授權模型，未發Assistant任務。計算頁實見122.6MB、0B對話工作區、腳本網路預設關閉。

F01由App「去開啟」觸發首次通知權限，拒絕後系統granted=false/USER_SET；再次由App要求並允許後granted=true，App顯示已允許及對應頻道狀態。`fresh-F01-first-prompt.png`拍在系統視窗出現前，只顯示App，不能當prompt圖；正確再授權prompt採`fresh-F01-reprompt.png`，終態`fresh-F01-granted.png`，兩張已實看。詳`bd-fresh-initial-receipt.json`及`bd-fresh-F01-U21-receipt.json`。

本段只是fresh與定向子套件完成，尚非整輪清理。剩餘索引`remaining-runner-1715.json`；最終角色／語音修正待簽署487 APK，holder與本輪私有模型設定尚待結束時清理。


### 17:24 — 不依賴487的最後手填欄靜態補格

`bd-independent-manual-final-gaps.json`補齊ED/ZL主角色normal/extreme與ED語音extreme底部，五張實圖已目視；僅過濾模型列表，不選模型、不按Use。手填標籤／完整placeholder／Use可讀。ED極大能力標籤仍缺unconfirmed，屬待487修正，不能以手填欄PASS掩蓋。現在獨立bd缺格已完成，只餘487能力標籤／語音狀態四格回歸及最後清理。


### 17:30 — 487最後兩項排版驗收

`487-final-target-receipt.json`逐EL/ED/ZL/ZD列normal（font1/density420）與extreme（font2/density540）實圖，全部由runner目視。角色列表英文極大字的「Tool calling · unconfirmed」完整換成兩行，繁中完整「工具呼叫 · 未確認」；未改模型選擇。語音手機內建說明與Available／可用改為上下排列後可讀，英語極大字以top及status兩張重疊覆蓋說明與None列；繁中top已包含完整狀態。`ZD-487-speech-extreme-status.png`實際為手填欄底部，不以該檔名主張狀態通過。`487-about-verified.png`實見版本3803對應0.1.37-apporo.3及Build f7b08b0。沒有發模型請求、選語音模型或重跑已完成核心功能。

### 17:33 — 最終清理與文件凍結

- 本輪Apporo與ADB Keyboard卸載成功；第三方套件清單只剩原有`io.woowtech.smart.debug`，原PID3447仍在。無Apporo helper或應用程序，兩個本機fixture PID67984／74243經比對完整自有命令後SIGTERM，已不存在。
- ADB forward／reverse皆空；font1、density420、night no、旋轉自動、Gboard、硬體鍵盤顯示IME=0、無障礙off/null、Wi-Fi與mobile data開啟、airplane off。MikaPanel debug property清空。`locksettings verify`未提供credential即成功，沒有遺留本輪PIN。
- 17:32:07 touch DONE後holder正常關閉模擬器，17:32:09 heavy exit0，release log記`review host healthy`與`SLOT_EXIT=0`。另外實查heavy free及woowtech-review-demo／apporo-review-demo均running，沒有把舊turnover當本次結果。
- 最終文字證據精確金鑰掃描869檔、命中0、讀取錯誤0；不擴張為OCR或任意秘密掃描。憑證原檔未修改；fresh App私有模型設定隨卸載移除。

收據 `cleanup-final/FINAL-RECEIPT.json`、`device-host-receipt.json`、`heavy-status.txt`、`containers.txt`，與`slot2/release.log`。`monitor-status.json`為COMPLETE_CLEANED；runner停止UI操作，文件凍結交parent，未commit/push／未merge／未發佈。

保留限制：U21離線準備／失敗狀態未直接觀察；極大字IME彈出時MCP新增對話框標題部分裁切，收鍵盤恢復；歷史heads-up首次暴露前短暫重疊仍PARTIAL；platform有效帳密、Shopee登入／驗證、外部OAuth／認證MCP、正式Apporo更新頻道與實體聲音不在本輪完成範圍。cloud API30/32/35/36只證安裝啟動，沒有替代各API真實AI操作。其他逐格可見範圍、source-bound沿用及未測條件入口仍以矩陣和原始收據為準。
