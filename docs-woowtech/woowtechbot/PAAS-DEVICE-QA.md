# PaaS 真機驗收紀錄（2026-11-26）

本輪使用 POCO C85 / Android 15 上原簽章 `io.woowtech.agent`，版本 `0.1.37-woow.12`。不變更商店版。以下是進行中的紀錄，不代表完整推播驗收通過。

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
- 指定 `WOOWTECHBOT_FIREBASE_PROPERTIES` 執行 `:app:generateWoowtechReleaseResValues` 成功；確認四個必要資源存在且 project ID 正確，未輸出 API key。這只驗證建置設定，尚未重包／替換手機 APK。
- 未建立 sender 私鑰；已向 PaaS 協調 workload identity 或專用發送身份的安全部署方式。
- 新的後端規格使用 `/api/woowtech/android-push/device`，不能向舊 `/api/push/device` 送擴充欄位。capability 缺席時維持 SERVER_NOT_READY。完整 HTTP adapter、受限 cookieOnly 測試及真實 FCM 尚未完成。
