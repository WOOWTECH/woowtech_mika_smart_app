# 瀏覽歷史重啟測試保存邊界（2026-11-22）

**修正UITest在保存前便可能終止App的條件；native297精確一案1/1通過。** 沒有修改產品的BrowserSession／Workspace保存或恢復程式，不能把這次test修補說成已修真實裝置資料遺失。

## 原失敗與既有對照

舊cohort03／來源847a83013的`BrowserSearchUITests.testCustomSearchQueryAndSettingsSurviveRelaunch`在原line54重啟後10秒找不到recent history。原log t53.47地址列query匹配、t53.62 terminate；同時AX顯示正在載入及phase=requested，重啟有Fixture Search但history.empty。不能從截短counter推定didFinish=0；最後AX至terminate缺逐callback／save時間線，無法完全排除其他寫入失敗。

原分支已做的隔離macOS WebKit比較（base f4a7a999，Debug／Release各59 assertions）記錄：真didCommit時pill已匹配，但獨立vault及新workspace仍history0；讓真didFinish同步返回後兩者history1。父線本次找回既存原輸出並核來源路徑，沒有重新執行59-assert harness或下載1GB證據。舊native7一次PASS保留，不能證明競態已修。

## 最小修補

基於runtime來源`21a884b88434b88d148d91ab369acaa6fc435485`，只改`ios/Tests/WoowAssistantUITests/BrowserSearchUITests.swift`：

- 原75秒predicate仍要求精確搜尋詞，另要求`browser.status.value`以`phase=ready;`開頭，再確認沒有`browser.workspace.error`。地址列在requested／commit即可匹配；產品onPageFinished同步save早於ready。
- 保留case180秒、重啟後history10秒、URL／文字／引擎／移除斷言、相同namespace與真terminate／launch。沒有sleep、skip、retry、放寬斷言或先closePage幫忙保存。
- 兩個邊界各保留一份安全XCTAttachment，只輸出此隔離fixture的固定QA URL／名稱、封閉status及布林；意外值遮罩，不附全畫面或任意頁面內容。

此條件拒絕「pill已匹配但尚未完成」的原受控狀態。若save失敗，workspace error或原重啟斷言仍應失敗。

## native297實際結果

iPhone17／iOS27 Simulator、真App／WebKit／持久化與XCTest操作；頁面為本機合成fixture，無商用網站／模型／原iPhone。1/1 PASS、failure0、skip0；案例92.612658秒，外層170.37秒、exit0、`source_changed_during_command=false`。原75／10／180秒均未變。

`before-terminate`安全snapshot：ready、requested1／started1／committed1／finished0／observed1、failure=none，workspace error不存在，精確fixture URL吻合。此查詢頁分支在真didFinish呼叫onPageFinished之後記observed→ready，**finished0不是沒有呼叫didFinish**，不得改寫為finished1。

`after-relaunch`同namespace：historyCount1、精確搜尋label吻合、empty=false、引擎Fixture Search、無workspace error、地址列不存在。重新打開該歷史及刪自訂引擎回Google的原斷言亦通過。重啟後status不合封閉格式，附件如實遮罩；沒有填入猜測值。

證據根目錄`R=/Users/woowtech/Documents/WOOWTECH-iOS-validation/documents-20261120`：`Documents-297-browser-history.xcresult`、`native-297-browser-history.{log,json}`、source-before/after及containers收據。`T=R/testflight-20261122/browser-history-followup-20261122/`含原摘錄／分析、候選patch SHA256 `26ca93783945fe35788730f25d8c172a2af8eebca48ad0362d75b992adf41cb2`、297 tests／summary及兩份context附件。兩個已授權容器均恢復；finally shutdown收到已Shutdown的非致命405，測試及外層exit0各自保留。

舊失敗的逐callback時間線、新iPhone真搜尋保存／恢復、真網站登入跳轉、外部下載仍未由本案驗收。沒有為此test-only修補重上傳或重建TestFlight272。
