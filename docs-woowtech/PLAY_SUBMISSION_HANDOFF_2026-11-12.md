# 渥屋助理商店版：送審與實機驗收交接

> 2026-11-12 後續 Console 核對：WOOWTECH 已確認為機構帳戶；首頁列出的八個 App 未見 `io.woowtech.assistant`，尚未確認是否存在其他草稿。本次未建立或送審渥屋助理；完整狀態與舊文件落差見 `PLAY_REVIEW_READINESS_2026-11-12.md`。

狀態：準備中，尚未送審。套件 `io.woowtech.assistant`，與 GitHub APK `io.woowtech.agent` 共存。送審依據是最終 AAB、實際網路流量與 Play Console 畫面，不能從其他渥屋 App 的申報複製答案。

## 可借用的既有案例

| 案例 | 已核對的做法 | 本 App 的差異 |
| --- | --- | --- |
| [woowtech aiot Google Play](https://play.google.com/store/apps/details?id=com.woowtech.aiot) | 商店頁列功能、使用前提、支援聯絡方式與公開隱私政策。 | 助理會把使用者輸入送到自選模型服務，語音可能送辨識服務，另有 AI 回覆檢舉；Data safety 必須重新盤點。 |
| [woowtech smart 發布文件](https://github.com/WOOWTECH/woowtech-smart/blob/main/docs/android.md) | 建置、提交與 Play Console 軌道狀態分別驗證。 | 本專案是原生 Gradle AAB，不沿用 smart 的 EAS 提交流程或憑證。 |
| [woowtech platform 公開頁](https://apps.apple.com/tw/app/woowtech-platform/id6814763046) | 公開頁有隱私政策、支援和帳號刪除說明。 | 目前僅核對到 iOS App Store 頁，需負責人提供 Google Play 案例或 Console 紀錄才能參考其 Android 申報。 |

## 現有可交付物

- 分支 `playstore/woowtech-compliant-20261111`；Release AAB 可編譯，位於本機 `app/build/outputs/bundle/woowtechRelease/app-woowtech-release.aab`。AAB 尚未上傳 Play Console。
- 商店文案草稿 `PLAY_STORE_LISTING_DRAFT.md`、Data safety／隱私政策工作稿 `PLAY_DISCLOSURES_DRAFT.md`、政策與權限盤點 `PLAY_STORE_RESEARCH_2026-11-11.md`。
- APK 權限已核對；仍須按最終 AAB 重新檢查。AI 回覆檢舉中繼程式已通過測試，正式服務尚未部署與驗收。POCO Debug APK 已可 ADB 安裝；實測細節見 `PLAY_POCO_ACCEPTANCE_2026-11-12.md`。
- 2026-11-12 重跑 `:core:test`：3,019 項、0 失敗、7 跳過。商店分支的獨立 README 不沿用原版 README 自動段落及翻譯結構，相關 4 項文件檢查明確跳過；其餘跳過為原有項目。中繼 `wrangler deploy --dry-run` 通過，**未部署**。

## 目前需要負責人提供的事項

1. **POCO 安裝已完成**：商店版 Debug APK 已透過 ADB 安裝並與 GitHub 版共存；仍須由 Play 內部測試軌安裝最終簽署版本，不能把 ADB 安裝當成商店安裝驗收。
2. **Play Console 狀態**：確認開發者帳號是否為公司帳號；建立 `io.woowtech.assistant` 草稿 App，提供「需要處理」頁、測試軌與應用程式簽章頁的畫面或協作者存取。請勿在聊天中傳私人金鑰。
3. **審查員測試方式**：提供可供 Google 審查員使用的模型服務測試帳號／受限 API Key，或選定可公開測試的免費模型流程；使用者自備 Key 的 App 仍需讓審查員進入核心功能。憑證走 Console 的 App access 欄位，不寫入 Git。
4. **隱私政策實務**：確認 AI 檢舉、中繼與網站日誌的營運者、保存時間、刪除管道及聯絡信箱；指定公開 HTTPS 網址。完成內容審核後，需同一 URL 出現在商店頁與 App 內。
5. **資料同步範圍**：決定「同步」是僅手機在線時遠端讀取，或手機離線也要跨裝置歷史。後者需要帳號、伺服器儲存、刪除機制與 Data safety 再盤點；目前尚未實作。

## 技術與 Console 驗收順序

1. 完成手機安裝、首次啟動、模型登入／Key、真實對話、語音辨識、照片與文件附件、瀏覽器、記憶、AI 檢舉、外部 MCP 工具呼叫的實機紀錄。檢查崩潰與前景服務通知。
2. 定稿並公開隱私政策；在 App 內加入入口，驗證 HTTPS 頁免登入可由全球開啟。部署並驗證 AI 檢舉收件端；按最終網路流量填 Data safety。
3. 對最終 AAB 檢查套件名稱、versionCode、target API、簽章、權限及服務；補 Play Console 的 App content、App access、內容分級、目標受眾、廣告、前景服務用途與商店圖文。
4. 先上傳內部測試軌，用 Play 商店安裝到 POCO 驗證更新與基本功能；再依 Console 顯示的帳號資格選封閉測試或正式軌。以 Console 顯示的處理／審核狀態為準。

Google 官方：[準備審核](https://support.google.com/googleplay/android-developer/answer/9859455)、[Data safety](https://support.google.com/googleplay/android-developer/answer/10787469)、[內部與封閉測試](https://support.google.com/googleplay/android-developer/answer/9845334)、[建立並推出版本](https://support.google.com/googleplay/android-developer/answer/9859348)。新個人帳號是否須 12 名測試者連續 14 天，按帳號類型和 Console 狀態確認：[官方規則](https://support.google.com/googleplay/android-developer/answer/14151465)。
