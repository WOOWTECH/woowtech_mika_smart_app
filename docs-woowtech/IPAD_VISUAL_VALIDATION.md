# iPad 版面與視覺回歸，2026-11-21

本輪回應 iPad 左右異色邊帶與整體視覺協調問題。實機為 USB iPad 第 9 代（iPad12,1），iPadOS 26.6.1。安裝採覆蓋升級，沒有卸載或重置使用者資料。

目前實機為 **267**，runtime 來源 `edf61387513e7d0520bc188ccd069c24fbbd84f8`。已修正全幅背景、共用欄寬、玻璃輸入框與短畫面提示、主題切換對比、受控對話的排版卡死與完成回覆裁切、附件容量錯誤文案，以及操作路線的重複箭頭。下面分別保留每個版本的真機、模擬器、失敗及未測證據；不宣稱整體商用驗收完成。

原始證據根目錄（下稱 E）：`/Users/woowtech/Documents/WOOWTECH-iOS-validation/documents-20261120`。各 `ipad-*` 資料夾保留操作步驟、XCTest completion receipt、截圖與原始日誌。操作 receipt 通過仍須核對畫面，不代表商用驗收。

## 實際缺陷與修正

1. 對話先限制為 720 pt，再向外展開；背景留在內層，露出 NavigationStack 的黑／白底，形成左右邊帶。新增 `MikaPageLayout`，可讀內容置中、背景鋪滿容器與安全區。實機像素對照：修前深色邊緣 `(0,0,0)`、內部 `(14,14,16)`；修後直橫向取樣一致為 `(14,14,16)`。淺色修前外側白色、內側 `(247,247,248)`。
2. 記憶、工具、設定、外觀、通知、關於、模型設定、網站登入／操作路線等頁面統一可讀欄寬與全幅背景。瀏覽器首頁採可讀欄寬；實際載入的網頁仍為全寬，已用 Example Domain 實機確認。
3. 輸入框保留玻璃材質、淡色覆層與陰影，將隨高度變圓的 Capsule 改為固定 32 pt 圓角，讓多行文字保有空間。系統「減少透明度」仍使用實色背景。
4. 淺色開鍵盤旋轉後，導覽標題／狀態列曾變白；明確指定 toolbar color scheme。另發現回覆完成後再切換外觀，導覽圖示沿用白色；257 對選單、返回、新對話圖示明確指定主題顏色，保留送出中的停用色。
5. 極短 transcript 會裁掉半顆「回到最新訊息」按鈕；空間不足時隱藏整顆按鈕，收鍵盤後恢復。最大輔助字級的橫向鍵盤畫面改為一行可捲動草稿，長提示可在有界區域捲動；內容短時縮回自然高度，不留大塊空白。這些尺寸直接由版面計算，不以 geometry 回寫 state。

6. 真機 257 在同一段有表格、PDF／CSV 的八則歷史對話，只輸入中文、尚未送出就進入主執行緒忙迴圈。258 僅將較早訊息的 `LazyVStack` 改為 `VStack`；保留同一原始對話與實際附件後，輸入、送出與後續選單操作均可完成。259 保留同一執行邏輯，補註解及六則跨到八則的原生回歸（只建置／測試模擬器，未安裝真機），不改存檔或分支附件規則。沒有證據可把此現象直接等同原 iPhone A31 故障。最終版本將所有訊息合成單一 eager ForEach，維持訊息身分與完整歷史。

7. 窄畫面原生回歸另外發現，鍵盤轉場的動畫傳入 transcript，使同一內容高度下的 offset 位移被判成讀者捲動，完成回覆落在可見區之外。訊息區隔離繼承的動畫後，原嚴格可見範圍與串流返回測試通過；先前無效的計時補丁已移除。
8. 小附件因剩餘空間不足拒收時，原本誤顯示單檔 200 MB 超限。266 保留容量／大小／其他原因並分組顯示，未放寬既有容量與檔案限制。

修改檔案以 `ios/Sources/App/ContentView.swift`、`MikaPageLayout.swift` 為主，另包括 `BrowserStartPageView.swift`、`BrowserView.swift`、`MemoryDataView.swift`、`MCPToolsView.swift`、`MikaAlignedSettingsView.swift`、`MikaLanguageAppearanceView.swift`、`MikaAboutView.swift`、`ModelProviderSettingsView.swift`、`SavedDataViews.swift`、`TaskNotificationSettingsView.swift`。沒有新增依賴。Android 對照依據為 `app/src/main/java/com/wangzan101/mika/ui/components/Surfaces.kt` 的 `GlassBar`（模糊、半透明覆層、0.5 dp 描邊、14 dp 陰影、最低 52 dp），以及 `ChatScreen.kt` 的輸入列。iOS 沿用原生 material 與平台降透明度設定；不是 Android 實機逐像素驗收。

## 版本與建置來源

| 版本／測試標籤 | Runtime commit | 變更 |
| --- | --- | --- |
| 252 | `bfcf469ebcf1faa4d225da53cc7af42e8a95550e` | 全幅背景、共用欄寬、輸入框圓角 |
| 253 | `67cd1732e3aa689441254110a655741da3ff4c06` | 旋轉後導覽列對比 |
| 254 | `5d10d6e1a032f9b34712db5b30fac60e581ca024` | 短畫面的回到最新控制項 |
| 255 | `e6225098` | 最大字級短畫面與提示捲動 |
| 256 | `591694a3ae3dd5d72deb74aaf6bd1ec2cc256816` | 提示區依內容縮回高度 |
| 257 | `04872ec73fe4d543db03d8292127213bc3144854` | 外觀切換後導覽圖示對比；實測發現輸入／送出卡死 |
| 258 | `d0f010c7` | 同資料單變量排版對照；輸入與真模型送出可操作 |
| 259（僅 native） | `7dbf6f19` | 完成回覆可見範圍 FAIL；串流返回 PASS；沒有真機安裝 |
| 265（僅 native） | `6d3a9add` | 精簡後回覆可見範圍與串流返回 2/2 PASS |
| 266（實機） | `57478bf33072fdf579a82ae930888483935cc018` | 整合排版修補與附件拒收原因；原生附件測試 4/4 PASS |
| 267（實機） | `edf61387513e7d0520bc188ccd069c24fbbd84f8` | 移除記憶頁操作路線列的重複箭頭 |

252–258、266–267 的實機安裝包為 MacBook 本機 Release/arm64 建置；259–265 為 Debug 原生模擬器回歸標籤，未安裝到實機。均非 GitHub／TestFlight 安裝包。包內 `source-commit.txt`、`document-build.json`、IPA 與 binary SHA-256、UUID、9 個 framework 的簽章驗證及安裝後版本回讀，保存於 `device-N-artifact.json`、`ipad-N-install.json`、`ipad-N-installed-version.json`。所有重型建置／模擬器測試使用既有 `heavy.sh` 序列執行，來源前後未改變；兩個已授權暫停的 review 容器均已恢復。

257 的編譯、簽章與 ZIP 建立成功，原包裝腳本因版本字串替換意外將 `sha256` 改成不存在的 `sha257`，在產出摘要 metadata 時 exit 1。已修正腳本；`device-257-finalize` exit 0，從既有簽章 App／ZIP 核對相同 binary 與包內來源並產生摘要，未重建。原失敗紀錄保留，不將它寫成整段 build wrapper 首次成功。

## 已執行驗證

| 範圍 | 實際結果與證據 |
| --- | --- |
| 邊帶與頁面 | 251 修前與 252 修後的深淺色、直橫向對照；`ipad-252-00-before`、`01-before-pages`、`03-before-light-keyboard`、`05-after-dark`、`06-after-dark-pages`、`07-browser-layout`；像素證據 `ipad-252-canvas-pixel-samples.json` |
| 導覽標題旋轉 | 252 相同鍵盤旋轉條件重現白字；253 相同條件恢復深色文字，`ipad-253-01-rotation-contrast`、`ipad-253-navigation-contrast.json` |
| 正常字級輸入／附件 | 256 深淺色、直橫向、六行草稿（顯示五行後內捲）、有效 CSV 附件加 201 MiB 檔案拒收提示、鍵盤收放；`ipad-256-09-normal-attachments`、`10-dark-and-return`。錯誤、附件與按鈕未互相覆蓋；極短 transcript 的控制項完整隱藏 |
| 最大字級 | 系統 Larger Dynamic Type 開、slider 100%、減少透明度開；256 直橫向及鍵盤開關，短畫面單行草稿；長提示可捲至「200 MB」限制，收鍵盤後可關閉；`ipad-256-01-largest` 至 `05-dismiss-large-notice`。100% 設定原證據 `ipad-253-12-max-confirm` |
| 真實模型回覆 | 252 實際回覆與表格、損壞 PDF 的明確錯誤回覆；256 以已設定模型完成三段中文與完成標記，沒有 fixture。`ipad-256-real-reply-verification.json` 與 `ipad-256-11-result-check` 核到實際最終內容。提示中的「完成」字樣是測試內容，並非模型替驗收背書 |
| 主要頁面淺色 | 256 記憶、工具、設定、外觀、瀏覽器首頁的完整可見畫面，`ipad-256-12-light-pages`。設定截圖含服務主機標籤，留在本機證據，不公開嵌入報告 |
| 252 原生模擬器 | `testComposerGrowsThenScrollsAtFiveLinesAndAttachPanelKeepsDraft` 1/1、0 fail、0 skip；`native-252-composer` |
| 255 原生模擬器 | 上述草稿案例及 `ChatStreamingUITests.testReturningToBottomByDragOrButtonResumesLaterFragments` 2/2、0 fail、0 skip，405.19 秒；`native-255-viewport` |
| 256 原生模擬器 | 高度收尾後草稿案例 1/1、0 fail、0 skip，149.87 秒；`native-256-composer`。模擬器為 iPhone17/iOS27，模型為 fixture；不能當實機供應商驗收 |

258 完成深→淺主題切換、直橫向鍵盤，以及記憶／工具頁面返回，圖示使用正確的主題色。證據為 `ipad-258-04-theme-keyboard`、`06-light-keyboard`、`08-visible-pages`，包含實機截圖與操作 completion。

252、255、256 及 259 原生結果另有 `Invalid frame dimension (negative or non-finite).` 警告，未因 case PASS 宣稱所有版面診斷乾淨；警告來源尚待精確定位。

## 卡死對照與結果界線

同一測試對話 `42EE97D9-F84B-47DA-9825-421378394783` 保留原始表格、實際 PDF／CSV 附件與完整歷史，沒有利用分支複製省略附件。257 送出後取得三份連續 stackshot；主執行緒 user time 持續增加，CPU 98.68–100.88%。重新開啟可看到已保存的模型回覆，故不能說模型沒有完成。再只輸入同一句中文而不送出，同樣卡死，CPU 98.47–100.84%。

258 唯一 runtime 差異是歷史容器由 LazyVStack 改為 VStack。相同八則內容、同附件與同一句未送出的文字，19.3 秒完成完整操作；五秒取樣 11 筆 CPU 0–0.092%。同條件比較僅指八則起點的「未送出輸入」段：257 的送出為六→八則，258 的後續送出為八→十則，兩者不是同一歷史長度的送出對照。接著送出簡單指定回覆，實際看到 `IPAD258完成`，20.6 秒完成送出、收鍵盤、選單開關，後續五秒 11 筆 CPU 0–0.029%。這是取樣區間，並非整段請求的連續 CPU 上限。

證據：`ipad-257-send-freeze.json`、`ipad-257-input-stack.json`、`ipad-258-controlled-input.json`、`ipad-258-freeze-regression.json`、`ipad-258-02-send-control/attachments/send-result.png`。系統符號不足，未將未知堆疊位址臆測為具名 framework 函式；實驗支持排版容器為本重現的觸發條件，尚不能證明附件是必要條件。

259 新增測試使用合成 PNG／TXT 與固定模型回覆，目的為驗證第六則跨至第八則時的鍵盤、附件面板、記憶提示、完成回覆與互動。不能把該測試說成原始真機 PDF／CSV 或外部模型的商用驗收。

## 自動化未通過紀錄與界線

- `ipad-258-07-toolbar-pages` 在最後一步嘗試按已不存在的「回到最新」失敗；頁面已回到尾端。且立即截圖曾只更新導覽標題、內文仍在轉場，未將這些畫面列為頁面驗收。`ipad-258-08-visible-pages` 等待該頁實際 status 元素與轉場後重取記憶／工具畫面，22.5 秒完整 PASS。
- `ipad-252-14-clear-pending` 嘗試移除已送出、已歸檔的附件，無 pending remove 按鈕；未刪原資料。
- `ipad-253-02-refresh-file-location` 使用錯誤的系統位置標籤；`ipad-253-05-accessibility` 查詢不可見的設定側欄；已依實際畫面導航，沒有歸因為裝置授權失效。
- `ipad-253-07-reduced-large` 的操作完成不代表設定成功；後續 AX 明確核對粗體關、減少透明度開、字級 100%，才列入對照。
- `ipad-255-03-large-notice` 尚未真正選到最大字級下畫面外的檔案，後續草稿查詢失敗。先捲動檔案選擇器再選取才成功。
- `ipad-255-06-notice-scroll` 在 AX hierarchy 擷取期間未取得 testcase completion，161.3 秒後逾時，不列 PASS。後續 8.6 秒操作可關提示、收鍵盤；五秒恢復階段 CPU 樣本有回到 0%，但不能推論先前逾時根因。256 相同提示捲動／關閉短步驟有完整 completion，沒有宣稱原 A31 卡死已修。

歷史容器改為直接排版後，尚未驗證存檔上限 1,000 輪對話的效能與記憶體；本輪不新增分頁，也不截斷既有歷史。

本輪沒有在 Android 實機重新驗視覺，也沒有證明所有 iPad 多工視窗／外接螢幕尺寸。原 iPhone A31 既有對話高 CPU、MCP unknown／工具錯誤、多供應商、登入跳轉與跨 App 接收端等商用項目仍未結案；這份紀錄僅界定 iPad 視覺修補與實際覆蓋範圍。

## 新原生失敗的精確證據

`native-259-transcript` 來源 `7dbf6f19`、503.99 秒 exit 1、source unchanged；build 成功。附件／表格／記憶提示第四輪回覆測試在 line 134 未過：reply index 7 的 AX frame `(12, 399.333, 221.667, 43)`，transcript `(12, 195, 378, 209)`，回覆僅約 4.7 pt 落在可見區域。不是模型失敗或主執行緒卡死，也沒有放寬可見範圍斷言。`ChatStreamingUITests.testReturningToBottomByDragOrButtonResumesLaterFragments` 同輪 PASS，189.694 秒。

原始 app AX log 擷取保存於 `native-259-failure-frame-extract.json`，摘要 `native-259-transcript-summary.json`；xcresult 未提供該失敗的截圖附件，沒有宣稱看過不存在的截圖。後續將訊息合成單一 eager ForEach，避免新增訊息時跨容器搬移，再以相同完整步驟驗證。

260 (`5a7dc2e2`) 把訊息合成單一 eager ForEach，**相同步驟仍未通過**：reply `(12,390.667,221.667,43)`、viewport bottom `404`，截圖可見文字被裁掉且「回到最新」按鈕出現。因此跨容器搬移不是本裁切的充分解釋，尚不能宣稱 flatten 修正裁切。`native-260-boundary` 245.54 秒 exit 1、source unchanged；失敗截圖保存於 `native-260-boundary-attachments/E123458B-E7ED-4E8B-B0D3-F5255C22F0BB.png`。

261 (`a3ff0c72`) 保留相同操作，只加入 DEBUG 數值診斷。捕捉到第四輪 revision 8、contentHeight 1164、viewport 191 保持不變時，底端從 195 移到 222；沒有使用者往上滑，`followsTail` 卻從 true 轉 false。前面同一 revision 已經過多次鍵盤高度變化並消耗有限跟隨額度。證據 `native-261-safe-geometry.json` 與 `native-261-geometry-trace.log`；此輪仍 FAIL，261.46 秒、source unchanged。

262 (`7515d4fe`) 由鍵盤／附件面板事件明確開始轉場保護，轉場期間不將系統自動 offset 變化當讀者捲動；在鍵盤動畫時間後加 0.1 秒安定期，只給一次有限跟隨機會。不是從 geometry 回報反覆重設額度。既有閱讀暫停與真正 drag/settle 仍優先，新對話取消舊計時器。`scroll-262-policy` 三項 portable 測試 PASS（含 mutation 檢查），6.40 秒；這不取代原生與真機驗收。

262 原生結果：build 成功，第四輪可見範圍仍 FAIL（169.104秒）；串流返回 PASS（189.122秒）。整輪439.82秒 exit1、source unchanged。純邏輯PASS不等於此修補有效，轉場計時仍不足以避免後續版面位移；這個失敗不能省略。

263（43343c3c）取消訊息區繼承鍵盤的動畫。native-263-animation 在 configure 的 consent.agree 未消失而 FAIL，沒有進入第四輪重現，故不能作排版成敗證據。226.63秒、source unchanged。264（6ff53952）僅加入 DEBUG 隔離 namespace 的合成模型與同意預設，讓此版面案例不再重跑無關模型設定；正式 Release 不包含此 API，原版面斷言完全保留。

264 首輪在真實附件匯入路徑拒收兩個小型 fixture 檔案，尚未到第四輪。最小可用空間428,019,712 bytes，低於附件存放500MiB保留值；目前訊息錯誤混用「單檔不超過200MB」。先清理本案舊DeviceDerivedData-248、SwiftBuild及已關閉的專用模擬器Caches，共873,144,320 bytes，保留來源／IPA／xcresult／日誌與實機資料，再以同head重驗。沒有改容量門檻或略過附件斷言。

264 清理後同head native-264-space-recovery：1/1 PASS、0 fail／skip，案例150.864秒，wrapper220.84秒，最小free2,836,455,424 bytes，source unchanged。原嚴格可見斷言及回覆後再次輸入、兩次面板切換均保留。265（6d3a9add）移除無效轉場計時實驗，保留eager單一訊息集合與訊息區不繼承鍵盤動畫，重新核對兩項原生案例，結果另記。

265 精簡版 native-265-minimal：2/2 PASS、0 fail／skip，wrapper357.47秒、source unchanged；第四輪100.899秒。串流閱讀／回到底部恢復後續片段案例亦PASS。仍有兩則未定位的 Invalid frame dimension warning，不能宣稱 runtime warnings 清零。

266（57478bf3）將附件失敗保留大小、容量、其他原因；容量預留500MiB、單檔200MiB與混合批次接收順序不變。修正正確原因顯示與繁中／英文資源，新增四項原生hosted檔案IO／容量邊界／混合原因／清理測試。容量由注入值模擬，不把測試寫成已在iPad實際塞滿儲存空間。產生資源1055keys／2languages parity PASS。

266 原生 hosted 結果：4/4 PASS、0 fail／skip，wrapper120.53秒，source unchanged，最小free942,415,872 bytes。摘要 `native-266-attachment-errors-summary.json`，原始 `Documents-266-attachment-errors.xcresult`。本輪 hosted summary 無 runtime warning，但啟動 console 另記錄 ChatTranscriptViewportPreferenceKey 同一frame多次更新；未將此事隱藏或推論為已修。

## 266 整合安裝與實機回歸

本機 Release 266 來源 `57478bf33072fdf579a82ae930888483935cc018`，67.8 秒建置成功、來源前後一致；簽章與九個 framework 驗證通過。IPA SHA-256 `573eeefc51db255c83363225967480d22af50e30732d0476283b8cf40bb105da`；binary SHA-256 `3fab12c431391354336d5b1b63721ee626d7ec78bd9046b0557f0801a40da730`。安裝相同 staged App 後回讀 bundle version 為 266，沒有宣稱從手機讀回完整 binary hash。`device-266-artifact.json` 是建置時靜態紀錄；安裝證據另見 `ipad-266-install.json` 及 `ipad-266-installed-version.json`。

`ipad-266-01-same-archive` 19.6 秒 PASS：相同 42EE 存檔、十則起始歷史，實際 PDF/CSV 名稱保留，輸入同一句中文。`ipad-266-02-send-control` 19.9 秒 PASS，AX 與收鍵盤後截圖均確認真正模型回覆 `IPAD266完成`，並完成選單開關。首次開鍵盤的 send-result 截圖仍停在先前閱讀位置，不能當成最終回覆可見證據；實際可見證據為 `attachments/after-interaction.png`。

CPU 取樣：輸入窗口 19 筆 0–78.243%，末筆 0%；送出／互動後窗口 39 筆 0–50.513%，末筆 0%，均無 >90% 樣本。窗口含操作瞬間負載，沒有把峰值略去，也不是完整請求期間的連續上限。安全摘要 `ipad-266-real-reply-regression.json`，原始 `ipad-266-input-cpu.log` 及 `ipad-266-send-cpu.log`。

266 深色六行草稿、附件面板、旋轉與鍵盤開關：`ipad-266-03-dark-keyboard` 14.6 秒 PASS。淺色相同草稿、返回最新、旋轉、實際 CSV 接收＋201 MiB 檔案大小拒收提示：`ipad-266-05-light-attachments` 27.3 秒 PASS。已實際檢視截圖，相同畫面中的有效附件與拒收提示保留各自狀態。

266 在最大字級與減少透明度開啟時，直橫向鍵盤與長提示／待送附件呈現可操作；`ipad-266-11-largest-layout` 15.0 秒、收鍵盤後關閉提示與移除待送附件 `ipad-266-12-largest-dismiss` 7.3 秒皆 PASS。長內容在有界提示區捲動，不保證短畫面同時完整展示全部文字。初次點選設定列未切換減少透明度、初次還原拖曳未改變字級，沒有把操作 completion 當設定成功；最終以實際 AX 值核對：`08-largest-size` 字級 100%／更大字體開，`10-reduced-verified` 減少透明度開。

恢復正常字級後，`ipad-266-17-tail-reply` 23.9 秒 PASS：先返回最新，再送出真實模型請求；鍵盤仍開啟的畫面實際看到 `IPAD266尾端完成`。回覆底端 y=605，小於草稿頂端 y=667 與鍵盤頂端 y=815，完整可見；數值及畫面證據 `ipad-266-tail-visibility.json`。這次沒有以 AX 存在但畫面不可見當作通過。

`ipad-266-18-pages` 23.5 秒 PASS，實際檢視記憶／工具頁，並確認返回。工具頁明示這台 iPad 尚未設定 MCP；本次頁面可操作不等於 MCP 查詢或原 iPhone 工具錯誤已驗收。

266 八個 App 操作序列與截圖摘要收錄 `ipad-266-visual-evidence-index.json`。這是操作序列數，不能當成八項商用功能全部驗收。

## 267 導覽列修補

266 截圖發現「記住的操作路線」有兩個右箭頭，因共用 dataRow 的自訂箭頭與 NavigationLink 系統箭頭同時出現。267 僅讓該 NavigationLink 不畫自訂箭頭，其餘按鈕保留；沒有修改對話或附件邏輯。

來源 `edf61387513e7d0520bc188ccd069c24fbbd84f8`，本機 Release 建置 53.08 秒 PASS、來源前後一致；簽章驗證後覆蓋安裝並回讀版本 267。IPA SHA-256 `ac0a667ae1dda8a990729fe44f243b40495619d8def5d877cc75f5409ffbf903`，binary SHA-256 `b2bd25cc065d13abd89d0f144b52fa3bb97bcdaea5d2ce9fd70c53ae33c09845`。建置／安裝證據 `device-267-artifact.json`、`ipad-267-install.json`、`ipad-267-installed-version.json`。

`ipad-267-01-memory-disclosure` 19.0 秒 PASS，實際檢視記憶頁截圖確認只有一個箭頭，點入後取得真正 `routes.count` 元素與操作路線頁；`ipad-267-02-return` 9.7 秒 PASS，返回記憶頁及聊天草稿。267 相對 266 只修改 MemoryDataView 的箭頭呈現，未重跑相同聊天／附件整套測試充數；265 的 2 項原生 UI 與 266 的 4 項 hosted 測試仍標示其實際執行版本。

## 資料與設定還原

本輪建立的視覺重現對話 `42EE97D9-F84B-47DA-9825-421378394783` 在 266 回歸後由 App 個別刪除；刪除前後以真正 AX row identifier 核對，原有 16 筆對話 ID 全部保留。原 A31 對話與其他手機資料未觸碰。證據 `ipad-266-cleanup-verification.json`。

僅刪除本輪三個已核對大小的測試檔 `IPAD252_BROKEN.pdf`（68 bytes）、`IPAD252_LAYOUT.csv`（58 bytes）、`IPAD253_TOO_LARGE.txt`（201 MiB）。Documents 刪除前後目錄比較確認其餘路徑保留；證據 `ipad-266-owned-file-cleanup.json`。Mac 上的原始截圖、日誌、堆疊、xcresult、簽章 IPA 與測試來源保留。

`ipad-266-16-font-restored` 已核對更大輔助字體關、slider 50%、粗體關、減少透明度關；原有 AssistiveTouch 開啟未變更。早期測試在原購物對話的兩則測試內容與個別瀏覽歷史仍保留，因沒有逐則／逐筆刪除入口，沒有清空使用者資料來清理。

267 最終恢復深色與直向，`ipad-267-04-final-inventory` 6.8 秒 PASS；升級後再核對 16 個原對話 ID 相同。本機完整還原紀錄 `ipad-267-final-restoration.json`、三個 267 操作序列與截圖摘要 `ipad-267-visual-evidence-index.json`。沒有留下正在執行的手機自動化序列；兩個授權暫停的容器均已恢復。

原 `BrowserSearchUITests.testCustomSearchQueryAndSettingsSurviveRelaunch`、`MemoryToolUITests.testUpdateOfManualMemoryPersistsAfterRelaunch` 的舊 CI 失敗，不在本輪視覺回歸覆蓋範圍；不可由頁面能開啟或附件 hosted PASS 推論它們已修復。原 iPhone A31、MCP 工具錯誤／unknown、多供應商與斷線逾時、瀏覽器登入下載、雙平台實機接收端、1,000 輪歷史效能及原生版面警告仍需分別驗證。

## 269 後續團隊進度

後續長歷史分頁、MCP 安全分類、共用鍵盤 Done、273–275 原生結果與 269 正式／隔離 QA 實機證據，見 [269 團隊回歸](IPAD_269_TEAM_VALIDATION.md)。該紀錄保留未重現的間歇延遲、原 iPhone／真 Apporo 連線缺口及 Android 差異；不將本頁 267 結果套成 269 完整商用驗收。
