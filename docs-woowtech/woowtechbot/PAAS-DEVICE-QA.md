# PaaS 真機驗收紀錄（2026-11-26）

## 最新狀態：真 FCM 輪換、冷程序喚起與精確路由通過；專用登出驗收通過

3818 一般包已原簽章覆蓋安裝，diagnostics=false，30 項 core push 測試通過；交付 APK 與手機 hash 相符，firstInstallTime 保留，詳見 artifact.json。專用 android-qa-logout-lab53 新 profile 顯示未配對頁，原兩服務登入保留，登出與後端撤銷已通過（見下方核對），未測真正 cookieOnly 手機流程。

3817 一般包事件 `c1af0598-4d29-407c-90da-705d5523859a`：Home 後執行 `cmd activity stop-app`，發送前 PID absent、stopped=false，未手動啟動。PaaS bot→relay POST 起始10:36:12.012Z、FCM接受ACK10:36:13.289Z；手機 AMS 10:36:12.789Z 由 Google Play services 的 FirebaseInstanceIdReceiver 啟動 PID21939。實際通知 tag 對應此事件，點本文進 lab43 QA bot/composer，picker 勾選「未命名對話」而非 device thread。PaaS metadata 確認該項為原 seed 129113b5-a24c-4062-a9af-b56ef4eb0005。此為無程序後真 FCM 喚起與一般包精確 lab43 seed 通過；不是 force-stop 或低記憶體回收測試。lab53 精確 seed 目前歸屬先前診斷包結果。

3818 專用登出：獨立 profile `android-qa-logout-lab53` / serviceId `0443073a-d3d3-40ec-a190-24880be70b63`。PaaS 10:53:10.419967Z 固定 client/cookieOnly=false、server+relay revision1 ACK baseline 後，手機只操作該服務「登出服務」，最終顯示「已在這支手機登出」。通知頁短暫 PENDING 後回 REGISTERED。未按全域 OFF/deleteToken，原兩 profile 未登出。PaaS 10:54:58.018893Z 核對 session revoked、server absent、relay tombstone/tokenRemoved 全 true、revision1→2、pending事件0；原43/53的session/server/relay全部保留registered/revision1。

3818 一般包後續事件 `69381ac3-40d5-400a-8987-014a38b24f47`：PaaS 10:55:40.144Z 發送、10:55:41.258Z FCM接受ACK。手機 Home 背景 active tag 完整匹配原lab53/service/bot/seed/event，attention/SECRET；展開群組後精確點本文進 BotServiceActivity/原lab53/QA bot/composer。未點選thread，所有對話中seed灰底active、device無底，正常包精確seed通過。PaaS 10:58:39.439Z 只讀 messages=0 metadata 另確認 bot.threadId 正是 seed、device 未選中，沒有讀取訊息內容。此為人工fixture，不是自然模型完成。

後續僅移除已登出的專用本機服務；沒有可用cookie時App保守提示無法確認遠端撤銷，未把空cookie當成功。遠端撤銷證據來自前一步PaaS核對。此項不代替「仍有有效session時直接移除」驗收。

以下為歷次過程紀錄，狀態以本節最新摘要為準。

本節更新下方歷史紀錄。PaaS 回報 bot 0839、relay 0853 已部署，兩 lab enabled/ready、server/relay ACK，原手機 session 保留。

- `cededf26-cc1d-41a1-a3d7-879ee3fd2524`：3814 前景收到 lab53 seed 的 finished 通知。首次點擊只觀察 MainActivity，未確認點中本文，不先判定導頁 bug。
- `38db46c7-730c-4e57-88b2-50c8f6d43515`：3815 Home 背景、未 force-stop，收到 lab53 seed 的 permission 通知。展開群組後精確點擊本文，進 BotServiceActivity/lab53 QA bot/composer；但「所有對話」高亮 device-b76e869b，精確 seed thread 未通過。
- 兩筆皆為人工六欄 data-only fixture，沒有模型呼叫。FCM 接受為 PaaS 回報，手機實收以對應 notification tag/channel 核對；不列為自然模型完成。
- 3815 增加持久 pending inbox，等待冷程序身份發現完成；限制原始 TTL 最長600秒、容量、profile/identity 與去重。5項新 core 測試連同 HTTP14、push9，共28項通過。背景收件通過，系統回收程序後收件尚未驗。
- 3815 通知設定已顯示 REGISTERED，移除舊固定 SERVER_NOT_READY 提示。3816 修正 discovery 失敗、cookie 缺失或途中改變時，保留既有 ledger 並重試，避免誤觸 DELETE；最後 assemble 成功，安裝與雙服務保留待補。
- PaaS 合成 token 的 DELETE/登出 cascade 測試不等於手機驗收。手機輪換須依序：3816 雙 REGISTERED → PaaS 固定 baseline/ACK → UI opt-out → 雙 absent/舊 tombstone/token 清除 → opt-in → changed 布林與新 ACK。尚未執行本輪 opt-out。
- 0839 成品確認 `/?thread=<id>&bot=<id>` 格式正確，參數被一次性消費後網址回根路徑是預期；精確 thread 切換仍在定位。

3816 最終補編譯成功，原簽章覆蓋安裝成功、firstInstallTime 保留；手機與交付檔 SHA256 均為 `f16a55f10ff8e9cb4878e48862a74e22a122e0b44a258a6192d4ffe4c24bbb1b`，六個必要 DEX 類別檢查通過。通知頁實見 REGISTERED。

PaaS 於 10:12:33 UTC 固定雙服務 revision1/ACK baseline 後，手機 UI opt-out 顯示 OFF。PaaS 10:13:22 UTC 確認雙 absent、舊 relay tombstone/revision2、tokenRemoved 與 ACK 全 true，原手機 session 有效。收到確認後才按 opt-in，手機先 PENDING 後 REGISTERED；真 token changed 仍待 PaaS 比對，不能以新註冊代替。

無憑證的手機畫面證據見 [本輪 FCM 截圖](evidence/20261126-fcm/)。未保存通知欄其他 App 內容。

10:14:16 UTC PaaS 比對完成：lab43、lab53 `changed=true`、新 registration/revision1、serverRelayACK=true，舊 tombstone/token 清除狀態保留。這是實際手機 UI deleteToken/重新取得後的輪換，不是合成 token 測試。

輪換後第三筆 `be5a07e1-e536-45f7-a1a6-6a8e080f0b61`（lab43 seed、人工 attention）：Home 背景真收件，tag/service/bot/thread/event 對應正確；點擊本文進 BotServiceActivity、lab43 origin/QA bot/composer，跨服務路由通過。但未旋轉或 reload，立即開 sidebar thread picker 仍勾選 device thread，seed 未選；精確 thread 依然未通過。PaaS 獨立 client Chrome 用同一 deep-link 可 POST200 並選 seed，診斷 session 已撤，手機登入未動；下一步為本機顯式診斷包核對 target 是否在 Activity/WebView 初始化過程丟失，不修改 URL 格式。

### 精確 thread 修復對照

受控診斷事件 `22d4637c-e148-4763-b605-05e9e89466f3`：完整目標先載入（explicitTarget/threadPresent/targetQueryMatches 均 true），隨後 WebView 再初始化兩次，變成無 target、restore 舊頁。稍後 switchTask 雖發生，但 expectedTarget=false。診斷僅記布林與 HTTP method，不記 URL、headers、內容或憑證；先前即時觀察尚無 POST，完整後續 log 補上這項。

BotServiceActivity 改為原位處理與既有 MainActivity 同組畫面 configuration changes，避免頁面尚在解析目標時被銷毀並還原舊頁。新事件 `43cf83ec-017b-4361-abfa-311e17540690`：只一次 activityCreate/initial，完整目標載入，POST expectedTarget=true；手機選單 seed 高亮、device 未高亮，composer 可見。橫轉直沒有重新初始化，維持 seed。此為診斷包通過，3817 一般包尚待覆蓋與驗證。系統自動旋轉已恢復原值1/0。

本輪使用 POCO C85 / Android 15 上原簽章 `io.woowtech.agent`，初始版本 `0.1.37-woow.12`，後續升級至 `0.1.37-woow.13`。不變更商店版。以下是進行中的紀錄，不代表完整推播驗收通過。

## 測試範圍

PaaS 協調對話：`87403362b3664839bd9dcc34cdc37ba6`。Android 回覆對話：`ff9ee02365d04f45b296077c894a7a40`。

| 實例 | 專用 bot | 初始 thread |
| --- | --- | --- |
| lab43 `https://paas-cs-671d61b1-e823b18c.woowtech.io` | `07dd5fb3-968b-4b05-9c8c-09011a8e5aed` | `129113b5-a24c-4062-a9af-b56ef4eb0005` |
| lab53 `https://paas-cs-21bb5dd5-f28b74d7.woowtech.io` | `c7cbca1f-9556-44f1-8a62-25bd03013f98` | `b0a6dc06-dbaf-4401-90f7-feb30f2bbd91` |

只在上述 bot 建立 `android-qa-*` 測試資料。保留 lab43 既有 bot、thread、帳號與共用模型登入；lab53 由 PaaS 協調者於驗收完成後清除。兩服務未登入模型，不能驗證真實模型完成事件。

PaaS 回報來源映像 `20261126.0431@sha256:11214e6bc8b27b774a83603180efdefb2989189af1efb9f753cce16aa6b5b1d3`，共用 patches 在 `woow-paas/paas-odoo-ci`，main `e120fcabd2375f9f7041a3e4a51c702a48e15432`，上游 `b832de78c43c8d76e92d6f50fb1a8d33be364480`。

## 已觀察到的結果

- Mac 以正常瀏覽器 UA 請求 lab43 `/api/health` 回 200；未授權 auth/session 與 push/device 回 403，不能據此判定服務故障。
- 手機從原生「助理與服務」介面新增 lab43、lab53；兩者各自載入真實 HTTPS 配對表單。
- lab43 與 lab53 配對成功；PaaS 各確認新增一筆有效 session，`scopes=["client"]`、`cookieOnly=false`。lab43 初次查詢誤以產碼 label 篩選，後端以建立時間及瀏覽器 label 交叉核對後更正。
- lab43 配對後首次開啟 lab53 仍是空白配對表單；其後 lab53 使用自己的單次碼成功配對。
- 明確 force-stop App 後重新手動啟動，從原生服務清單分別開啟 lab43、lab53，皆未要求重新配對，顯示各自 QA bot 名稱／圖示。這是登入持續性測試，**不是 force-stop 後推播送達測試**。
- 發現兩服務內容區與 composer 空白；lab53 返回列表後也未顯示既有 QA thread，選擇「與 android-qa-lab53-20261126 開始新…」仍沒有輸入區。已向 PaaS 協調者回報 client 可見性與請求錯誤檢查；原因尚未確定。草稿、完整 thread 與登出隔離尚未通過。

## 憑證處理

Mac 沒有對應 PaaS authorized_keys 的 SSH 金鑰，未新增 SSH 授權。由協調者以本輪暫時 RSA 公鑰，採 OAEP-SHA256 / MGF1-SHA256 加密五分鐘單次 client 碼；本機僅在記憶體解密並輸入手機。文件、日誌、截圖不保存明文配對碼、cookie 或 session token。不得提交暫時私鑰或加密碼。

## 尚待完成

1. 排除已登入後的 thread／composer 空白問題；不得將可見 bot 標題等同完整對話可用。
2. 在兩個指定 QA bot 驗證 thread、草稿、返回、重新開啟與登出隔離。
3. Firebase 專案與 Android 設定已完成，見下節；發送端身份與中繼尚未部署。
4. 受限推播 capability、session 綁定與 relay 尚未接通；不得把普通 `via=cookie` 配對當成真正 `cookieOnly` 驗收。
5. 前景／背景／冷啟動的真實 FCM、token 輪換及伺服器撤銷仍待驗證。

## Firebase 設定（2026-11-26 後續）

使用者明確選定新建獨立專案，並指定透過本機 Chrome MCP port 12306 操作已登入的 Console。

- 專案名稱：WOOWTECH Assistant；project ID：`woowtech-assistant`。
- Android app：`io.woowtech.agent`，暱稱 `WOOWTECH Assistant Android Direct`。
- Console 確認 Firebase Cloud Messaging API (V1) 已啟用；舊版 API 停用。
- 建立時未啟用 Analytics 或 Gemini，保留 Spark 方案。
- 自有 `google-services.json` 下載後移至 repo 外私有目錄（0600），已由 `tools/woowtechbot/firebase_config.py` 驗證並轉成外部 properties。未提交 API key、服務帳戶私鑰或 FCM token。
- 指定 `WOOWTECHBOT_FIREBASE_PROPERTIES` 執行 `:app:generateWoowtechReleaseResValues` 成功；確認四個必要資源存在且 project ID 正確，未輸出 API key。其後已重包並覆蓋安裝 3813，見下節。
- 未建立 sender 私鑰；已向 PaaS 協調 workload identity 或專用發送身份的安全部署方式。
- 新的後端規格使用 `/api/woowtech/android-push/device`，不能向舊 `/api/push/device` 送擴充欄位。capability 缺席時維持 SERVER_NOT_READY。HTTP adapter 與普通／真 cookieOnly fixture 測試已完成；受限 cookieOnly 真服務測試及真實 FCM 尚未完成。

## 3813 原簽章覆蓋安裝與未就緒保護

- 2026-11-26：含獨立 Firebase client 設定與 v1 HTTP adapter 的 `0.1.37-woow.13` 已編譯、簽章核對及 `adb install -r` 成功。APK DEX 必要類別六項通過，手機與交付 APK SHA-256 一致。
- appId 10315、firstInstallTime 2026-11-09 13:12:33 保留；歷史對話、lab43/lab53 設定仍存在。lab53 仍能顯示已登入的專用 QA bot，沒有重新配對。未宣稱全資料庫逐項比對。
- 真機開啟「允許機器人通知」後顯示服務通知整合尚未提供（SERVER_NOT_READY）；沒有誤報 REGISTERED。此為 UI/未就緒保護驗證，沒有取得或檢查真 FCM token，也沒有真推播。
- lab53 的 WebView thread/composer 空白仍可重現，留為未通過。
- 2026-11-26：Cloud SDK 登入完成，WIF pool `paas-k3s-test`、provider `cluster1`、專用 SA 與兩項精確 IAM 綁定已實際建立；apply 後另一次唯讀驗證 `verified=true`。公開 JWKS、issuer、subject/UID condition、ACTIVE 狀態及沒有 user-managed key 均核對通過。
- project NUMBER `795023111689`；SA `woowtech-assistant-fcm-test@woowtech-assistant.iam.gserviceaccount.com`。配置與重現方式見 `tools/woowtechbot/wif/README.md`。
- 已向 PaaS 協調對話送達開始 STS／SA impersonation 正負向驗證的通知（HTTP 202）；通知送達不等於對方測試已完成。STS、真 FCM、lab 新版部署仍待回報與實測。

## PaaS 回報：實際 WIF 驗證（2026-11-26）

以下為 PaaS 協調者回報，非 Android 本機重跑：

- 一次性 Pod 的 kubelet projected KSA token（600 秒）核對 issuer、subject、UID、audience 與公開 JWKS 簽章後，Google STS 200、專用 SA impersonation（firebase.messaging scope，600 秒）200。
- FCM HTTP v1 `validateOnly=true` 測試 topic 回 200；只驗請求與權限，沒有手機通知，不算真收件驗收。
- 另一 KSA 的合法簽章 token（錯 subject/UID）被 attribute condition 拒絕；錯 token audience、錯 provider audience、篡改 UID 保留原簽章均拒絕。
- 未驗「相同 subject、合法簽章、僅 UID 不同」：未重建原 KSA，也未接觸簽章私鑰。不得以篡改簽章測試代替獨立 UID 條件測試。
- 臨時 Pod、ConfigMap、負向 KSA 已要求清除，尚待清除結果；原 KSA、lab sessions 與 QA 資料保留。sender 未啟用。
- 下一前置是 bot/relay 候選映像與 digest，PaaS 依既有 sealed approval 流程提供具體核可單；尚未收到候選成品或部署結果。手機 token、真 FCM 收件與 WebView 空白仍未通過。

## Android 追加真機測試（2026-11-26 16:41–16:44 台北）

設備與版本：既有 POCO、3813；未重新安裝、清資料或更換登入。

| 操作 | 實際結果 | 判定範圍 |
| --- | --- | --- |
| lab43 橫向轉直向；開啟 lab53 直向 | 兩個服務的 QA bot 標題可見，thread/composer 仍空白 | 失敗；不是僅橫向高度不足 |
| lab43 簡易模式引導視窗 | 完整顯示、完成按鈕可關閉；關閉後仍空白 | 網頁部分 UI 能渲染及回應觸控 |
| lab43 網頁返回、加號與開始新對話 | 列表與選單可操作，開始後內容仍空白 | 不宣稱新 thread 建立成功；已請 PaaS 核對並加 QA 名稱，未送模型訊息 |
| lab43 → lab53 切換 | 各自顯示正確 QA bot，未要求重新配對 | 登入保留與畫面服務對應通過；不等於完整隔離驗收 |
| lab53 中斷連線 | 顯示已在此手機中斷，lab43 列表狀態仍可開啟 | 本機開關狀態未連動其他服務；不是遠端 revoke 驗收 |
| lab53 重新連線 | 自動開啟原 QA bot，未要求配對；空白仍在 | 本機中斷／恢復的登入保留通過 |
| Home 後透過 launcher 重開 | 回到本機助理首頁 | 沒有恢復遠端頁；本次不列遠端背景返回狀態通過 |
| 鍵盤遮擋、草稿保存 | 無 composer 可供輸入 | 未測，不能列通過 |

`dumpsys activity top` 顯示直向原生 WebView 範圍 `0,0–720,1334`，排除零尺寸容器；這不是 CSS viewport 數值。列表搜尋列出現在螢幕 y475–561 附近而底下大片留白，已交 PaaS 對照 root/visualViewport 高度計算；尚未定位根因。近期 logcat 篩選沒有取得 Chromium ERROR/CONSOLE，不代表沒有前端錯誤。

截圖位於 [本輪證據目錄](evidence/20261126-device-additional/)。測試後已恢復原系統自動旋轉設定（accelerometer_rotation=1、user_rotation=0），lab53 已重新連線。未改商店版、未清任何 profile、未呼叫模型或發送推播。

## PaaS 對照與受控手機幾何診斷

PaaS 確認 lab43 新 thread `c566dd9c-8f21-495e-b76c-373dbc88a0ff` 建立於16:41:58，已命名 `android-qa-device-1642`，未發模型訊息。獨立 client Chrome 的四組橫直向 viewport，以及含 wv UA 的三組 viewport 均可見 composer，root 高度符合 viewport；這不是手機 WebView 驗收。診斷 sessions 已撤銷，手機 sessions 保留。

WIF 臨時 Pod、ConfigMap、負向 KSA 已由 PaaS 再次確認不存在。bot build49555 成功、sealed 核可單787建立；relay PR786五項CI通過，候選建置進行中。尚無雙映像部署結果。

新增 `-PbotViewportDiagnostics=true` 僅供明確啟用的 WOOWTECH 本機診斷包；所有預設建置為 false，其他渠道固定 false。固定 JS 只讀 bounding rect、computed CSS 高度鏈、viewport 與 feature 布林，不讀文字、輸入值、URL、cookie 或 storage，不新增 JS bridge 或遠端除錯。頁面完成後須仍為本服務同源、同一 WebView 才執行，logcat tag 為 BotViewportQA。本診斷不代表已找到或修復空白問題；測試後恢復一般包。

## WebView 高度塌陷修復與真機前後比較（16:56–17:00）

根因對照：原生容器有尺寸，但未指定 WebView LayoutParams 時，百分比 HTML 高度計算塌陷。修正只在 setProfile 後、loadUrl 前指定 MATCH_PARENT/MATCH_PARENT；未修改網站 CSS、session、權限或模型設定。

| 同一 lab43 橫向測量（CSS px） | 修正前 | 修正後 |
| --- | --- | --- |
| inner / visualViewport | 800×227 | 800×227 |
| html / body / root / app 高度 | 全0 | 全227 |
| composer y / height / bottom | -60 / 44 / -16 | 167 / 44 / 211 |

修正前 logcat 單行被截斷，但上述前段欄位完整；修正後使用分段 log，已重組為完整 JSON。診斷只取幾何欄位，證據見 [viewport-fix](evidence/20261126-viewport-fix/)。

同簽章診斷包實測：lab43 橫向與直向、lab53 直向均顯示 composer。lab43 鍵盤彈出後輸入區可見且可打字；未送出的測試草稿 `android-qa-draft-viewport` 在切到 lab53 時未出現，切回 lab43 保留；測試後已用 UI 清除文字。未發模型訊息。這驗證本次草稿與登入切換，不宣稱全部 thread 權限或完整資料隔離已驗收。

一般升級包使用3814並關閉診斷；安裝結果另記。歷史紀錄中較早的空白失敗仍保留作前後證據，現以本節修復結果為準。

3814 一般包驗證完成：assembleWoowtechRelease 成功；產生的 BuildConfig 確認 BOT_VIEWPORT_DIAGNOSTICS=false。原憑證 SHA256 `806b3db808ecbb4d2d032b34624baa7e193802f17a07afbde2a03e78da9474c8` 通過 apksigner；adb install -r 成功，appId10315 與 firstInstallTime 2026-11-09 13:12:33 保留。一般包重新開啟 lab43 不需配對且 composer 正常可見。交付 APK 與手機已安裝 APK SHA256 一致：`0769d54a3e34da51a9753aa0cde0d41b4defb148bc9e4c1659e9b3a15240aea6`。系統旋轉設定已恢復1/0，未送任何測試模型訊息。FCM 仍待後端部署與真手機收件驗收。
