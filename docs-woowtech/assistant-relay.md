# 渥屋助理個人帳號中繼網站

服務：[assistant-relay.woowtech.io](https://assistant-relay.woowtech.io/)。登入沿用 [aiot.woowtech.io](https://aiot.woowtech.io/)。

這個目錄說明的是 **Cloudflare Worker + Durable Objects 中繼網站**，不是 APK。現有 [`tools/relay`](../tools/relay/) 是另一個 Go 閘道實作，本次不取代它；Paseo 的 `relay.woowtech.io` 也不屬於本服務。

## 文件與原始碼

| 內容 | 位置 |
| --- | --- |
| 網站、路由、中繼協定 | [`src/index.ts`](../tools/woowtech-relay-worker/src/index.ts) |
| Odoo OAuth 登入與帳號 | [`src/auth.ts`](../tools/woowtech-relay-worker/src/auth.ts) |
| App 必讀介面契約 | [`app-integration.md`](../tools/woowtech-relay-worker/docs/app-integration.md) |
| 部署、維運與回復 | [`operations.md`](../tools/woowtech-relay-worker/docs/operations.md) |
| 資安邊界與限制 | [`security.md`](../tools/woowtech-relay-worker/docs/security.md) |
| 部署與驗收紀錄 | [`DEPLOYMENT.md`](../tools/woowtech-relay-worker/DEPLOYMENT.md) |
| 登入故障分析 | [`login-incident-2026-11-10.md`](../tools/woowtech-relay-worker/docs/login-incident-2026-11-10.md) |
| 實機 MCP 連線紀錄 | [`device-connectivity-2026-11-10.md`](../tools/woowtech-relay-worker/docs/device-connectivity-2026-11-10.md) |

## 架構與資料流

```text
瀏覽器 ──登入／同意授權── aiot.woowtech.io（Odoo）
   └──回呼── Worker ── AccountAuth（帳號 → 個人通道）

電腦 CLI / MCP ── HTTPS /r/<tenant>/mcp 或 /api/v1
                         │
                         ▼
               該帳號的 RelayDurableObject
                         ▲
                         │ WSS /device，mika-relay.v2
                     已配對手機
```

每個帳號目前一支手機。帳號主體來自 Odoo 的不可變使用者 ID；通道識別碼由網站產生，不能由表單指定他人的帳號。原有單手機 `primary` 通道保留。

OAuth 使用 authorization code + S256 PKCE、一次性 state、瀏覽器 Cookie 綁定、精確 callback 及 `relay:identity` scope。登入權杖留在伺服器，瀏覽器拿的是短效 opaque session Cookie。這不是把 Odoo 帳號密碼交給中繼網站。

## 使用流程與網址

1. 在網站以 WoowTech 帳號登入並同意授權。
2. 在個人頁產生五分鐘內有效、單次使用的配對碼。
3. 手機設定閘道 origin 為 `https://assistant-relay.woowtech.io/`，輸入配對碼，開啟遠端存取。
4. 電腦使用個人頁的 `/r/<tenant>/mcp`，Authorization 使用手機提供的 **MCP 存取權杖**。
5. CLI 使用個人 API 路徑；相容指令碼在 [`downloads/woow-relay-cli.py`](../tools/woowtech-relay-worker/downloads/woow-relay-cli.py)。權杖應透過私人檔案讀取，不貼到文件或任務中。

| 值 | 用途 | 不可混用 |
| --- | --- | --- |
| 閘道 origin | 手機配對、WebSocket 與裝置資訊查詢 | 不要填入個人 `/r/.../mcp` |
| 個人 MCP URL | 電腦選擇帳號通道 | 網址本身不是操作授權 |
| 配對碼 | 單次換取裝置憑證 | 不是永久權杖 |
| `deviceToken` | 手機連 `/device` 與 `/device/info` | 不得貼進電腦 MCP 設定 |
| 手機 MCP 存取權杖 | 手機驗證電腦操作權限 | 不是網站登入或配對憑證 |
| `OWNER_KEY` | 伺服器管理與受保護診斷 | 一般使用者與 App 都不需要 |

網站登出只結束網站工作階段，**不會斷開手機**。撤銷配對會使裝置憑證失效並關閉通道。離線請求不排隊、不自動重送；`delivery_unknown` 代表結果不確定，不能直接重複提交付款等操作。

## App 與網站的相容性

歷史 App 把 origin + `/mcp` 當作電腦網址，並嚴格驗證 `/pair` 的回應。網站升級成多帳號後，這個根網址不再代表個人通道。

為避免破壞舊 APK，網站保留 `/pair` 原本兩欄位格式，新增 **`GET /device/info`**。新版 App 可使用已儲存的 `deviceToken` 取得正確 `mcpUrl`、`apiBaseUrl`，不必重新配對。完整驗證規則、錯誤碼與 App 待辦見介面契約。

本次 GitHub 匯入不修改 Android 原始碼；App 是否已整合此介面，應以後續 App 提交及實機測試為準。網站已支援不等於所有歷史 APK 已修正「複製設定」。

## 已驗證與未完成

- 本機：舊版配對、兩帳號隔離、撤銷、偽造路由拒絕、流量限制、OAuth 回呼保護與裝置資訊查詢。
- 正式站：實際 Odoo 登入／同意授權、模擬手機配對／WSS 轉送／撤銷、新介面查詢。
- 瀏覽器：取消授權後重試、登出、320／360／1280 寬度首頁與錯誤頁。
- 使用者回報的 Pixel：個人端點 MCP 初始化與 10 個工具清單成功，另三輪各閒置 22 秒後重新連線成功；沒有呼叫手機工具。
- 尚未全面驗收：新版 App 的裝置資訊整合、長期背景連線、網路切換、所有 Android 品牌、正式站同時兩名真人使用者的完整流程。
- 尚未實作：停用 Odoo 帳號時自動撤銷既有手機通道、月流量額度、端對端加密。一次暫時性離線的根因仍未確定。

詳細日期與證據以部署／事件文件為準，不把單次通過解讀為所有功能全面通過。
