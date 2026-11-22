# TestFlight 271 發佈紀錄（2026-11-22）

**0.1.0 (271) 已可供既有內部群組下載，並已在原iPhone經TestFlight原地更新。** Apple回傳 `VALID`、`IN_BETA_TESTING`；上傳處理為 `COMPLETE`，errors／warnings為空。裝機與更新保留證據見下節；畫面及商用功能仍逐項驗證，不以安裝成功代替。

App `io.woowtech.assistant`／App Store Connect `6834435121`，WOOWTECH team `W4UWZ8NP2P`。沿用使用者上傳新版及原地實測授權，沒有公開上架、新增測試者或外部Beta送審。

## 來源與修補

來源提交 **`28deae96ca3a7718743d78e6d0ddc2a42d1be020`**，已推送 `origin/feature/documents-ios-android-20261120`。正式封存開始前工作樹乾淨，封存、線上驗證及上傳期間來源皆未變更。

- 「回到最新訊息」由覆蓋對話的浮層改成獨立列，viewport扣除控制區；保留原玻璃輸入框及80則分頁政策。
- 已知鍵盤與輸入框尺寸變化保留跟隨意圖，真正拖曳與閱讀停留仍優先。修正輸入框高度被預設零值覆蓋的通知，處理多行草稿遮住最後訊息。
- 空白處拖曳納入原手勢範圍；排隊的回尾請求在執行前再次檢查拖曳狀態。純串流增長不持續推遲版面穩定計時。
- 整合原iPhone270的半小時追蹤、手動記憶CRUD與清理證據。這些是270的結果，不是271重新驗完。

文件處理的後續候選（來源錯誤提示、CSV預覽UTF-8邊界、暫存額度分類及取消解析）**未包含於271**。後續主線修改不得倒推進已封存版本。

## 測試結果及界線

[完整回尾／鍵盤驗證](CHAT_RETURN_CONTROL_VALIDATION_20261122.md)保留全部失敗與來源雜湊。

| 執行 | 真實結果 |
| --- | --- |
| native286 | 短對話錯誤終態：1/1 PASS，112.314秒；單行／四行草稿、鍵盤收放、閱讀停留與回尾 |
| native287 | 3/4 PASS、skip0：附件第四輪117.130秒、no-op拖曳161.231秒、串流回尾178.592秒；80則跨頁123.138秒在AX讀取逾時失敗 |
| native288 | 僅重驗前述80則案例，1/1 PASS、skip0，100.656秒；送出→取消→停止訊息可見→返回原1998則合成歷史 |
| 其他必要檢查 | policy三項測試、測試類別登錄與語系檢查通過；inventory143為登錄總數，不是本次執行143案 |

五個不同案例分批通過，**不是同一輪全過**。287失敗、AX空樹、取樣時間缺口及未定位原因均保留；288沒有更改產品、斷言、時限或重送訊息。清理僅涉及本案可重建中間檔及可完整還原的合成檔壓縮，不以清理後通過宣稱資源根因成立。

上述native在iPhone17／iOS27 Simulator使用隔離DEBUG合成模型，實際執行App、存檔、鍵盤、手勢與渲染；**不是原iPhone、商用模型或Apporo MCP驗收**。VoiceOver未實測；新穩定期在VoiceOver執行時不啟用，沿用原保守閱讀政策。

## 封存、簽章及Apple回執

外部證據根目錄 `T=/Users/woowtech/Documents/WOOWTECH-iOS-validation/documents-20261120/testflight-20261122`；外層heavy／來源收據在其父目錄。私密簽章與Apple日誌不進儲存庫。

- 12:18:02–12:20:22台北：device Release封存及App Store匯出成功，外層139.64秒exit0。arm64、最低iOS17、共10個Mach-O核驗；DEBUG fixture未編入，`get-task-allow`關閉，ATS Debug例外不存在。封裝的privacy宣告與權限用途檢查通過。
- 本機匯出IPA：8,144,087 bytes，SHA256 `8347ba0ac1180d157a40b252361e6738c2609b52ad33b8107129f5df21ada970`。
- 本機主程式SHA256 `8a36968df2d26dd2878aaaad68a751a71f41550d851d4f7cc65b5e5edb0cd91d`；UUID **`99F0FBB1-4E23-3FA7-B2FC-DD33E2084810`**，實際dSYM UUID吻合。Apple重簽／加密後下載包不主張逐位元相同。
- 12:21:09–12:22:35：Apple線上Validate exit0，`method=validation`、`destination=upload`；distribution logs確認 `IDEDistributionMethodiOSAppStoreValidation`。這是驗證流程，不是正式上傳。
- 12:23:17–12:25:11：正式上傳exit0；ContentDelivery日誌確認 `UPLOAD SUCCEEDED`，buildUpload **`d1735f4c-ef3e-47dd-91fe-aff15c45f6a3`**。Apple uploadedDate對應12:25:10台北；最初狀態PROCESSING。
- **13:33:07台北**恢復後核對：buildUpload COMPLETE、errors／warnings空；build271 VALID、`expired=false`、0.1.0、`usesNonExemptEncryption=false`。既有「渥屋內部測試」group `69ca89bb-73ec-4e93-860f-35979a9601ff` 已關聯，internal IN_BETA_TESTING、autoNotifyEnabled=true。外部狀態READY_FOR_BETA_SUBMISSION不代表已送外部審查。

精確回執：`release-271/report.json`、`release-271/symbols-evidence.json`、`validation-271/receipt.json`與`safe-evidence.json`、`upload-271/receipt.json`、`web-status/271-resume-builds.private.json`、`web-status/271-resume-upload.private.json`、`release-status-271.json`。封存時report內的未上傳旗標是當時狀態；日後狀態以有時間的Apple查詢為準，不改寫原封存回執。

## 實機交接及未驗收

13:46:39台北，原分支工具實際查詢 `CFBundleVersion=271`、`0.1.0`、`SignerIdentity=TestFlight Beta Distribution`，同時TestFlight顯示271「打開」。更新前原WDA程序為0；手機可讀且截圖沒有鎖定證據。依既有授權由同一操作者一次恢復原服務，ready／PID3290後才繼續更新，未啟第二組服務。

13:46:55–59首次啟動前，conversations.vault、learning.vault及原PNG的bytes／SHA逐項與本輪更新前基準一致。之後首次啟動App PID3300；此處只證明更新瞬間資料保留，不主張整輪UI操作後加密vault仍逐位元相同。原始輸出在 `T/iphone-271-install-progress.private.json`（installed output `88b1cb50c56659178bd346f51e78157a`、preservation output `973395301fb55e56b155302529c8dcbc`）。原WDA未就緒的歷史阻礙及其小報告保留於 `T/iphone-271-initial-connection/`，不用舊阻礙覆蓋更新後進度。

沿用同一原iPhone分支作為唯一操作者，經TestFlight原地更新；不刪原A31對話、圖片或記憶，也不重啟第二組裝置服務。更新後須核271／TestFlight簽章、原資料保留，驗中文與多行草稿、鍵盤開關、舊文閱讀、回尾控制及附件畫面，留下實際可見性與CPU時間窗。

原24輪仍為實送2／正常0／未送22；兩次模型限流沒有證明MCP收到請求。[270手動記憶CRUD](IPHONE_270_MEMORY_CRUD.md)已限定通過，不重跑湊數。原A31高CPU根因、真Apporo兩筆tool_errors／unknown、模型恢復、多供應商、超時／斷線、文件接收端與Android同情境視覺差異等依[驗收缺口](ACCEPTANCE_GAPS_20261122.md)保留，不能以本次發佈結案。

使用者可從[TestFlight頁](https://appstoreconnect.apple.com/teams/fb3afe28-8d7d-4b0e-9318-135c87a529a0/apps/6834435121/testflight/ios)核對；手機TestFlight內選「渥屋助理」→0.1.0(271)更新。此段表示可下載，不表示已安裝。
