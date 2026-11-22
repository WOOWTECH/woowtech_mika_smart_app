# PDF呈現時鍵盤動畫發布修補（2026-11-22）

**已定位並修正本次PDF呈現的SwiftUI Publishing警告，native必要回歸3/3。** 修補尚不在TestFlight272；原A31高CPU與其他viewport警告不因此關閉。

## 實證與最小修補

先前native289／291／292均在PDF預覽附近出現Publishing警告。298改用暫時DEBUG事件夾界，沒有LLDB attach、改fixture時序或產品邏輯：PDFView建立／解碼／document指派，以及ChatKeyboardDock既有發布前後各記固定階段；只在隔離UITestMode與診斷環境開啟。

298精確PDF案例1/1通過、58.898秒；15:31:28.087 PDF document指派與make結束，.088 update進入；同主執行緒3a60394在.276記keyboard.duration.before，接著兩筆SwiftUI Publishing fault，.278記keyboard.duration.after。這次fault在`animationDuration`的`@Published`寫入夾界內，並非PDF document setter直接發布。診斷／堆疊有額外成本，只作事件順序證據，不作效能基準。三檔診斷已逐位元核對並精確reverse，未留進產品。

`animationDuration`只供`ChatKeyboardReserveModifier`在reserve變化時設定動畫曲線。duration-only通知沒有改變幾何；下一次`frameInWindow`發布或modifier自身幾何變化重算時，會讀到最新duration。因此將它改為普通`private(set)`主執行緒屬性，保留同步更新順序與`frameInWindow @Published`。沒有延後整批鍵盤事件、frame clamp、改動畫規則或壓制警告。

為驗證真通知／真publisher，ChatKeyboardDock可注入私有NotificationCenter；既有`ChatKeyboardDock()`仍使用.default並在deinit移除同一center的觀察。測試以自有center送hide＋新duration，隔離於host App的系統鍵盤，不用window或假publisher。

## 失敗→通過

| 執行 | 真實結果 |
| --- | --- |
| native299，只有隔離center與新測試，保留原@Published | 0/1、failure1、skip0；0.451539秒，line26實測objectWillChange為1，預期0。編譯成功，失敗不是工具鏈／timeout |
| native300，套最小fix | 3/3、failure0、skip0，外層260.19秒、exit0、source_changed=false |
| 300 publisher案例 | 0.003秒；新duration同步更新、frame仍nil、duration-only發布0 |
| 300原PDF UI案例 | 55.823秒；真PDF生成、預覽、關閉及草稿保留，未另發模型回合 |
| 300原四行／鍵盤／Return案例 | 112.584秒；原terminal可讀、閱讀停留／回尾與鍵盤幾何斷言通過 |

300原始native log的Publishing字串0；unified stream實際fault事件0，另有144個TRANSCRIPT控制事件。stream過濾器標頭本身含Publishing文字一次，**不是warning事件**。未修改／靜音XCTest runtime issue收集。兩個已授權測試容器均恢復。

`R=/Users/woowtech/Documents/WOOWTECH-iOS-validation/documents-20261120`：298–300的xcresult、原log、wrapper、source-before/after及container收據。`T=R/testflight-20261122`下：`pdf-preview-bracket-diagnostic-candidate/298-disposition.json`／事件片段／精確撤回patch；`pdf-keyboard-duration-fix-candidate/`含red與fix patch、299／300結構化結果、來源hash及`red-green-verification.json`。

上述UI使用真App／UIKit／SwiftUI／PDFKit及隔離合成模型，是本機回歸；不是原iPhone新修正版、Apporo訂單或完整商用驗收。後續Release及實機以新版本來源鏈驗證，不把本結果回填272。295長按串流間歇逾時、原A31正常串流／MCP、字級還原輸入框高度及hosted viewport多次更新警告仍各自保留。
