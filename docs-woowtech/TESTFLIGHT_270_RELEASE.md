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

**正式上傳成功；登入後已核 Apple 處理完成／VALID。270 目前因缺少加密出口合規申報，仍不可供 TestFlight 下載。**

- 線上 Validate：2026-11-22 07:39:35–07:41:10（台北），exit 0。`IDEDistributionMethodiOSAppStoreValidation` 與成功 marker 均已確認。最初 CLI 將 validation 的 destination 設成 export 而在啟動前 exit 70；改為 Xcode 要求的 upload destination 後，執行的是 Validate 方法，非正式發佈。
- 正式 upload：07:41:22–07:43:01（台北），exit 0，`UPLOAD SUCCEEDED with no errors`。Apple `buildUploads` id `bc04b9de-6ff3-474e-9b1d-bb61ed8995f5` 從 AWAITING_UPLOAD 變為 PROCESSING；`uploadedDate` 為 `2026-11-21T15:43:00-08:00`，即台北 11/22 07:43:00。遠端 errors／warnings 均為空。
- 證據：T/`validation-r2/receipt.json`、`safe-evidence.json`；T/`upload/receipt.json`、`safe-build-upload-observations-final.json`；最新彙整 T/`release-status.json`。收據內未核驗的旗標不是日後狀態；以有時間的 Apple 觀察與彙整為準。
- 上傳當時 Chrome 尚在登入頁，Xcode 快取登入完成驗證與上傳。使用者後續完成登入，最新核對如下。未擷取登入憑證，未接受合約或代作出口合規聲明，未新增測試者。
- 連結：[此 App 的 TestFlight](https://appstoreconnect.apple.com/teams/fb3afe28-8d7d-4b0e-9318-135c87a529a0/apps/6834435121/testflight/ios)。本次未重送已成功上傳的 270。

## 登入後核對（2026-11-22 07:53，台北）

- 使用者已在官方 Chrome 頁面登入，確認 WOOW TECH CO., LTD.／「渥屋助理」6834435121。TestFlight 的實際新路徑含 team id；舊的無 team 清單路徑會返回 Apps。第一次頁面載入出現泛用錯誤，受控重整後可讀；沒有重送 build。
- 透過同一已登入瀏覽器唯讀查看 Apple 回傳：buildUpload `COMPLETE`，errors／warnings 皆空；build270 `processingState=VALID`、`expired=false`，preReleaseVersion=0.1.0。
- 真正阻擋是 `internalBuildState=MISSING_EXPORT_COMPLIANCE`、`externalBuildState=MISSING_EXPORT_COMPLIANCE`、`usesNonExemptEncryption=null`。原生建置與上傳完成不會自動填寫此申報。
- 既有「渥屋內部測試」group `69ca89bb-73ec-4e93-860f-35979a9601ff` 為 internal、`hasAccessToAllBuilds=true`。當次 build270 的 betaGroups 關聯仍為 0；申報完成後仍須確認可測狀態及實際群組關聯，不能預先宣稱已能下載。
- 使用者待辦已具體指出：在 TestFlight 展開「版本 0.1.0」，於270的「管理」完成加密出口申報。頁面另有舊的1.0.0 builds1–4，不能誤選為本輪270。
- 技術盤點確認本機文件用 CryptoKit AES-256-GCM；Security 提供 Keychain、隨機數及 RSA 驗簽，網路由 URLSession／WebKit 處理。實際 IPA 的10個Mach-O依賴皆為 Apple 系統或本專案 framework，未發現自製或第三方加密演算法實作。不是「完全未使用加密」，也未代替帳號所有者作法律判定。
- Apple 官方說明：[加密文件要求](https://developer.apple.com/help/app-store-connect/reference/app-information/export-compliance-documentation-for-encryption/)、[完成 TestFlight 出口合規資訊](https://developer.apple.com/help/app-store-connect/test-a-beta-version/provide-export-compliance-information-for-beta-builds/)。帳號所有者確認申報；本次未修改 `ITSAppUsesNonExemptEncryption` 或遠端申報欄位。
- 新證據 T/`web-status/verified-state.json`、`build-270-beta-status.json`、`upload-status-authenticated.json`、`existing-internal-group.mhtml`、`testflight-owner-view.mhtml` 及 SHA-256 清單；T/`encryption-technical-audit.txt` 與 packaged dependencies／bound imports。原始登入頁資料僅存本機私密證據目錄，不進提交。T/`release-status.json` 更新為申報待完成；上傳當下快照保留於 `release-status-at-upload.json`。

## 實機範圍與尚未驗收

269 iPad 與原生回歸見 [IPAD_269_TEAM_VALIDATION.md](IPAD_269_TEAM_VALIDATION.md)。270 的 TestFlight 實際下載／安裝／啟動尚未測試。原 iPhone A31 同歷史同附件、真 Apporo 兩筆錯誤、偶發長延遲、Android 同步視覺對照及完整外部檔案接收端仍待驗收。

保留原對話與附件。分支仍要求附件重新加入；沒有為測試修改此既定行為。沒有刪除手機資料或重開手機測試服務。本次只停止授權的兩個本機測試容器，建置結束均已恢復。

TestFlight 下載後優先核版本 270，保留原 A31 對話，重測開啟→中文輸入→送出→可操作→唯讀 MCP 最終結果與來源；再測鍵盤、附件及 PDF／HTML／CSV。未知結果的業務寫入不可盲目重送。
