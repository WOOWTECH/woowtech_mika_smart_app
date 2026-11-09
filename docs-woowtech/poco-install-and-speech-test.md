# POCO 正式包安裝與語音實測（2026-11-09）

## 測試環境

POCO C85 / 25078PC3EG，Android 15 / HyperOS 2。手機已安裝 `io.woowtech.agent` / `0.1.37-woow.4`。

## 正式 APK 安裝：確認被攔截

測試檔是手機 Download 中的 `woowtech-agent-v0.1.37-woow.4-arm64.apk`，與公開版檔案相同：

- SHA-256：`2da75046061ca0f23c94a076b8f405abf1c13554dc46bf789505193afbe13442`
- 本機同檔 `apksigner verify --print-certs` 通過。
- 簽章 SHA-256：`806b3db808ecbb4d2d032b34624baa7e193802f17a07afbde2a03e78da9474c8`
- 簽章名稱：WOOW TECH CO., LTD. / woowtech agent Android Release。

從手機 Files 點選 APK，經系統安裝器確認「要更新這個應用程式嗎？」後按更新。Google Play 安全防護顯示「已封鎖有害的應用程式」「這個應用程式可能有害」。未完成覆蓋安裝；原版 lastUpdateTime 仍為 2026-11-09 13:12:33。

這證明攔截並非只發生在不同套件名稱的 Debug 包。這次是保留資料的同版本覆蓋安裝，不能標成全新安裝通過。畫面沒有具體檢測原因，不能推定為誤判，也不能靠換簽章、換包名推定可解決。

Files 安裝來源權限已恢復為 REQUEST_INSTALL_PACKAGES=deny。沒有關閉 Play 安全防護，未移除正式版或清除資料。

## 語音：重現 zh-TW 辨識失敗

- RECORD_AUDIO 已授權。
- 預設辨識服務：Google 語音辨識及合成的 GoogleTTSRecognitionService。
- 系統亦列出 AiAiSpeechRecognitionService 等服務，因此不是「沒有任何辨識服務」。
- 實際長按渥屋助理輸入列，Google 服務記錄 callingApp=io.woowtech.agent、locale=zh-TW。
- AiAi 與 Google TTS 均記錄 `Failed to get language pack of required locale: error 12`、`LANGUAGE_PACK_ERROR`。

Android 官方定義：12 = ERROR_LANGUAGE_NOT_SUPPORTED；13 = ERROR_LANGUAGE_UNAVAILABLE（支援但目前不可用，例如尚未下載）。雖然 Google 日誌使用 language pack 字樣，不能只根據它保證「下載語言包」就能修好。

官方參考：https://developer.android.com/reference/android/speech/SpeechRecognizer

## 本次程式修正

1. 本機辨識因語言錯誤切換至預設辨識器時，明確將 EXTRA_PREFER_OFFLINE 設為 false；原版仍帶 true。
2. 語言錯誤最多觸發一次該回退，保留已辨識文字，不做無限重試。
3. 錯誤碼 12/13 顯示語言不支援／語言包不可用說明，不再誤報辨識器不存在。
4. 繁中、簡中與英文說明不再保證中文一定可離線；錄音標籤使用「手機自帶」，不以硬體具備離線能力就宣稱本次在離線辨識。
5. 沒有自動改用付費服務商、替使用者更換辨識語言或修改全機辨識器設定。

單元測試涵蓋語言錯誤分類、一次回退後撤銷離線偏好、保留已辨識文字、一般語音流程。最終結果：89 項、0 失敗／錯誤／略過；woowtech Debug 編譯成功。日誌 `/tmp/woow-speech-final-build.log`。

## 尚未完成與限制

- 獨立診斷程式已收到最終中文字串，但與指定測試句不符；正式 App 尚未取得正確語音轉寫，不能宣稱已恢復。
- 使用者已同意實機操作與配合語音。已通知說話並執行兩個 App 的長按測試；尚待確認 14:38 診斷收音時實際說的內容。
- 修正版只在工作分支完成，未安裝到正式版手機、未發布。撤銷離線偏好只是允許預設服務自行選擇；不保證預設服務具備該語言的線上能力。
- 原版成功執行的無障礙手動解除與 USB API 測試，不能當成語音成功證據。


## 接續實機測試（14:34–14:40）

使用者確認可接續操作後，重新測試原版與 Mika：

| 測試 | 實測結果 |
| --- | --- |
| 渥屋助理原版長按 15 秒 | 14:34:24.319 開始；14:34:24.674 本機 error 12，14:34:24.970 預設服務再回報 error 12；未產生輸入文字 |
| 同機 Mika 長按 | 14:35:53 本機與預設服務均回報 zh-TW / error 12；未產生輸入文字 |
| ADB 開啟 Google RECOGNIZE_SPEECH Activity，指定允許連網 | Activity 隨即關閉，不能算有效的 SpeechRecognizer API 測試 |
| 獨立診斷程式，預設辨識器、zh-TW、PREFER_OFFLINE=false | 14:38 收到 READY、SPEECH_START、PARTIAL、SPEECH_END，14:38:40 收到非空 RESULT；文字與指定句不符，準確率未通過 |
| 同一診斷程式、zh-TW、PREFER_OFFLINE=true | 14:40:00.999 回報 error 12，其後又收到 READY；應用程式不能因後續 READY 就忽略已收到的終止錯誤 |

獨立診斷程式套件 `io.woowtech.speechprobe`，只要求麥克風／網路，透過 ADB 安裝，沒有無障礙服務、沒有替換渥屋助理或 Mika。原始碼與重建腳本暫存在 `/tmp/woow-speech-probe/`；實機紀錄 `/tmp/poco-voice-authorized.log`。這項診斷程式的 ADB 安裝成功，不代表正式 APK 經 Files 安裝通過 Play 安全防護。

`checkRecognitionSupport` 的回呼包含 supportError=14，且後續又收到支援清單；installed/pending 為空、supportedDevice 包含 `cmn-Hant-TW`、online 為空。此服務回呼不一致，不能只用 online 空清單斷言不支援連網。實際 `zh-TW + PREFER_OFFLINE=false` 已收到最終中文字串，也不能只因離線清單沒有 zh-TW 就直接更改 App 的語言代碼。另試 cmn-Hant-TW 收到 error 11；因前一個 session 曾被中止，不作為語言相容性的決定性證據。

這些測試支持撤銷回退後的離線偏好，但尚未證明修正版在正式 App 裡正確完成整條語音輸入流程。診斷收音沒有自動送出聊天或執行任務，也沒有切換付費轉寫服務。

## 使用者重試後的 error 11 與診斷程式修正

使用者回報連按仍 error。14:41:59–14:42:10 共七次 `recognitionError=11`，發生於獨立診斷程式的預設辨識器／zh-TW／允許連網配置。Android 定義 11 為 ERROR_SERVER_DISCONNECTED，不能與原版的語言錯誤 12 混為一談，也不能據單次非空 RESULT 宣稱可穩定使用。

舊診斷程式在建立畫面時建立辨識器，並在斷線後沿用同一個物件。已修正為按開始時才建立全新辨識器、終止時銷毀、使用 session generation 過濾舊回呼、收音中禁用重複開始、30 秒截止。查詢支援清單與實際收音分開，本次手動收音畫面不再同時執行支援查詢。

更新診斷程式後，實機連續兩次按開始均收到 READY、畫面顯示「請說話」。第一次未要求使用者說話，按結束後 error 7（未匹配文字）；第二次仍可重新進入 READY。這只證實診斷程式可重新連線，語音準確率與正式 App 修復仍待驗證。未替換或移除正式 App。
