# 渥屋助理商店版：送審與實機驗收交接

> 2026-11-13 更新：WOOWTECH 已確認為機構帳戶；先前首頁列出的八個 App 未見 `io.woowtech.assistant`，尚未確認是否存在其他草稿。此交接檔保留較早背景；以 `PLAY_SUBMISSION_STATUS_2026-11-12.md` 為最新狀態。仍未上傳或送審渥屋助理。

狀態：準備中，尚未送審。套件 `io.woowtech.assistant`，與 GitHub APK `io.woowtech.agent` 共存。送審依據是最終 AAB、實際網路流量與 Play Console 畫面，不能從其他渥屋 App 的申報複製答案。

## 可借用的既有案例

| 案例 | 已核對的做法 | 本 App 的差異 |
| --- | --- | --- |
| [woowtech aiot Google Play](https://play.google.com/store/apps/details?id=com.woowtech.aiot) | 商店頁列功能、使用前提、支援聯絡方式與公開隱私政策。 | 助理會把使用者輸入送到自選模型服務，語音可能送辨識服務，另有 AI 回覆檢舉；Data safety 必須重新盤點。 |
| [woowtech smart 發布文件](https://github.com/WOOWTECH/woowtech-smart/blob/main/docs/android.md) | 建置、提交與 Play Console 軌道狀態分別驗證。 | 本專案是原生 Gradle AAB，不沿用 smart 的 EAS 提交流程或憑證。 |
| woowtech platform（Play Console：`io.woowtech.odoo`） | 已在 WOOWTECH 機構帳戶的 App 清單確認正式版；其公開政策與帳號刪除頁可作為網站配置參考。 | 不能直接套用其他 App 的 Data safety、帳號刪除聲明或簽章；助理應按自身最終功能與資料流核對。 |

## 現有可交付物

- 分支 `playstore/woowtech-compliant-20261111`；本機有已用專用上傳金鑰簽章、通過 bundletool 與 16 KB 對齊檢查的候選 AAB，並有 `tools/build-play-candidate.sh` 防止誤用未簽章包；仍未上傳 Play Console。
- 商店文案草稿 `PLAY_STORE_LISTING_DRAFT.md`、已公開的雙語隱私頁 `https://assistant-relay.woowtech.io/privacy/play`、審查資料草稿 `PLAY_CONSOLE_REVIEW_INPUT_DRAFT.md` 與圖文／影片素材已準備。舊 `PLAY_DISCLOSURES_DRAFT.md` 含已移除功能的敘述，不可直接填報。
- 最終 AAB 的套件、權限、服務與不含沙箱執行環境已核對。AI 回覆檢舉收件端已正式部署；POCO Debug 版的送達、管理員讀取及測試資料刪除均已驗證；`play.3` Debug 版又完成 ChatGPT 短對話與 HA MCP 列表。實測界線見 `PLAY_POCO_ACCEPTANCE_2026-11-12.md`，均不等於 Play 軌道安裝或審核通過。
- 2026-11-12 重跑 `:core:test`：3,019 項、0 失敗、7 跳過。商店分支的獨立 README 不沿用原版 README 自動段落及翻譯結構，相關 4 項文件檢查明確跳過；其餘跳過為原有項目。中繼型別檢查、smoke、雙帳號測試、`wrangler deploy --dry-run` 均通過；正式 Worker 已部署 v3，檢舉線上測試通過。

## 目前需要負責人提供的事項

1. **POCO 安裝已完成**：商店版 Debug APK 已透過 ADB 安裝並與 GitHub 版共存；仍須由 Play 內部測試軌安裝最終簽署版本，不能把 ADB 安裝當成商店安裝驗收。
2. **Play Console 狀態**：WOOWTECH 已確認為機構帳戶；核對 `io.woowtech.assistant` 是否已有草稿、套件名稱是否可用及上傳權限。完成政策和出口聲明的事實核對後再建立 App，並查看「需要處理」、測試軌與應用程式簽章頁。請勿在聊天中傳私人金鑰。
3. **審查員測試方式**：提供可供 Google 審查員使用的模型服務測試帳號／受限 API Key，或選定可公開測試的免費模型流程；使用者自備 Key 的 App 仍需讓審查員進入核心功能。憑證走 Console 的 App access 欄位，不寫入 Git。
4. **隱私與檢舉營運**：公開 HTTPS 隱私頁及 App 內入口已存在；仍須指定每日處理 AI 檢舉的人，確認隱私聯絡信箱可持續收件，並在 Console 如實填寫資料處理情形。
5. **資料同步範圍**：依使用者後續決策，商店版保留對外 MCP 連線，移除電腦連接；先前手機在線時的遠端讀取記錄不應作為商店版現有功能宣傳。若將來需要跨裝置歷史，須另行設計及盤點資料保存、刪除與 Data safety。

## 技術與 Console 驗收順序

1. ADB Debug 版已完成上述功能中的多項實測，AAB 衍生版亦完成乾淨安裝與英／繁中首次設定；真正的 Play 安裝版仍須按 `PLAY_INTERNAL_TEST_CHECKLIST_2026-11-13.md` 重驗，尤其是官方 API Key、真人語音與前景服務通知。
2. 雙語隱私政策已公開並在 App 內有入口；正式填 Data safety 時，仍要和最終網路流量、第三方模型及檢舉營運逐項核對。
3. 對最終 AAB 檢查套件名稱、versionCode、target API、簽章、權限及服務；補 Play Console 的 App content、App access、內容分級、目標受眾、廣告、前景服務用途與商店圖文。
4. 先上傳內部測試軌，優先在乾淨、可使用 Play 商店的測試裝置安裝並驗證。POCO 現有同套件 Debug 版，若 Play 分發簽章不同，不可直接覆蓋或直接清除其資料；先核對簽章與資料保留方案。內測通過後再依 Console 當時的資格及要求進入正式軌；以 Console 顯示的處理／審核狀態為準。

Google 官方：[準備審核](https://support.google.com/googleplay/android-developer/answer/9859455)、[Data safety](https://support.google.com/googleplay/android-developer/answer/10787469)、[內部與封閉測試](https://support.google.com/googleplay/android-developer/answer/9845334)、[建立並推出版本](https://support.google.com/googleplay/android-developer/answer/9859348)。新個人帳號是否須 12 名測試者連續 14 天，按帳號類型和 Console 狀態確認：[官方規則](https://support.google.com/googleplay/android-developer/answer/14151465)。
