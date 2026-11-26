# PaaS 真機驗收紀錄（2026-11-26）

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
