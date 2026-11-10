# 資安邊界與已知限制

## 信任邊界

HTTPS/WSS 在 Cloudflare 中繼終止。中繼技術上可讀取轉送的 Authorization、任務內容與結果；**不是端對端加密**。Paseo 僅是部署形式參考，不代表本服務繼承其加密設計。

Odoo 是登入身分來源；AccountAuth 儲存伺服器端 OAuth token 與 session，個別 RelayDurableObject 儲存配對／裝置憑證的 SHA-256 hash。網站 session 最長一小時且受 Odoo token expiry 限制，使用 HttpOnly、Secure、SameSite=Lax host cookie。網站查詢時進行 token introspection。

## 防護與限制

| 項目 | 目前行為 |
| --- | --- |
| 帳號隔離 | 不可變 Odoo subject 對應隨機 tenant；表單 tenant 不決定授權 |
| 登入 | S256 PKCE、一次性 state、瀏覽器綁定、精確 callback |
| 伺服器 HTTP | 固定 HTTPS 身分來源、15 秒逾時、禁止跟隨 credential redirect |
| 配對碼 | 五分鐘、單次使用，控制操作序列化 |
| 裝置憑證 | 只保存 hash；查詢／連線須通過驗證；撤銷後拒絕 |
| 手機操作權限 | 由手機驗證 MCP 存取權杖；網址不授予權限 |
| 轉送 | 每帳號每分鐘 240 請求、同時 8 個、body 1 MiB |
| 管理 | 每帳號每分鐘 8 次；Origin 檢查；撤銷二次確認 |
| 裝置資訊 | 每通道每分鐘 60 次；no-store；拒絕 Origin；不回傳權杖 |
| 斷線 | 離線不排隊，不重播請求；不確定交付明確回報 |
| 網頁 | CSP、HSTS、nosniff、no-store、同源表單限制 |

配額不等於完整 DDoS 防護，帳號入口目前仍為單一 Auth Durable Object。公開擴大使用前，需評估容量、帳號濫用及成本。

## 不能誤解的事項

- 網站登出不撤銷手機配對。
- 停用 Odoo 帳號目前不會自動斷開已配對的手機 WebSocket；仍需獨立撤銷裝置。
- 移除管理金鑰不是撤銷手機權杖；三種憑證用途不同。
- 月流量額度、完整稽核平台、災難復原自動化、端對端加密均未實作。
- 關閉 observability 不等於 Cloudflare 或其他基礎設施絕不產生日誌。不要在 URL query 傳送權杖；使用 HTTPS Authorization。
- 手機若開放遠端喚醒／解鎖，具有效手機權杖者可能具有相應能力。按最小權限開啟，不為測試擅自放寬。

## 發布與憑證處理

GitHub 只收錄程式、假測試資料、部署定位資訊與不含秘密的紀錄。不提交 `.env`、`.dev.vars`、Cloudflare OAuth、MCP URL credentials、owner key、真實手機權杖／配對碼、私人截圖或 Durable Object 狀態。

對話、日誌或第三方工具曾接觸的權杖，應依風險安排輪換；網站程式匯入 GitHub 不會替使用者自動輪換任何權杖。將疑似漏洞透過維護者的私人管道回報，不在公開 issue 貼秘密。
