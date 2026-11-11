# iOS 同倉庫遷移紀錄

iOS 為獨立 App，程式位於本倉庫 `ios/`，以 Android 渥屋助理作為外觀與功能對照基準。初次匯入使用 git subtree，來源為 `WOOWTECH/woow-assistant-ios` 的 `a1bf53f0a6a5490f6d969cc36bdce64851160ffc`；該提交是匯入提交的父提交，原始 Git 歷史保留在新倉庫的 ancestry 中。舊 repo 的 issue、Actions 執行紀錄、artifact、release、變數和 secrets 不會因 Git 匯入而搬移。

## GitHub Actions

可執行的 iOS workflows 位於倉庫根目錄 `.github/workflows/ios-*.yml`。來源模板保留於 `ios/.github/workflows/`，編輯模板後從倉庫根目錄執行：

```sh
python3 ios/scripts/sync_monorepo_workflows.py
python3 ios/scripts/sync_monorepo_workflows.py --check
```

產生的 workflow 把 shell 工作目錄設為 `ios/`，並把上傳 artifact 的相對路徑指向 `ios/build/`。一般 iOS 回歸只在 iOS 相關檔案或其 workflow 改動時隨 push／PR 啟動；其餘發行、真實服務及來源比對依各 workflow 的手動觸發條件執行。歷史的 `diagnose-ios17-runner.yml` 固定指向舊 repo 的特定執行紀錄，保留作歷史證據，未列為新倉庫可用驗證。

舊 repo 已設定的四個測試 secret 名稱為 `WOOW_HA_MCP_TEST_URL`、`WOOW_MODEL_TEST_API_KEY`、`WOOW_MODEL_TEST_BASE_URL`、`WOOW_MODEL_TEST_MODEL`；舊 repo 另有 `WOOW_MODEL_TEST_BASE_URL`、`WOOW_MODEL_TEST_MODEL` 兩個 variables。新倉庫已用使用者提供的測試設定建立這些名稱。GitHub 不提供讀回 secret 值；新倉庫的 live workflow 仍須實際執行，才能驗證設定與程式的整合。簽章與 TestFlight secrets 亦須依 [IOS_DISTRIBUTION.md](IOS_DISTRIBUTION.md) 核對；本次沒有轉移或建立這些值。

## 舊倉庫封存前

完成本分支與介面修正的審查整合，驗證新倉庫的 iOS 建置、測試與需要的真實服務 secrets／variables，並在 iPad 實機驗收後，將舊 repo README 更新為新位置與舊 issue／release 的存取說明，再依使用者授權封存舊 repo。不要把保留 Git 歷史當成 issue、Actions 或 secrets 已搬移的證明。
