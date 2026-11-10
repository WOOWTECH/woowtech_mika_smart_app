# main 到 App 更新

App 使用本儲存庫 `/releases/latest`。候選 prerelease、GitHub Actions artifact、沒有增加 versionName 的重建，都不會成為 App 的新版提示。

## 發新版

1. 在同一份 PR 增加 `app/brand.gradle.kts` 的 `woowtechRevision`（1..99），新增 `docs-woowtech/releases/v<版本>.md`。
2. 合併進 main。`woowtech.yml` 為尚未正式發布的新版本自動產生 APK 與 GPL 原始碼包。
3. 發佈機每五分鐘執行已審核的 `woowtech/release/publish.py`，只接受當前 main 同一 commit 的 `ci.yml` 與 `woowtech.yml` push 執行成功。下載核對 artifact SHA-256，檢查 APK 包名、版本碼與版本名稱，使用既有金鑰簽章並驗證憑證。
4. 先建草稿，四個附件（arm64／通用 APK、GPL 原始碼、SHA256SUMS）上傳及摘要核對後，才公開並標為 latest。不修改既有公開版本。同版本不重複發布、舊版本不降版；失敗留在日誌，下一輪重試。若 main 在上傳期間推進，草稿保留供人工檢查，不錯把它當最新 main 發布。
5. 手機打開 App 時自動檢查（兩分鐘節流），設定頁顯示更新提示；關於頁也可立即手動檢查。下載後 Android 要求使用者確認覆蓋安裝。

這不是 App 關閉時的即時通知推播，也不會靜默安裝。只有推送程式碼而未增加版本號，不會產生新版本。CI、GitHub 網路、發佈機開機且登入都會影響更新可用時間。

## 發佈機

正式金鑰不進 CI。macOS LaunchAgent `io.woowtech.mika-release` 每300秒執行本機已審核的 worker；腳本更新需人工部署，不能把遠端分支腳本直接在簽章機上執行。

本機目錄：`~/.local/share/woowtech-mika/auto-release/`，包含安裝的 worker、日誌、鎖與各版本收據。API 使用發佈機既有 GitHub 登入；金鑰與密碼沿用私有路徑。不要把此目錄或認證檔提交到 Git。

檢查：`python3 <已安裝的 publish.py> --state <state目錄> --check`（不簽章、不上傳）。
停止：`launchctl bootout gui/$(id -u)/io.woowtech.mika-release`。

若新版本停留草稿，先看 worker 日誌與對應 commit 的 CI；若草稿的來源與 main 不同，人工確認後移除未公開草稿／標籤再重試，或改用新的版本號。不能覆寫已公開 APK。

草稿恢復：GitHub 的依 tag 查詢對未公開草稿會回傳404，worker 另查分頁發佈清單以找回同一草稿；失敗上傳遺留的 `starter` 附件會先清理再重傳。已完整上傳但摘要不同的附件仍停止發布，不能靜默替換。
