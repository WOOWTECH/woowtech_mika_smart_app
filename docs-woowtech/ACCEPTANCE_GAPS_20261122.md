# iOS／Android 驗收缺口（2026-11-22）

**原iPhone已核實裝274受控Development簽章Release；官方273、274已上傳，19:12 TestFlight仍只見272。** 274首次啟動前及限定UI完成後45檔完整，原22前綴及安裝前24則、兩記憶／設定保留；單次字級還原、正常四行／淺深色／鍵盤及一頁PDF有真結果，保留15秒source逾時；後續最大字級首末／提示捲動可達另留[X]。原A31兩個獨立送出批次皆模型限流、正常回答0；後一批159筆連續CPU未見持續100%，不證原卡死根因已修。Android MCP修補已推送且精確單元／品牌編譯通過，實機／真服務仍待。270遮字、295串流等待及301拖曳失敗保留；完整商用驗收未完成。

證據根目錄 R：`/Users/woowtech/Documents/WOOWTECH-iOS-validation/documents-20261120`；T：`R/testflight-20261122`。主要依據：

- **[Q]** [iPhone270半小時追蹤](IPHONE_270_QA24_FOLLOWUP.md)：實送2、正常0、未送22；CSV附件匯入／完整性／清理通過，4則訊息及鍵盤收放仍重現遮字。資料及觀測延遲界線獨立記錄，未替代原A31或真MCP驗收。
- **[I]** [原iPhone271限定驗證](IPHONE_271_LIMITED_VALIDATION.md)：裝機、原資料、草稿／鍵盤、穩定回尾及短PDF／HTML有證據；保留AX失敗，沒有模型／MCP新請求或原送出CPU回歸。
- **[N]** [TestFlight272文件修補發佈](TESTFLIGHT_272_RELEASE.md)：來源`21a884b8`、native28940/40與Android2908/8、Apple VALID／IN_BETA_TESTING、原iPhone272／TestFlight簽章及更新保留各自留證；文件／原送出回歸另收結果。
- **[J]** [原iPhone272文件及A31送出](IPHONE_272_VALIDATION.md)：短HTML／PDF實檔、實際取消、限定清理；15:08／17:21各一次送出都模型限流、正常0，兩批17／159筆CPU分開保留，原18→20→22前綴完整，真MCP未取得。
- **[S]** [271服務探測與vault差額](IPHONE_271_SERVICE_PROBE.md)：獨立模型一次已接受／正常0／UI限流、QA限定清理；MCP當下目錄41工具不等於業務工具成功；21-byte差額只證外層編碼。
- **[B]** [瀏覽歷史測試保存邊界](BROWSER_HISTORY_PERSISTENCE_VALIDATION_20261122.md)：修正UITest過早終止前置，native297精確一案1/1；無產品保存／恢復程式修改，保留舊失敗缺證。
- **[K]** [PDF呈現鍵盤動畫發布修補](KEYBOARD_ANIMATION_PUBLISHING_FIX_20261122.md)：298夾界定位duration-only發布、299真publisher失敗→300三案通過；不在272內。274真機PDF／鍵盤UI另見[G]，警告管線無控制事件仍UNKNOWN。
- **[A]** [272外觀與字級還原](IPHONE_272_APPEARANCE_AND_FONT.md)：空draft還原後71秒樣本仍64pt，新增僅空白／未聚焦欄位重建。301一過一失敗、302暫時觀測兩案通過分開保留；含修補274真機單次循環另見[G]，不改寫272失敗。
- **[R]** [TestFlight273發佈](TESTFLIGHT_273_RELEASE.md)：來源`4e2c8c64`、真Validation／Upload成功、IPA／App／dSYM及完整archive gate留證；Apple處理／可安裝及273實機尚待，不以302替代。
- **[H]** [Android MCP執行修補](ANDROID_MCP_EXECUTION_CONTRACT_20261122.md)：初批62/62、三transport安全診斷92/92；對話步驟unknown／截斷consumer及語系40/40、兩品牌compile成功。含文件八語系38 keys補齊及PDF256頁文案修正；實機／真服務仍待，不將unit當商用驗收。
- **[E]** [241既存兩筆MCP錯誤取證](MCP_241_STORED_ERRORS_REVIEW_20261122.md)：找回4／4／2及8條dispatch；completed在isError檢查前記錄，缺精確結果locator／code，細分類仍未知，沒有重放工具。
- **[L]** [iOS分類後安全日誌修補](IOS_MCP_RESULT_DIAGNOSTIC_20261122.md)：native303精確22/22，實際Simulator日誌222事件／111組完整關聯；返回結果／工具錯誤／協定異常與拋錯分開。已隨274裝原iPhone，但真MCP分類尚待，不能回填241舊錯誤原因。
- **[T]** [TestFlight274發佈](TESTFLIGHT_274_RELEASE.md)：來源`611d6bfa`，archive／signed IPA／Apple Validation及Upload成功，actual archive全payload gate留證；與273及手機272分開，不將上傳算可下載／已驗收。
- **[C]** [272附件大檔／PDF恢復](IPHONE_272_ATTACHMENT_RECOVERY_20261122.md)：真201MiB拒收、小PDF匯入完整bytes、系統三頁Quick Look、取消／移除與限定清理；保留待送卡片預覽缺口及原生首頁徽章限制，不算App產生多頁PDF或CPU驗收。
- **[O]** [相簿取消逾時及版本對照](PHOTO_PICKER_CANCELLATION_20261122.md)：272故障窗各30筆CPU、stack TypeError／根因未知；native304另一環境1/1。274真機唯一Cancel／source約1.736秒正常、8有效CPU樣本／程序、stack0；準備檔名衝突保留，單次正常不回填舊FAIL或證明修復。
- **[G]** [274受控原地更新及限定UI](IPHONE_274_CONTROLLED_UPDATE_20261122.md)：唯一安裝callback錯誤後直接讀回274，無重送；UI前後45檔、全24／原前綴及記憶／設定保留。一次空draft字級還原、正常四行／淺深色／鍵盤、原圖與一頁PDF有限通過；保留15秒source逾時、最大字級內部捲動未測及日誌未知，非TestFlight通過。
- **[W]** [274新鮮模型單次探測](IPHONE_274_SERVICE_PROBE_20261122.md)：20:53實送1／正常0，UI限流、raw HTTP未知，故A31 send0且停止服務請求；12有效CPU樣本及原24／QA前綴保留。43檔相同／兩vault變更，Learning完整狀態未知，新QA回合保留，與[G]零模型階段分開。
- **[Y]** [274公開URL歷史保存](IPHONE_274_BROWSER_HISTORY_20261122.md)：真正WebKit內容完成後新history與舊一筆、引擎在一次正常重啟後保留；原A31全24一致。保留腳本誤假設自動回原對話的斷言及一筆QA history，不是自訂搜尋／登入／下載驗收。
- **[X]** [274最大字級首末捲動](IPHONE_274_ACCESSIBILITY_SCROLL_20261122.md)：7次editor短滑、2次獨立提示區手勢，首／末及提示末尾實圖可達、47字hash與109pt frame不變。還原後source15.0153秒逾時／自然恢復仍保留，沒有據初張裁切圖改產品。
- **[Z]** [Android雙品牌APK就緒](ANDROID_APK_READINESS_20261122.md)：來源`57b9972f`，一次SDK環境失敗保留後61.31秒assemble成功、source未變；兩包簽章／DEX來源核驗，無新儀器／實機操作。沿既有直接APK管道，Play的target36遷移分開，不當已上架。
- **[U]** [回尾／鍵盤修補驗證](CHAT_RETURN_CONTROL_VALIDATION_20261122.md)：同runtime五個native案例分批通過，保留287 AX逾時及288單案重驗；尚非271實機驗收。
- **[M]** [iPhone270手動記憶CRUD](IPHONE_270_MEMORY_CRUD.md)：新增／同ID修改、關鍵字重啟讀回、限定刪除及第二次重啟限定PASS；38檔獨立核對與原資料保留另有證據。模型記憶／技能語意仍未測，不增加24輪正常完成數。
- **[F]** [TestFlight 270 發佈與原 iPhone 實測](TESTFLIGHT_270_RELEASE.md)，尤其「原 iPhone 實裝與部分驗證」；機器摘要為 T/`iphone270-validation-summary.json`，觀察時間 `2026-11-22T02:13:49Z`。私密原始工具輸出留在 T，不複製進本文件。
- **[P]** [iPad 269 團隊回歸](IPAD_269_TEAM_VALIDATION.md)，含 native273–275、正式／QA iPad、Android 實機及保留失敗。
- **[D]** [文件產生實作與逐次驗證](DOCUMENT_GENERATION.md)，含 iPad248–251、iOS／Android 模擬器、文件生命週期與能力邊界。
- **[V]** [iPad 歷史視覺回歸](IPAD_VISUAL_VALIDATION.md)。舊段落的「未測」以後續精確版本結果補充，不整段升格為新版通過。

## 版本與執行環境不能互換

| 證據 | 實際範圍 | 不可推論 |
| --- | --- | --- |
| 原 iPhone **249** | [F] 保留該分支手動記憶新增／修改／重啟的歷史結果；本次摘要未附其完整來源 hash／逐案結果 | 不能移植成270 CRUD通過，也不能與同號 **iPad249** 混算 |
| 原 iPhone **270** | iPhone16,1／iOS26.5；0.1.0(270)、`TestFlight Beta Distribution`；來源鏈 `7026c468`。更新時原 conversation／learning bytes 相同、原照片保留；短篇 PDF／HTML實際產生、預覽、存檔、系統重開 [F] | 未完成CSV正向、多頁PDF、外部分享接收、MCP最終結果或A31穩定回歸 |
| 原 iPhone **271** | 同機同OS，來源交接`28deae96`；TestFlight原地更新、18則A31與兩筆記憶保留；中文／四行草稿、原圖預覽、穩定回尾與短PDF／HTML實際保存 [I] | 原AX不是全PASS；正常兩則不能代替兩／四則錯誤終態。沒有原送出、真模型／MCP完成或完整商用矩陣 |
| 原 iPhone **272** | 來源`21a884b8`、TestFlight簽章及更新保留；短HTML／PDF實存、兩批A31 send／CPU，另有201MiB附件拒收及三頁PDF系統預覽／匯入／取消／清理 [N,J,C] | A31皆模型限流、正常0，無MCP最終結果；15秒手勢逾時根因、新版字級、產生多頁PDF／CSV／接收端等仍缺。系統預覽不等於App待送卡片預覽 |
| 原 iPhone **274** | 來源`611d6bfa`、同Team **Development簽章Release**，非TestFlight；唯一安裝回應TypeError後直接讀回274，45檔UI前後一致，原22前綴及安裝前24則／兩記憶／選擇metadata保留；限定字級／正常四行／淺深色／鍵盤及一頁PDF [G] | 安裝前新增一對顯示符合舊限流回合，無intent／dispatch，來源仍未知；不能自動算成功。保留15秒source逾時；最大字級首末及提示捲達另見[X]，真MCP／原卡死仍未關閉；不能把此包說成TestFlight可下載 |
| 正式 iPad **248–251** | 第9代／iPadOS26.6.1；已設定真模型，文件、記憶、技能等依[D]各版本結果 | 不是iPhone249，也不是269／270重新驗完 |
| 正式 iPad **269** | `b81ff349`，runtime同`84e012a4`；真模型短答、16個原對話ID保留、主題／鍵盤／減少透明度；MCP未設定 [P] | 畫面能開啟不代表MCP成功；真模型短答不代表全供應商／技能／工具通過 |
| 隔離 QA iPad **269** | 獨立bundle／Keychain，DEBUG合成1000輪資料；可見回覆及27.7秒操作序列、有限窗CPU／footprint證據 [P] | 雖在實體iPad執行，資料與模型仍為fixture；不是原A31或正式商用流量 |
| iOS native／模擬器 | 本輪iPhone17／iOS27：273為7/7；274為13/14，失敗在MCP測試先Return再找Done；修正測試後275精確兩案2/2。UI模型為fixture；MCP另有真TCP/HTTP loopback及URLProtocol [P] | native不等於實機；loopback不等於Apporo；已有PASS仍未攔下270遮字 |
| Android API36模擬器 | PDF原生instrumentation修補回歸3/3；真正觸控CSV UI回歸1/1。另有JUnit／品牌編譯，皆分開記錄 [D] | instrumentation確實執行，但此列不是實體手機；編譯不算儀器測試 |
| Android POCO C85／Android15 | Play runtime `c9fbb5d8`：WOOWTECH 0.1.37-play.3(3)、Apporo 0.1.37-play.1(1)。真機instrumentation WOOWTECH先13/14、修browser fixture後單案1/1；Apporo14/14。六份文件大小／hash吻合 [P] | 不合併成同次全過；外部test-process讀合成分享檔，不等於商用接收者收到；不是iOS270結果 |

## 能力／缺口矩陣

「部分驗證」只承認下列流程；「未提供」有來源或明示規格依據；「受阻」寫出實際前置；其餘保持未知，不以缺少測試推定未實作。

| 能力 | 已有實作／證據 | 尚缺與最小下一步 |
| --- | --- | --- |
| 更新、資料保留與啟動 | **272／274限定通過**：272 TestFlight版本／簽章，更新前／首次啟動前／文件批後兩vault與原圖metadata一致；原18prefix及2memory顯示字典一致，原圖可讀 [N,J]；274 Development原地更新及限定UI前後45檔比對、全24／記憶／設定保留另見[G]。269／270歷史各留原版本 [F,P] | 原A31後續send會新增2則，整個conversation／Learning檔hash可變；不得把文件批相同移植至送出後全庫。原資料只依各批明確prefix／圖片／記憶範圍判定 |
| 長歷史、原A31與效能 | **部分驗證／根因未知**：80則分頁、1000輪邊界有native／QA iPad證據 [P]。272兩個原A31單次send皆模型限流；第二批159筆連續CPU最高58.4265%、最大間隔0.725691秒、0筆≥90%，Done可用；原18→20→22前綴保留 [J] | 原47／53秒尖峰未完整歸因；快速限流不覆蓋正常長串流／MCP。15秒native手勢逾時後UI／CPU可讀，後續被動trace未重現症狀且缺server時間線，不能斷言USB或App根因。不以合成1000輪代替原資料 |
| 回尾、回覆可見與鍵盤版面 | **270失敗保留／271限定改善**：獨立Return列及跟隨修補、五個native案例分批通過 [U]；271原A31與草稿／鍵盤／附件選定穩定截圖未見遮字 [I]。補充長按295失敗／加DEBUG觀測296通過，未改產品，兩筆分開保留 [U] | 保留287 AX逾時、295第二段串流等待逾時與271原始矩形斷言失敗；296不證295根因已修。Return出現區間非精確render延遲。仍缺獨立2／4則錯誤終態與逐幀過渡／全部裝置字級矩陣，不以穩定截圖當全面完成 |
| 共用Done、主題與無障礙 | **部分驗證**：native273–275完整stderr Invalid-frame皆0；一般／XXXL及表單Done有測試，iPad269實際減少透明度switch=1與44pt Done有證 [P] | 外接／浮動／分離鍵盤受實際硬體與模式前置限制；274首末文字／提示區已實際捲達[X]；VoiceOver與全部附件組合未完。只補代表性未測組合，不重跑全部已過表單 |
| 記憶 | **270手動CRUD限定PASS**：新增→同ID修改內容／關鍵字→重啟查回→限定刪除→第二次重啟確認；原兩筆記憶與選回A31後18則顯示hash保留 [M]。iPhone249、iPad249與native7的歷史結果仍各屬原版本 [F,D] | 270手動持久化缺口已關閉；**270模型記憶工具／語意反轉仍未測**，真模型路徑待服務可用後驗證。表單Done PASS不替代CRUD，未確立舊CI間歇失敗根因 |
| 技能／學習 | **部分驗證**：iPad249做法核准後回想；iPad251真技能建立→重啟→精確中文別名搜尋／讀取、試用轉正式 [D]。249某輪AX逾時仍保留失敗 | 270未完成技能生命週期；用一份QA技能補修改／停用／刪除與語意改寫檢索，分別核工具步驟及結果。真模型限流／帳號未就緒時屬受阻，不能用普通短答證明技能被套用 |
| MCP與原Apporo錯誤 | **受阻＋部分驗證**：多伺服器安全metadata、native與loopback已有結果 [P]；271目錄41工具 [S]。272兩批原A31各送一次皆模型限流，正常0／MCP counter null，空dispatch且無控制事件不證服務端零請求 [J]。舊241已找回4／4／2及8條事件，但completed不足以判工具成功 [E] | 原兩筆結果缺精確locator／安全code，細分類仍unknown；不可拿今日模型限流解釋。原訂單最終結果／來源待可用模型，未知寫入不可盲重送。新增安全診斷不能追溯補造舊結果 |
| 預設選擇／認證／模型供應商 | **部分驗證／目前單模型受阻**：272唯讀清單只有1個既有且selected項，未切換／探測；strict credential狀態unknown。固定「已連線」不當可用性，型別只由來源映射推論 [J]。既有ChatGPT/xAI入口及舊iPad真短答保留 [P] | 274於20:53單次探測仍UI限流[W]（raw HTTP未知），無既有替代供應商；真服務恢復需可用模型／已授權帳號。全新安裝預設、登入到期／恢復、多供應商／視覺／斷線逾時仍缺。全域picker有隱含probe及consent寫入，不盲切；不捏造憑證或把限流當認證失敗 |
| 瀏覽搜尋／歷史 | **部分驗證／測試前置已修**：舊受控WebKit對照證明pill匹配可早於保存；UITest現要求ready且無workspace error，native297精確案例1/1，重啟同namespace讀到1筆精確搜尋及引擎 [B]；舊iPad／native7結果各留原版本 [D,F] | 舊失敗最後AX至terminate缺逐callback時間線，不能完全歸因；297為本機WebKit合成頁，無產品保存程式修補；274另補公開URL真載入／一次重啟保存[Y]，未重跑自訂搜尋。真網站的新增查詢、登入／跳轉仍須正式裝置證據；commit本身不當保存界線 |
| 瀏覽器網站登入／跳轉 | **已有入口、商用流程未完**：網站資料保留與合成登入案例有歷史文件；這批270未做新登入／跳轉 [F,D] | 需指定已授權網站與帳號，由使用者完成必要驗證；最小檢查登入→同源／跨源回跳→重啟會話→明示登出。fixture cookie保存不能替代真網站驗收 |
| 瀏覽器下載／單筆歷史刪除 | **目前未提供，不是待測PASS**：270人工瀏覽明確拒絕下載；只有清空全部歷史UI，沒有單筆刪除入口 [D,F；來源見下] | 下載屬2026-11-14配合Play移除的能力，不依舊文件當成現存功能。若恢復成產品需求，先定下載授權／檔案交付／清理規格再實作；單筆歷史底層方法存在，缺的是UI。既有文件匯出成功不能填此格 |
| HTML／PDF基本文件 | **272短篇限定通過**：既有39字回覆→生成／預覽重開／系統保存，HTML1271、PDF18442 bytes與cache逐byte一致；PDFKit1頁完整來源、實際取消及4檔限定清理 [J]。舊iPad100列5頁留原版本 [D] | 下一個未測情境為中文寬／長表多頁PDF、系統閱讀器與實際接收端；不重跑短篇充數。不挪用舊iPad多頁結果補272 |
| 文件錯誤與預覽邊界 | **已實作／本機限定通過**：`21a884b8`來源錯誤／UTF-8／quota修補，native28940/40、Android2908/8與兩品牌編譯 [D,N]；272短篇文件／系統取消有真機證據 [J]。PDF Publishing本次定位並修duration-only發布，299紅→300三案綠，尚不在272 [K] | 272未驗無效來源／64KiB／生成中取消；274已有一頁PDF／關閉後鍵盤及Return實機[G]，警告管線無控制事件仍UNKNOWN。hosted preference、294 AX及295串流失敗仍各留；Android新修補instrumentation／真機、CSV接收端／ENOSPC仍缺 |
| CSV正向與接收端 | **270未測；其他環境部分通過**：iPad248真CSV保存與精確bytes、公式防護／前導零；Android API36真觸控CSV與POCO文件證據 [D,P] | 在iPhone選一張含中文／引號／換行／前導零／公式字串的表，保存並比對完整bytes。目標試算表開啟需實際接收App（舊iPad缺Numbers）；與系統預覽分開判定 |
| 文件分享、異常與生命週期 | **部分驗證**：iOS真取消不報成功；Android FileProvider與外部test-process讀取有儀器證據 [D,P]。272真201MiB附件拒收→小PDF完整匯入／picker取消／正式移除、精確清理已驗 [C] | 外部接收者／接收App、外部文件提供者、低儲存及交付中檔案壽命仍缺。附件拒收不是產檔quota／ENOSPC通過；不把分享面板／activity completed當送達，對外寄送另依明確授權 |
| 相機／相簿／附件 | **部分驗證／失敗可重現**：272 PDF匯入／copy／取消留證，待送預覽為共同缺口 [C]；相機UI／取消及恢復後Files取消有限通過。Photos逾時另受控重現15.0525秒，故障窗30CPU樣本／程序；無有效stack，根因未知；native304另一環境1/1 [O] | 274單次取消／source正常、stack0已留[O]；間歇故障若再現，再以已審stage／serializer觀測取當窗堆疊，不把CPU峰值或事後stack當根因。新拍照／自有asset選取、拒權→恢復未完，不以控制／fixture替代 |
| 未送出草稿重啟恢復 | **尚無持久化實作**：`ChatDraft`只存記憶體，iPad248/249終止後草稿不恢復 [D；來源見下] | 如納入本輪實作，先定保存範圍、敏感資料保護及清除時機，再做一案真terminate／launch；不要把已保存對話／附件保留混寫成草稿已保存 |
| Android同步與跨平台差異 | **部分實測／新來源已修**：POCO舊版文件及instrumentation留原版本 [P]；Android `cde78672`／`b9d3c9bb`／`d6513bd4`已補不盲重送、category/code/outcomeUnknown及步驟警告，62／92／40精確測試分開通過，兩品牌編譯成功 [H]。Android匯出來源可編輯，iOS仍是唯讀snapshot | 新修補兩品牌Debug APK已核來源／簽章[Z]，未裝Android真機；待單一操作者時段再補同情境視覺／鍵盤／接收端及真MCP，不以編譯替代。來源可編輯是產品差異，不為湊測試擅加iOS編輯器；iOS分頁與Android LazyColumn不同，不據此推定誰更快 |

## 已確認的實作邊界

- [ChatSession.swift](../ios/Sources/App/ChatSession.swift)：`ChatDraft.text`為記憶體狀態；[BrowserSession.swift](../ios/Sources/App/BrowserSession.swift)：`shouldPerformDownload`／不可顯示response拒絕及`noDownloadMessage`；[BrowserStartPageView.swift](../ios/Sources/App/BrowserStartPageView.swift)只有清空歷史入口，[BrowserWorkspace.swift](../ios/Sources/App/BrowserWorkspace.swift)已有`removeHistory`方法。以上將「未提供UI／持久化」與「缺測試」分開。
- [ModelProviderSettingsView.swift](../ios/Sources/App/ModelProviderSettingsView.swift)及[帳號／多MCP計畫](../ios/docs/ACCOUNT_SIGNIN_MULTI_MCP_PLAN.md)可用來定位設定與登入路徑；計畫的Phase／Done means不是實際通過證據。[連線檢查邊界](../ios/docs/MODEL_CONNECTION_CHECK.md)亦明示單一文字測試不保證串流、工具、視覺或供應商全支援。
- [Memory／Skills文件](../ios/docs/MEMORY_SKILLS_PARITY.md#ios-only-screens-removed--2026-11-14)保留2026-11-14移除頁面／瀏覽下載的決策；前面的歷史實作與[11/12瀏覽器稽核](../ios/docs/ANDROID_BROWSER_PARITY_AUDIT.md)不能倒推270仍有下載。任意自然語言產檔代理、Word／Excel、雲端產檔、自動外送仍在[D]首版範圍外，不假裝已實作或自動擴增本輪任務。

## 接續順序與關閉條件

1. **先關實際遮字缺陷**：Parent修產品／串流測試、Mendel加嚴可見性回歸；本文件不碰其檔案。只在新build的精確native案例及原iPhone相同短歷史畫面過關後更新該列，270本身的失敗不改寫。
2. **補不依賴新帳號的缺口**：iPhone CSV正向／多頁PDF、一次新增搜尋重啟、相機／相簿、未測鍵盤模式；先利用已保存回答／自有QA資料。實際執行由Parent序列安排，此表不是新的全套測試指令。
3. **有前置才驗真服務**：模型限流解除後做原A31唯讀MCP完整終態，再補有授權的供應商／網站登入；無有效服務／帳號或外接硬體就明記blocked，不用mock補成商用通過。技能真模型檢索與外部接收端亦各自留證。
4. **實作缺口另列變更**：持久草稿、單筆歷史入口、已移除下載、Android錯誤契約先確認範圍；不得因舊測試或舊能力表存在就聲稱已完成。每次關閉缺口須附來源commit、安裝build／裝置OS、真／合成服務、具體步驟與產物／畫面；保留失敗及未測邊界。

本表整合各證據文件的實際執行結果；獨立核對不重複計為新實機操作，任何單項PASS均不表示270或後續版本商用全數通過。
