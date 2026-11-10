# 部署與維運

## 範圍

此目錄保存 2026-11-10 已部署網站的程式。公開時僅調整開發／測試工具可攜性與文件，網站 runtime 原始碼維持部署版本。上線域名為 `assistant-relay.woowtech.io`，不得覆蓋 Paseo 的 `relay.woowtech.io`。

## 本機與 CI

需要 Node.js 22、npm；CLI 另需 Python 3.10+。Wrangler 版本由 lockfile 固定。

```sh
cd tools/woowtech-relay-worker
npm ci
npm run check
npm test
npm run test:accounts
npx wrangler deploy --dry-run
```

`check` 先執行 `wrangler types` 產生本機型別，再執行 TypeScript。`worker-configuration.d.ts`、`node_modules`、`.wrangler`、`dist` 均不提交。CI 只跑上述離線／本機測試，不登入 Odoo、不部署、不操作手機。

`npm run test:provider` 額外對正式 Odoo 發送一次無效假授權碼，驗證真正 workerd 的 HTTP transport；它需要外網，不屬於預設 CI。

## Cloudflare 部署

`wrangler.toml` 內 account_id、Worker 名稱、網域是部署定位資訊，不是憑證。若另建測試環境，必須一起修改 `src/auth.ts`、`src/index.ts` 中的固定 origin／OAuth client 及 callback 設定；不能只改 DNS 就認為可用。

1. 以有權限的 Cloudflare 帳號登入 Wrangler；憑證由本機管理，不提交。
2. 用密碼管理器產生至少 32 字元的隨機管理金鑰，安全備份。
3. 首次設定 secret：`npx wrangler secret put OWNER_KEY`。於提示中輸入，不放在命令列或 repo。既有部署不應無故重設金鑰。
4. 檢查 `RELAY`／`AUTH` bindings 及 v1／v2 migrations。保留現有名稱與儲存，不刪除 Durable Objects。
5. 通過本機測試及 dry run 後，明確執行 `npx wrangler deploy`。
6. 記錄版本 ID，驗證 `/healthz`、登入導向、未登入保護及測試通道。不要用真實使用者配對執行撤銷測試。

此 repo **沒有自動正式部署 workflow**。GitHub 提交本身不會更新網站或發行 APK。

## Odoo OAuth

需在受授權的 prod Odoo 建立專用 public client：

| 設定 | 值 |
| --- | --- |
| client_id | `woowtech-assistant-relay` |
| client_type | `public`，不使用 client secret |
| require_pkce | `true` |
| redirect URI | `https://assistant-relay.woowtech.io/auth/callback` |
| redirect match | `exact` |
| scopes | `relay:identity` |
| grant_types | `authorization_code` |

本程式使用 `/oauth2/authorize`、`/oauth2/token`、`/oauth2/introspect`、`/oauth2/revoke`。不自動部署 Odoo addon。

可透過已授權的 Odoo MCP 執行 `node tools/odoo-inspect.mjs` 唯讀檢查；`--register` 會在 client 不存在時建立，已存在時只讀取，**不是自動修正差異**。

將 MCP URL 儲存在 repo 外的私人檔案（權限 0600），設定 `WOOWTECH_ODOO_MCP_URL_FILE` 指向它。也支援 `WOOWTECH_ODOO_MCP_URL`，但不得將值放進提交、截圖、shell history 或 CI。工具使用 MCP 的 `default` instance；執行前確認它確實是授權的目標。

## 正式驗收（有寫入，需明確執行）

```sh
npx playwright install chromium
node test/live-login.mjs --prod --browser
```

這會透過 MCP 建立臨時 portal-only 帳號、正常登入與同意授權，測試專屬通道、新 `/device/info`、模擬手機 WSS 與撤銷。最後停用測試帳號、輪換其密碼並撤銷其 OAuth 權杖；不刪除稽核紀錄。測試帳號不是管理者，不寄邀請信。

需要先配置私人 MCP URL。測試程式依 client_id 與 `base.group_portal` 查詢 ID，不依賴特定資料庫流水號。若出現 `CLEANUP FAILED`，按輸出的測試 user ID 手動檢查；不得以刪除其他使用者來清理。

`RELAY_LIVE=1 npm test` 是歷史單手機測試，會操作 primary 配對。**不要對有真實手機的 primary 執行**；一般正式驗收使用獨立帳號腳本。

## 診斷與回復

- `/healthz` 只證明服務存活，不證明手機在線。
- 網站個人頁顯示配對／通道狀態；MCP initialize + tools/list 才能驗證手機 MCP 可達，仍不證明任務會成功。
- `/device/info` 是配對資料查詢，不是健康探針；不要持續輪詢。
- 受保護的 `POST /r/<tenant>/admin`，表單 action=`diagnostics` 加管理金鑰，可讀取連線狀態／tags／pending 數量，不回傳憑證。不要在 shell 命令列明文填入金鑰。
- `device_offline`：核對是否為個人網址，再檢查配對與手機遠端開關；不要直接清空帳號資料。
- `delivery_unknown`：結果不確定，先查任務結果，不自動重送。
- Worker 與既有 Durable Object 更新可能短暫不同版本，部署成功不代表每個既有通道立刻換版。不要藉重新配對掩蓋版本差異。
- 回復前檢查版本及 migration 相容性；程式回復不會自動回復資料。保留配對與帳號儲存。緊急停機只操作本 Worker／網域，不碰 Paseo 服務。

部署與稽核資料的備份、告警、月流量控管尚未由此 repo 自動化，不宣稱已有完整營運平台。
