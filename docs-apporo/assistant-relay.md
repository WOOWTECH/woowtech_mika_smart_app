# Apporo Assistant 遠端連線

Apporo Assistant 的遠端方案沿用手機現有的 MCP 與任務 API，為 Apporo 帳號建立獨立的雲端中繼。網站採英文版為主，網址預定為 https://assistant-relay.apporo.ai；身分驗證在既有的 https://www.apporo.ai Odoo 網站進行。這是 Apporo Assistant 的服務，不使用渥屋助理的網站、帳號配對資料或 Cloudflare Durable Objects，也不覆蓋 Apporo Smart 的 relay.apporo.io。

## 使用者流程

1. 在中繼網站選 Continue with Apporo，瀏覽器前往 www.apporo.ai 登入及核准「Apporo Assistant remote access」。中繼網站只收到限於身分確認的短期 OAuth 權杖，不取得 Odoo 密碼、網站 Cookie 或業務資料。
2. 回到個人頁建立五分鐘內有效、僅能使用一次的配對碼。在手機的 Settings → Connect to computer → Remote 開啟中繼網站、填入配對碼，再開啟遠端存取。
3. 個人頁與手機會提供專屬 MCP／CLI 網址。電腦連線使用手機另外核發的 MCP 存取權杖；配對碼與手機的裝置憑證都不能拿來當電腦權杖。
4. 中繼透過 WebSocket 把請求轉交在線手機。手機離線時不排隊，也不自動重送不確定是否送達的任務。需要斷開手機時在個人頁選 Disconnect phone；網站登出只結束瀏覽器會話。

## 組件與界線

| 組件 | 作用 |
| --- | --- |
| Odoo 附加模組 | 固定單一公開 OAuth 客戶端、精確回呼、PKCE S256、一次性授權碼、短期身分權杖、撤銷與每日清理 |
| Cloudflare Worker + Durable Objects | 保護個人頁、建立每帳號專屬通道、一次性配對、裝置 WebSocket 與 MCP／CLI 轉送 |
| Android App | 預填 Apporo 中繼地址、開啟登入網站、儲存配對及安全取得個人通道資訊；既有協定 mika-relay.v2 不變 |
| 電腦端 | 使用個人網址及手機 MCP 權杖；本站提供改成 Apporo 預設值的 CLI |

HTTPS/WSS 保障傳輸，但中繼服務在轉送時技術上能讀取請求與結果，並非對中繼營運者的端對端加密。網站登入不等於電腦端 MCP OAuth；目前需要可送 Bearer 權杖的 MCP 客戶端。實際 Apporo 帳號登入、手機連線與遠端任務都必須在部署後另外驗收，不能由本地模擬測試推論已通過。

實作及部署進度見 tools/apporo-relay-worker/DEPLOYMENT.md；Odoo 模組見 tools/apporo-relay-oauth/README.md；手機與網站契約見 tools/apporo-relay-worker/docs/app-integration.md。
