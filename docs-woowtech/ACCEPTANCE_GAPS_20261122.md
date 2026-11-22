# iOS／Android 驗收缺口（2026-11-22）

**270 已在原 iPhone 經 TestFlight 更新並部分實測；完整商用驗收仍未完成。** 本表整合既有結果，不新增執行、重跑已過測試或把候選修補列為通過。原 iPhone A31 本次未重現持續高 CPU，仍未證明根因已修；回尾按鈕遮字則有實際失敗證據。

證據根目錄 R：`/Users/woowtech/Documents/WOOWTECH-iOS-validation/documents-20261120`；T：`R/testflight-20261122`。主要依據：

- **[Q]** [iPhone270半小時追蹤](IPHONE_270_QA24_FOLLOWUP.md)：實送2、正常0、未送22；CSV附件匯入／完整性／清理通過，4則訊息及鍵盤收放仍重現遮字。資料及觀測延遲界線獨立記錄，未替代原A31或真MCP驗收。
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
| 更新、資料保留與啟動 | **270限定通過**：TestFlight版本／簽章、更新前後vault bytes、照片與兩筆記憶保留；正常terminate／launch後既有瀏覽資料仍在 [F]。iPad269另有16個ID一致 [P] | 保留這些PASS；下一個含runtime修補的版本僅補原地更新、原對話／附件可讀與重啟。不能把更新瞬間bytes相同說成整輪測試後都相同 |
| 長歷史、原A31與效能 | **部分驗證／根因未知**：80則呈現分頁、1000輪存檔邊界有native與QA iPad證據。270原A31送出前16則，中文輸入／一次送出仍可操作；CPU 13.25%、22.19%、2.65%，未重現持續100% [F,P] | 原47／53秒尖峰未完整歸因。下一版保留同一原資料，記錄輸入→送出→終態→互動及CPU時間線；不要換成合成1000輪代替。原手機已有遠端分支可操作，舊「手機不在本Mac」不是所有驗證的永久硬體阻擋 |
| 回尾、回覆可見與鍵盤版面 | **已知產品失敗**：270 `chat.returnToLatest` 遮住最後錯誤文字；`45-270-original-after-send.jpg`及AX有證 [F]。269只移除>80則長頁的重複浮鈕，不能涵蓋A31短頁 | 已整合獨立Return列、鍵盤／composer跟隨與空白區拖曳修補；同runtime五個native案例分批通過 [U]。287 AX逾時未定位，288同案重驗通過不抹除失敗。仍須271實機短歷史／鍵盤／附件／錯誤終態，不以模擬器當商用完成 |
| 共用Done、主題與無障礙 | **部分驗證**：native273–275完整stderr Invalid-frame皆0；一般／XXXL及表單Done有測試，iPad269實際減少透明度switch=1與44pt Done有證 [P] | 外接／浮動／分離鍵盤受實際硬體與模式前置限制；新版正式實機最大字級／VoiceOver與全部附件組合未完。只補代表性未測組合，不重跑全部已過表單 |
| 記憶 | **270手動CRUD限定PASS**：新增→同ID修改內容／關鍵字→重啟查回→限定刪除→第二次重啟確認；原兩筆記憶與選回A31後18則顯示hash保留 [M]。iPhone249、iPad249與native7的歷史結果仍各屬原版本 [F,D] | 270手動持久化缺口已關閉；**270模型記憶工具／語意反轉仍未測**，真模型路徑待服務可用後驗證。表單Done PASS不替代CRUD，未確立舊CI間歇失敗根因 |
| 技能／學習 | **部分驗證**：iPad249做法核准後回想；iPad251真技能建立→重啟→精確中文別名搜尋／讀取、試用轉正式 [D]。249某輪AX逾時仍保留失敗 | 270未完成技能生命週期；用一份QA技能補修改／停用／刪除與語意改寫檢索，分別核工具步驟及結果。真模型限流／帳號未就緒時屬受阻，不能用普通短答證明技能被套用 |
| MCP與原Apporo錯誤 | **受阻＋部分驗證**：多伺服器／安全錯誤metadata、native表單／Keychain、loopback HTTP/RPC/toolError/timeout/cancel已驗 [P]。270原唯讀訂單請求在模型限流處結束，沒有MCP最終結果 [F] | 等原模型可用及既有唯讀服務授權，單次原查詢對齊request／server／結果來源；保留原兩筆tool_errors／unknown。iPad未配置MCP是帳號／服務前置，不是缺實作；未知寫入不可盲重送 |
| 預設選擇／認證／模型供應商 | **部分驗證**：已有主模型設定、API key與ChatGPT/xAI登入入口；iPad269沿用設定真回覆，270回覆限流錯誤 [F,P；來源見下] | 這些不證明全新安裝預設、重新認證、過期／取消／重啟或各供應商均可用。用隔離資料先驗未設定提示與預設選擇保存；現有授權帳號再驗一次登入／到期恢復與真請求。多供應商、工具／視覺及靜默逾時逐項留缺；不要捏造預設憑證或把限流直接歸為認證失敗 |
| 瀏覽搜尋／歷史 | **部分驗證＋時序未知**：iPad249/250既有設定／歷史重啟；native7 BrowserSearch案通過；270只重開既有歷史／引擎 [D,F] | 新增搜尋commit時序競態尚未重驗。補一個可識別QA查詢，等真導航commit後terminate／launch，核新增記錄與引擎；不得清空原歷史。舊Google子框架假錯誤修補不等於此競態已修 |
| 瀏覽器網站登入／跳轉 | **已有入口、商用流程未完**：網站資料保留與合成登入案例有歷史文件；這批270未做新登入／跳轉 [F,D] | 需指定已授權網站與帳號，由使用者完成必要驗證；最小檢查登入→同源／跨源回跳→重啟會話→明示登出。fixture cookie保存不能替代真網站驗收 |
| 瀏覽器下載／單筆歷史刪除 | **目前未提供，不是待測PASS**：270人工瀏覽明確拒絕下載；只有清空全部歷史UI，沒有單筆刪除入口 [D,F；來源見下] | 下載屬2026-11-14配合Play移除的能力，不依舊文件當成現存功能。若恢復成產品需求，先定下載授權／檔案交付／清理規格再實作；單筆歷史底層方法存在，缺的是UI。既有文件匯出成功不能填此格 |
| HTML／PDF基本文件 | **270限定通過**：一則短中文回答→產生→預覽→我的iPhone存檔→系統閱讀器重開；取消未誤報成功 [F]。iPad248/249另有100列5頁、末端標記及單一標題 [D] | 下一個未測情境選中文寬／長表多頁PDF，核頁數、末列／結尾、表頭及系統重開；不重跑同一短篇充數。270未有多頁證據，不能挪用舊iPad結果補齊 |
| CSV正向與接收端 | **270未測；其他環境部分通過**：iPad248真CSV保存與精確bytes、公式防護／前導零；Android API36真觸控CSV與POCO文件證據 [D,P] | 在iPhone選一張含中文／引號／換行／前導零／公式字串的表，保存並比對完整bytes。目標試算表開啟需實際接收App（舊iPad缺Numbers）；與系統預覽分開判定 |
| 文件分享、異常與生命週期 | **部分驗證**：iOS真取消不報成功；Android FileProvider與外部test-process讀取有儀器證據。iPad249曾拒收201MiB附件並恢復小檔操作 [D,P] | 外部接收者／接收App、外部文件提供者、低儲存及交付中檔案壽命仍缺。先選一個本機接收App檢查實際開啟，不把分享面板／activity completed當送達；涉及對外寄送另依明確授權 |
| 相機／相簿／附件 | **部分驗證**：270原照片仍可讀且hash保留；iPad舊版PDF／CSV真匯入與重啟；native合成PNG／TXT與附件第4輪有回歸 [F,D,P] | 原照片保留不證明新拍照／相簿選取。需真機實拍、限定相簿選取、取消／拒權→恢復→送出／預覽，先以一張自有QA影像完成；不宣稱fixture覆蓋相機硬體 |
| 未送出草稿重啟恢復 | **尚無持久化實作**：`ChatDraft`只存記憶體，iPad248/249終止後草稿不恢復 [D；來源見下] | 如納入本輪實作，先定保存範圍、敏感資料保護及清除時機，再做一案真terminate／launch；不要把已保存對話／附件保留混寫成草稿已保存 |
| Android同步與跨平台差異 | **部分實測／部分來源差異**：POCO真機文件及instrumentation已有結果；新配對視覺因另一操作者使用同App而未完成 [P] | 等取得單一操作者時段，只補新版同情境畫面／鍵盤／接收端。`c9fbb5d8` MCP缺iOS的category/code/outcomeUnknown契約是實作差異；先核現行Android來源是否仍缺，再決定移植。iOS分頁與Android LazyColumn不同，不據此推定誰更快 |

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
