# 渥屋助理商店版：送審進度與交接

更新：2026-11-12，Asia/Taipei。套件 `io.woowtech.assistant`，候選版 `0.1.37-play.3`、`versionCode=3`、target API 36。**尚未在 Play Console 上傳此版，尚未送審；是否已有此套件的草稿仍待確認。** 下列測試只證明列出的路徑，Google 的政策審核結果仍以 Console 為準。

## 已完成並有實測證據

| 項目 | 結果 |
| --- | --- |
| AI 檢舉收件與管理員讀取 | 正式 `assistant-relay.woowtech.io` 收件、獨立管理員金鑰讀取、錯誤金鑰拒絕、回執刪除及二次刪除 404 均已實測；測試資料已清除。管理員權杖保存在本機權限 0600 的檔案，沒有提交到 Git。操作指引見 `PLAY_AI_REPORT_OPERATIONS.md`。 |
| 使用者自行刪除 | POCO 上從 AI 回覆送出標記測試檢舉，再由同一回覆畫面確認刪除；正式收件端管理員查詢已不見該筆，App 本機佇列亦已刪除。無回執而可能已送達的狀態會保留本機紀錄並提示聯絡信箱。 |
| 30 天清理 | 報告在收到後 30 天起停止管理員讀取，Durable Object alarm 每小時清除到期資料。固定時間、超過 1000 筆分頁及 IP 限流紀錄清理有自動測試；**無法在今天觀察真實 30 天時間流逝**。上線後仍應監看排程與儲存量。 |
| 橫向側欄 | POCO 1600×720 畫面已直接顯示「最近」對話，清單可滾動至下方設定項。 |
| 隱私政策 | 雙語免登入頁 `https://assistant-relay.woowtech.io/privacy/play` 已公開，POCO App 設定入口可開啟；營運者與聯絡信箱已和既有 WOOWTECH Play 帳戶核對。 |
| 傳輸加密 | 商店版模型及 MCP 設定限制手機以外的端點為 HTTPS；Android 網路安全設定預設禁止明文，僅允許同機 `localhost`／`127.0.0.1`。POCO 實測私人 IP HTTP MCP 被拒，既有 HTTPS HA MCP 可連線並列出 77 工具。 |
| 簽章與安裝 | 用專屬上傳金鑰建置 `play.3` AAB，bundletool 驗證並在全新 Android 36 模擬器安裝分割 APK、啟動 App。這**不等於 Play 商店安裝**；最終 commit 後仍須重建並記錄 SHA-256。 |

## 尚需完成才能正式提交

1. **AI 內容防護決策與實作。** 現在仍允許任意自備模型端點，未有跨所有供應商的內容防護保證。Google 要求防止受限內容並提供 App 內檢舉。檢舉已完成；模型支援範圍或額外審核服務待產品決策及測試。[Google AI 內容政策](https://support.google.com/googleplay/android-developer/answer/13985936?hl=en)
2. **審查員可用的模型。** 需要穩定、可重複使用的測試模型位址／模型名／受限憑證，審查期間可完成真實對話且不要求一次性驗證。先前提供的模型端點曾頻繁限流，不宜直接當審查帳號。憑證只填 Play Console 受限欄位，不能提交到倉庫。[App access 說明](https://support.google.com/googleplay/android-developer/answer/15748846?hl=en)
3. **Play Console。** 在既有 WOOWTECH 機構帳戶確認是否已有 `io.woowtech.assistant` 草稿，建立或接續 App，完成商店圖文、內容分級、目標對象、廣告、Data safety、AI 內容、App access、隱私政策及前景服務聲明。`TaskService` 和 `ChatGptSignInService` 為 `specialUse`，需各自說明並提供實際操作影片。[FGS 申報](https://support.google.com/googleplay/android-developer/answer/13392821?hl=en)
4. **最終包與 Play 內測。** 以最終 commit 重建簽章 AAB，驗證上傳憑證、manifest、16 KB 對齊、bundletool；上傳內部測試軌後，從 Play 商店安裝到 POCO，逐一驗證首次設定、模型對話、外部 MCP、語音、瀏覽器、記憶與檢舉刪除。現有 ADB 與模擬器安裝不能替代這一步。
5. **Console 環境。** Chrome 已登入 WOOWTECH Play Console，但 macOS 的 `node` 控制 `System Events` 權限視窗目前尚未取得允許，因此不能在 Console 點選或上傳。此為 OS 權限，需由電腦使用者在視窗按「允許」。

## 待使用者提供／確認

- 選擇 AI 內容防護方案：商店版先只支援有可驗證安全措施的正式供應商，或保留任意自訂模型並提供額外內容審核服務。
- 提供可供 Google 審查期間使用的測試模型方案；請勿在對話中貼出正式 API Key，改由 Play Console 受限欄位填入。
- 在 Mac 上允許 `System Events` 權限，以便操作已登入的 Play Console。

相關較早研究資料保留作歷史紀錄：`PLAY_REVIEW_READINESS_2026-11-12.md`。其中 `play.2`、未簽章 AAB、尚無公開隱私政策等敘述已由本檔更新。
