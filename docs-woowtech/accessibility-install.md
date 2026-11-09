# GitHub APK 安裝後的無障礙設定

## Pixel 與小米／POCO 的入口不同

先在系統「無障礙設定 → 下載的應用程式」選擇渥屋助理。若顯示「由受限制的設定控管」或「應用程式存取權已遭拒絕」，請開啟**渥屋助理自己的應用程式資訊**：

- Pixel：右上角「更多／⋮」→「允許受限制的設定」。
- POCO C85 / HyperOS 2：**向下捲到應用程式資訊底部**，在「進階設定」區找到「允許受限制的設定」。實測右上角只有「應用程式詳情、分享」，解除入口不在該選單。

依系統提示確認，再返回無障礙設定，手動開啟渥屋助理。解除限制與開啟服務是不同步驟；App 會等待服務真正連上才顯示已開啟。

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

### 實機尚未完成的部分

點擊頁面底部入口時，手機被與本測試無關的 Google 帳戶登入確認畫面中斷。沒有代使用者核准或拒絕；已請使用者自行處理。

暫停時已用 ADB 恢復原本 ACCESS_RESTRICTED_SETTINGS=allow，並保留既有服務清單、恢復渥屋助理的服務。`dumpsys accessibility` 已確認 Mika、渥屋助理及系統無障礙選單都已綁定，Binding/Crashed services 為空。這是測試後還原，不算手動解除流程通過。

仍需完成：POCO 從底部入口手動確認、關閉再開啟服務並核對綁定；全新 GitHub APK 側載安裝；Pixel 實機對照。不得宣稱以上已通過。

### 交付狀態

變更位於 `fix/accessibility-install-guide`，基於公開版 `v0.1.37-woow.4`。未更新版本號、未覆蓋手機正式 APK、未發布新的 GitHub Release。Debug APK 供本機測試，不能當成正式簽章的覆蓋更新包。

