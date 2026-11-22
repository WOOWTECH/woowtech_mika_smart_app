# 274最大字級：輸入欄與提示末端可達，返回讀取逾時保留

原iPhone16,1／iOS26.5，Development簽章Release0.1.0(274)，runtime`611d6bfa75ec46d39fd9654ac97ff2de6291a1a0`，非TestFlight。**本輪實際捲動證明首／末段及提示末尾可達**；不是四行同時可見，也沒有以AX完整value代替畫面。

先前[限定UI](IPHONE_274_CONTROLLED_UPDATE_20261122.md)只見109pt輸入欄前段，該收據的未測狀態保持。本次獨立受控循環使用既有QA四則及同一47字／四行未送草稿，SHA `498a6f7427068351e8f9809ec21c7a3fe646b260f51b9753a080069e8ba6ac95`。一次最大字級、一次輸入，0Send／模型／MCP／asset，不重跑PDF或0／5／15／30秒字級矩陣。

## 真正手勢與畫面

鍵盤動畫起初AX為82pt、稍後截圖已不同；操作者先取兩份穩定位置，才使用draft矩形`x62/y312/w225/h109`。七次短滑的起訖皆在其中：`x174.5/y411→322`三次，再反向四次，避開Send／麥克風／附件／Done。每次raw snapshot的47字hash、109pt frame及QA訊息hash相同，pending0且未送出。

第三次PNG可見第四行末段「送出第四／行」；第六次回第一行末段，第七次回「QA274未」開頭。Parent實際下載、核manifest並親看第三／第七張，不把相同value或單次裁切當作完整視覺結果。Send與Done可見且在手勢外，Send未按；Done在收尾實際關鍵盤。

上方`chat.composerContext`是約141／142pt獨立ScrollView，notice內容181pt。本輪另兩次僅在提示區滑動，看到末尾「任何訊息。」並回開頭，草稿hash不變；Parent亦親看末尾PNG。這一有限情境不支持「109pt讓末行永久不可讀」，因此沒有據初張裁切圖重寫TextField或改版面。全部無障礙、VoiceOver及裝置矩陣未因此通過。

## 仍然失敗的返回讀取

已還原較大輔助文字0／slider50%／降低透明度0後，21:14:52正常activate回App的唯一source在等待headers **15.015295416秒**逾時。Parent從manifest核過的`04-restore-preserve-http.jsonl`找到同一request四個事件，與disposition逐項相同、重算時間吻合；無當窗CPU或stack，USB／App／XCTest根因仍未知。

一次status ready控制及一次有界source自然恢復，原QA四則與47字草稿仍在；沒有重滑、重啟App或WDA來蓋過失敗。恢復後只清自己的未送草稿、還原外觀system，最後pending0。原A31全24／原22前綴、4270byte PNG、兩記憶及兩個UserProfile未提交源檔保留。原Mac檔案比對收據與瀏覽階段差異metadata相同、無新增／遺失，並非Parent下載全45份原資料重算。

準備時QA欄位名不合的KeyError及Settings頁面guard均保留，修正前沒有輸入／盲切設定。所有HTTP hook已恢復，logging failure0。後續「只切Settings、不改字級」對照另立收據；本次不能證明字級改動是逾時原因。

## 版本及證據

私密原件`T/resume-20261122/editor-scroll274-20261122/`，`T=/Users/woowtech/Documents/WOOWTECH-iOS-validation/documents-20261120/testflight-20261122`。report／result／manifest SHA256依序為`ce332d82113848245640c1112e52cb2ceea9af694c007d8ed1a827395ea53341`、`10a64833694fd916c409d8bf82641f30b387684592e17c8e9fedc54926d618ef`、`2d5e4d8c67cd696ecded38d95e06373faeb97e25734ef0a87fc1c9bc55530052`。Parent核455項manifest中的27份原件，重算七個草稿／frame及原timeout事件，見`parent-independent-verification.json`；這些是同一次實測的獨立核對，不新增通過數。
