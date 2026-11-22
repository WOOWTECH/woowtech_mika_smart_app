# TestFlight274：Apple已處理，實機安裝管道分開記錄

**0.1.0(274)已通過Apple Validation並成功上傳；最新登入後官方讀取為VALID／IN_BETA_TESTING，外部狀態READY_FOR_BETA_SUBMISSION。** 原iPhone已安裝相同Release binary的Apple Development重簽版274，詳見[受控安裝及資料保留](IPHONE_274_CONTROLLED_UPDATE_20261122.md)；這不是從TestFlight下載的證據。此為新來源的診斷修補，沒有重傳273或274；[273原發佈紀錄](TESTFLIGHT_273_RELEASE.md)獨立保留。公開送審已獲授權、完成版本及建置選取，但尚未提交，詳見[公開上架狀態](PUBLIC_APP_STORE_SUBMISSION_20261122.md)。

## 最新上傳狀態核對

使用者指定的iPhone回合`codex_01a20379-8d30-7260-b7a4-062e5500aa1d`已經HTTP200讀取：該回合是274受控字級還原測試，沒有新增runtime修補或上傳。核對本工作樹至`c43182e6`，相較上傳來源`611d6bfa`的`ios/Sources`沒有差異；iOS目錄僅增加附件UI測試，最新實作已包含在274。

實際archive的Distributions仍為`uploadedBuildNumber=274`、`uploadEvent.state=success`、`2026-11-22T10:45:43Z`（臺北18:45:43）。原登入前收據在`T/resume-20261122/latest-release-check-20261122/release-check-safe.json`，保留其當時未登入限制。

使用者完成登入後，2026-11-22T15:37Z起的官方讀取確認build `7035b2a6-8482-45d5-a058-8b235183d7b0`為274、pre-release0.1.0、processing VALID、internal IN_BETA_TESTING、external READY_FOR_BETA_SUBMISSION。已將原遭拒版本1.0.0改為0.1.0並選取274；關聯PATCH204及GET200讀回同一build ID。商店版本為PREPARE_FOR_SUBMISSION／MANUAL，尚未提交或公開。新收據在`T/public-app-store-20261122/`。沒有新archive或重傳；這個管理端狀態不證原iPhone已從TestFlight下載。下方交接／19:12清單是歷史紀錄，後續274實機結果以[缺口矩陣](ACCEPTANCE_GAPS_20261122.md)為準。

## 來源與產物

| 項目 | 實際結果 |
| --- | --- |
| App／Team | `io.woowtech.assistant`／`W4UWZ8NP2P`，ASC App `6834435121` |
| 版本／來源 | `0.1.0(274)`；`611d6bfa75ec46d39fd9654ac97ff2de6291a1a0`，clean tree建置 |
| 相較273的iOS runtime | 僅`MCPConversationRunner.swift`：分類後記錄returned／failed、安全code／unknown／monotonic耗時；仍包含273鍵盤發布及空欄字級修補 |
| 簽章IPA | 8,156,199 bytes；SHA256 `d72102f5d992bc2458aaff7c15ff0e8cdae8061eeee79d0dad15a6111b79dcf0` |
| App／archive／dSYM UUID | `7CE1BB7D-7066-3E04-B2F8-8280E33F5B05`，三者一致 |
| Release gate | iphoneos、minimum17.0、非DEBUG、10個Mach-O簽章／profile／entitlements／privacy等既有gate通過；未新增SDK或權限 |

工具鏈為本機Xcode27／SDK27；本輪亦重新核對[Apple上傳SDK要求](https://developer.apple.com/news/upcoming-requirements/)及[Xcode支援表](https://developer.apple.com/xcode/system-requirements)，沒有自行升級工具鏈或改deployment target。

`R=/Users/woowtech/Documents/WOOWTECH-iOS-validation/documents-20261120`；`T=R/testflight-20261122`。本包只在`T/release-274/`，不混用兩份273 archive。

## 已執行與來源鏈

| 階段 | 結果 |
| --- | --- |
| 精確MCP native303 | [22/22、零failure／skip](IOS_MCP_RESULT_DIAGNOSTIC_20261122.md)，77.53秒；實際Simulator log222事件／111組完整關聯。這是fixture／真loopback，非商用MCP |
| archive／signed export | `R/release-274-archive.json`，exit0、109.74秒、source_changed=false |
| Validation | `R/release-274-validation.json`及`T/validation-274/receipt.json`，exit0、89.17秒、source_changed=false；實際archive的validationEvent在**10:43:05Z**為success／Validation succeeded |
| Upload | `R/release-274-upload.json`及`T/upload-274/receipt.json`，exit0、110.54秒、source_changed=false；實際archive task=distribute、uploadedBuild274、uploadEvent在**10:45:43Z**為success／Uploaded to Apple |

均沿原heavy.sh序列化、容量floor0，原授權兩個containers恢復。每輪command、before／after及helper hash保留，不重跑正常CI。團隊另獨立核native303的22個唯一case與完整OS log，`T/ios-mcp-result-diagnostic-followup/REVIEW.md`沒有指出此有限修補的阻斷問題，不將此審查擴大成整體Release驗收。

Validation及Upload均核對**實際傳入archive**全部164項manifest、codesign、來源與UUID，而非只核未傳入的IPA。pre-validation payload SHA256 `e7bb52d55c319933a1417d00a8ded90a54fbc180e6ed5cbe37e496e63a5b2a37`；post-validation `444521ac9782273bcd2dc1b24fbd2b10b7d7b8a0d8283ed0c8f3064a97d8ef84`；post-upload `d4336a70f7184c7c5ca9c2c6e9729e644d505906fb02b8867d81ea63820790c4`。每次只改root Info.plist的Distributions，其他163項相同；回復該key可逐byte重建pre-validation root，App／dSYM payload未變。

注意Xcode Upload會改寫Distributions紀錄，最終archive只留本次distribute。Validation success是在Upload前實際讀取並assert；安全觀察收據`validation-event-observed-before-upload.json`明示由該次工具輸出轉錄，**不是另存的原始post-validation plist**。原始Validation operation log、exit回執、post-validation manifest及seal收據均保留；Upload事件另有從最終archive擷取的`apple-distribution-events-safe.json`。

## 手機交接與未測

已把274的來源／SHA／UUID交原唯一iPhone操作者，HTTP202收據在`T/resume-20261122/release274-phone-handoff-receipt.private.json`。先完成272附件及相機／相簿取消批次；只有完成時距Upload已至少15分鐘，才正常查一次新版本，不為此輪詢或睡等。可見才依原授權原地更新，先核A31全22前綴／原圖片／記憶／保護檔，再驗字級還原、非空草稿、鍵盤／Return／原縮圖及PDF。

上述是最初交接指令，不以272或native303回填274實機。後續Development簽章274的限定結果已有獨立文件；原A31高CPU根因、真Apporo最終結果與241兩錯誤、App模型限流、Android實機對照、正向CSV／長表PDF／接收App及其他商用條件仍依[缺口矩陣](ACCEPTANCE_GAPS_20261122.md)。登入阻礙已解除，Apple處理狀態已確認；19:12未見版本的當時成因仍無法倒推。

## 原iPhone19:07／19:12可見性補充

19:07恢復既有TestFlight清單只見272／271／270，資料新鮮度未知；這批原封存在`T/resume-20261122/testflight274-20261122/`，沒有回寫成正常重進結果。19:12另完成此前未做的導航：正常返回版本群組→點0.1.0一次，**19:12:04.786147+08仍只見272／271／270，未見274或273**。沒有下拉刷新／循環查詢或安裝，Apple後端處理／群組原因仍unknown。

Parent親看`T/resume-20261122/testflight274-20261122-normal-entry/07-normal-entry-list.png`，核17項選定manifest bytes／SHA、正常返回／進入原生request及前後22則／三原檔metadata／UserProfile字典一致。回App仍0.1.0(272)／TestFlight簽章、A31空draft，memory直接UI核對沿前camera批、Learning bytes／SHA未變；沒有把本次當重新CRUD。首次以name找返回控制失敗由guard攔下，之後以實際label及frame完成一次返回；沒有socket timeout。

本輪report／result／manifest SHA256依序 `a26a253a250ec76f7d674323446ae457a7fe137cf0855b73404f27d2294575d0`、`9fbac55c57f38374e0a6caab950e822acb61d23ef0d72313a4d1fe13dc248099`、`6c2197f1624907e13bb6bc0d813893806901f5e19dc8dce058f68299c2fdbe1d`。該19:12批次未安裝274；後續Development簽章274字級／鍵盤／PDF結果另記，真MCP仍未完成。沒有為此再上傳或建置同一包。
