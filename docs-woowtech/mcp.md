# 電腦連線（MCP）：讓電腦上的 AI 工具把事情交給渥屋助理

繁體中文 | [English](mcp.en.md)

> 想用 CLI 或 Skill？請看 [電腦端 AI 快速連線](agent-quickstart.md)。這份寫的是 MCP 用戶端怎麼直接連線。完整技術細節見上游的 [MCP 說明](https://github.com/wangzan101/Mika/blob/main/docs/mcp.md)（簡體中文；裡面的套件名是上游的 `com.wangzan101.mika`，渥屋助理要換成 `io.woowtech.agent`）。

打開「連接電腦」後，渥屋助理就是一個 MCP 伺服器。電腦上支援 MCP 的 AI 工具（MCP 用戶端）可以交辦事情給它，渥屋助理在手機上用自己的方式完成，再把結果交回去，例如操作 App、用內建瀏覽器、處理檔案。電腦只說要做成什麼，怎麼做由手機上的渥屋助理決定。

連線方式有兩種，各有自己的開關和權杖，可以同時開：

- **經 USB（建議）**：手機用傳輸線接電腦並打開 USB 偵錯，在電腦跑一個指令就能開啟，不用碰手機。它只在手機本機上監聽，Wi-Fi 連不到。
- **經 Wi-Fi 或私人網路**：在手機設定裡開，預設關閉。電腦和手機在同一個 Wi-Fi，或在同一個私人 VPN 網路裡，就能直接連，路由器不用設通訊埠轉發。

## 經 USB 連線（建議）

電腦要有 adb，`adb devices` 看得到手機，手機上的渥屋助理至少打開過一次；第一次打開時，它會把腳本寫到手機上。

1. 在電腦執行：

   ```
   adb shell sh /sdcard/Android/data/io.woowtech.agent/files/connect-computer.sh
   ```

   它會先啟動手機操作小幫手（已經在跑就跳過），再打開 USB 模式，最後印出連線資訊，內容有 `url`、`headers`、`token`、`port`、`forward` 等欄位。

2. 把電腦的 8765 埠轉到手機：

   ```
   adb forward tcp:8765 tcp:8765
   ```

3. 在 MCP 用戶端新增 Streamable HTTP（有的用戶端叫「HTTP」）伺服器：位址 `http://127.0.0.1:8765/mcp`，請求標頭 `Authorization: Bearer <權杖>`。設定範例見下面「經 Wi-Fi 或私人網路連線」，位址改成 `http://127.0.0.1:8765/mcp` 即可。

之後想再看連線資訊：

```
adb shell cat /sdcard/Android/data/io.woowtech.agent/files/mcp-usb.json
```

開啟以後要知道的：

- 通知欄會一直有「電腦連線已開啟」的通知，渥屋助理在背景時也會保持開啟。手機的「設定 › 連接電腦」一開始顯示「等待電腦連線」，收到請求後才顯示「已收到電腦請求」和請求時間。
- **拔插傳輸線後**（或電腦上的 adb 重啟），要再執行一次 `adb forward tcp:8765 tcp:8765`。權杖不變。
- 開啟狀態下再跑一次第 1 步的指令，權杖不變，設定好的用戶端照樣能用。
- **手機重開機後會關閉**。再跑一次第 1 步的指令即可；這時權杖是新的，要更新用戶端的設定。

關閉 USB 模式（任選一種；舊權杖立刻失效，連線資訊檔也會刪掉，下次開啟會拿到新權杖）：

```
adb shell sh /sdcard/Android/data/io.woowtech.agent/files/connect-computer.sh off
```

也可以在手機的「設定 › 連接電腦 › 進階設定」關掉「經 USB 連線」，或按通知上的「關閉」；按通知會連 Wi-Fi 模式一起關掉。

不用腳本、直接下指令也可以。注意元件名稱前半是套件名 `io.woowtech.agent`，後半的類別名稱和動作沿用上游：

```
adb shell am start-foreground-service -n io.woowtech.agent/com.wangzan101.mika.mcp.McpService -a com.wangzan101.mika.mcp.USB_ON
adb shell cat /sdcard/Android/data/io.woowtech.agent/files/mcp-usb.json
adb shell am start-foreground-service -n io.woowtech.agent/com.wangzan101.mika.mcp.McpService -a com.wangzan101.mika.mcp.USB_OFF
```

開啟後要等一兩秒，連線資訊檔才會出現。

## 經 Wi-Fi 或私人網路連線

### 在手機上開啟

1. 在渥屋助理打開「設定 › 連接電腦」，選「MCP」›「Wi-Fi / VPN」，再按「開啟網路存取」。網路存取預設關閉，只選指南不會打開它。
2. 開啟期間，通知欄會有「電腦連線已開啟」的通知，按通知上的「關閉」就能直接關掉。
3. 選一個電腦連得到的位址，按「複製設定」，加進 MCP 用戶端。複製的設定裡有位址和權杖；「預覽」預設收起，展開也只顯示權杖的佔位字。
4. 在用戶端連線或重新整理工具，確認手機頁面頂部顯示「已收到電腦請求」和請求時間。

存取開關、複製和更換權杖、遠端喚醒與解鎖都在「進階設定」裡，預設收起。權杖跟模型的 API Key 一樣，加密存在手機上。

### 從電腦連線

- **同一個 Wi-Fi**：用清單裡的 Wi-Fi 位址，通常是 `192.168.*.*` 或 `10.*.*.*`。
- **私人 VPN 網路**：手機和電腦加入同一個網路後，用清單裡該網路的位址；這類網路常用 `100.64.*.*` 到 `100.127.*.*`。
- 手機用行動數據，或對方是公開位址時，渥屋助理會拒絕連線。

在 MCP 用戶端新增「HTTP」（也叫 Streamable HTTP）類型的伺服器，填入位址，加上請求標頭 `Authorization: Bearer <權杖>`。各家用戶端的設定檔寫法略有不同，大多長這樣：

```json
{
  "mcpServers": {
    "woowtech-agent": {
      "type": "http",
      "url": "http://192.168.1.23:8765/mcp",
      "headers": { "Authorization": "Bearer <權杖>" }
    }
  }
}
```

## 工具

| 工具 | 參數 | 做什麼 |
| --- | --- | --- |
| `mika_run_task` | `goal`（必填）；`conversation`、`request_id`（選填） | 交辦一件事，立刻回傳 `task_id`。任務會記在 App 看得到的對話裡；要接著上一件做，帶上那件回傳的 `conversation`。 |
| `mika_task_status` | `task_id` | 任務現在的狀態、最新進度、在等什麼，完成時附上答案。 |
| `mika_wait_task` | `task_id`、`timeout_s`（選填，預設 30，最多 50） | 等到狀態改變或時間到，再回傳狀態。 |
| `mika_answer` | `task_id`、`text` | 回答渥屋助理在這件任務裡問的問題。 |
| `mika_steer_task` | `task_id`、`text` | 對進行中的任務補充指示（最多 4000 字）。 |
| `mika_cancel_task` | `task_id` | 停止任務。 |
| `mika_list_tasks` | `limit`（選填，預設 10） | 電腦交辦過的最近任務，新的在前。 |

工具名稱沿用上游的 `mika_` 開頭，改了電腦端工具會壞。建議流程：`mika_run_task` → 重複 `mika_wait_task` → 遇到 `waiting_for_answer` 用 `mika_answer` 回答 → 直到 `done`、`failed` 或 `cancelled`。

遠端喚醒與解鎖（`mika_device_state`、`mika_wake_device`、`mika_unlock_device`）預設關閉，要在手機「進階設定」裡自己打開，並在手機上設定兩次目前的 PIN 或密碼。電腦不能設定或讀取這組 PIN 或密碼。

## 安全

- **預設關閉**；只有開啟時才監聽，關掉立刻停止。
- **USB 模式只在手機本機（127.0.0.1）監聽**，電腦經 adb 轉發進來，Wi-Fi 和其他網路都連不到。
- **只有電腦能開啟 USB 模式並拿到權杖**：服務只接受 adb shell 這類有系統權限的呼叫方。權杖寫在 `/sdcard/Android/data/io.woowtech.agent/files/mcp-usb.json`；Android 11 起，其他 App 讀不到這個資料夾。
- **每個請求都要權杖**。同一個位址一分鐘內錯 5 次，會被擋一分鐘。
- **拒絕瀏覽器請求**：帶 `Origin` 標頭的請求一律拒絕，網頁無法透過你的瀏覽器連到這個埠。
- **只收私人網路**：兩端必須在區網、私人 VPN 網路或手機本機上；來自公開位址的連線會直接斷掉。
- **付款和確認只能在手機上做**：電腦交辦的任務裡，付款和需要你同意的動作一律不執行，不管有沒有開自主模式。`mika_answer` 只能回答問題，不能代替你同意。
- **電腦只看得到自己交辦的任務**：看不到、也停不了你在手機上開的任務。
- 連線是一般 HTTP，只在信任的網路上用。不要把權杖給別人；懷疑外洩就到「進階設定」換新權杖。

## 連不上時

- **清單裡沒有位址**：手機沒連 Wi-Fi，也不在私人 VPN 網路裡。
- **USB 腳本說檔案不存在**：先打開渥屋助理一次，等幾秒再試。
- **USB 連不上**（`curl` 回報連線被拒或被重設）：再執行一次 `adb forward tcp:8765 tcp:8765`；手機重開機過的話，先重跑第 1 步的開啟指令。
- **電腦的 8765 埠被占用**：換一個空的埠，例如 `adb forward tcp:18765 tcp:8765`，設定裡的位址改成 `http://127.0.0.1:18765/mcp`。手機端不用改。
- **HTTP 429**：同一個位址錯太多次權杖，等一分鐘。
- **任務一直沒開始**（呼叫立刻失敗，或兩分鐘後變成 `failed`）：在手機上打開渥屋助理再試。Android 有時會擋背景 App 自己開始工作，打開過一次就好。
- **任務一直是 `paused`**：手機多半鎖著。渥屋助理要手機解鎖才能操作。
