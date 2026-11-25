# 瀏覽器下載規格（2026-11-25）

owner 2026-11-25 決定：下一版（291 之後）內建瀏覽器恢復下載，**刻意與 Google Play 版不同**。2026-11-14 為對齊 Play 移除下載（`b96a1eb2`）；本文件是恢復前要求先定的「下載授權／檔案交付／清理規格」（[驗收缺口](ACCEPTANCE_GAPS_20261122.md)「瀏覽器下載」一列），實作在分支 `feature/ios-next-files-20261125`，**不在審查中的 291**。助理建立的檔案（file_create）用同一套交付與清理規則，見[文件產生](DOCUMENT_GENERATION.md#2026-11-25-助理建立檔案file_create)。

## 範圍

- 只有使用者自己在頁面上點的下載才會開始。瀏覽器沿用既有導覽許可：手動點連結、送出表單、上一頁、重新整理時發許可（`BrowserNavigationIntent`），WebKit 的 `didBecome download` 必須拿到同一次決策發出的許可，30 秒內有效、只能用一次。
- 研究、單次核准的頁面動作、路線重播不下載：直接取消，不顯示提示。
- 頁面腳本自己發起、沒有使用者點按的下載，子框架裡的下載，或許可不符的下載：取消，顯示「這個下載不是你在頁面上點選開始的，所以沒有下載。」。
- 只下載瀏覽器本來就能開的公開 HTTPS 網址；轉址也逐次檢查，最多 5 次。`blob:`／`data:` 網址的下載（部分網站的「匯出」按鈕）會被既有導覽規則擋下，目前不支援。
- 下載的觸發：`<a download>`（`shouldPerformDownload`）、`Content-Disposition: attachment`（不分大小寫、可帶參數），以及 WebKit 不能顯示的類型（`canShowMIMEType == false`）。
- **對話裡的網頁任務仍然不下載**。任務操作的頁面開始下載時，任務分頁取消它，執行器自動把頁面交給使用者（既有「需要你處理」卡片，原因「下載檔案」），模型收到 `download_needs_user` 和交接結果，提示裡也寫明不要再試。使用者按「我來處理」接手後，自己在頁面上點的下載跟瀏覽器一樣先問再下載。

## 授權

每一個下載開始寫入前，畫面最上層跳出提問（不論在瀏覽器或對話）：

> 要下載這個檔案嗎？
> 「檔名」／大小：（已知才顯示，否則「不明」）／來源：（網站名稱，不含網址路徑與參數）
> 下載後只存在這個 App 裡，可以再存到檔案、分享或附加到對話。
> 〔取消〕〔下載〕

- 提問出現在 WebKit 交回回應之後（`decideDestinationUsing`），才拿得到伺服器給的檔名與大小。WebKit 已送出請求、持有回應；按「下載」之前**不會有任何資料寫進 App 的資料夾**。「取消」或兩分鐘沒有回答，下載即結束，什麼都不保留（逾時會在清單顯示「兩分鐘內沒有確認」）。
- 一次只顯示一個提問，其他排隊。同一個下載只有第一次、且在時限內的回答有效。
- 不保存網址、查詢參數、Cookie、標頭、恢復資料或 WebKit 原始錯誤；只記網站名稱給提問與清單用。

## 交付

- 下載寫進 `Library/Caches/Downloads`：下載中在 `Partial/<UUID>/`，完成後移到 `Files/<UUID>/`。資料夾不備份（`isExcludedFromBackup`）、權限 0700，完成的檔案設為「首次解鎖前受保護」。不會出現在「檔案」App，也不會自動傳給任何人。
- 按「下載」後打開下載清單（半頁，可拉大）。下載中顯示進度與「停止下載」。完成時清單已關閉的話，畫面上方出現提示（「已下載『檔名』」／「『檔名』沒有下載」，10 秒後消失），點「查看」打開清單。瀏覽器「更多」裡的「下載項目」也能打開。
- 完成的檔案提供：
  - **存到檔案**：系統檔案面板存一份副本；選好位置才算完成，取消不算。
  - **分享**：系統分享面板；系統回報完成才算，取消不算。
  - **附加到對話**：只在對話讀得到這種檔案時出現（與挑選附件同一個 `ChatAttachmentReader` 判斷，例如 PDF、Office、文字、圖片；ZIP 不出現）。檔案以暫存副本進入對話的附件列，像從「檔案」挑選一樣，再切回對話；回覆進行中不能附加。
  - **移除**：刪除 App 裡的檔案並從清單移除。

## 限制

| 項目 | 值 | 說明 |
| --- | --- | --- |
| 單一檔案 | 200 MB（200 MiB） | 與對話附件上限相同，讀得到的下載都能附加。已知大小超過：不提問直接拒絕；大小不明：下載中超過即停止並刪除 |
| App 裡合計 | 500 MB（500 MiB） | 已完成未處理的檔案，加上下載中已收到或宣告的大小 |
| 同時 | 3 個 | 等待回答與下載中都算 |
| 回答時限 | 120 秒 | 逾時即取消 |
| 轉址 | 5 次 | 每次轉址的網址都要是允許的公開 HTTPS |
| 清單 | 20 筆 | 已結束的舊項目先離開清單；完成但未處理的檔案不會因此被刪 |

失敗都有明確訊息：檔案超過 200 MB、App 裡的下載已達 500 MB、一次最多 3 個、網路中斷（請在網頁上重新下載）、裝置空間不足（ENOSPC 與網路失敗分開）、網址不在允許範圍、逾時、下載資料夾不能用。

## 清理

- 存到檔案、附加到對話、移除：立即刪除 App 裡的副本。
- 分享完成：30 秒後刪除（接收端可能還在讀取）。
- App 啟動時（建立瀏覽器工作區時）：刪除所有 `Partial`（上次沒下載完的，WebKit 無法續傳）；刪除 `Files` 裡最後變動超過 24 小時的項目；其餘完成檔重新列在清單上，仍可存、分享、附加或移除。
- 清除網站資料時，先停止所有等待回答與下載中的下載。
- 只處理以大寫 UUID 命名的項目資料夾；不跟隨符號連結，其他名稱不動（`PendingFileFolder`）。
- 2026-11-14 之前版本放在 `Application Support/BrowserDownloads` 的舊下載，啟動時照舊刪除。

## 實作

| 部分 | 檔案 |
| --- | --- |
| 純規則（限制、提問狀態與時限、檔名、`Content-Disposition`、裝置已滿） | `ios/Sources/AssistantBrowser/BrowserDownloadRules.swift` |
| 項目資料夾、保護、清理 | `ios/Sources/AssistantBrowser/PendingFileFolder.swift`（建立檔案共用） |
| WKDownload 委派、提問佇列、進度、搬移與重啟後清單 | `ios/Sources/AssistantBrowser/BrowserDownloadManager.swift` |
| 瀏覽器導覽決策、`didBecome download` | `ios/Sources/App/BrowserSession.swift`、`BrowserWorkspace.swift` |
| 網頁任務交接、接手後下載 | `ios/Sources/AssistantBrowser/ChatWebTaskRunner.swift`、`ChatWebTaskTypes.swift`、`ios/Sources/App/ChatWebTaskTab.swift` |
| 提問、清單、提示 | `ios/Sources/App/BrowserDownloadViews.swift`、`ContentView.swift`、`BrowserView.swift` |

部署目標 iOS 17.0（`ios/project.yml`），`WKDownload` 與導覽委派的下載 API 為 iOS 14.5 起。

## 驗證與尚待真機確認

本機已執行（2026-11-25，`/usr/bin/lockf -k /tmp/woow-swiftc.lock`）：

- `check_browser_downloads.py`：Debug／Release 各 **62** 項全過（限制、提問與兩分鐘、檔名、Content-Disposition、ENOSPC、清理、重啟後清單、建立檔案的儲存上限），另 iOS 17 typecheck。
- `check_browser_site_modes_app.py`：真 WebKit，Debug／Release 各 118 項、loopback 12 項全過；手動點 `download` 連結現在得到 `.download` 決策且沒有錯誤訊息（探針在網路前攔下，不會真的下載）；研究／動作中的下載仍為 `.cancel`。
- `check_chat_web_task_core.py` Debug／Release 268／268、`check_browser_search_app.py` 170 項、`check_browser_manual_lan.sh` 622 項全過；App target 對 iOS 17 SDK typecheck 通過。

沒有執行 xcodebuild、模擬器或真機。完整建置後要實際確認：

1. 真實網站：`<a download>`、`Content-Disposition: attachment`、不能顯示的類型各一，提問的檔名／大小／網站正確；取消後清單沒有項目、App 資料夾沒有檔案。
2. 按「下載」前 WebKit 是否已大量接收資料（記憶體／暫存），兩分鐘逾時是否乾淨結束。
3. 進度、停止、200 MB 單檔與 500 MB 合計在真網路上的停止點；轉址；網路中斷與裝置空間不足的訊息。
4. 存到檔案、分享（含 AirDrop／郵件）完成與取消的回呼；分享 30 秒後刪除是否夠接收端讀完。
5. 附加到對話（PDF／Office）之後模型讀得到；回覆進行中按鈕停用。
6. 網頁任務遇到下載時出現「需要你處理：下載檔案」，接手後下載走同一個提問；任務繼續時模型不重試。
7. 重啟：下載中的被刪、完成未處理的重新列出、超過 24 小時的被刪；iPad 上提問、清單與分享面板的呈現；VoiceOver 與大字體。

隱私權政策與 App 審查備註不在本分支修改，由協調者與 owner 處理。
