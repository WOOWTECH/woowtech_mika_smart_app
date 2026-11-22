# 241既存MCP錯誤：取證範圍與分類缺口

**已找回4 attempted／4 received／2 tool_errors的活動紀錄；兩筆錯誤細分類仍未知。** 本次只查既有檔案，沒有重放工具、模型請求、裝置操作或新成功輪次。241來源診斷語意核對`254871cab19bb72c0a69d7246c4e58f6b58eda39`，不能拿11月22日模型限流解釋這批11月20日工具錯誤。

原 `mcp-diag241-visible.log` 在第6／8行分別達2 received／1 tool_errors與3 received／2 tool_errors，第10行為4／4／2。另一份 `mcp-diag241-mcp.log` 的2／2／0是獨立樣本，沒有合併。8條sanitized dispatch分成4組started／completed，elapsed依序1454／164／2271／1840ms；全為category=none，沒有HTTP status或RPC code。原時間沒有時區，不標成UTC。

活動紀錄沒有dispatch UUID或精確conversation／result locator，因此錯誤增加與第二、三組dispatch只能依序推定，無法直接correlate逐筆結果。歷史程式先在executor返回時寫completed／none，之後才檢查isError；true或異常型別都增加App工具錯誤數。**completed只證App執行路徑返回，不證工具業務成功或服務端收件。** 目前也不能區分參數／schema拒絕、工具業務錯誤或異常結果。

操作者限定檢查兩份活動log、對應notes／文字證據、sanitized dispatch及精確檔名引用。沒有遍歷手機對話或讀取／解密vault；兩張既存業務JPG只記大小／hash，未開啟；兩個0-byte syslog檔與有效8條事件檔分開。停止點是缺少原工具結果的精確locator及綁定的安全錯誤欄位，未盲重試未知寫入。

Parent取回report／result／manifest與6份安全JSON，逐項bytes／SHA核對；不執行下載helper。私密證據位於 `/Users/woowtech/Documents/WOOWTECH-iOS-validation/documents-20261120/testflight-20261122/resume-20261122/stored-mcp-errors-20261122/`。report／result／manifest SHA256依序：

- `e57140ea7e3ac5740d055181c436bcfe19ce3cbd6ebabcd050a57759c39f2ef5`
- `4f3d2c1e63f0a072c9048ea1bcda3a42222397481ca8089ca6d5085c96fdb3d0`
- `6d8b6d482d10a39c3fb83339bbfc39b58dc1358a6b6496e6622b2bfb514007b3`

原UserProfile兩檔hash本輪重算仍同；22則A31／原圖片／記憶保留僅承接前輪封存，本次未重新操作手機驗證。沒有產生需清理的裝置資料。結果為證據恢復通過、錯誤細分類缺證；新增診斷只能改善未來觀察，不能追溯補造原錯誤原因。

後續已實作[分類後的安全日誌](IOS_MCP_RESULT_DIAGNOSTIC_20261122.md)，native303精確22/22及實際OS日誌222事件／111組通過；原iPhone及真Apporo仍待新build／有效服務，不將這些合成或loopback結果回填為舊兩錯誤已修。
