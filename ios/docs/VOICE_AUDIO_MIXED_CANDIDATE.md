# 聊天語音：混音 session 候選

## 重新評估

先前將「所有 WebView 必須銷毀、所有音訊入口必須完全獨占」當成語音前提過於嚴格，會讓已開過瀏覽器的使用者長期無法聽寫。Apple 的 [`playAndRecord`](https://developer.apple.com/documentation/avfaudio/avaudiosession/category-swift.struct/playandrecord) 支援同時錄音與播放，可搭配 [`mixWithOthers`](https://developer.apple.com/documentation/avfaudio/avaudiosession/categoryoptions-swift.struct/mixwithothers) 混合其他 App 的音訊。這些文件描述的是系統 session 與其他 App 的混音；它們不保證同一 App 的 WebKit、所有音訊路由或同時麥克風擷取一定無中斷。

`AppleMixedVoiceRuntime.makeDriver()` 是可以供後續介面接入的**候選工廠**：共用單一語音協調器，不要求 WebView ticket 或全域獨占，也不預先要求權限。它目前沒有掛到介面；原先 `AppleVoiceInputDriver()` 的無參數建構仍保留拒絕行為，避免既有呼叫默默切換策略。獨占 fence 留作另選的隔離實驗，不是此混音候選的接入門檻。

## 行為與限制

- 使用者啟動後，driver 分別處理 Speech／麥克風授權；手指已放開、取消或離開畫面後，不可由遲到的授權回呼開始錄音。辨識仍限 Apple 裝置上可用的語言，不自動轉送雲端或服務商。
- 取得語音 lease 時不操作 session。開始錄音前保存 category／mode／options，設定 `playAndRecord`、`.default`、`mixWithOthers`，並提供 Bluetooth HFP／A2DP 選項，然後要求 activation；不強制喇叭。只序列化本 App 的語音 lease；不要求背景分頁停止。iOS 可能拒絕 activation，例如高優先權通話，需回報失敗並允許下一次使用者操作再試。
- `mixWithOthers` 不承諾 WebKit 同 App 播放一定不中斷；設定 category 或 mode 時，Apple 說明活動中的 session 可能立即改變路由。Bluetooth 同時啟用 HFP 和 A2DP 時，支援兩者的裝置可能優先使用 HFP。可能的輸出設備、音量、播放／辨識品質與藍牙切換均需實測；不以強制 `defaultToSpeaker` 覆蓋使用者路由。[Category 設定](https://developer.apple.com/documentation/avfaudio/avaudiosession/setcategory%28_%3Amode%3Aoptions%3A%29)、[Bluetooth 路由](https://developer.apple.com/documentation/avfaudio/avaudiosession/categoryoptions-swift.struct/allowbluetootha2dp)。
- 錄音結束／取消／中斷先停 engine，然後在當前 category／mode／options 仍與候選所安裝設定相同時嘗試還原保存值；若讀不到設定、設定已變、設定失敗或還原失敗，記錄區分結果並不盲目覆寫。設定成功後若讀回的設定不是混音錄音類別，停止啟動，不把第三方設定當成自己所擁有。
- 這是**盡力而為**，不是共享 session 的原子 compare-and-swap：另一使用者可能恰好使用相同設定、先改後改回，或在檢查與還原之間改變設定；category／mode／options 也不包含完整路由與偏好。未持續協調的 WebKit 行為不能因此宣稱安全。設定失敗可能已產生部分系統副作用；錯誤可重試，但不宣稱完全回復。
- iOS 無法由此程式可靠讀回錄音前 App session 是否 active；為避免 `setActive(false)` 停止仍在使用的 App 內音訊，候選不無條件 deactivate。結果可能是 session 仍 active，且還原非混音原 category 可能影響其他音訊；這是明確待原生驗證的取捨，不是完整恢復。可由 `AppleMixedVoiceRuntime.lastCleanup` 查看狀態。若未來可靠掌握「不再有其他 App 內音訊使用者」，可再設計受控 deactivate；不能用單次 WebKit 播放查詢假裝原子保證。[Apple 對停用中音訊物件的說明](https://developer.apple.com/documentation/avfaudio/avaudiosession/setactive%28_%3Aoptions%3A%29)。
- iOS 17 使用 `interruptionNotification`；中斷開始、耳機／輸入裝置連接或移除、媒體服務重置時，候選停止本次錄音並回報失敗供宿主顯示，不自動重啟麥克風或送出；頁面離開、切換對話或 scene 非 active 仍需宿主呼叫 `cancel()`。route/category 變動帶來的通知需在原生測試排除自己的設定造成誤取消。Apple 對[中斷](https://developer.apple.com/documentation/avfaudio/handling-audio-interruptions)、[路由](https://developer.apple.com/documentation/avfaudio/responding-to-audio-route-changes)及[媒體服務重置](https://developer.apple.com/documentation/avfaudio/avaudiosession/mediaserviceswereresetnotification)的說明。

## 實際接線與驗證設計

介面可在完成原生建置後注入 `AppleMixedVoiceRuntime.makeDriver()` 到 `VoiceInputStateMachine`；不需要建立 `VoiceAudioRuntimeCandidate` 或聲明所有 WebView 可控。需先接上文字／麥克風手勢、文字草稿與使用者可見失敗訊息；離開對話、切換對話和 scene 非 active 時必須 `cancel()`。允許使用者按住重試；長按取消不能提交文字。此提交沒有修改首屏，語音功能仍不可從 App 使用。

本機可執行：

```sh
bash scripts/check_mixed_voice_audio.sh
python3 -m unittest discover -s scripts -p 'test_voice_input.py' -v
```

測試呼叫實際純 Swift 協調器和可注入假 session，驗證保留現有假 WebKit 播放、語音排他、取消及重入、第三方變更不覆寫、失敗後再試和未知 active 狀態。假物件不能證明 WebKit 真實混音；Apple adapter、原生音訊通知及平台型別在此主機尚未編譯或執行。

MacBook 上先用 XcodeGen 與 iOS 17+ SDK 建置 Debug 和 Release；再新增可重跑的 XCTest／UI 測試和本機合成 HTML、合成音訊，保存 `.xcresult`、系統版本和可公開的狀態證據，不記錄音訊、辨識內容或私密網址。至少分開記錄：

1. 原生授權允許、拒絕、受限制、授權畫面期間鬆手／背景、重試；不把模擬器無麥克風／無裝置辨識的跳過當通過。
2. WebKit 已播放、暫停、背景分頁、popup、多來源和來源搜尋的受控網頁，在開始／停止／取消語音前後記錄播放狀態、currentRoute、category、mode、options 及實際使用者可聽結果；單次播放狀態不是排他鎖。
3. 網站擷取麥克風與聊天錄音互相競爭、不同開啟順序與授權狀態；裝置或 simulator 不支援時明列未驗，不能以假辨識結果代替硬體驗證。
4. activation 被拒、音訊中斷開始／結束、scene 離開、媒體服務重置、耳機／Bluetooth 路由切換及外部 category 變更；確認 engine 先停，舊回呼不填草稿、不自動重啟或發送，並檢查條件還原及同一 App 的播放是否受影響。
5. Compare 實際 audio session 狀態及可聽行為，而非假設先前 active 能讀回；包含 `.allowBluetooth`／A2DP 的路由與可能降質，以及取消後 session 仍 active 的影響。超出 simulator 能力的驗收只記為未驗。其他 App 和實機情境需要另行明確授權，這次不操作。
