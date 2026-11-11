# Apporo Assistant Poco 遠端問題修正與實測（2026-11-11）

## 範圍

在 Poco `25078PC3EG`（Android 15，ADB `ZHO7GIKRHYNRKZRC`）上，以相同簽章的 `0.1.37-apporo.9`／`3809` 測試 APK 原地更新 `.8`。手機的首次安裝時間仍為 2026-11-10 15:14:03。這輪將修正接上主分支最新的畫面擷取與首頁捷徑變更後，重新建置、簽章並安裝。最終簽章測試 APK SHA-256：`582ab00c5885f14efd0d86211c988fd12aeb65b8e9bdf62ec0bafa739eb92394`，簽章憑證 SHA-256：`3573aeaeecbbe99d5074ad424022a6e58ad2bbfd44ff2509862aa146afaf9169`，與 `.8` 相同。證據目錄：`~/.local/share/apporo-assistant/test-evidence/physical-remote-fixes-20261111/`。測試 APK 不是已發佈的更新。

## 修正與結果

| 問題 | 修正 | Poco 實測 |
| --- | --- | --- |
| 網站撤銷手機配對後，同一手機重新配對使舊電腦權杖恢復可用 | Apporo 每次成功建立新網關配對時，先換掉手機儲存的電腦存取權杖，再保存配對。解除配對對話框提醒使用者更新仍信任電腦的權杖。 | **通過。** 撤銷後舊權杖回 `device_offline`；重新配對並開啟遠端後，舊權杖回 `access_denied`，新權杖可連線到 `.9`。測試配對碼已刪，電腦端私人權杖檔已換成新權杖，沒有寫入報告。 |
| 遠端已開啟，設定首頁的「Connect a computer」仍顯示 Off | 摘要狀態計入 relay 開關。 | **通過。** 相同手機的 UI XML 在 `.8` 顯示 `Off`，更新 `.9` 後顯示 `On`；遠端實際連線正常。證據：`03-advanced-before.xml`、`11-advanced-after.xml`。 |
| Dozing 時 `wake_device` 回 `awake`，但未證實面板亮起 | 裝置狀態同時檢查 `PowerManager.isInteractive` 與主顯示器 `STATE_ON`；其中一項不符就不回報互動中。 | **實際黑屏喚醒通過；Dozing 特定狀態待複現。** 將無關通知的干擾隔離後，量到 `Asleep/OFF`，MCP `mika_device_state` 回 `interactive=false`；中途仍為 `Asleep/OFF`；呼叫 `mika_wake_device` 後量到 `Awake/ON`。通知干擾是另一個 App 的 `Websocket Issues` 警示，會自行亮屏。測試暫開的勿擾模式已還原為關閉。證據：`wake-e2e-dnd.json`。 |
| AI 提問後由電腦回答、steer 後的最終結果 | 無程式碼修正；先排除模型服務限流並重做完整任務。 | **待完成。** 原 `apporo/gpt-6.1-sol` 路由在這輪的簡單算式仍回 `too many requests; try again later`。證據：`model-preflight-start.json`、`model-preflight-wait-2.json`。 |

## 驗證與限制

- 本機 `:core:test`、`:app:assembleApporoRelease`、Apporo 原始碼及 APK 品牌檢查均通過；`git diff --check` 通過。
- 這輪只改 Apporo 新配對時的權杖輪換；Mika 與渥屋助理共用的配對行為沒有變動。
- 新配對會讓原本仍被信任的電腦也必須更新權杖；這是撤銷舊電腦存取的必要效果。
- Poco 上的 App 視窗設有 `FLAG_SECURE`，ADB 截圖會是黑色；判斷面板是否點亮使用系統 power/display 狀態，介面文字使用 UI XML。這些黑色截圖不能當作螢幕未亮的證據。
- `Asleep/OFF` 喚醒已證實，但本次隔離測試未重現 `mWakefulness=Dozing` 且面板 OFF 的特定組合；不能宣稱每一種常亮顯示／Dozing 模式都已驗證。
