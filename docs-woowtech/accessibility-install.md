# GitHub APK 安裝後的無障礙設定

## Pixel 與小米／POCO 的入口不同

先在系統「無障礙設定 → 下載的應用程式」選擇渥屋助理。若顯示「由受限制的設定控管」或「應用程式存取權已遭拒絕」，請開啟**渥屋助理自己的應用程式資訊**：

- Pixel：右上角「更多／⋮」→「允許受限制的設定」。
- POCO C85 / HyperOS 2：**向下捲到應用程式資訊底部**，在「進階設定」區找到「允許受限制的設定」。實測右上角只有「應用程式詳情、分享」，解除入口不在該選單。

依系統提示確認，再返回無障礙設定，手動開啟渥屋助理。POCO / HyperOS 還會顯示敏感權限確認頁：勾選風險確認、等待倒數結束，再按「確定」。解除限制與開啟服務是不同步驟；App 會等待服務真正連上才顯示已開啟。

若選項不存在，先嘗試點選無障礙清單中的渥屋助理，再重新開啟應用程式資訊並查看底部與右上角。若已可開啟服務，無須再解除限制。其他系統版本的名稱與位置可能不同。

不需解除安裝、清除資料、關閉全機防護或把 APK 改成其他安裝來源。一般 App 不能自行解除系統限制。ADB 設定是另外的部署方式，不是手動流程測試的通過證據。

Google 的通用說明：https://support.google.com/android/answer/12623953?hl=zh-Hant

## 本次修改

- 初次手機設定：補充三步驟與兩種系統入口。
- 設定 → 手機操作：Android 13 以上、無障礙尚未運作時，持續提供引導與兩個設定入口。
- 一般設定頁不以 AppOps 的推測值決定是否隱藏協助：讀不到或誤判權限時仍可自行操作。
- 繁體中文、簡體中文、英文；品牌文字由既有品牌層產生。
- 只開啟系統頁面，不修改系統權限、不以返回 App 當成授權成功。

## 驗證記錄（2026-11-09）

實機：POCO C85 / 25078PC3EG / Android 15 / HyperOS OS2.0，公開版 0.1.37-woow.4。

已在原版重現：

1. 暫時將該 App 的 ACCESS_RESTRICTED_SETTINGS 設為 ignore，清單反灰。
2. 點選後顯示系統拒絕提示。
3. 應用程式資訊右上角無解除選項。
4. 捲動至頁面底部後找到可點選的「允許受限制的設定」。

這是既有安裝的限制狀態重現，不是全新下載安裝測試。Pixel 流程依使用者回報與 Google 文件；本次尚未接入 Pixel 實機。

### 程式與自動測試

- `:app:testUpstreamDebugUnitTest`（PhoneSetupCopyTest、StatusCopyTest）：13 項，0 失敗。
- `:app:assembleUpstreamDebug`、`:app:assembleWoowtechDebug`、`:app:assembleUpstreamDebugAndroidTest`：成功。
- Android 16 / API 36 arm64 Google APIs 模擬器：AccessibilityInstallHelpTest、PhoneSetupScreenTest、SettingsScreenTest 共 53 項；第一輪 49 項通過，4 項因未捲動至控制項而失敗。
- 僅調整失敗案例的測試操作：先 performScrollTo，再點擊或輸入，保留原斷言；重跑 4 項全數通過。不是宣稱原始第一輪全綠。
- 新增兩項測試涵蓋：限制探測值為 false 仍有協助入口、按鈕回呼、開啟設定不代表完成、EnabledNotRunning 保留協助、服務 On 後收起，以及 Android 12 不顯示限制說明。
- 既有初次設定入口點擊測試亦通過。品牌生成資源已確認繁中顯示「渥屋助理」、英文顯示「woowtech agent」；介面 instrumentation 跑共用 upstream 變體，不能冒稱 woowtech 變體的 instrumentation。
- `git diff --check`：通過。

### 實機續測：手動解除已完成

前一輪曾因無關的 Google 登入確認而暫停；使用者處理後已繼續。

1. 用 ADB 將既有安裝的限制狀態恢復為 ignore，重現反灰與系統拒絕提示。此步只用於建立測試條件。
2. 從系統 App 資訊底部點選「允許受限制的設定」，讀回 AppOps 為 allow；解除階段沒有執行 appops allow 指令。
3. 返回無障礙清單，渥屋助理由反灰變成可點選、狀態為「已關閉」。
4. 打開「使用渥屋助理」，出現 HyperOS 的風險勾選與倒數確認頁；完成後開關為 true。
5. dumpsys 確認渥屋助理、Mika、系統無障礙選單均已綁定，Binding/Crashed services 為空。
6. 原版 USB API /api/v1 與 /api/v1/device 均 HTTP 200；server_version=0.1.37-woow.4，interactive/helper_available/user_unlocked/ready 均為 true。

已證實這支 POCO 支援透過系統頁面解除限制，入口在資訊頁底部；不需靠 ADB 授權指令完成解除。

### 全新隔離套件安裝：被 Play 安全防護擋下

為保留正式版資料，用 Gradle init script 將測試 APK 的 applicationId 改為 `io.woowtech.agent.installtest`，使用 Debug 簽章；其餘為本次修改的 woowtech 原始碼。這個測試包不等同正式簽章的公開 APK。

- 透過 USB 傳檔到 Download，再由手機 Files 點 APK，進入系統安裝器；未使用 adb install。
- Files 原本不允許安裝未知來源。暫時經系統確認開啟，接著按安裝。
- Play 安全防護要求掃描；執行掃描後顯示「已封鎖有害的應用程式」「此应用可能有害」。詳細頁沒有具體分類或原因。
- 沒有選「仍要安裝」。系統回報「未安裝應用程式」，套件清單確認 installtest 不存在。
- 已移除手機上的測試 APK，將 Files 的未知來源安裝權限關回原狀。正式版套件、資料與無障礙服務保留。
- 測試包 SHA-256：`4db96b808bfdeb157a88131f07b46d2fd73ef8b7eb13ae193e3e0c5fec607899`；本機留存 `/tmp/woow-accessibility-installtest.apk`，不作發布用途。

因此，全新隔離 APK 安裝沒有通過；不能據此推定正式 APK 必定被擋，也不能宣稱是誤判。這是安裝掃描階段的問題，與已實測通過的受限制設定解除入口分開記錄。

Pixel 仍未接入實機，不能宣稱 Pixel 實測通過。正式簽章公開 APK 的全新安裝亦未在保留使用者資料的前提下重做。

### 交付狀態

變更位於 `fix/accessibility-install-guide`，基於公開版 `v0.1.37-woow.4`。未更新版本號、未覆蓋手機正式 APK、未發布新的 GitHub Release。Debug APK 供本機測試，不能當成正式簽章的覆蓋更新包。


## 後續正式包與語音測試

已用公開版相同 SHA-256 的正式簽章 APK 重做同版本覆蓋安裝，亦被 Play 安全防護攔截。另已重現 zh-TW 語音錯誤並完成程式修正，尚未取得實機成功轉寫。詳見[後續測試紀錄](poco-install-and-speech-test.md)。
