# Apporo Assistant Poco 遠端問題修正與實測（2026-11-11）

## 範圍

在 Poco `25078PC3EG`（Android 15，ADB `ZHO7GIKRHYNRKZRC`）上，以相同簽章的 `0.1.37-apporo.9`／`3809` 測試 APK 原地更新 `.8`。手機的首次安裝時間仍為 2026-11-10 15:14:03。這輪將修正接上主分支最新的畫面擷取與首頁捷徑變更後，重新建置、簽章並安裝。最終簽章測試 APK SHA-256：`582ab00c5885f14efd0d86211c988fd12aeb65b8e9bdf62ec0bafa739eb92394`，簽章憑證 SHA-256：`3573aeaeecbbe99d5074ad424022a6e58ad2bbfd44ff2509862aa146afaf9169`，與 `.8` 相同。證據目錄：`~/.local/share/apporo-assistant/test-evidence/physical-remote-fixes-20261111/`。測試 APK 不是已發佈的更新。

權杖輪換、設定摘要及喚醒的完整操作是在接上最新主分支之前的 `.9` 候選包上完成；接上主分支後的最終包已在同一台 Poco 原地重裝，確認新版號及個人 MCP 通道仍可連到手機。兩包的上述修正程式碼相同；主分支新增的是畫面擷取與首頁捷徑變更。

## 修正與結果

| 問題 | 修正 | Poco 實測 |
| --- | --- | --- |
| 網站撤銷手機配對後，同一手機重新配對使舊電腦權杖恢復可用 | Apporo 每次成功建立新網關配對時，先換掉手機儲存的電腦存取權杖，再保存配對。解除配對對話框提醒使用者更新仍信任電腦的權杖。 | **通過。** 撤銷後舊權杖回 `device_offline`；重新配對並開啟遠端後，舊權杖回 `access_denied`，新權杖可連線到 `.9`。測試配對碼已刪，電腦端私人權杖檔已換成新權杖，沒有寫入報告。 |
| 遠端已開啟，設定首頁的「Connect a computer」仍顯示 Off | 摘要狀態計入 relay 開關。 | **通過。** 相同手機的 UI XML 在 `.8` 顯示 `Off`，更新 `.9` 後顯示 `On`；遠端實際連線正常。證據：`03-advanced-before.xml`、`11-advanced-after.xml`。 |
| Dozing 時 `wake_device` 回 `awake`，但未證實面板亮起 | 裝置狀態同時檢查 `PowerManager.isInteractive` 與主顯示器 `STATE_ON`；其中一項不符就不回報互動中。 | **實際黑屏喚醒通過；Dozing 特定狀態待複現。** 將無關通知的干擾隔離後，量到 `Asleep/OFF`，MCP `mika_device_state` 回 `interactive=false`；中途仍為 `Asleep/OFF`；呼叫 `mika_wake_device` 後量到 `Awake/ON`。通知干擾是另一個 App 的 `Websocket Issues` 警示，會自行亮屏。測試暫開的勿擾模式已還原為關閉。證據：`wake-e2e-dnd.json`。 |
| AI 提問後由電腦回答、steer 後的最終結果 | 在 LiteLLM 查出原 `apporo/*` 路線的上游帳號額度耗盡，將 Poco 測試主模型切到既有且可用的 `toypark1234/gpt-6.1-sol`，再由個人 MCP 通道重做完整任務。 | **通過。** `mika_wait_task` 先回 `waiting_for_answer`；電腦用 `mika_answer` 回答 `green`，獲 `accepted=true`。任務回到 `running` 後，`mika_steer_task` 要求最終回答加入 `POCO_REMOTE_STEER_OK`，獲 `accepted=true`，狀態為 `joined`。最終狀態 `done`，答案同時包含 `green`、`6 * 7 = 42` 與 steer 標記。App 畫面還顯示實際執行的 `python3 -c 'print(6 * 7)'`，不只是在答案裡聲稱用了 Python。證據：`answer-steer-e2e.json`、`answer-steer-ui.json`。 |

## 驗證與限制

- 本機 `:core:test`、`:app:assembleApporoRelease`、Apporo 原始碼及 APK 品牌檢查均通過；`git diff --check` 通過。
- 這輪只改 Apporo 新配對時的權杖輪換；Mika 與渥屋助理共用的配對行為沒有變動。
- 新配對會讓原本仍被信任的電腦也必須更新權杖；這是撤銷舊電腦存取的必要效果。
- Poco 上的 App 視窗設有 `FLAG_SECURE`，ADB 截圖會是黑色；判斷面板是否點亮使用系統 power/display 狀態，介面文字使用 UI XML。這些黑色截圖不能當作螢幕未亮的證據。
- `Asleep/OFF` 喚醒已證實，但本次隔離測試未重現 `mWakefulness=Dozing` 且面板 OFF 的特定組合；不能宣稱每一種常亮顯示／Dozing 模式都已驗證。
- 原 `apporo/gpt-6.1-sol` 和 `apporo/gpt-5.6-sol` 的失敗收據分別保留在 `answer-steer-e2e-before-model-switch.json`、`answer-steer-e2e-apporo-gpt5.6-route.json`；`chatgpt/gpt-6.1-sol` 的拒絕收據在 `answer-steer-e2e-chatgpt-route.json`。LiteLLM 直接呼叫 `apporo/gpt-6.1-sol` 回 HTTP 429，內層錯誤為上游 `usage_limit_reached`，該帳號預計 2026-11-17 20:05（台北時間）重置。Mac 用的 LiteLLM 金鑰 `/key/info` 沒有 RPM、TPM 或預算上限；提高這把金鑰的數值無法解除上游帳號額度。另一既有路線 `toypark1234/gpt-6.1-sol` 直接呼叫 HTTP 200 並成功呼叫測試工具，才用於 Poco 完整驗收。脫敏診斷：`litellm-route-diagnosis.json`。
- Poco 測試主模型目前維持 `toypark1234/gpt-6.1-sol`，讓後續測試可用；其他裝置、共用 LiteLLM 路由及金鑰額度沒有修改。跨 APK 更新後 USB 小幫手曾顯示停止；已執行目前 APK 產生的 `usb-start.sh`，確認 `com.apporo.assistant:helper` 以 `shell` 身分執行，系統的 Apporo 無障礙服務在 `Bound services` 清單中。`uiautomator dump` 會短暫中斷無障礙服務，不以 dump 當下的「Needs attention」字樣判定小幫手仍停止。
- 測試時暫開的「Allow wake and unlock through the gateway」已關閉；重新讀取 UI 時開關為 `false`，個人 MCP `tools/list` 只剩 7 個任務工具，沒有喚醒／解鎖／裝置狀態工具。遠端任務連線維持原本開啟狀態，最近 10 筆任務中沒有執行中的任務；勿擾模式為關閉。
- 提問／steer 的 API 規則已有 `RemoteTaskApiTest` 和 `McpTaskToolsTest` 覆蓋，包括只讓開放中的問題由電腦回答、steer 接收與 `joined` 回報。Poco 實機最終答案另有上述獨立收據。PR #21 在文件提交後的 Android、Core、CLI、Relay、品牌、英文 Android 35/36 和啟動檢查均通過；GPL 原始碼包作業按 CI 設計略過。
