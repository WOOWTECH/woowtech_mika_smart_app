# Apporo Assistant中繼：App 整合契約 v1

更新：2026-11-11。Apporo 專用中繼與 Android App 的契約；正式網站與新版 APK 仍需分別部署、驗收。本文不包含任何真實憑證。

## 保留現有協定

閘道 origin 是 `https://assistant-relay.apporo.ai/`。手機仍呼叫根路徑 `/pair`、`/device`，WebSocket 子協定仍為 `mika-relay.v2`。

`POST /pair` 的成功 JSON **不新增欄位、不更改舊 mcpUrl**：

```json
{"deviceToken":"<配對裝置憑證>","mcpUrl":"https://assistant-relay.apporo.ai/mcp"}
```

原因：現有 Kotlin App 嚴格解碼，並要求 mcpUrl 恰為 origin + `/mcp`。此舊欄位是相容性欄位，不代表個人帳號的電腦入口。新版 App 應另呼叫下列查詢，不得直接把相容性欄位作為個人連線設定。

## GET /device/info

原生 App 呼叫：

```http
GET /device/info HTTP/1.1
Host: assistant-relay.apporo.ai
Authorization: Bearer <配對時取得且已儲存的 deviceToken>
Accept: application/json
```

這是**配對裝置憑證**，不是手機的 MCP 存取權杖，也不是網站登入 Cookie 或管理金鑰。不要放進 URL、日誌、剪貼簿或電腦端 MCP 設定。瀏覽器帶 Origin 的請求會被拒絕，不開放 CORS。

個人通道成功回應（識別碼為佔位符）：

```json
{
  "schemaVersion": 1,
  "gatewayUrl": "https://assistant-relay.apporo.ai/",
  "mcpUrl": "https://assistant-relay.apporo.ai/r/<tenant>/mcp",
  "apiBaseUrl": "https://assistant-relay.apporo.ai/r/<tenant>/api/v1",
  "relayProtocol": "mika-relay.v2"
}
```

舊版單手機配對回傳根 `/mcp`、`/api/v1`，其餘欄位相同。伺服器從通過驗證的配對憑證選擇通道；不採用客戶端自填 tenant 或 x-relay-tenant。回應為 `Cache-Control: no-store`，不回傳任何權杖。

此查詢不建立／更換配對、不產生新憑證、不開啟或關閉 WebSocket、不喚醒手機、不提交任務。即使手機 WebSocket 尚未在線，仍可取得已配對的連線網址；**成功不代表 MCP 可用**。

錯誤 JSON 為 `{"error":"<code>"}`：

| HTTP | error | App 處理 |
| --- | --- | --- |
| 401 | invalid_device_token | 憑證錯誤、已撤銷或配對失效；停止把舊設定顯示為可用，提示檢查配對 |
| 403 | access_denied | 原生呼叫不應帶 Origin；不要透過網頁 JavaScript 呼叫 |
| 405 | method_not_allowed | 只使用 GET |
| 429 | rate_limited | 至少等一分鐘再試；上限每通道每分鐘 60 次，不做輪詢 |
| 404 | 舊伺服器未提供此介面 | 明確顯示不支援自動取得網址，讓使用者使用管理網站上的網址；不能把未驗證的根 /mcp 宣稱為個人通道 |
| 5xx／逾時 | 暫時性故障 | 保留已驗證設定並顯示暫時無法更新；有限重試，不自動解除配對 |

部署期間新 Worker 與既有 Durable Object 版本可能短暫不同；404 不能直接觸發重新配對。

## App 接手事項

1. 新配對：先按既有方式保存 deviceToken，再用它查詢 `/device/info`。
2. 既有配對升級：讀取原本加密儲存中的 deviceToken 查詢即可；不要求解除配對。
3. 嚴格檢查 schemaVersion=1、relayProtocol=mika-relay.v2。URL 必須與設定的 HTTPS 閘道同 origin（含 port），不得含帳密、query、fragment。
4. gatewayUrl 必須為原 origin 的 `/`；mcpUrl 只允許 `/mcp` 或 `/r/[A-Za-z0-9_-]{22}/mcp`；apiBaseUrl 必須與其同一路徑前綴並以 `/api/v1` 結尾。忽略未認識的未來欄位，不放寬 URL 驗證。
5. 保存通過驗證的 mcpUrl/apiBaseUrl，綁定目前 gateway + 配對憑證；換閘道、換配對或解除配對時清除舊資料。不要只依 deviceToken 字串猜測路由。
6. 「複製 MCP 位址」使用新 mcpUrl。「複製設定」的 url 使用新 mcpUrl，但 Authorization 仍是**手機 MCP 存取權杖**，絕不能改填 deviceToken。
7. 手機 WebSocket 仍連 origin + `/device`，不得改連個人 MCP URL。
8. CLI 使用 apiBaseUrl 或對應個人前綴；需支援個人路徑的相容 CLI，本站提供 `/downloads/apporo-relay-cli.py`。

## 驗收界線

網站測試涵蓋舊配對格式、個人通道查詢、兩帳號隔離、偽造路由、無效／撤銷憑證、HTTP 方法、Origin 拒絕及查詢後原 WebSocket 轉送仍可用。App 必須另外驗收新配對、既有配對升級、複製設定、離線／重試及解除配對流程。
