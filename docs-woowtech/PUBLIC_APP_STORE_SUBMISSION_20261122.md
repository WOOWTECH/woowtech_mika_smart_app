# iOS 公開 App Store 送審：2026-11-22

使用者已要求「要去處理公開上架了」，公開送審及核准後發佈納入授權。目前**未提交審查、未公開上架**；先前僅限TestFlight的範圍已被本次要求擴充。

## 實際狀態

| 項目 | 已確認結果 |
| --- | --- |
| App | 渥屋助理，`io.woowtech.assistant`；ASC `6834435121`；team `W4UWZ8NP2P` |
| 最新上傳 | `0.1.0(274)`，runtime `611d6bfa75ec46d39fd9654ac97ff2de6291a1a0`，Apple成功回執2026-11-22T10:45:43Z（臺北18:45:43）；[來源鏈](TESTFLIGHT_274_RELEASE.md) |
| 新程式差異 | 至`d8e47b78`的iOS產品來源及設定與274相同，只有附件UI測試與紀錄改動；沒有重傳成功的274 |
| 直接阻礙 | 原官方Chrome分頁仍為`appstoreconnect.apple.com/login`；已帶至前景並請擁有者完成登入及必要2FA。沒有讀密碼、Cookie、header或複製私密審查憑證 |
| 歷史商店版本 | 保存的商店頁顯示**1.0.0／遭拒絕**，與274的0.1.0不同。當前版本及拒絕原因尚待登入讀取，不能預設274可選或擅改版本 |
| 素材用建置 | Xcode27／Simulator SDK27，Release、0.1.0(274)，135.93秒exit0、source_changed=false、最低可用3,502,718,976 bytes。不是新Store archive或實機驗收 |
| Simulator截圖 | 第一批303.12秒exit1：iPhone首張白畫面不可用，iPad bootstatus90秒逾時。暖啟動批106.0秒exit1：JPEG呈現完整歡迎頁，但命令45秒逾時，完成界線未知，不算整批成功或核心功能素材 |
| 清理 | 只移除本次新建、已核Shutdown且沒有使用者資料的兩個Simulator；原證據及其他裝置資料均保留 |
| 真iPhone素材 | 原唯一操作者完成淺／深兩張，0 Send／模型／MCP，還原外觀並清除自有草稿。父線已取回並親看，只有固定產品範例及自有草稿；逐byte核原PNG的尺寸、bytes／SHA。原始1178×2556、RGB不含alpha，寬度不符Apple列出的1179／1206等尺寸，**目前不可標成可上傳**；已要求只核既有原生能力，不修圖或新開服務 |
| 新原生候選 | 沿既有RSD／DVT一次takeScreenshot，1.248686秒，取得真正**1179×2556／16-bit RGB**原檔947,243 bytes；SHA256 `6d6785b13d3188f695bd51145300b9d93616ffdc3ed299aacda40696a238dfc1`。父線親看無私人資料，核三項seal散列及三個精確根路徑manifest項；不宣稱全manifest已下載。未修圖、補邊、改顯示模式或新啟服務；承載USB或Wi-Fi未另證明。尺寸符合，但16-bit等整體素材條件仍待ASC實際驗證，尚未上傳 |

## 可審閱的草稿

- [中英文商店文案](app-store/20261122/metadata-draft.json)：名稱、副標題、宣傳文字、描述、關鍵字及更新說明。本機字數檢查通過；關鍵字UTF-8為71／73 bytes。尚未寫入ASC，不是Apple欄位驗證。
- [英文審查說明補充](app-store/20261122/review-notes-supplement.en.txt)：模型設定、第三方服務、同意、附件、文件、瀏覽器與選用MCP的操作路線。不含API Key或私人聯絡資訊。
- [自有中文範例](app-store/20261122/review-sample.zh-Hant.txt)：中文、單一表格與特殊字元。是範例輸入，沒有宣稱模型／產檔已執行。

文案描述現有入口，不宣稱Word／Excel、其他App控制、離線AI或分享送達。價格、地區、著作權、支援網址與既有審查憑證先保留，登入後核對，不任意改商業設定。

## 隱私與審查核對

團隊直接核實際Store IPA、來源、三份privacy manifests及公開政策。IPA SHA256仍為`d72102f5d992bc2458aaff7c15ff0e8cdae8061eeee79d0dad15a6111b79dcf0`，UUID `7CE1BB7D-7066-3E04-B2F8-8280E33F5B05`。Info為iOS17+、SDK27、iPhone/iPad及`ITSAppUsesNonExemptEncryption=false`。沒有新增SDK、權限或私鑰。

- 正式[隱私政策](https://assistant-relay.woowtech.io/privacy/ios)與App內連結一致；一次公開GET為HTTP200、46,455 bytes，SHA256 `8b248286fcd50d2e0cca42c82cbe96cf1dae8f74efc75228301536a1a551ecc4`。政策描述檢舉供人員檢視、最長30天及IP雜湊防濫用；頁面可讀不代表後端刪除已驗證。
- App會POST使用者送出的AI回覆檢舉，不能直接申報「不收集資料」。至少核對Customer Support／Other User Content及App Functionality；身分關聯、IP衍生資料與合作服務保留用途依真實處理填寫，不由空manifest陣列推成無收集。
- 已有第三方AI接收方及分享內容同意畫面；沒有本輪新真機同意、檢舉或伺服器刪除通過的證據。
- 一般HTTP(S)瀏覽器對應Unrestricted Web Access；依Apple真實問卷計算年齡，不擅填4+。未找到原生用戶間聊天、公開動態牆或已核實年齡驗證。
- 未找到App自有帳號註冊或StoreKit購買實作。既有審查備註曾提供專用模型服務，目前有效性及額度未核，不能假定不存在或可用。原iPhone20:53模型限流不能證明該審查服務同樣失效。

詳細安全審查保存在本機`T/public-app-store-20261122/PRIVACY_REVIEW.md`。`T=/Users/woowtech/Documents/WOOWTECH-iOS-validation/documents-20261120/testflight-20261122`。本工作樹未找到對應報告端的部署實作，本輪不把政策敘述當伺服器已驗。

真機兩批在本機`T/public-app-store-20261122/physical-candidates/`與`physical-native-candidate/`；原生批report／result／manifest SHA256依序`65122ec524f6053f3e16a3d61a9f62fd1996167b1e85c1de9f88e8d01d9834f2`、`49cd2d69e87b4dd6ea769fc2b240fe45fb4523f0f6ff96e59e5ef3d5bd0f83e9`、`9579d473bbdeaa7be4dbcc9c7c442ba14760c54aed8e0307706919ae1f184b68`。草稿已清空、返回A31；原資料保留依唯一操作者收據，不宣稱父線另讀全45原檔。舊1178候選與失敗Simulator素材均未冒充通過。

## 登入後接續

1. 讀原App、目前版本、拒絕詳細原因及metadata；保留現有審查憑證及聯絡資訊。
2. 核274 processing、可選build及0.1.0／1.0.0關係。確定需要新版本號或程式修補時才建新archive，不重傳成功的包。
3. 核現有截圖是否符合最新UI與Apple尺寸，只上傳已檢視且無私人資料的真實介面；iPad支援仍需13吋素材。
4. 核隱私、支援網址、App Privacy、年齡、內容權利、價格／地區及聯絡欄位。缺擁有者事實時列精確欄位，不補造聲明。
5. 透過既有授權確認專用審查模型服務可用、處理實際拒絕項並保存操作路線；原高CPU／MCP及[其他商用缺口](ACCEPTANCE_GAPS_20261122.md)仍保留。
6. 核實資料後加入送審草稿、提交並讀回實際狀態；維持手動發佈，Apple核准後依公開上架授權繼續發佈及核公開頁。Ready for Review或上傳成功都不算公開可下載。

## 官方依據

- [送審流程](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-app/)與[審查存取資訊](https://developer.apple.com/help/app-review/before-submitting-for-review/complete-review)。
- [截圖規格](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications)：iPhone及支援iPad時的13吋素材，依實際接受尺寸核對。
- [App隱私定義](https://developer.apple.com/app-store/app-privacy-details/)、[審查準則](https://developer.apple.com/app-store/review/guidelines/)及[上傳工具鏈要求](https://developer.apple.com/news/upcoming-requirements/)。
