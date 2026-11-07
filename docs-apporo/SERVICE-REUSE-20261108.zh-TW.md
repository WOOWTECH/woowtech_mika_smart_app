# 既有示範環境接續驗證（2026-11-08）

使用者已要求沿用渥屋助理與既有產品測試資料。本輪從歷史審查驗收紀錄找到 aiot、platform、smart 的既有示範環境，實際執行登入與唯讀 API 驗證。這是服務層驗證，不是新增的模擬器畫面驗收，也不是 Assistant 自主操作成功的證據。

| 服務 | 本輪結果 | 實測範圍 |
| --- | --- | --- |
| Apporo aiot | PASS | 既有家庭示範主機登入、交換權杖、API 認證、讀取 784 個實體狀態；包含 28 個 light、19 個 switch、295 個 sensor。沒有控制設備或註冊手機；測後撤銷本輪 refresh token。 |
| Apporo smart | PASS | 使用既有受保護配對資料，經 relay 讀回 2 個專案、2 個 agent；沒有交辦任務或批准既有待處理事項。 |
| Apporo platform | BLOCKED | 既有 demo111 審查站回覆 `odoo.exceptions.AccessDenied`。沒有成功建立登入工作階段，未讀取業務資料。此結果不能單獨證明是帳密過期、權限變更或 App 缺陷。 |

aiot 資料來源是既有產品的 `STORE-ACCEPTANCE-TEST.md`；platform 是既有 `play-login-details.en.txt`；smart 是既有審查主機與私密配對檔。這些不是 11/07 渥屋助理已完成的三個產品整合測試；當日助理報告明確記載 aiot 沒有安裝。

證據在本機 `~/.local/share/apporo-assistant/test-evidence/service-reuse-20261108/`：

- `aiot-results.json`、`platform-results.json`、`smart-results.json`：僅記結果與數量，沒有帳密、權杖、配對連結或專案內容。
- `check-aiot.py`、`check-platform.py`、`check-smart.py`、`smart-read.mjs`：重跑用程式，從既有來源讀取登入資料，不在程式內嵌入帳密。platform 認證被拒後沒有重試。

本輪開機前檢查發現 `release-woowtech-agent-followup-1108` 已持有 heavy slot，PID 14034，且模擬器正在另一輪測試中。因此沒有對現有模擬器安裝、點擊、dump、修改心跳或結束時段，也沒有暫停／恢復別人的測試。新一輪 Apporo 模擬器驗收仍待獨占時段。

後續可直接用已確認的 aiot 與 smart 環境做 Android 登入／配對，不需使用者重新指定房間或電腦才能開始。platform 需要可用的替換測試帳密；Assistant 自主操作需要替換先前已曝光的模型金鑰。實體手機聲音仍未驗收。
