# 聊天語音輸入：第一階段，尚未接入

此提交只提供可審查的底層候選。輸入區沒有語音按鈕或手勢，使用者不能使用此功能；未宣稱與 Android 完整對齊。純 Swift 狀態機及合成 driver 以 Command Line Tools 測試，Apple Speech 介面、iOS SDK 類型檢查、模擬器與實機均尚未驗證。`content-transcribe` 技能處理的是已核准的文字／字幕，與聊天聽寫不同。

## 接線契約

- 在聊天介面持有 `VoiceInputStateMachine(driver: AppleVoiceInputDriver())`，所有操作在 MainActor。`begin(gestureStartedAt:)` 的時間與預設 `ProcessInfo.processInfo.systemUptime` 同源；手勢長按約 0.3 秒後呼叫，`drag` 使用同一座標單位的向上距離及門檻，離開手指呼叫 `release`，中斷手勢呼叫 `cancel`。由 UI 定期呼叫 `tick`，也必須在離開聊天、切換對話、scene 非 active 或物件釋放前 `cancel`；不可只依賴計時器。
- 以 `onStateChange` 顯示錄音、辨識中的文字、取消落點、收尾及錯誤，提供權限遭拒／受限制和辨識不可用的可理解提示。權限彈窗可能中斷手勢：授權後由使用者重新按住，不能在手指已離開或 App 已離開聊天後自動錄音。另需提供 VoiceOver 可操作的開始／結束／取消入口，並實測與文字選取、鍵盤、附件及切換頁面共存。
- 以 `onFinal` 將結果透過 `VoiceDraftJoin.join` 加到 **當下** 草稿，不自動送出。介面要以對話身份或世代確認結果仍屬當前對話；切換時先取消。不要把 partial 寫入草稿或保存音訊。草稿合併以 Unicode scalar 與 CJK 常用區塊判斷，包含擴充漢字；Android 現有程式以 UTF-16 `Char` 判斷，因此邊界文字不保證逐碼相同。
- 回呼必須維持 session ID，舊 session 的回呼在取消、失敗、逾時及新手勢後均被忽略。手指按住期間的 final 要等鬆開決定，取消時丟棄；少於 0.5 秒的手勢丟棄；預設 60 秒觸發收尾，收尾最多等待 5 秒。系統 driver 的 60 秒獨立 deadline 作為額外防線，但主執行緒被阻塞或系統暫停時不能視為即時保證。UI timer、scene 中斷及音訊工作階段管理仍須整合驗證。

## 權限與隱私

Debug 和 Release 的麥克風說明涵蓋聊天及經同意的網站；兩者均新增語音辨識說明。發行檢查現在要求封裝後 plist 含非空語音辨識用途說明。`AppleVoiceInputDriver` 依序要求 Speech 與麥克風授權，只在 session 仍有效時開始，並檢查服務與裝置上辨識可用性，再設定 `requiresOnDeviceRecognition`；不回退到雲端或服務商，不儲存錄音，也不輸出音訊或逐字稿日誌。

音訊 session 是 App 共用資源：候選在清理時嘗試停用及還原原 category／mode／options，尚未證明與 WebKit 網站音訊、通話中斷、其他音訊路由或其他 App 功能互不干擾。整合前需設計共用資源的協調方式並實測。即使只用裝置辨識，Apple 仍要求 Speech 用途說明。未來新增雲端服務時，須另設明確選擇、目的地與資料處理說明、隱私揭露及測試；不能沿用「只在裝置上」的文案。

## 驗證與剩餘工作

在 `ios/` 執行：

```sh
bash scripts/check_voice_input.sh
python3 -m unittest discover -s scripts -p 'test_voice_input.py' -v
python3 -m unittest discover -s scripts -p 'test_release_ios.py' -v
```

這些檢查執行真實純狀態機、假 driver 和 plist／發行檢查的合成 fixture；不會執行 Apple adapter 或權限對話框。`#if os(iOS) && canImport(...)` 只隔離平台，不能證明 Apple API 編譯通過。

MacBook 後續先以完整 Xcode、XcodeGen 及 iOS Simulator SDK 執行下列建置（在 `ios/`）：

```sh
xcodegen generate
xcodebuild -project WoowAssistant.xcodeproj -scheme WoowAssistant -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project WoowAssistant.xcodeproj -scheme WoowAssistant -configuration Release -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

另需在具備 iOS 17 runtime 的環境選擇對應 simulator，檢查實際封裝的 plist，執行加入 adapter 假音訊／授權抽象的原生單元測試及 UI 接線測試：授權、拒絕、限制、首次授權期間鬆手、無服務／無裝置辨識、取消、逾時、前後景、頁面／對話切換、音訊中斷及遲到回呼。再於獨立授權的實機條件下核對真實麥克風、語言辨識、音訊路由、VoiceOver 和 WebKit 相容性；任何模擬器或假服務結果都不得標為實機證據。Android 的服務商模型選擇及任務執行中插話另待實作。
