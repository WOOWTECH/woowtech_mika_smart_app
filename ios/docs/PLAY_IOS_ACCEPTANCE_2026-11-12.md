# 渥屋助理 Play 候選／iOS 對照與驗收

此清單追蹤使用者要求的功能與畫面對照，不是通過證明。以實際 iOS 版本和 Android 商店候選逐項驗證；iOS 不實作手機或其他 App 的控制。測試資料、畫面、執行結果與模型設定應使用隔離空間，不將金鑰、端點、真實對話、裝置識別碼或私人截圖提交到倉庫。

## 基準與來源

- Android 商店分支 `playstore/woowtech-compliant-20261111`，來源 `420b1d26f99110635d6a2827ee9414541c7a6c35`；`io.woowtech.assistant`、`0.1.37-play.2`。依[送審準備紀錄](https://github.com/WOOWTECH/woowtech_mika_smart_app/blob/420b1d26f99110635d6a2827ee9414541c7a6c35/docs-woowtech/PLAY_REVIEW_READINESS_2026-11-12.md)，當時尚未上傳 AAB 或送審；不可稱作已經 Play 發行的安裝檔。分支正在開發，後續來源變更須重新固定版本。
- 2026-11-12 再查商店分支已到 `6a6cf18bc46e1672b0e124a3288cfe666a2bcc0e`；與上述基準比較只有送審文件增加 16 KB 相容性紀錄，沒有產品源碼差異。本表及 APK 仍固定在 `420b1d26`；後續若產品源碼變更須重新建置及比對。
- POCO Android 15 的真模型對話、記憶、技能與唯讀 HA MCP 多數證據來自 ADB 安裝的 `play.1`；`play.2` 的安裝與重啟紀錄不能升格成全部流程重測。參見[實機紀錄](https://github.com/WOOWTECH/woowtech_mika_smart_app/blob/420b1d26f99110635d6a2827ee9414541c7a6c35/docs-woowtech/PLAY_POCO_ACCEPTANCE_2026-11-12.md)。
- iOS 實體 iPad 第 9 代／iPadOS 26.6.1 的產品來源為 `bf34bd9976f0407f44518761d9b20a50ebb79bc6`，本機簽章 Release 已安裝；[實機紀錄](https://github.com/WOOWTECH/woow-assistant-ios/issues/1#issuecomment-6818332596)。`d60fd8a` 是 `bf34bd9` 的 Git 祖先；分支指向時間不能證明前者較新。
- 舊版 iOS 18.5 模擬器曾有[真模型個人資料](https://github.com/WOOWTECH/woow-assistant-ios/actions/runs/42868747738)與[真模型／HA 混合對話](https://github.com/WOOWTECH/woow-assistant-ios/actions/runs/42879196152)各 1/1 的紀錄，來源分別為 `017976b`／`395ee5a`；不代表目前 iPad 或最新整合候選通過。
- Craft Anything CLI 0.6.0 已檢查[精確來源 CI 建置](https://github.com/WOOWTECH/woowtech_mika_smart_app/actions/runs/43183040946)的 ARM64 未簽章 Release 候選 APK；檔案雜湊與 CI 一致，解析為 `io.woowtech.assistant`、`0.1.37-play.2`、versionCode 2，繁中字串 1,966/1,966 項已分頁讀取。[選定聊天字串與來源證據](evidence/craft-play-420b1d26-chat.json)不可證明頁面實際顯示或功能可用；APK 不是 Play 發行檔。先前檢查的 `io.woowtech.agent` `0.1.37-woow.7` 則為不同的 GitHub 直載版。

## 功能與畫面驗收

狀態「待驗」不表示失敗；「未對齊」表示有具體來源差異但尚需按精確版本測試。每項功能需記錄：Android 與 iOS 的 SHA、裝置／系統、語言／深淺色、初始資料、具體操作、預期／實際結果、截圖或 XCResult 與重測結果。真人語音、真實網頁及真實模型須分開記錄，不得把假資料或 skip 計入通過。

| 區域 | 已有證據／差距 | 下一步 |
| --- | --- | --- |
| 首屏與聊天視覺 | `bf34` iPad 基本導覽通過；歡迎區冷啟動曾延遲約 20–52 秒才顯示。商店版與 iPad 沒有同條件逐頁像素／佈局對照。 | 同語言、外觀及資料狀態下比對首頁、抽屜、輸入列、回覆及鍵盤；重現首頁延遲並修正。 |
| 模型設定與連線 | Play 候選有多服務商／模型管理；iOS 有單組 URL、模型和 Keychain 設定。 | 核對新增、修改、切換、刪除、連線失敗及舊設定遷移，不得洩漏憑證或讓舊回覆跨目的地。 |
| 真實對話 | `bf34` iPad 尚未做真模型對話。主線電腦用 App 類 UA 對先前授權服務發送受控請求，非串流及串流均收到 HTTP 429；尚未確認 iPad 是否同配置。 | 實機確認模型設定、送出、顯示、續問、停止、錯誤、草稿及重啟歷史；將服務限流與 App 缺陷分開。 |
| 訊息操作 | Play 有複製、引用、選取等操作；iOS 相關候選未在本版本逐項驗收。 | 比對可用條件、長按選單、引用、分支與未完成回合；不把尚未整合的候選算入主線。 |
| 圖片、檔案及 PDF | POCO `play.1` 測過選圖縮圖與移除，未驗真模型理解。iPad 已選入合成 PDF 並核准讀取，尚未擷取／發送；結束時選檔按鈕定位失敗。 | 真機測相簿／文件選擇、預覽、移除、傳輸以及 PDF 完整流程；真模型收到附件須另有證據。 |
| 語音 | POCO `play.1` 真人語音可轉成草稿。`bf34` 含系統語音／停用候選；provider 選擇尚未開放，iOS 真人音訊未驗。 | 實機測麥克風和辨識權限、按住／取消／背景／結果入草稿與停用；測試 simulator skip 不得當作通過。 |
| 外部 MCP | POCO `play.1` 真模型自主呼叫唯讀 HA 和長結果二次讀取有證據；`bf34` iPad 未做真 MCP 對話。 | 比對伺服器設定、允許清單、工具／資源、拒絕及長結果，並在授權下實測真服務。 |
| 記憶與技能 | POCO `play.1` 真模型跨對話有證據；iPad 已巡覽三個記憶分段，未驗真模型操作。 | 比對手動 CRUD、開關、待確認、技能試用／評分、真模型使用與刪除後遲到回覆。 |
| 瀏覽器 | `bf34` iPad 分頁及真 HTTPS 通過；點擊最近瀏覽後仍停首頁的實機案例失敗。 | 原斷言保留，定位點擊／狀態／載入，修正後測分頁、歷史、書籤、網站資料、登入與檔案。 |
| 設定、語言、通知、關於 | `bf34` iPad 有基本入口及測試隔離資料的記憶開關通過，未完成逐頁畫面及通知聲音驗收。 | 按商店版逐入口比對；必要的系統授權及 iPad 權限狀態單獨記錄。 |
| AI 回覆檢舉 | 商店候選有入口，正式收件與重試仍待驗；iOS 尚未找到同等入口。 | 先核對商店版最終資料流與可用後端，再對照 iOS 實作及可靠送達，不以畫面存在代替服務可用。 |

## 對話候選審查

- `5fc067499e0bcae19d6468b20b0c88747ce822ee` 是一般對話與技能模型 HTTP 429 分類的隔離修正，並非 iPad 已安裝版本。合成測試通過；GitHub iOS 原生測試排隊中，尚未驗證實機。
- 獨立審查發現兩條尚未覆蓋的限流路徑：回答完成後的自動記憶整理，以及 PDF 問答。前者必須清楚表示回答已完成，而不能誤稱草稿保留；兩者均不得自動重送或洩漏服務回應。已交付補修及重測，未把候選列為完整修復。
- 對話首次畫面六項建議文字已按商用候選 APK 比對；`8d4130c8c040b47caccbf29862b45a5c4d65bdaf` 為另行審查中的可及性候選，尚未整合或在 iOS 真機／模擬器通過。Android 式插話、回答模式及首頁提示狀態仍需比對與實作。

## 2026-11-12 晚間：MacBook 實機、POCO 與修正候選

- 對照工具：MacBook 安裝 Craft Anything CLI 0.6.1（`~/.local/bin/craft-anything-cli`），下載檔 SHA-256 與 Developer ID 簽章已核對；分析自家 APK 時以單次 `--deep` 執行，不改其永久設定。
- POCO：`io.woowtech.assistant` `0.1.37-play.2`（versionCode 2）是 17:39 以 ADB 更新安裝的 Debug 版，不是 Play 下載。Craft 從實機取出的 APK 讀到繁中字串 1,983 項；未設定模型時 Android 聊天顯示卡片「還不能開始任務」「還缺:還沒有能用的模型」，按鈕「知道了」「去設定」。品牌替換正常，只有 2 項含 Mika（來源授權標示）；先前懷疑 `explain_no_model_body` 品牌外洩不成立。
- iPad 實機（`bf34bd9` Release）：「可以按，但沒有反應」是未設定模型或金鑰時 `chat.send` 停用且沒有說明。另有 `chat.transcript` 高度 0、輸入列被推到導覽列下方，「請先到設定…」提示因此被藏住；這個狀態在鍵盤收放、畫面重建及 App 重開後都持續。18:29 已重開機，待解鎖後驗證；根因（鍵盤或容器安全區）未定。
- 修正候選 `ios/chat-send-feedback-bf34bd9`（`0f58b08`、`6bb2d88`、`7493223`）：送出回饋比照 Android（有文字就能按，按下時說明缺少的條件，含 PDF；VoiceOver 會播報）；聊天畫面改為不採用 SwiftUI 鍵盤安全區，只為本 App 停靠底部的鍵盤留白，且只在編輯草稿時留白。本機 macOS 檢查通過（ChatSession Debug 245／Release 202 項、鍵盤幾何 14 項）；Xcode 型別檢查、模擬器與實機尚未驗證。另有只在帶 `-ChatLayoutProbe` 參數啟動時才輸出幾何數值的診斷版，不併入候選。
- 新增差距（owner 指出）：Android「＋」是附件面板（相簿多張、拍照、最近照片、任意檔案），iOS 只有「附加 PDF」。iOS 可以實作，必須對齊；由 MacBook 實測對話在 `ios/attach-tray-android-parity` 負責。既有附件候選分支（`10b049d` 等）在 GitHub 上沒有任何 Actions 執行紀錄，只能當作未經模擬器驗證的參考實作。
- 已知未對齊：iOS 的「還不能開始任務」卡片放在輸入列上方；Android 則放在對話列表最後，並在阻擋時隱藏首頁歡迎區，樣式為 surface 底色、0.5 dp 邊線、16 dp 圓角。待版面根因確認後再決定是否移入對話列表。

商店候選本身刻意移除定時任務、手機對電腦 MCP 服務及手機操控等能力；不得把這些視為已從商店候選驗收的共同功能。其他不涉及手機控制的既有使用者需求仍需獨立追蹤，不能因本表未列而宣稱完成。
