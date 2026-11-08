# Apporo Assistant wave5 模擬器驗收（裝置與時段已清理，通知補修待 Wave6）

2026-11-08；唯一 UI runner。最後受測 APK 為 **83734282／0.1.37-apporo.3（3803）／build b899a5e**，SHA256 `eb168d087b6a08a4653c2fbd46e0f277fd7479e958e7a57c69536ae51a90d82a`。第五輪結束時，82e84d35 尚未完成裝置回歸；後續結果見[第六輪](EMULATOR-WAVE6-20261108.zh-TW.md)，不倒填為本輪通過。各版本按改動定向回歸，並非所有案例在837重跑。測試執行者只操作裝置與記錄證據；產品修正由協調者另外提交。

證據：`~/.local/share/apporo-assistant/test-evidence/wave5-20261108/`；即時狀態 `monitor-status.json`。

| 驗收項目 | 最終已有證據／限制 |
|---|---|
| 大字體重要按鈕 | a179英／繁完整換行PASS；26 P1/P5等待卡無PiP、恢復執行後依偏好恢復PASS |
| 膠囊幾何／觸控／完整QS | 403三次開關、草稿與觸控、直橫向及QS PASS |
| heads-up避讓 | 49穩定避讓／消失後恢復PASS；系統暴露窗口前仍短暫重疊，零遮擋目標 **PARTIAL** |
| 通知View與鎖屏 | 625只有View／Decline；View與解鎖前0新FINAL，完整卡單次允許後12:20:13.960產生1筆、dup=false（W0004）。total4是整輪累計，非重複送單 |
| 通知定向與drawer | 837側欄→View、Settings→View、普通Settings返回三路徑PASS；膠囊建立B、Recents留A、B通知View回B完整卡PASS（314–318），0新FINAL |
| View後旋轉 | **FAIL**：837 Settings297旋轉後跳回chat298；82補修待測。提問／接手通知定向亦待82，不外推為PASS |
| momo自主搜尋 | 403原提示新對話首答明列兩瓶組、型號價格獨立核對PASS；discount already applied徽章未獨立支持，保留限制 |
| 蝦皮 | 49自主搜尋如實停止PASS，商品資料因登入 **BLOCKED**；837按登入後323空表單與公開網址已保存，登入入口PASS |
| UI語言／主題 | a179英文指定7頁淺深、26footer、625About極大字、系統語言切換均有定向證據；完整33入口四格轉Wave6補齊，不稱全面完成 |
| helper隔離 | 雙helper自主唯讀與移除WOOW後Apporo可用PASS；837反向移除Apporo後WOOW存活、再移除WOOW後退出PASS，原smart.debug未動 |
| CLI／MCP、自檢／提醒 | 既有取消撤銷PASS；26自檢12PASS；精準提醒enqueue+51ms／alert+258ms，該提醒窗口無SILENT/autogroup；不等於實體音效 |
| 清理 | Apporo／本輪WOOW／ADBKeyboard、helper、PIN、fixture已清；forward/reverse空、Gboard與設定還原。13:07:00正常退出，review healthy、SLOT_EXIT=0、heavy free，見兩份cleanup收據 |

模型沿用授權gateway，但實際路由 `apporo/gpt-6.1-sol`，不是先前不可用的 `chatgpt/gpt-6.1-sol`。USB跨APK更新須重跑目前指令恢復，沒有放行StaleApk。platform舊帳號AccessDenied不重試；實機聲音／其他API與ABI未驗。以下保留歷史缺陷及修復過程，歷史等待狀態不代表目前結果。

## 環境

開機前磁碟不足 21 GiB。將六個未用於本輪安裝的舊建置輸入與下載封裝移到外接磁碟專屬封存目錄，逐檔 SHA-256 核對、原路徑保留 symlink，沒有刪除其內容；已簽 APK 與證據留內建碟。詳 artifact-relocation.json。內建磁碟回到 21 GiB 後才啟動 holder；AC、heavy free、記憶體 64%，Apporo review 持續運作。

## 舊版大字體／縮放 baseline（09:55–10:00）

font_scale 1.5、density 480：首頁可捲動、輸入送出可用；英文 P1 同意卡金額 NT$590／Refuse 完整，但 Allow this once 截成 Allow this…，一次性範圍不可見（W5-01，ui/15-large-en-approval-stable.png）。

font_scale 2.0、density 540：繁中卡片可捲到底，拒絕按鈕可達，但允許這一次截成允許…（ui/19-extreme-zh-bottom.png）。沒有把正常需要捲動誤列為不可達。縮圖會蓋住部分卡片文字，操作區可捲到。

W5-02：浮動膠囊會覆蓋系統通知本文（ui/22-extreme-en-shade-stable.png）；完整快速設定時蓋住 Modes 下半與 Flashlight 右側（ui/23-extreme-quick-settings.png）。還原 font1.0、density420 後仍在快速設定上層，蓋住 Wallet／Device controls 上緣（ui/25-default-quick-settings.png）。未操作被遮住的系統開關；這是視覺遮擋證據，不推論所有按鈕完全無法按。

以上截圖均已實際開啟檢視，已立即回報 parent；parent 正在修重要按鈕換行。P1 baseline 最後選拒絕。

付款接手卡同樣可捲到底，英文 I’ll handle it 截成 I’ll ha…、繁中我來處理截成我來…；Skip／跳過與取消任務完整可達（ui/31-extreme-payment-bottom.png、32-extreme-payment-zh-bottom.png，已檢視）。最後選跳過。大字體兩個任務截至此時 FINAL=0。

遮擋的補充系統收據：system/overlay-expanded-windows.txt、overlay-expanded-accessibility.txt、overlay-collapsed-windows.txt、overlay-collapsed-accessibility.txt。是在付款停在接手卡、AI 不再執行步驟時擷取；未用 uiautomator。更早 system/large-overlay-window.txt 的完整 window dump 可見 mCurrentFocus=NotificationShade。

## 隱藏私人內容的鎖屏：PASS（舊版 baseline）

透過 Android UI 設定本輪臨時六位 PIN，私有檔 0600、未輸出值。lock_screen_allow_private_notifications=0；sleep 後等 7 秒再喚醒，window policy showing=true、secure=true（立即 sleep/wake 的第一張仍是桌面，不算鎖屏證據）。

ui/45-hidden-lock-after-delay.png、47-hidden-expanded.png 已檢視：只顯示 Needs your OK: Place order／Unlock to see the recipient and content，金額、對象、商品及 Approve/Decline 皆未顯示。點展開要求 PIN，hidden-open-bouncer.txt 的 mBouncerShowing=true；保護畫面截圖為黑色，不能宣稱看到了 PIN 鍵盤。hidden-before-auth.json 證明解鎖前 FINAL=0。

解鎖後 ui/51-unlocked-notification.png 顯示金額 NT$590 及 Approve／Decline；此畫面另證實膠囊覆蓋 Decline（W5-02 必驗）。只在解鎖後點 Approve 一次，10:08:07.248 產生唯一 FINAL /final/p1，dup=false，W20261108-0001，僅假商店訂單、未付款。臨時 PIN 暫留供新版回歸，最終必須移除並恢復設定。

### momo 網站自主搜尋與獨立核對（原答缺漏、補正完成）

Assistant 原答 2 steps／53 s／245K Token，前三筆 SM-JF48+SM-JF48、SM-SR48E+SM-SR48E、SM-ZB48E+SM-ZB48E，列表價 NT$999／1,177／1,177。未遇登入或驗證。

獨立開來源網址後，64-momo-independent-stable.png、65-momo-third.png 已實際檢視，三筆可見型號前段及價格吻合；標題均寫「買1送1」，不是單瓶。原回答只有型號相加，沒有清楚說明兩瓶組，記為資訊缺漏，不能評為數量資訊完全正確。已在同一對話要求依來源補正每組數量與單瓶換算；未做購物車／下單／付款。獨立頁為響應式列表，即使已切 Desktop 仍非原代理六欄布局，故未把版型相同列為通過。長標題尾端視覺截斷，尚未完整逐字核對。

### 閒置 QS／首頁完整對照

idle-overlay-snapshots.json 記錄：QS full window 10:10:27.982、accessibility 10:10:28.027、58-idle-qs.png 10:10:28.581；Home full window 10:10:30.815、accessibility 10:10:30.864、59-idle-home.png 10:10:31.770。兩張截圖已檢視；舊版 QS 上膠囊仍遮控制區。此組為無任務、面板穩定至少2秒的對照。新版 a1792d68 尚未安裝，不先宣稱修正通過。

補正結果：73-momo-correction-result.png、74-momo-correction-prices.png 已檢視，Assistant 明確說每組兩個480ml瓶，單瓶換算999÷2=499.50、1177÷2=588.50，並區分自行平均、網站列表價及未驗證結帳價。補正能力 PASS；原答數量描述缺漏保留。橫滑可到最右欄，舊版沒有滑動提示，供新版回歸。補正引用的商品頁組合內容尚未逐頁獨立核對，獨立確認範圍為搜尋列表三筆「買1送1」及價格。

### 雙品牌 helper 並存（功能回歸 PASS、跨品牌浮層有限制）

新裝 WOOW.4（SHA256 c7eaab4a86142a1788162a4b6594e6502697f2e55a8e8cc71a7b891c8a78eedc），原環境無此套件。兩個 USB helper 同時 shell 身分執行：Apporo PID4510、WOOW PID8312。App UID 分別10213／10216，dataDir 分開，見 system/*package-isolation.txt、dual-helper-processes.txt。WOOW 首次模型頁無既有服務商或金鑰（77-woow-model-empty.png 已檢視），沒有配 WOOW 模型。

Apporo 在雙 helper 存活時自主讀 Android Settings，7 steps／28s／130K Token，回報 Android16；83-independent-version-stable.png 已獨立檢視16一致。移除本輪 WOOW 後，其 helper 退出，Apporo PID4510 未變，見 after-woow-uninstall-settled-processes.txt。第二次自主讀值也回 Android16（2 steps／18s／65.1K Token），已通過。

並存 UI 限制：WOOW 膠囊蓋住 Apporo 右上新對話，79-new-phone-chat.png、81-dual-phone-result.png 已檢視，改用側欄可開新對話。此為跨品牌浮層遮擋，不宣稱並存介面完全無干擾。原有 io.woowtech.smart.debug 未動。

### a1792d68 Apporo.3 歷史回歸（當時有未通過項，後續修正見403）

原地升級成功（build/upgrade-a179.txt），USB helper 如預期需重跑，90-a179-helper-ready.png 已檢視「一切就緒」。英／繁錯誤說明提到更新後重跑並等 Ready，但「下方指令」用在沒有指令的設定摘要不精確；parent 已另修，尚未驗最終版。

雙 helper 最後回歸通過：WOOW 移除後 Apporo 2 steps／18s／65.1K Token 再讀 Android16（84-after-woow-phone-progress.png 已檢視）。

膠囊：一般無輸入焦點時 QS 會隱藏（96-a179-qs-hide.png），回首頁恢復圖示。**尚未整體修好**：輸入框焦點、ADB Keyboard 顯示時，QS 等6秒仍被整個面板遮擋（103-a179-qs-stable6.png）；草稿「W5 draft preserve 1027」保留。後補 full window/accessibility system/a179-draft-qs-* 與105截圖是鍵盤收起後的正常隱藏情境，不能當103失敗當下證據；需再重現並同步抓取。另第一次展開以及 QS 收合再開時面板偏右、超出螢幕（94、95、104）；關閉再開曾正常置中（99）。以上截圖均已實際檢視。96 的系統文字缺角原因未確認，不歸因 Apporo；103 已不是單純缺角，而是完整面板遮擋。

重要核准按鈕回歸 PASS：font2.0／density540，110-a179-en-approval-buttons.png 顯示完整 Allow／this／once 三行，112-a179-zh-approval-bottom.png 顯示完整允許這／一次兩行，拒絕都可見可點。實際拒絕後114-a179-summary.png 表示未送單，fixture FINAL 總數仍為先前鎖屏測試的1筆（本案例新增0）。摘要已改為 Activity · 2 min 15 s · 273K Token，未再顯示過濾後步數。大字體下縮圖遮住卡片上方內容仍存在，未遮底部按鈕；不將此寫成整張卡完全無遮擋。

付款接手卡重要按鈕回歸 PASS：font2.0／density540，116-a179-payment-en-bottom.png 的 I’ll／handle／it、Skip、Cancel task 完整，117-a179-payment-zh-bottom.png 的我來處／理、跳過、取消任務完整；已實際檢視。按跳過，未接手付款。英文任務內容切到繁中介面仍為英文，屬已生成內容保留，不算字串漏翻。


### a179 同步重現證據（10:37–10:39）

全程沒有 uiautomator，依序 screencap → 完整 dumpsys window → dumpsys accessibility → screencap，每份時間記於 chronology.json。

- `capsule-sync/02-offscreen-after-close-tap/`：前後畫面卡片均偏出右邊；WMS 卡片為 ACCESSIBILITY_OVERLAY、TOP CENTER、Requested w=0 h=0。
- `capsule-sync/03-offscreen-composer/`：切到對話卡仍偏出右邊；草稿 W5 draft preserve 1027 保留。嘗試點畫面上輸入欄時觸控穿到桌面 YouTube，未進行登入或其他操作，隨即 Home。
- `capsule-sync/04-offscreen-QS/`：無輸入焦點時 QS 正常隱藏卡片。
- `ui/125-focused-before-QS.png` 確認輸入游標及 ADB Keyboard。`capsule-sync/05-focused-input-QS/`：前後畫面完整對話卡均蓋 QS；此時 WMS mCurrentFocus 為 Apporo，Accessibility overlay id507 focused=true。這組才是故障當下同步 dump，先前 a179-draft-qs-window 對應的是正常隱藏的105畫面，不能代用。

已目視檢查各組 after.png（03另有122同狀態畫面），未把新合併修正版視為已通過。


### a179 表格提示（10:41–10:42）：PASS

同一回答包含 A/B 兩欄窄表及八欄寬表。129 截圖：窄表沒有提示，寬表下有英文 Swipe left or right to see all columns。實際橫滑兩次後 130 完整顯示 ColumnEight / END-MARKER；132 繁中提示為「左右滑動表格，查看所有欄位。」窄表仍無提示。三張均目視確認。語言切換曾回到先前 Wallet 對話，從最近對話重新開 Narrow and Wide 後完成繁中驗證。

父協調者通知：WOOW PR10 已合併，最新基線 main 1f96ab20 與 woow4 4ff45fc2 同 tree；Apporo d0ed39a9 合併主線無額外檔案變更。尚未安裝/宣稱通過待產出之合併修正版。


### 電腦存取取消與撤銷（10:43）

CLI connect 回 connected=true、server_version=0.1.37-apporo.3。實際交辦唯讀問題，回 waiting_for_answer、Display/Sound 選項與 Apporo Assistant note；cancel accepted 與最終 cancelled 以 mcp/cancel.json、cancelled-status.json 為證。MCP initialize HTTP200、serverInfo.title Apporo Assistant；tools/list HTTP200 列出10個工具。此次任務取消走 CLI task API，沒有把它冒充 MCP tools/call 的取消測試。

connect-computer.sh off exit0，mcp-usb.json 已移除；記憶體中舊 token 重新請求時連線不可用。這證實服務關閉，未宣稱觀察到 HTTP401。權杖只在記憶體使用，未落檔或輸出；本次臨時 forward 已移除。收據 mcp/mcp-revoke-receipt.json。


### 語言與深色補驗（10:44–10:49）

134–138：英文深色的外觀、記憶、技能、MCP伺服器、檔案計算環境，已目視檢查，未見截斷或品牌錯誤。未按清除、重設或新增外部服務。這是新增頁面抽查，非宣稱全部頁面均跑過暗亮矩陣。

App 設 Follow system，get-app-locales=[]；透過 Android 語言設定新增並切換繁體中文台灣為第一語言，system_locales=zh-Hant-TW,en-US，143 App 深色畫面自動繁中。再移除本輪新增的繁中系統語言，system_locales恢復 en-US，145 App 自動英文（144 為還原後的系統語言清單）。跟隨系統英→繁→英 PASS。暫保持深色供後續卡片測試，最終需恢復原外觀。


### 長問題選項與 MCP tools/call 補驗

147 深色問題卡及149極端字體2.0／密度540：兩個長英文選項完整換行，取消按鈕可見且可操作；150已顯示Stopped。字體、密度已恢復1.0／420。

MCP實際tools/call執行 mika_run_task → mika_wait_task → mika_cancel_task（cancelled=true）。緊接的status仍running，屬取消尚未完成；約24秒後再次透過MCP查詢最終cancelled（mcp/mcp-cancel-final-status.json）。不把cancel accepted當成已停止。最後再次off並移除本次forward。

**膠囊偏位是功能缺陷，非僅外觀。** 卡片可見但WMS尺寸為0，點可見輸入區曾穿透到底層Home的YouTube。修正版必須驗證非零Requested尺寸、輸入確實聚焦、草稿保留，以及開關三輪；不能只看卡片位置恢復。


### 相容性自我檢查（10:54–10:55）

40秒完成，App回報12 pass／0 partial／0 fail／0 skipped；153與154已目視，完整文字在 system/selfcheck-final.txt。helper以shell執行，虛擬螢幕1080×2400、ASCII/中文輸入/點按/捲動/返回、持續15秒更新、主畫面不被打斷、內建瀏覽器點按、echo與python3均通過。App copies 的PASS實際內容是0 usable other profiles，不能當成已測跨工作設定檔。自檢顯示build6989aed，APK檔案來源仍為父協調者提供的a1792d68 artifact且SHA已核對；不把UI build短碼改寫成來源head。


### 深色剩餘頁補查（10:56–10:57）

155 App access、156 Task running、157 Step limit對話框、158 Token usage 已目視確認英文版。未變動App封鎖、步數限制、自主模式或模型。Token usage 的模型長名稱使用省略號，圖表及數值可見；這是顯示抽查，非帳單精確核算。來源工具文字中的全形逗號（Trend，Daily）只出現在無障礙文字，畫面為分開標題，沒有視覺中文殘留。


### 英文明暗模式指定頁面矩陣（11:00–11:03）

目前 a179 APK、預設字體1.0／密度420；以下截圖均已目視檢查。授權頁檢查頁首與第三方元件區的顏色與排版，並非重新逐字掃描整份授權全文。

| 頁面 | 淺色證據 ui/ | 深色證據 ui/ | 結果 |
|---|---|---|---|
| Chat | 169-light-chat-actual.png | 177-dark-chat.png | PASS |
| Drawer | 167-light-chat.png（實際為側欄） | 176-dark-drawer.png | W5-03 頁尾名稱裁切 |
| Model | 161-light-model.png | 171-dark-model.png | PASS |
| Settings | 160-light-settings.png | 170-dark-settings.png | PASS |
| Notifications | 162-light-notifications.png | 172-dark-notifications.png | PASS |
| About | 164-light-about-actual.png | 173-dark-about.png | PASS |
| Licenses | 165-light-licenses.png、166-light-license-scroll.png | 174-dark-licenses.png、175-dark-license-components.png | PASS（外觀） |

W5-03：預設縮放下，側欄底部 About Apporo Assistant 超過可見寬度而裁切；淺深色均出現，屬外觀問題。模型頁 WOOW LiteLLM 是沿用測試服務商的自訂名稱，不判為品牌外洩。暫保持 Always dark，供最後 APK 回歸。

最終候選來源 403345ba 的共享／Apporo／WOOW CI 已由父協調者回報通過；PR 合併建置預期顯示 f142f04。尚待簽章 READY，不能把 CI 通過列為裝置回歸通過。

11:08 補驗 W5-03：179 重現裁切；直接點側欄 About 區域後180正常開啟關於頁，入口可操作。兩張已目視，故維持外觀缺陷分類。


### 403345ba 最終候選開始回歸（11:09–11:13）

SHA256與READY一致，覆蓋安裝成功。181英文／182繁中指引均正確指向「設定手機操作」裡目前的USB指令；重跑後183 Ready。預設縮放三輪打開卡片均居中，Requested840×1434（07/10/12同步證據），185/186/187實際輸入進入草稿，沒有穿透桌面。08有焦點QS、11無焦點QS、13有焦點通知欄均無Apporo overlay；收合後恢復泡泡，再打開保留W5 final draft 1111，第三輪可追加cycle3。所有after圖已目視。沒有用uiautomator干擾這組同步證據。極端縮放與橫向尚在測。

11:14–11:16 極端font2/density540：14卡片完整在螢幕內，189輸入聚焦，15有焦點QS及16無焦點QS均隱藏；17恢復草稿。預設縮放橫向需開系統Settings（Home固定直向）：19卡片置中，193輸入追加landscape命中正確；20橫向有焦點QS隱藏。極端系統QS字樣本身裁切，不是Apporo遮擋。還原font1/density420及原旋轉設定auto1/user0。這些是穩定前後截圖，未宣稱已用連續影片排除每一幀閃爍。


### 403 鎖屏私人內容與 P1（11:19–11:23）：PASS

先在任務進行中鎖屏，通知回覆 Will continue once you unlock your phone，沒有偷偷繼續；故解鎖待同意卡出現，再鎖屏。197/198通知只顯示 Needs your OK: Place order 與 Unlock to see the recipient and content，沒有金額、收款方、商品、直接同意按鈕。點通知觸發已驗證keyguard bouncer，私密輸入PIN後199卡片顯示NT590。核准前本案例FINAL=0；只點一次Allow this once，11:23:17.140產生一筆/final/p1（seq57），200任務完成，訂單W20261108-0002，未付款。fixture全輪累積2筆（含早先baseline1筆），不可誤算重複提交。

About194實際build f142f04，與來源403345ba／READY PRmerge對應。下一個待驗候選改為26ae3cad（大字體等待卡縮圖與側欄頁尾修正），尚未安裝，不提前算通過。


### 403 P5／P8（11:24–11:30）

P5 201付款接手卡只有Skip／I’ll handle it／Cancel task，沒有Allow this once；按Skip後202如實回報未付款、未完成，FINAL=0。

P8首次直接開checkout/pickup因購物車空白而返回cart，203如實停止，屬測試前置未備妥。補充從首頁加入假行動電源、選門市自取後，205顯示NT790折抵前的下單同意卡、優惠碼已輸入；Refuse後206回報未按Enter、未成立訂單，FINAL=0。實際timeline Step10明確是模型主動Ask for your OK，因此本輪不能宣稱驗到「模型不問就按Enter」的強制攔截；207／system/403-p8-actual-timeline.txt顯示Needed your OK／You declined，該拒絕步驟未標Worked。全輪fixture FINAL總數維持2（各次P1一次）。

11:30 以原始 prompts/momo-web.txt 開全新對話，開始驗證新版首次回答是否直接明列組數，不用追問補正。


### 403 momo 首答包裝數量（11:30–11:34）

原始提示詞、全新對話，37秒／94.9K Token完成。208–210首次回答直接寫buy-one-get-one，三項價格皆明確是two-bottle offer：SM-JF48+SM-JF48 NT999；SM-SR48E+SM-SR48E NT1177；SM-ZB48E+SM-ZB48E NT1177。不需要追問。回答區分列表價與未驗證結帳總額，列滿1111折111、折價券／登記／贈品等，沒有虛構登入完成或交易。

獨立用Chrome開同搜尋詞；211/212目視確認三項買1送1、型號開頭、價格、滿額優惠及前三項無Sponsored/Ad字樣。另透過Chrome CDP只讀此momo頁document.body.innerText，完整型號與買1送1均一致，存system/403-momo-independent-dom.txt與-url.txt；臨時forward已撤。來源長標題在畫面截斷，完整型號由DOM補證。

限制：Assistant另稱第2/3項marked discount already applied；獨立Chrome手機版畫面及DOM沒有此文字，未因此宣稱這個徽章也獨立核對通過（可能桌面版排版不同，仍需來源證據）。包裝數量修正與可核對名稱價格通過；保留舊版首答漏組數及追問補正紀錄。


### 26ae3cad 最終候選定向回歸（11:44 起，進行中）

原地安裝 apporo.3/3803，SHA256 dd25e6a37f2b01d586d650a8b31b5ff8111fbf735a3a9776b6300a7b1fa7b617；214 About 已目視 Build c983c25。USB helper 重跑目前指令恢復。26 不代表重跑全部 a179/403 案例；本段是新修正定向回歸。

側欄 footer PASS：213/219 一般深/淺，218/220 font2 density540 深/淺，Settings、About Apporo Assistant 全文完整，極端時 About 自動換行；點擊 About 成功（214、217）。216 截圖在縮放生效前，不能當極端證據。

新缺陷 W5-04：217 About 內容版本列於 font2 density540 把 Beta 擠成四字直排，Build未在該畫面顯示；標題省略。這是 About 內容排版，不是已修好的側欄 footer。已回報 parent，未宣稱所有大字體頁面無裁切。

26 P1 preview PASS：226 執行時手動拖到左上；228/229 等橫幅自然退去後 font2/density540 卡片無 PiP，長內容可捲到底且完整 Allow this once 可達；230 font1.5/density480 同樣無 PiP；231 回 font1/density420，等待卡上的 PiP 恢復左上。再切極端縮放，233 核准一次，234 Running 狀態 PiP 恢復左上。235 任務完成，僅新增一筆 FINAL（seq89，11:52:09.711，W20261108-0003），未付款。26-p1-finals.json 為收據。

另列 W5-05：227 系統 heads-up 在 font2/density540 把 Amount:NT$... 截斷，卻仍提供 Approve；這不是 App 內 PiP。parent 已決定改通知為 View 開完整卡，待新版才驗，26 不宣稱此項通過。

26 P5 PASS：237 長付款卡、238 卡底，font2/density540 沒有PiP，NT500與Skip/I’ll handle it/Cancel task 完整；選Skip，241回報未付款、任務未完成，FINAL無新增。保留頁面2小時是產品行為，清理會關閉本輪頁面/移除本輪App。

26 自我檢查 PASS：247 已顯示 Run again；248 與 system/26-selfcheck-report.txt 為最終12 pass、0 partial/fail/skipped，42秒，build c983c25。244是尚未進入檢查頁、245/246仍在跑，不能用檔名當完成。App copies為0 usable profiles，保留限制。

26 背景提醒 PASS（事件/時序，非實機聲音）：USE_EXACT_ALARM granted，alarm window0 policy_permission，due11:59:41.397；enqueue11:59:41.448（+51ms）、alert11:59:41.655（+258ms），beep1/mute_reason0。+1/+5/+10 flags與originalFlags均AUTO_CANCEL、results群組、mIsInterruptive=true，無SILENT；該分鐘App autogroup事件0。+1/+5橫幅可見，+10已正常退去。收據26-reminder-flags.json、26-reminder-offsets.json、system/26-reminder-events.txt與alarm。26-reminder-watch是未成功送提示前中止的空觀察，不當實測證據；有效錄製為26-reminder-actual。

W5-06：ui/26-reminder-plus1.png、plus5.png顯示Home上的Background page running膠囊蓋住提醒橫幅右上標題，本文Time to stand up and stretch仍可讀。已回報parent；此為heads-up局部區域，不是403已通過的全屏QS/shade。未宣稱完全無通知遮擋。

12:01 唯讀回看403 momo任務：253–255 Step3來源截圖已目視，內嵌六欄縮圖不足以可靠辨認折扣小字，沒有新增模型請求；discount already applied限制保留。提醒heads-up事件11:59:41.930→47.681，約5.751秒。autogroup=0僅指11:59提醒窗口，完整events檔含10:52歷史進度通知分組，不寫全檔0。

W5-06 同步重現：capsule-sync/21-headsup-reminder-26，12:04:54.986→57.606，screenshot→完整window→accessibility→screenshot，前後均目視確認遮標題，無uiautomator。SystemUI TYPE_SYSTEM id1177 bounds(42,0–1038,375)、focused=false；Apporo overlay(423,147–1070,294)與之相交；Home仍focused。完整chronology已保存。

跨版本/服務限制：本輪沿用授權WOOW LiteLLM測試資訊，模型實際使用apporo/gpt-6.1-sol；先前WOOW基準chatgpt/gpt-6.1-sol路由不可用屬服務差異，不能說模型路由完全相同。USB helper跨APK更新遇StaleApk須重跑新APK目前USB指令，本輪403/26均依指引恢復；不是讓舊helper繞過APK驗證。真實手機聲音、platform新帳密登入、跨其他ABI、完整33頁雙語雙主題及所有OEM浮層尚非本輪已完成。

### 62587879 追加回歸（12:14–，About build 31f54d5）

- SHA256 核對後覆蓋安裝、重跑目前 USB 啟動指令。font2.0/density540 的 About Beta 與 Build 完整（258，已目視）。
- 英文 Network proxy 對話框已目視，取消未儲存（257）；MCP新增對話框因新版到達未補測。
- 通知只有 View／Decline（262）；View 返回目前任務，但先前已展開的側欄仍保留，需手動收合（263、272、273）。
- 任務執行及等待期間側欄禁止切換舊對話（260、272），所以 A→B 跨對話定向未能按指定流程驗證。
- 私人內容隱藏時鎖屏不顯示金額（264、265）；另暫設允許私人內容以露出 View（269、270），點 View 後 dumpsys 證明 keyguard bouncer=true，驗證 PIN 後返回 App；截圖271是黑畫面，不能作可見 PIN 畫面證據。PIN未入證據。之後已還原隱藏私人內容。
- View／解鎖／完整卡出現均未產生新FINAL，625-before-allow.json為0；12:20左右才在完整卡單擊Allow this once，結果已核對：12:20:13.960僅1新FINAL，見下段。

625 結果：12:20:13.960 唯一新FINAL，訂單W20261108-0004，Activity4m36s；274已目視。625-after-allow.json記錄完整server事件。View不送單、完整卡一次核准各通過。鎖屏View以270可見按鈕＋625-view-keyguard.txt bouncer=true驗證；271黑畫面不作視覺解鎖證據。

12:21–12:22 625唯讀補頁：275 MCP新增HTTP對話框欄位與選項完整，Back兩次取消，仍No MCP server added；276 Speech to text頁英文完整，原Built into the phone仍選取、Available，沒有選模型或送語音測試。兩張已目視。

### 49ac3518 heads-up與QS（12:26–12:30）

SHA256核對後升級、USB helper重啟。新任務開本機測試首頁並保留背景頁，建立12:28:26一分鐘提醒（49-alarm.txt，window=0）。capsule-sync/23–26保存before/during/after/fullQS同步截圖與window/accessibility，全程未uiautomator。24/before.png起拍12:28:26.640仍有長膠囊與banner重疊；49-panel-log.txt於12:28:27.336才yield=true；24/after.png（28.338起拍）banner仍在而膠囊已隱藏。25/after.png顯示banner消失後長膠囊恢復，280實點能開背景頁卡；26/after.png完整QS未遮擋。上述圖片皆目視。結論：避讓及恢復生效，但初始短暫重疊仍在，不能稱零遮擋；截圖耗時不等於精確影格曝光時間，不以此聲稱精確毫秒延遲。

### 49 蝦皮自主搜尋（12:30–12:34，登入阻擋）

沿用wave4原提示，搜尋https://shopee.tw/search?keyword=象印%20保溫瓶%20480ml。Assistant自行在27秒後Not finished，3 model round trips／59.1K Token；報告請登入與語言選擇框，未報商品或價格，沒有等待登入（282已目視）。無需取消已結束任務。獨立在內建瀏覽器重開相同公開網址、僅確認繁中語言選項，288目視「請登入／看起來您尚未登入。請登入以繼續，或返回首頁」，與原答一致；沒有按登入、輸入憑證或繞過。商品搜尋驗收BLOCKED，阻擋如實回報PASS。281縮圖與286顯示語言框。12:34關閉本輪手動頁面。

49最終判準：**PARTIAL（零遮擋目標）**。穩定避讓／恢復及QS通過；12:28:26.713及27.188讀取的a11y只有statusbar與Home，27.330才出現heads-up id1246，27.336 yield=true。系統尚未暴露視窗前仍有短暫重疊，不是未知owner重試，不能稱完全消除。

### slot5正常交接（尚非最終清理）

12:35:51 DONE，12:35:53 qemu全部退出、HEAVY_EXIT=0、review host healthy、SLOT_EXIT=0；heavy free、記憶體62%。收據slot/turnover-receipt.json。AVD保留Apporo49及臨時PIN供837回歸，fixture仍留本機；沒有執行中的Assistant任務。新時段前磁碟僅17GiB，未繞過21GiB門檻。最終反向helper及PIN/設定清理尚未完成。

### 83734282 定向 View 與旋轉（12:49–12:56，build b899a5e）

已核對SHA並覆蓋升級，重跑目前USB指令後就緒。291：原側欄開啟→通知View直接完整NT$590卡、側欄關閉；293–295：Settings→通知View回完整卡；300–301：普通Settings返回仍保留側欄，沒有反覆自動關閉。上述截圖已目視。

**新缺陷：View後進Settings（297）僅旋轉橫向，會自行跳回等待中的對話（298）；未再點通知或核准。** 12:55已回報parent，記FAIL，待新修正版回歸。旋轉已恢復。

837第一個P1最後Refuse，305目視Not finished，837-view-refusal-receipt.json證明新FINAL=0。另完成不需並行的A→B：Home閒置膠囊New chat建立B837（311/312），Recents返回已結束A（314/315，246K Token）；B通知316的View直接切至B837完整卡317。全程唯一執行任務，未核准；837-A-to-B-receipt.json新FINAL=0。此定向路徑PASS，不能外推尚待修正的提問／接手通知。

13:02 蝦皮交接：從原搜尋頁按登入，323目視空白手機號碼/Email/使用者名稱＋密碼表單，沒有輸入。公開入口 https://shopee.tw/buyer/login?__mobile__=1；實際含站台追蹤參數的網址存shopee-login-handoff.json。商品搜尋仍BLOCKED，觸發登入入口PASS，隨後關閉本輪頁面。

### 反向helper與最終裝置清理（13:03–13:07）

reverse-before-processes.txt：Apporo helper4137、WOOW helper5646同為shell。移除Apporo後僅WOOW helper5646仍在；再移除本輪WOOW後兩者皆退出，smart.debug3579未變。329 XML確認Screen lock=None；私有PIN檔刪除。cleanup-device-receipt.json記錄套件、helper、forward/reverse、IME/字體/密度/旋轉/隱私/a11y/debug均還原，own fixture/logcat已停、僅本輪momo Chrome分頁關閉。13:06:57 DONE，13:07:00 qemu退出，HEAVY_EXIT0、review host healthy、SLOT_EXIT0、heavy free；cleanup-slot-receipt.json為最終時段收據，早先slot5收據僅交接。通知82補修與剩餘矩陣移至Wave6。
