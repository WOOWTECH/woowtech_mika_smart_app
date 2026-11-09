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

## 使用者完成實際語音（14:48）

使用者按開始後，14:48:03.920 READY、14:48:05.498 SPEECH_START、14:48:09.610 SPEECH_END，14:48:09.690 收到 RESULT：`今天測試我無助理語音輸入`。畫面亦顯示同一文字，這次 session 未記錄 error 11/12。

指定句為「今天測試渥屋助理語音輸入」；品牌「渥屋」被辨識為「我無」，其餘文字相符。因此本次診斷程式的實際收音到文字流程通過，逐字準確率未完全通過。手機閒置約四分鐘後才按開始，新的按鍵時建立連線方式本次仍能完成辨識。這不等於正式 App 修復已驗證；正式 App 尚未安裝修正版，且尚須驗證長按、鬆手、連續多次輸入的整合流程。


## 正式簽章修正版覆蓋安裝（14:54）

使用者要求套用正式 App 並完整驗證後，從本分支 `8f61ffb3` 建置 `assembleWoowtechRelease`，BUILD SUCCESSFUL（2m34s）。以原正式憑證簽署 arm64 APK，再透過已授權 ADB `install --no-incremental -r` 成功覆蓋 `io.woowtech.agent`，沒有移除套件或清除資料。

- 本機驗證包：`woowtech-agent-woow4-speech-8f61ffb3-arm64.apk`。
- APK SHA-256：`169407a72c1e5ed22e7218a70b4dccb90cc490e36ff0dc1bf3582c131f8e7d2c`。
- apksigner 憑證比對原正式版通過；安裝後從手機讀回 base APK 的 SHA-256 與上述完全相同。
- firstInstallTime 保持 2026-11-09 13:12:33；lastUpdateTime 更新為 2026-11-09 14:54:39。
- 版本名稱／代碼仍為 `0.1.37-woow.4` / 3804，本機測試包用來源 commit 與 APK 雜湊區分，**不是 GitHub 上原公開 APK**，尚未公開發布。
- 主畫面啟動成功，未進入首次安裝流程。
- ADB 覆蓋成功不能取代 Files／GitHub 下載安裝的 Play Protect 測試；先前正式公開 APK 被擋的問題仍未解決。

已請使用者在正式 App 新對話長按輸入列，說「今天測試語音輸入，一二三四五」，鬆手後不送出；等待實際語音與輸入回填驗證。仍須區分模擬語音的介面測試與實機 Google 辨識，不能僅根據前者宣布後者通過。

### 修正版介面與無聲實機檢查

API 36 模擬器執行 `VoiceHoldTest`：7 項全部通過（47.89 秒）。新增／強化驗證取消保留原文、取消後遲到結果不回填、失敗後新會話可輸入，以及回填不觸發 onSend。既有案例驗證長按鬆手、聚焦後使用獨立麥克風、聚焦後長按保留系統選字、上滑取消、不同麥克風錯誤提示。這些使用 FakeVoice，不能當作 Google 辨識準確率證據。結果：`/tmp/woow-voicehold-ui-results.log`。

POCO 實機檢查：短按可開鍵盤並顯示「按住說話」按鈕；無聲長按 4.5 秒後回到空白輸入框，未留下卡住的收音視窗；DOWN→等待→向上 MOVE→UP 後亦回到空白輸入框。修正版日誌明確顯示原本本機 zh-TW error 12 後，預設 Google 服務開始 `Online recognizer - start listening`。

14:57:49 與 14:58:00 另有實機收音紀錄，14:58:02.585 Google 回報 `onResults withSpeech: true`。未取得該兩次對應的輸入框文字及使用者確認，不據此宣稱語音輸入準確或完整流程通過。正式 App 的實際語句回填、多次追加與送出流程仍待驗證。

## 正式 App 實際語音與回覆（15:00–15:01）

使用者回覆完成後讀取實機畫面：已送出訊息「今天測試語音輸入1 2 3 4 5」，助理已回覆確認收到；與指定內容相符，數字以阿拉伯數字及空格呈現。

Google 日誌：15:00:51.480 原套件 io.woowtech.agent 開始 zh-TW 收音；本機 error 12 後，15:00:51.649 開始 Online recognizer；15:00:54.035 偵測語音，15:00:56.778 stopListening，15:00:56.893 onResults withSpeech=true。這次正式 App 收音、辨識、形成訊息與模型回覆的流程可確認完成。

因先前要求鬆手後不要送出，而讀到的畫面已有回覆，已向使用者確認是否另外按傳送。在確認前，不將本次當作「沒有自動送出」的實機通過證據；該項目前只有介面測試通過。實際連續追加仍未驗證。

使用者隨後明確確認「有按傳送」，因此這一輪的語音辨識→手動送出→助理回覆流程通過，無自行送出的使用者回報。仍保留區別：手動傳送是使用者確認，畫面本身只能證實已送出與收到回覆。

接續追加測試：在空白輸入框輸入測試前綴，手機輸入法實際呈現 `test：`。請使用者透過聚焦輸入框右側的「按住說話」麥克風，分兩次說「第一段測試」「第二段完成」，每次鬆手待回填，兩次都不送出，待核對前綴保留與依序追加。
