# iOS 公開 App Store 送審：2026-11-22批次

使用者已要求「要去處理公開上架了」，並完成Apple官方登入。本批已實際修改App Store Connect的版本、建置、中英文介紹與一張原生截圖；**目前為0.1.0（274）／PREPARE_FOR_SUBMISSION／手動發佈，尚未重新送審或公開上架**。最後官方讀回為2026-11-22T15:57Z起；臺北已跨至11月23日。

## 已實際完成

| 項目 | 結果與界線 |
| --- | --- |
| App | 渥屋助理，`io.woowtech.assistant`；ASC `6834435121`；Team `W4UWZ8NP2P`；未修改其他App |
| Apple登入 | 原官方Chrome分頁已登入，版本、建置及審查資訊均可讀；沒有擷取密碼、Cookie或auth header |
| 274處理 | 官方build `7035b2a6-8482-45d5-a058-8b235183d7b0`：0.1.0／274、VALID；內部IN_BETA_TESTING，外部READY_FOR_BETA_SUBMISSION。這不證原手機已從TestFlight下載 |
| 來源 | runtime `611d6bfa75ec46d39fd9654ac97ff2de6291a1a0`；Store IPA 8,156,199 bytes，SHA256 `d72102f5d992bc2458aaff7c15ff0e8cdae8061eeee79d0dad15a6111b79dcf0`；UUID `7CE1BB7D-7066-3E04-B2F8-8280E33F5B05`。本批沒有新archive、重傳或runtime修改 |
| 版本對齊 | 原1.0.0遭拒版本`e8552737-0b4a-44e0-8b12-9469cb58d931`改為0.1.0／MANUAL，PATCH200；build關聯PATCH204及GET200確認選取274。最新GET200為PREPARE_FOR_SUBMISSION |
| 商店文案 | zh-Hant及en-US的description、keywords、promotionalText均PATCH200，逐字讀回一致；名稱、副標題、更新說明仍是草稿，沒有寫入 |
| 新原生截圖 | 原手機274真實1179×2556／16-bit RGB PNG、947,243 bytes；SHA256 `6d6785b13d3188f695bd51145300b9d93616ffdc3ed299aacda40696a238dfc1`。建立素材201、PUT200、commit200，Apple實際處理為PREPARE_FOR_SUBMISSION，無stateDetails錯誤；未修圖、縮放或補邊 |
| 截圖掛載及排序 | asset `f9000019-75d3-8431-8005-3cf1d11d90a9`已掛zh-Hant／IPHONE_DYNAMIC_ISLAND_MEDIUM_PROFILE，placement `24800019-75d3-8431-8f01-72b95f5177b8`；POST201、GET200，state ACTIVE。排序POST201及GET200核新圖第一、原五張完整保留，共六張。ACTIVE／處理成功不是App Review核准 |
| 支援網址 | 保留兩語系原support／marketing URL `https://aiot.woowtech.io/`；單次無認證公開GET200，轉址`/en`、217,857 bytes。這只證頁面可讀，未假裝已完成客服處理 |

原iPhone仍是**Development簽章的相同Release binary274**；原A31、附件、歷史與記憶保留，單一操作者未改。Apple後端IN_BETA_TESTING與手機安裝管道分開記錄。[發佈來源鏈](TESTFLIGHT_274_RELEASE.md)及[實機缺口矩陣](ACCEPTANCE_GAPS_20261122.md)保留所有未通過／未測項。

## 原拒絕與必要產品事實

官方原訊息日期2026-11-16T16:00:35Z，針對1.0.0／build4，理由為**4.3 Spam及4.2.6 App Generation Services**，涉及重複功能、缺乏差異與內容提供者／提交者關係；不是僅缺新截圖。Apple要求顯著修正，或以九題完整說明既有合規依據。

同帳號實際另有**Apporo Assistant，`com.apporo.assistant`，ASC `6835318500`，1.0.0／WAITING_FOR_REVIEW**。兩者原公開介紹高度相近；Apporo介紹載明APPORO UNION INC.與WOOW TECH開發關係。這些公開描述不替代負責人的權屬／實際產品定位確認；本批未修改、撤回或取消Apporo。

團隊已完成[九題英文回覆草稿及技術證據](APP_REVIEW_43_RESPONSE_DRAFT_20261122.md)，明確區分原創實作、Mika Apache-2.0衍生／技能素材及可能共用的Apporo框架。文件匯出在11月20日加入，是可具體展示的後續改動；不能僅以新增框架、改品牌或文案當成已排除重複問題。

仍需負責人提供真實事實，才能完成並送出九題回覆：

1. 渥屋助理與Apporo Assistant各自的用戶、任務、服務／內容與真正功能差異；若主要是同核心換品牌，請明說，由負責人決定整併或產品差異方向。
2. 兩者的實際所有者／內容及服務提供者、WOOW與Apporo關係，屬自有產品或受託開發；開發服務／模板與素材來源依事實說明。
3. 真實用戶需求、外部beta回饋與已發布版本的共用程式／素材資訊。已有受控開發QA可引用，但不能冒稱獨立客戶調查或完整商用通過。

沒有向Apple送出含OWNERFACT佔位符的回覆，也沒有補造「全部原創／無共用／無第三方」聲明。等待的是產品事實，不是重複索取公開送審授權。

## 審查服務實際失敗

保留既有私密審查聯絡與3688字備註，沒有將其內容、API URL、模型名或API Key寫進repo。本批只把審查備註中的既有設定放在記憶體，向原服務送純合成「Reply with only the word OK.」；無商業查詢、模型切換或MCP工具。

| 對照 | 真結果 |
| --- | --- |
| 第一次，預設urllib客戶端 | 0.107268秒、HTTP403、17 bytes；僅保存body hash，離線對照為Cloudflare1010。不能由此判金鑰無效 |
| 一次明確UA控制 | 依Cloudflare官方說明，使用如實的`WOOWTECH-AppReviewAvailability/0.1.0 (authorized diagnostic)`，其餘原設定不變。0.305820秒、**HTTP402**；614 bytes，安全type=`invalid_request_error`、code=`402`，沒有chat completion |

兩次都不自動重試、不跟隨轉址；沒有修改防護／帳務或購買額度。原始服務端錯誤文字未保存，故**不能單憑HTTP402斷定帳務、餘額或配額哪項失效**。現有審查服務可用性未通過；請在ASC私密審查欄位恢復或更新可用的專用服務後通知驗證，不要在聊天貼金鑰。

這與原iPhone20:53的UI限流是兩份獨立證據；後者沒有raw HTTP狀態，不互相歸因或回填。

## 隱私、年齡及其他素材

- 目前ASC已發布的App Privacy是**Other User Content／App Functionality／Not Linked To You**，發布日期11月14日；不是「不收集資料」。本批只讀，未改隱私標籤。團隊建議對主動檢舉核Customer Support用途／分類及真實保留／身分關聯；未在缺事實時替負責人填聲明。
- 政策`https://assistant-relay.woowtech.io/privacy/ios`與App連結一致，先前單次公開GET200、46,455 bytes、SHA256 `8b248286fcd50d2e0cca42c82cbe96cf1dae8f74efc75228301536a1a551ecc4`。政策描述檢舉最長30天及雜湊IP防濫用；本工作樹未找到對應後端部署，未驗伺服器刪除。
- 現有年齡問卷unrestrictedWebAccess=true、override18+／舊17+；本批未降級或改答案。未找到App自有帳號註冊、StoreKit或廣告追蹤SDK；不由此推論所有外部服務都不收集資料。
- 原zh-Hant有iPad13吋2064×2752、iPhone大型1320×2868、中型1206×2622，各五張delivery COMPLETE。已實際下載及親看iPad／大型iPhone各首張，都是11月15日前後舊UI；iPad仍呈舊左右背景差異，不能說是274最新視覺驗收。其餘13張本批未逐張檢視；舊圖應在最終送審前核內容及刷新，保留至有合格替代品。
- 2026-11-22T16:06Z再查本機實體裝置，只有第9代iPad available／paired，沒有13吋實機；僅讀清單，未啟動裝置服務、安裝或操作原資料。Apple現行13吋必填尺寸為2064×2752或2048×2732（及其橫向）；不能將第9代原圖放大當原生13吋圖。既有13吋舊圖不是缺檔，缺的是更新後內容；需可用13吋Simulator取得新版真畫面，或13吋裝置。沒有機械重跑先前失敗的Simulator批次。
- 先前Simulator素材Release build135.93秒PASS；截圖批303.12秒FAIL／暖啟106秒FAIL均保留；只刪自有兩個新建Shutdown空裝置，原container恢復。本批沒有重跑舊成功建置或冒充新實機結果。

新原生圖只含產品固定範例與自有未送19字草稿，無私人對話、帳密或工具資料；原唯一操作者已清草稿、回原A31，原資料保留依其收據。原1178寬WDA候選不符合列出尺寸，仍未上傳或修圖。

## 收據與接續條件

`T=/Users/woowtech/Documents/WOOWTECH-iOS-validation/documents-20261120/testflight-20261122`，本批私密收據在`T/public-app-store-20261122/`，目錄0700、檔案0600。沒有儲存Apple臨時上傳URL／header能力或審查憑證。

主要收據：`version-alignment-mutation-receipt.json`、`selected-build274-readback.json`、兩語系`public-metadata-*-mutation.json`、`native-library-upload-receipt.json`、`native-placement-receipt.json`、`native-placement-ordering-receipt.json`、`placement-preflight-readonly.json`、`original-rejection-messages-sanitized.json`、`review-service-descriptive-client-control-safe.json`、`authenticated-privacy-safe.json`、`current-age-rating.json`、`public-support-link-safe.json`及`ipad-13inch-asset-availability-safe.json`。

完成產品事實及可用審查服務後，補全九題回覆與操作路線、核實隱私／素材及關鍵未通過項，再依既有授權提交並讀回真狀態；核准後手動發佈並核公開頁。原A31高CPU、兩筆MCP錯誤、間歇15秒source逾時、Android同步及文件接收端等[商用缺口](ACCEPTANCE_GAPS_20261122.md)仍未關閉。文件草稿、Apple素材處理及單元／fixture PASS都不代表完整商用驗收。

## 官方依據

- [App Review準則](https://developer.apple.com/app-store/review/guidelines/)，特別是4.3／4.2.6及審查期間服務必須可用。
- [送審流程](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-app/)及[審查存取資訊](https://developer.apple.com/help/app-review/before-submitting-for-review/complete-review)。
- [上傳並處理素材](https://developer.apple.com/documentation/appstoreconnectapi/uploading-and-managing-image-assets)、[掛載與排序](https://developer.apple.com/documentation/appstoreconnectapi/placing-assets-on-your-app-store-surfaces)及[截圖規格](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications)。
- [App隱私定義](https://developer.apple.com/app-store/app-privacy-details/)及[Cloudflare1010的客戶端控制說明](https://developers.cloudflare.com/support/troubleshooting/http-status-codes/cloudflare-1xxx-errors/error-1010/)。

## 2026-11-23 更新（Claude 接手）

- **審查服務 402 的原因**：審查金鑰本身額度正常（US$1.37／10，12/1 重置）。402 是閘道背後的 OpenRouter 帳戶以「billing reason」拒絕，所有 openrouter 路線都一樣；toypark1234／chatgpt 的 ChatGPT Pro 路線週額度到 11/28–29。當下能用的是 woowtech/claude-sonnet-5-5、apporo-elmo/claude-sonnet-5-5、openrouter/free。
- **owner 同意實測和審查都改用 Claude**：渥屋助理（review detail fe38c284…）與 Apporo Assistant（ca88fb2d…）兩份審查備註的模型都由 openai/gpt-6-sol 改成 woowtech/claude-sonnet-5-5；改前用各自備註裡的金鑰實測串流與一般回覆都 HTTP 200，PATCH 200，讀回逐字一致，其他欄位不變。金鑰沒有寫進任何檔案或紀錄。
- **275**（44c1e7ab）07:52 上傳，內部群組可下載；**276**（533cd6d8＝eb1acf9e 的三個上架修正：照片只加入權限說明、英文裝置名稱 woowtech agent、PrivacyInfo 宣告 AI 回覆檢舉）09:11 VALID，**已取代 274 選進 0.1.0 版本**。
- **4.3／4.2.6 回覆已送出**（09:14，兩段，讀回逐字一致），全文與 owner 提供的事實見 [APP_REVIEW_43_REPLY_20261123.md](APP_REVIEW_43_REPLY_20261123.md)。依 Apple 原訊息「認為符合就不要重送、回覆 9 題」，沒有重新送審。
- iPad 13 吋舊截圖仍是舊 UI，尚未更換。
