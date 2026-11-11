# 聊天語音輸入：第一階段，尚未接入

此提交只提供可審查的底層候選。輸入區沒有語音按鈕或手勢，使用者不能使用此功能；未宣稱與 Android 完整對齊。純 Swift 狀態機及合成 driver 以 Command Line Tools 測試，Apple Speech 介面、iOS SDK 類型檢查、模擬器與實機均尚未驗證。`content-transcribe` 技能處理的是已核准的文字／字幕，與聊天聽寫不同。

## 接線契約

- 尚未允許接入 Apple driver：預設協調器一律拒絕 lease，且目前沒有可用的正式共享音訊協調器。通過下述原生驗證後，聊天介面才能注入該協調器並持有 `VoiceInputStateMachine`；所有操作在 MainActor。`begin(gestureStartedAt:)` 的時間與預設 `ProcessInfo.processInfo.systemUptime` 同源；手勢長按約 0.3 秒後呼叫，`drag` 使用同一座標單位的向上距離及門檻，離開手指呼叫 `release`，中斷手勢呼叫 `cancel`。由 UI 定期呼叫 `tick`，也必須在離開聊天、切換對話、scene 非 active 或物件釋放前 `cancel`；不可只依賴計時器。
- 以 `onStateChange` 顯示錄音、辨識中的文字、取消落點、收尾及錯誤，提供權限遭拒／受限制和辨識不可用的可理解提示。權限彈窗可能中斷手勢：授權後由使用者重新按住，不能在手指已離開或 App 已離開聊天後自動錄音。另需提供 VoiceOver 可操作的開始／結束／取消入口，並實測與文字選取、鍵盤、附件及切換頁面共存。
- 以 `onFinal` 將結果透過 `VoiceDraftJoin.join` 加到 **當下** 草稿，不自動送出。介面要以對話身份或世代確認結果仍屬當前對話；切換時先取消。不要把 partial 寫入草稿或保存音訊。草稿合併以 Unicode scalar 與 CJK 常用區塊判斷，包含擴充漢字；Android 現有程式以 UTF-16 `Char` 判斷，因此邊界文字不保證逐碼相同。
- 回呼必須維持 session ID，舊 session 的回呼在取消、失敗、逾時及新手勢後均被忽略；同步 `.idle` 觀察者或 driver 清理若重入取消／開始新 session，也不交付舊結果。手指按住期間的 final 要等鬆開決定，取消時丟棄；少於 0.5 秒的手勢丟棄；預設 60 秒觸發收尾，收尾最多等待 5 秒。系統 driver 的 60 秒獨立 deadline 作為額外防線，但主執行緒被阻塞或系統暫停時不能視為即時保證。UI timer、scene 中斷及音訊工作階段管理仍須整合驗證。

## 權限與隱私

Debug 和 Release 的麥克風說明涵蓋聊天及經同意的網站；兩者均新增語音辨識說明。發行檢查現在要求封裝後 plist 含非空語音辨識用途說明。`AppleVoiceInputDriver` 必須先取得共享音訊 lease；預設拒絕時在要求任何權限之前回報不可用。只有注入可授權的協調器後，候選才會要求 Speech 與麥克風授權、檢查服務及裝置上辨識可用性，並設定 `requiresOnDeviceRecognition`；不回退到雲端或服務商，不儲存錄音，也不輸出音訊或逐字稿日誌。

音訊 session 是 App 共用資源：driver 不呼叫 `setCategory`／`setActive`，只透過可注入的 `VoiceAudioCoordinating` 取得並釋放 lease；協調器負責所有設定、啟用及撤銷，不能用過期快照覆寫其他使用者。`VoiceAudioLeaseSlot` 處理同步撤銷、過期回呼及重複釋放。預設 `UnavailableVoiceAudioCoordinator` 一律拒絕。隔離候選 `SharedVoiceAudioCoordinator` 與 `AppleVoiceAudioSessionAccess` 已分離：前者可用假 fence／假 session 執行測試，後者尚未經 iOS SDK 驗證；目前沒有覆蓋本 App 所有音訊使用者的正式 fence provider。未能涵蓋 WebKit、其他 App 內音訊使用者及 active 狀態時必須繼續拒絕，不能接線。即使只用裝置辨識，Apple 仍要求 Speech 用途說明。未來新增雲端服務時，須另設明確選擇、目的地與資料處理說明、隱私揭露及測試；不能沿用「只在裝置上」的文案。

## 隔離協調器的狀態與限制

### 音訊路徑清單（來源樹靜態盤點）

| 路徑 | 音訊能力與接線要求 |
| --- | --- |
| 手動瀏覽與保留分頁 | [`BrowserSession.webView`](../Sources/App/BrowserSession.swift) 延遲建立並保留 WebView；[`BrowserWorkspace`](../Sources/App/BrowserWorkspace.swift) 管理多個 session。網站可能播放媒體，符合條件的手動頁面可向 WebKit 要求麥克風權限。切換分頁與 `cancel()` 的 `stopLoading()` 不是媒體停止或 WebView 已釋放的證據。 |
| 新視窗／彈出分頁 | `BrowserWorkspace.makeSession` 的 `onCreateWindow` 建立另一個 `BrowserSession` 並取得其 WebView，須共用相同登記，不是額外獨立的安全域。 |
| 多來源研究 | [`MultiSourceResearchWebKitExecutor`](../Sources/App/MultiSourceResearchSession.swift) 為來源建立多個非持久 `BrowserSession`；視圖被覆蓋或研究取消不等於 WebKit 媒體已原生停止。 |
| 來源搜尋 | [`ResearchSourceDiscoveryWebKit`](../Sources/AssistantBrowser/ResearchSourceDiscoveryWebKit.swift) 在 AssistantBrowser framework 直接建立另一個非持久 WebView。雖然限制載入資源及 JavaScript，仍需將它納入生命週期盤點，不能單憑規則斷言對共享音訊無影響。 |
| App 原生錄音 | [`AppleVoiceInputDriver`](../Sources/App/AppleVoiceInputDriver.swift) 是尚未接線的 `AVAudioEngine`／Speech 候選；[`AppleVoiceAudioSessionAccess`](../Sources/App/AppleVoiceAudioSessionAccess.swift) 是候選 session 操作層。來源樹未找到其他直接 `AVAudioSession`、`AVAudioEngine` 或 `AVPlayer` 建立路徑；這不是對系統／第三方框架內部音訊的完整證明。 |
| 系統通知 | [`TaskNotificationCenterAdapter`](../Sources/App/TaskNotificationCenterAdapter.swift) 可要求系統播放預設通知聲；它不直接設定此 App 的 `AVAudioSession`。通知、來電及其他 App 的系統中斷仍須原生驗證。 |

靜態測試追蹤來源樹中兩個直接 `WKWebView(...)` 建立點，新增點必須重審；它不能捕捉所有動態建立方式或框架內部行為。Apple 的 [WebKit 播放狀態](https://developer.apple.com/documentation/webkit/wkwebview/requestmediaplaybackstate%28completionhandler%3A%29)及[麥克風擷取狀態](https://developer.apple.com/documentation/webkit/wkwebview/microphonecapturestate)可供原生檢查；由於播放查詢取得的是當下狀態，而頁面之後仍可能變化，單次查詢不足以建立持續獨占。這是依 API 與現有程式做的保守判斷，尚待原生測試。

### 有條件可取得的隔離 fence

[`VoiceAudioAdmissionFence`](../Sources/App/VoiceAudioAdmissionFence.swift) 現有可執行成功路徑：宿主必須先完成並明確聲明三類入口的全覆蓋，且所有 WebView／原生音訊參與者均已登記、完成原生銷毀並明確歸還 ticket。只要還有 ticket，就不呼叫 session。獨占持有期間會拒絕新參與者，通知語音停止，只有同步結束並交還後才容許參與者進入；未確認交還則繼續拒絕。初始化、取消與競爭都在 MainActor，重入在假 session 測試中覆蓋。

在全部入口受控且無參與者的前提下，fence 於使用者啟動語音的路徑嘗試 `setActive(false)`，建立**新的** inactive 基線。這個動作可能影響系統音訊行為；成功只表示操作成功，並不表示之前的 active 狀態已知或已還原。失敗即 quarantine，不能因 Apple 回傳錯誤就假設狀態未變。後續協調器在該新基線下執行；未啟動錄音時仍記錄 `baselineReset`，執行還原則記錄 `restorationAttempted`，均不聲稱原先活動狀態完全恢復。此策略依賴宿主完整攔截與原生驗證，不能在現有 App 直接假設成立。

[`VoiceAudioRuntimeCandidate`](../Sources/App/VoiceAudioRuntimeCandidate.swift) 組裝單一 fence 與協調器；預設沒有任何入口被聲明，所以安全關閉，但假 session 測試證明條件成立時可以取得 lease。它尚未掛到實際 App；`AppleVoiceInputDriver()` 的正式預設仍拒絕。不要呼叫 `attestIntegratedRoute` 宣稱已完成，直到兩個 WebView 建立點、所有原生音訊入口及系統中斷都已實際接入並通過原生驗證。

lease 的撤銷閉包型別為 `@MainActor`。撤銷先同步通知 driver 停止 engine，再由 driver 明確 release；未確認 release 時保留 fence 並拒絕新租用。啟用過程中重入取消會延後回收，直到啟用呼叫返回；重複撤銷與過期回呼不觸及新持有者。候選嘗試停用並還原 category／mode／options，但僅回報 `restorationAttempted`，不宣稱先前活動狀態已被證明完全恢復。任何步驟失敗或 fence owner 不接受交還，協調器進入 quarantine 並拒絕新租用；provider 必須保留 fence 直到獨立排除不確定性。系統 `setActive(false)` 在音訊物件仍運作時可能使其停止，即使回報錯誤也是如此；因此先停止 engine 的順序是必要條件。[Apple 文件](https://developer.apple.com/documentation/avfaudio/avaudiosession/setactive%28_%3Aoptions%3A%29?changes=_6)。

App 接入需要在兩個 WebView 建立點 **之前** 取得同一個 runtime 的 ticket；既有 `BrowserSession.webView` 與來源搜尋建立器都不是可失敗的 API，須設計可呈現的拒絕／等待路徑，不可在被拒後偷偷建立另一個 WebView。只有在原生驗證其媒體與擷取已終止、WebKit 不再持有可執行音訊的資源後才歸還 ticket；僅靠 `stopLoading`、切換頁面、參考計數或單次播放狀態不夠。來源搜尋位於另一 framework，需明確注入同一 runtime 的准入能力。系統中斷或所有權不可確認時呼叫 `systemStateBecameUncertain()` 並保持 quarantine；重建 owner 前須由宿主完成獨立協調，不能自行清除。

目前無可驗證的正式全 App fence 整合，Apple driver 預設拒絕且未接 UI。候選 Apple session adapter 只提供被注入的系統操作，沒有替既有 App 取得所有權；不能因純 Swift 假物件測試通過而宣稱與 WebKit、音訊中斷或系統 active 狀態相容。

## 驗證與剩餘工作

在 `ios/` 執行：

```sh
bash scripts/check_voice_input.sh
bash scripts/check_voice_audio_coordinator.sh
python3 -m unittest discover -s scripts -p 'test_voice_input.py' -v
python3 -m unittest discover -s scripts -p 'test_release_ios.py' -v
```

這些檢查執行真實純狀態機、lease slot、隔離協調器、假 driver／假 fence／假 session 和 plist／發行檢查的合成 fixture；Python 的 Apple driver 來源檢查只驗證靜態接線約束；不會執行 Apple adapter 或權限對話框。`#if os(iOS) && canImport(...)` 只隔離平台，不能證明 Apple API 編譯通過。

MacBook 後續先以完整 Xcode、XcodeGen 及 iOS Simulator SDK 執行下列建置（在 `ios/`）：

```sh
xcodegen generate
xcodebuild -project WoowAssistant.xcodeproj -scheme WoowAssistant -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project WoowAssistant.xcodeproj -scheme WoowAssistant -configuration Release -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

另需在具備 iOS 17 runtime 的環境選擇對應 simulator，檢查實際封裝的 plist，先完成能協調所有音訊使用者的正式 lease 實作，驗證租用、拒絕、撤銷、失敗回復以及網站播放／錄音和其他音訊使用者競爭；再執行加入 adapter 假音訊／授權抽象的原生單元測試及 UI 接線測試：授權、拒絕、限制、首次授權期間鬆手、無服務／無裝置辨識、取消、逾時、前後景、頁面／對話切換、音訊中斷及遲到回呼。再於獨立授權的實機條件下核對真實麥克風、語言辨識、音訊路由、VoiceOver 和 WebKit 相容性；任何模擬器或假服務結果都不得標為實機證據。Android 的服務商模型選擇及任務執行中插話另待實作。

### MacBook 原生接線驗收清單

在不更動首屏並與其合併前，先以獨立 simulator、非持久資料庫及本機合成網頁建立可重跑的測試；只在測試宿主對受控合成入口明確 attest，正式 App 的覆蓋聲明須待實際接入及驗證後才開啟。保留實際方法、結果與 `.xcresult`：

1. 從尚未建立任何 WebView 的聊天狀態進入語音，記錄覆蓋證明、基線 reset、授權／拒絕及收尾；單獨驗證 Debug／Release 打包的 plist。基線 reset 只能稱為成功建立新狀態。
2. 對手動頁面、背景分頁、popup、多來源 BrowserSession 和獨立搜尋 WebView 各持有 ticket，嘗試語音並核對未呼叫 session；測試載入中、已載入、背景切換、關閉與仍有保留參考。以原生媒體事件驗證拆除完成，而非僅依 `stopLoading()` 或 `deinit` 推論。
3. 以本機合成媒體測試播放、暫停、Web Audio、全螢幕／子畫面與麥克風擷取（環境不支援的案例明列未驗）；語音啟用中嘗試建立新 WebView，驗證先停止語音、再完成交還、最後才創建。測試兩個建立點與跨 framework 同一 owner，包含重複事件和 callback 遲到。
4. 注入 reset、category、activation、deactivation、restore 的失敗與同步重入；檢查 quarantine、無意外放行、無重複交還。以 simulator 可模擬的中斷／前後景／通知事件驗證停止、撤銷及恢復路徑，不能把未模擬的系統事件當成通過。
5. 確認使用者可理解並操作音訊忙碌／等待狀態、權限設定及 VoiceOver；核對既有瀏覽器、任務通知及鍵盤測試。完成上述驗收與首屏變更整合後，才可聲明已接線；iOS 17 真機音訊路由與麥克風結果仍須另經授權驗收。
