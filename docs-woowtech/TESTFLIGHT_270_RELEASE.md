# TestFlight 270 發佈紀錄（2026-11-22）

版本 0.1.0 (270)，App `io.woowtech.assistant`／App Store Connect `6834435121`，WOOWTECH team `W4UWZ8NP2P`。使用者本輪明確要求上傳 TestFlight；沒有公開上架或新增外部測試者。

## 來源與實作

封存來源 `7026c468c4bb5ad2c51517d9611a93f1a4cce8e8`。本版包含 269 的長歷史分頁、鍵盤與 MCP 分類修正；相較 269 的 `b81ff349` 沒有新增 Swift runtime 修改。此次補上 App 磁碟空間 E174.1／自身暫存時間 C617.1，以及 AssistantModels／AssistantSkills 的 UserDefaults CA92.1 宣告。審查涵蓋九個 framework 的 95 個來源檔。

新增的 ChatLongHistoryUITests 與四個 ChatAttachmentUITests 方法已歸入原生 CI inventory，保留完整精確覆蓋檢查。此處是測試登錄修正，不是重新宣稱原生案例已執行。

另外 `4d800f81e5970395bc316faf8bb943b45cb05e44` 修正發佈驗證腳本的 `codesign --extract-certificates=prefix` 參數。原格式把 prefix 當成待驗證路徑；同一真實 IPA 對照證明原命令 exit 1、修正命令 exit 0 且憑證吻合。此提交僅改兩個 Python 檔，沒有重建或偷換既有 archive。

## 本輪驗證與證據

原始證據：`/Users/woowtech/Documents/WOOWTECH-iOS-validation/documents-20261120/testflight-20261122`（T）。私密 Apple log 不進儲存庫；報告不包含憑證內容、token 或業務資料。

- Release guards 112／112、CI inventory guards 17／17 通過；修正憑證驗證後相關 45／45 通過。這些不是商用實機驗收。
- 正式 archive 與 App Store export 成功。114.22 秒外層命令 exit 1 發生於匯出後的憑證檢查；保留原失敗，另以修正驗證器確認同一 IPA。建置期間來源未變。
- 裝置 arm64／最低 iOS 17／SDK 27／Release `-O`，DEBUG fixture 未編入。App 加九個 framework 共 10 個 Mach-O 驗證成功。IPA 簽章為預期 Apple Distribution，非 adhoc，`get-task-allow` 關閉。
- 三份實際封裝 manifest 均已驗；沒有 Release ATS Debug 例外。
- IPA SHA-256 `162d046e09988b036138f62ebc787978354069322a5a165e1c579cf74b8291a0`，8,132,600 bytes。主程式 SHA-256 `1edf7847ced0a9b424c192e3812198c616eb5c6d73970912bb007c9051225ef1`，UUID `8EDDC835-5496-396D-8510-684CF2815B8D`。這是本機簽章匯出包；Apple 重簽／加密後下載包不主張逐位元相同。
- 檔案：`release-270d/report.json`、`packaged-privacy-evidence.json`、`codesign-prefix-reproduction.json`、`guard-tests-r4-receipt.json`、`release-codesign-guard-tests.log`。父目錄保留 heavy/source-before/after 與兩個容器恢復紀錄。

## Apple 狀態

**270 已開放內部測試，並於 11/22 在原 iPhone 透過 TestFlight 原地更新及部分實測。已核裝機 0.1.0 (270) 與 `TestFlight Beta Distribution`；回尾按鈕遮字及模型限流阻擋 MCP 等缺口仍在，未完成商用驗收。**

- 線上 Validate：2026-11-22 07:39:35–07:41:10（台北），exit 0。`IDEDistributionMethodiOSAppStoreValidation` 與成功 marker 均已確認。最初 CLI 將 validation 的 destination 設成 export 而在啟動前 exit 70；改為 Xcode 要求的 upload destination 後，執行的是 Validate 方法，非正式發佈。
- 正式 upload：07:41:22–07:43:01（台北），exit 0，`UPLOAD SUCCEEDED with no errors`。Apple `buildUploads` id `bc04b9de-6ff3-474e-9b1d-bb61ed8995f5` 從 AWAITING_UPLOAD 變為 PROCESSING；`uploadedDate` 為 `2026-11-21T15:43:00-08:00`，即台北 11/22 07:43:00。遠端 errors／warnings 均為空。
- 證據：T/`validation-r2/receipt.json`、`safe-evidence.json`；T/`upload/receipt.json`、`safe-build-upload-observations-final.json`；最新彙整 T/`release-status.json`。收據內未核驗的旗標不是日後狀態；以有時間的 Apple 觀察與彙整為準。
- 上傳當時 Chrome 尚在登入頁，Xcode 快取登入完成驗證與上傳。使用者後續完成登入並明確授權出口合規申報，執行結果見下節。未擷取登入憑證、接受其他合約、購買會員或新增測試者。
- 連結：[此 App 的 TestFlight](https://appstoreconnect.apple.com/teams/fb3afe28-8d7d-4b0e-9318-135c87a529a0/apps/6834435121/testflight/ios)。本次未重送已成功上傳的 270。

## 登入後核對（歷史狀態：2026-11-22 07:53，台北）

- 使用者已在官方 Chrome 頁面登入，確認 WOOW TECH CO., LTD.／「渥屋助理」6834435121。TestFlight 的實際新路徑含 team id；舊的無 team 清單路徑會返回 Apps。第一次頁面載入出現泛用錯誤，受控重整後可讀；沒有重送 build。
- 透過同一已登入瀏覽器唯讀查看 Apple 回傳：buildUpload `COMPLETE`，errors／warnings 皆空；build270 `processingState=VALID`、`expired=false`，preReleaseVersion=0.1.0。
- 真正阻擋是 `internalBuildState=MISSING_EXPORT_COMPLIANCE`、`externalBuildState=MISSING_EXPORT_COMPLIANCE`、`usesNonExemptEncryption=null`。原生建置與上傳完成不會自動填寫此申報。
- 既有「渥屋內部測試」group `69ca89bb-73ec-4e93-860f-35979a9601ff` 為 internal、`hasAccessToAllBuilds=true`。當次 build270 的 betaGroups 關聯仍為 0；申報完成後仍須確認可測狀態及實際群組關聯，不能預先宣稱已能下載。
- 當時使用者待辦為：在 TestFlight 展開「版本 0.1.0」，於270的「管理」完成加密出口申報；已於下節完成，無須再操作。頁面另有舊的1.0.0 builds1–4，不能誤選為本輪270。
- 技術盤點確認本機文件用 CryptoKit AES-256-GCM；Security 提供 Keychain、隨機數及 RSA 驗簽，網路由 URLSession／WebKit 處理。實際 IPA 的10個Mach-O依賴皆為 Apple 系統或本專案 framework，未發現自製或第三方加密演算法實作。不是「完全未使用加密」，也未代替帳號所有者作法律判定。
- Apple 官方說明：[加密文件要求](https://developer.apple.com/help/app-store-connect/reference/app-information/export-compliance-documentation-for-encryption/)、[完成 TestFlight 出口合規資訊](https://developer.apple.com/help/app-store-connect/test-a-beta-version/provide-export-compliance-information-for-beta-builds/)。帳號所有者確認申報；本次未修改 `ITSAppUsesNonExemptEncryption` 或遠端申報欄位。
- 當時證據 T/`web-status/verified-state.json`、`build-270-beta-status.json`、`upload-status-authenticated.json`、`existing-internal-group.mhtml`、`testflight-owner-view.mhtml` 及 SHA-256 清單；T/`encryption-technical-audit.txt` 與 packaged dependencies／bound imports。原始登入頁資料僅存本機私密證據目錄，不進提交。申報前快照保留於 `release-status-before-declaration.json`；上傳當下快照保留於 `release-status-at-upload.json`。

## 授權後完成申報與群組配置（2026-11-22 08:04–08:06，台北）

- 使用者針對先前申報限制明確回覆「可以」。依已核對的 270 原始碼與實際 IPA，在官方 Apple「App 加密文件」選擇「未使用上方提及的任一種演算法」，08:04:23 儲存一次。此答案表示沒有非豁免加密，並非聲稱 App 完全未使用加密。
- Apple 同一登入工作階段回傳 HTTP 200、`processingState=VALID`、`usesNonExemptEncryption=false`，內部狀態先轉為 `READY_FOR_BETA_TESTING`。沒有重新上傳或替換 IPA。
- 核對既有「渥屋內部測試」只有一位測試者，與目前登入帳號相符；08:05:32 透過官方頁面將 270 加入此群組。未邀請新測試者、送交外部 Beta 審查或公開上架。
- 最終讀回 `betaGroups` 包含原群組 `69ca89bb-73ec-4e93-860f-35979a9601ff`、`internalBuildState=IN_BETA_TESTING`、`autoNotifyEnabled=true`。這是帳號／群組可下載證據，並非手機已安裝或通知已送達的證據。
- 證據：T/`web-status/export-submit-receipt.json`、`post-declaration-build.json`、`270-existing-group-association-click.json`、`270-assigned-status.json`、`verified-ready-state.json`。最新彙整為 T/`release-status.json`；原申報前觀察檔仍保留。
- 後續來源設定在 Debug／Release 的 Info.plist 加入布林值 `ITSAppUsesNonExemptEncryption=false`。`plutil` 與逐鍵比對確認格式有效且只增加該欄位；這不是新一輪 archive 或實機測試。此設定不在已封存的 270 內；270 使用本次遠端申報。日後若新增自製或第三方加密能力，須重新審查該設定。

iPhone 操作：開啟 TestFlight →「渥屋助理」→ 安裝／更新，核對已安裝版本為 **0.1.0 (270)**。若先顯示舊的 1.0.0，從「先前的建置版本」選 0.1.0 的 270。08:06 時本機未連到原 iPhone；後續由另一台 Mac 的既有 iPhone 分支完成，見下節。不要刪除原 App 或對話來更新。

## 原 iPhone 實裝與部分驗證（2026-11-22 09:32–10:08，台北）

10:11 透過 Omnigent 原有登入權限唯讀核對 [iPhone 分支](https://omnigent.woowtech.io/c/3f02db4920244c69bcb403ece7494237)，包含實際工具輸出，非僅沿用助理的完成聲明。該分支在 `/Users/elmolin` 操作同一支 iPhone16,1／iOS26.5；本機未同時啟動另一個手機控制器。查詢時分支為 idle，host／runner 均 online。

- 09:32 已配對無線開發通道及 WDA ready；USB 問題並未因此證明修復。09:45 裝機查詢為 `io.woowtech.assistant`、0.1.0、270；09:55 再核 `SignerIdentity=TestFlight Beta Distribution`，並有 TestFlight 指定270／打開及首次啟動畫面。這是實際 TestFlight 更新證據，來源仍綁定本報告的7026c468；未將249／250／251結果套用。
- 原地更新後、送出測試前，conversations 與 learning vault 的 SHA-256 皆與更新前一致。後續原 A31、真圖片與兩個記憶項目仍可讀，記憶ID／文字比對相同；原圖片清理前後雜湊相同。之後正常保存可能改變加密檔案bytes，未宣稱整輪測試前後所有vault不變。
- 原 A31（送出前16則訊息）中文輸入、鍵盤開啟、唯讀訂單查詢送出一次後仍可操作。CPU採樣為13.25%、22.19%、2.65%（包含UI操作），本輪未重現持續100%；最終仍是模型「請求太頻繁」，沒有MCP最終結果，不能認定原卡死根因已修。
- `chat.returnToLatest` 仍遮住最後的錯誤文字，原生元素座標及 `45-270-original-after-send.jpg` 有證據。取回與270相容的84行候選patch，SHA-256 `da2c035179637e66a554227c5ad9eb4fa808b8dc4f0b82437a47e2bcf7834b9b`；保留80則顯示分頁與新版navigateTranscript路徑。該候選尚未套入本分支、建置或裝機，語法／隔離套用通過不是修復驗收。
- 使用既有真實中文回答完成短篇PDF／HTML產生、App預覽、實際存入「我的iPhone」及系統閱讀器重新開啟；取消操作未誤報完成。HTML重開初次導航失敗及自動化逾時保留，後續在檔案清單選正確項目才成功。不是長篇跨頁PDF、CSV正向或外部分享接收端驗收。
- 真正terminate／launch後，既有瀏覽歷史與搜尋引擎保留；未新增搜尋，因此不是新增歷史寫入時序問題的回歸。270僅有清除全部歷史，沒有單筆QA清理入口，本輪保留原歷史。
- 5個本輪QA文件副本／暫存檔逐一比對雜湊後刪除並驗不存在；沒有刪原對話、圖片或記憶。249上的手動記憶新增／修改／重啟測試另屬249證據，不當作270全流程通過。

本機證據：T/`iphone270-validation-summary.json`、`iphone270-verified-tool-excerpts.private.json`、`iphone-check-270-evidence-20261122.private.json`、`270-return-row-candidate-export.patch`。私密完整紀錄不進儲存庫。T/`release-status.json` 已更新為270實機部分測試；先前未實裝狀態保留於 `release-status-before-iphone270-validation.json`。

## 實機範圍與尚未驗收

269 iPad 與原生回歸見 [IPAD_269_TEAM_VALIDATION.md](IPAD_269_TEAM_VALIDATION.md)。270 的 TestFlight下載／安裝／啟動及上節限定情境已在原iPhone驗證。原 A31 根因與穩定回歸、真 Apporo 兩筆錯誤／最終MCP、遮字修補、多供應商／斷線逾時、偶發長延遲、CSV正向／多頁PDF、大檔與相機相簿、瀏覽器登入跳轉下載、Android同步視覺對照及完整外部檔案接收端仍待驗收。

保留原對話與附件。分支仍要求附件重新加入；沒有為測試修改此既定行為。沒有刪除手機資料或重開手機測試服務。本次只停止授權的兩個本機測試容器，建置結束均已恢復。

接續優先整合遮字候選並在新版本回歸；保持原A31及附件，完成開啟→中文輸入→送出→可操作→唯讀MCP最終結果與來源。模型限流未解除前不把錯誤回覆當MCP通過；未知結果的業務寫入不可盲目重送。
