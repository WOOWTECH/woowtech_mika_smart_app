# Apporo Assistant 遠端功能 Poco 實機驗收（2026-11-11）

## 範圍與環境

- 實機：Poco `25078PC3EG`，Android 15，ADB 序號 `ZHO7GIKRHYNRKZRC`。
- App：`com.apporo.assistant`，`0.1.37-apporo.8`，versionCode `3808`。
- 服務：正式的 Apporo Odoo 登入與同意頁、`https://assistant-relay.apporo.ai/`、個人 CLI/MCP 通道。電腦端以 Apporo relay CLI 和直接的 MCP HTTP 請求測試。
- 手機操作起初未設定；這輪在 HyperOS 開啟 Apporo 的「允許受限制的設定」、無障礙服務，並透過 App 提供的 USB 腳本啟動 helper，才進行真正的 UI 操作。
- 本次證據存放於 `~/.local/share/apporo-assistant/test-evidence/physical-remote-20261111/`。此報告及證據 JSON 不記錄帳號密碼、電腦 Bearer 權杖、裝置權杖或配對碼；含帳號通道的畫面留在本機證據目錄。

## 實測結果

| 功能 | 結果 | 實測內容與證據 |
| --- | --- | --- |
| CLI 連線、診斷、任務清單 | 通過 | 連到實機 `.8`；`doctor` 的連線狀態正常；遠端喚醒關閉時裝置狀態工具顯示不支援。`preflight.json`。 |
| MCP 初始化與工具 | 通過 | `initialize` 回協定 `2025-06-18`、Apporo Assistant 標題與 `.8` 版號；一般狀態列出 7 個任務工具。`mcp-preflight.json`。工具名稱仍採 `mika_*`，是既有協定名稱。 |
| CLI 實際執行 | 通過 | 手機上的 AI 以 Python 算 `7 × 8`，完成並回 `56`；wait、status、list 一致。`cli-task.json`。 |
| MCP 實際執行 | 通過 | MCP 交辦以 Python 算 `6 × 7`，完成並回 `42`；status、list 一致。`mcp-task.json`。 |
| 遠端操作手機 | 通過 | AI 從遠端開 Android 設定，回 Android 15 與電量 100%，耗時 51.6 秒；另以 ADB 的系統資料獨立核對。`phone-ui-task.json`、`phone-ui-verify.json`。 |
| 跨客戶端取消 | 通過 | MCP 建立的任務由 CLI 取消，狀態變 `cancelled`。`cross-client-cancel.json`。 |
| 重複提交保護 | 通過 | 相同 request ID 與目標回原任務；同 ID、不同目標回 HTTP 409 `conflict`。`idempotency.json`。 |
| 網站登入與授權 | 通過 | Poco Chrome 實際走 Apporo Odoo 同意頁；拒絕會回 `access_denied`，允許後到帳號頁。網站登出回公開頁，已配對的手機 CLI 仍連線。`consent-denied.png`、`account-authorized.png`、`account-signout-final.json`。 |
| 網站撤銷與重新配對 | 通過，見下方權杖觀察 | 點網站「Confirm disconnect」後舊連線回 `device_offline`；手機解除舊配對，用新碼重新配對並開啟遠端存取後恢復。已使用的配對碼再提交回 HTTP 403 `invalid_pairing_code`，測試暫存碼已刪除。`revoke-old-token-confirmed.json`、`repair-old-computer-token.json`、`pair-code-replay.json`。 |
| 遠端存取總開關 | 通過 | 關閉時 CLI 回 `device_offline`；開啟後恢復。離線提交任務回 `device_offline`，重連後同 ID 查詢仍為 `not_found`，沒有排隊。`remote-switch-off.json`、`remote-switch-on.json`、`offline-no-queue.json`。 |
| 身分與通道路由 | 通過（單一實際帳號） | 無權杖與錯誤權杖均回 HTTP 401；不存在的個人通道回 HTTP 404 `not_found`。`preflight.json`、`wrong-tenant.json`。第二個真實 Apporo 帳號的交叉存取仍需另測；雙帳號隔離先前只通過本機整合測試。 |
| 遠端喚醒與解鎖的權限邊界 | 通過；實際喚醒效果未證實 | 手機端兩道開關都開且 helper 就緒後，MCP 清單由 7 個增為 10 個工具；缺少其中一道開關時呼叫回 `disabled`，helper 不可用時回 `helper_unavailable`。按 Sleep 後系統進入 Dozing，`wake_device` 回 `awake`，但回傳狀態仍是安全鎖屏。因手機未設定供遠端使用的憑證，`unlock_device` 回 `credential_required`，沒有嘗試輸入。關閉兩道開關後清單恢復 7 個，直接呼叫也回 `Unknown tool`。`device-access-both-on.json`、`wake-from-screen-off.json`、`unlock-no-credential.json`、`cleanup-remote-state.json`、`wake-tool-hidden-call.json`。 |
| 已取消任務的保護 | 通過 | 對 `cancelled` 任務送 `answer` 與 `steer` 都遭拒，不能靠這兩個工具重啟。`closed-task-guards.json`。 |
| 開啟 App 的網站入口 | 通過 | 在 Poco Chrome 開 `https://www.apporo.ai/open-apporo-assistant`，點「Open Apporo Assistant」後切到已安裝的 Apporo。`deep-link-open.png`、`deep-link-success.png`。 |

## 尚未通過或需改善

1. **模型服務限流影響完整互動驗收。** `mika_steer_task` 已接受，狀態顯示指令加入任務，但任務最後因模型回 `too many requests; try again later` 失敗。之後只重試一次「AI 提問、電腦回答」流程，仍在提問前因同樣原因失敗。因此 steering 的最終產出與 `mika_answer` 對開放問題的完整流程**未驗證**；不能算通過。`steer-task.json`、`steer-task-failure.json`、`answer-flow.json`。
2. **網站斷開手機不會輪換電腦權杖。** 撤銷後舊電腦權杖暫時不能使用；同一手機重新配對後，它又能連線。這反映手機配對憑證與電腦權杖是兩套憑證。若使用者的目的是永久撤銷舊電腦或疑似外洩的權杖，還必須在 App 的「Connect a computer → Advanced settings → New token」重新產生權杖。網站確認頁應說明這點；本次沒有輪換正式權杖，以免讓既有電腦設定失效。`revoke-old-token-confirmed.json`、`repair-old-computer-token.json`。
3. **設定摘要錯誤。** 「Advanced & other」把「Connect a computer」顯示為 `Off`，但進入頁面後遠端總開關是 `On` 且網關已連線。程式碼 `SettingsScreen.kt` 的 `mcpOn` 只計算 USB 與 Wi-Fi，沒有計入 relay。`advanced-reopen.png`、`remote-offline-test-before.png`。
4. **從 Dozing 真正點亮螢幕尚未證實。** Poco 按 Sleep 後，系統的 `mWakefulness` 是 Dozing，但 App 的 `device_state.interactive` 仍是 `true`，`wake_device` 因而回 `awake`；後續擷取的鎖屏畫面為黑色。再後來的 Display State=ON 是在解鎖工具及人工互動之後量到，不能歸因於 `wake_device`。程式碼 `DeviceAccess.wake()` 只看 `interactive`，這是 Poco 常亮／Dozing 模式可能誤報成功的線索，需要獨立測面板喚醒。`wake-from-screen-off.json`、`locked-after-unlock-tool.png`。
5. **安全鎖屏中的任務完成與自動恢復未驗證。** 鎖屏交辦在觀察期維持 `running`，之後測試主動取消，最後為 `cancelled`；不能據此判定鎖屏操作成功或失敗。沒有手機端儲存的 PIN／密碼，本次也無法測憑證解鎖。`locked-task.json`、`locked-task-final.json`。
6. **第二個正式帳號隔離未實測。** 不存在的通道被拒絕，且既有雙帳號整合測試通過；仍須由第二個真實 Apporo 帳號在正式網站驗證看不到此手機。

## 收尾狀態

- 手機仍與原 Apporo 帳號配對、遠端存取開啟；CLI 可連到 `.8`。網站測試工作階段已登出。
- 遠端網關及手機本地的喚醒／解鎖開關均已關閉；MCP 只列 7 個一般任務工具。
- 最近 10 筆任務沒有 `starting`、`running` 或等待中的任務。ADB 臨時 Chrome DevTools 轉接已移除。手機操作的無障礙權限和 USB helper 仍保持就緒。
- 沒有執行真實購物、付款或帳號資料修改。本次沒有在手機輸入或讀取螢幕鎖定憑證。
