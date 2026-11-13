# 渥屋助理遠端中繼網站

沿用此專案 Mika 原生 Go 閘道、`mika-relay.v2`、手機配對與 CLI/MCP 流程；不需要為了網站更換手機通訊協定。管理頁提供繁體中文、簡體中文及英文，依瀏覽器語言選擇，也可手動切換。

每個部署只支援一位管理者與一支手機。這不是多人註冊平台，也不能將另一套 Paseo 的 `relay.woowtech.io` 直接改指到這裡。

## 部署前準備

- 一台可長期執行 Go 程式或 Docker Compose 的主機。
- 一個專用網域，DNS 指向該主機，主機允許 TCP 80/443。範例 `assistant-relay.example.com` 並非已部署網址。
- 持久化儲存，保存裝置配對、管理金鑰與 HTTPS 憑證。只執行一個閘道實例，不做多副本負載平衡。
- 若主機已由 Nginx 占用 80/443，改照原版 [Nginx 指引](README.md#existing-nginx-server)，使用獨立虛擬主機；不要同時啟動 Caddy 占用既有連接埠。

網站是嵌入 Go 執行檔的實際管理介面，不能只把 HTML 上傳到靜態網站主機。一般 Workers 託管也不能直接執行這份 Go 服務。

## Docker Compose 部署

在 `tools/relay` 目錄執行：

```sh
cp .env.woowtech.example .env.woowtech
# 編輯 .env.woowtech，將 WOOWTECH_DOMAIN 改為你的專用網域（不含 https://）。
docker compose --env-file .env.woowtech -f compose.woowtech.yaml build
docker build --target caddy-check .
docker compose --env-file .env.woowtech -f compose.woowtech.yaml run --rm relay -init-owner-key -owner-key-file /data/owner-key
docker compose --env-file .env.woowtech -f compose.woowtech.yaml up -d
```

首次初始化只執行一次；既有管理金鑰不會被覆蓋。每次使用同一個 Compose 檔案，資料卷以 `woowtech-assistant-relay` 為專案名稱隔離。只有 Caddy 公開 80/443，Go 後端不公開主機連接埠。

在私人終端讀取管理金鑰，不要貼到對話、Git、工單或 MCP 設定：

```sh
# scratch 容器沒有 shell/cat；使用 docker compose cp 複製到權限受限的本機目錄。
(umask 077; mkdir -p .private)
docker compose --env-file .env.woowtech -f compose.woowtech.yaml cp relay:/data/owner-key .private/owner-key
chmod 600 .private/owner-key
```

`.private/` 必須保持私有，不要傳到其他人電腦。管理金鑰只用於網站管理。

## 實際使用流程

1. 開啟自己的 HTTPS 網站，輸入管理金鑰，按「產生配對碼」。配對碼五分鐘內有效且只能使用一次；新碼取代舊碼。
2. 手機開啟「渥屋助理 → 設定 → 連接電腦 → 遠端」。填入網站顯示的閘道位址及配對碼，按「配對閘道」。
3. 配對成功後，另外開啟遠端存取。配對本身不會啟用連線；經閘道喚醒與解鎖預設仍關閉。
4. 回網站輸入管理金鑰並按「查詢手機狀態」。會分別顯示未配對、已配對但離線、通道已連線。這是當下快照，不是持續更新的在線監控；查詢受每分鐘管理操作限流約束。
5. 電腦 MCP 用戶端使用手機「MCP → 遠端」提供的設定，端點是 `https://你的網域/mcp`。`Authorization: Bearer ...` 使用手機存取權杖，不能填管理金鑰、裝置憑證或配對碼。
6. CLI 使用手機「CLI / Skill → 遠端」的指引；每次指定閘道 URL 和私人 token 檔案。`connect` 不會儲存遠端設定檔。

網站不要求輸入手機存取權杖，不將管理金鑰寫入 localStorage/sessionStorage 或填回 HTML。唯一偏好 cookie 是語言。既有瀏覽器密碼管理工具的儲存選擇由使用者自行管理。

## 暫停及撤銷

- 暫停：手機關閉遠端存取，關閉通道與自動重連，保留配對。
- 撤銷：網站輸入管理金鑰，按「解除手機配對」並確認。撤銷成功會斷線。手機上保留的舊憑證無法再連入，需清理舊配對後重新配對。
- 手機解除配對：先關閉通道，再通知閘道撤銷；網路失敗時保持關閉並保留資料供重試。
- 換手機存取權杖：讓舊電腦權杖失效，與撤銷配對是不同操作。重新配對不會自動更換手機權杖。
- USB 與 Wi-Fi/VPN 各自開關不會因遠端關閉而一起關閉。已建立任務也不保證取消；要停止任務，先取消並確認結果。

## 資料與故障行為

HTTPS/WSS 在閘道或其反向代理終止；閘道可讀取轉送標頭、任務與結果，並非電腦到手機的端對端加密。手機鎖屏憑證留在手機。服務不記錄請求內容及金鑰；反向代理也不應加入會記錄這些內容的設定。

`device_offline` 表示目前沒有手機通道；`delivery_unknown` 表示請求可能已執行。先查任務，不要自動重送修改、付款、傳送或解鎖。離線不排隊，重連不重播請求。`/healthz` 只驗證閘道程序，不能代表手機已連線或任務能成功。

## 驗證與停用

```sh
go test -race ./...
go vet ./...
go build -trimpath -o woowtech-relay .
# 從專案根目錄驗證真實 Go 閘道、正式 Kotlin 通道及 Python CLI：
./gradlew :core:relayTest
```

部署後還需驗證正式 HTTPS、手機配對與手動開關、不同網路 MCP/CLI、斷網重連、撤銷後拒絕舊憑證及手機待機。程式測試通過不能取代這些實機驗收。

停止網站但保留資料：

```sh
docker compose --env-file .env.woowtech -f compose.woowtech.yaml down
```

不要加 `-v`，除非確定要刪除配對、管理金鑰和憑證。版本還原使用原有資料卷；還原舊資料備份可能恢復已撤銷的裝置身分。
