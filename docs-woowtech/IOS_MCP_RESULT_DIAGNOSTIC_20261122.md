# iOS MCP結果診斷：分類後記錄，不把返回當成功

由[241既存兩筆錯誤](MCP_241_STORED_ERRORS_REVIEW_20261122.md)發現：舊日誌在檢查isError前即寫completed／none。現在以既有host-owned `MCPExecutionDiagnostic`記錄結果，保留一次UUID關聯及固定category、可選numeric code、outcome_unknown與monotonic elapsed_ms；沒有加入endpoint、工具名稱／參數、server文字或憑證。

executor返回時phase為returned：缺省／false旗標為result、true為toolError、異常旗標／非object為protocolFailure。拋出錯誤為failed，沿用原HTTP／RPC／timeout／transport等型別分類。returned不是已完成對話step或服務端收件證明；取消後的遲回仍會被既有fence攔下。結果內容、公開API、選定工具範圍、重複操作防護、三次連續拋錯停止與取消行為不變；沒有新增重試。

## 真實native303結果

受測來源為`2e655996e9795aa00715f053a2e06c56d7827540`＋本提交兩檔，已與handoff及source-before／after核對：

- `ios/Sources/AssistantMCP/MCPConversationRunner.swift`：SHA256 `0f4b4163213f1ceec2a08e47f888901dc8e4cd0cb62425f2554fc2bd49775eda`。
- `ios/Tests/AssistantMCPTests/MCPDispatchDiagnosticTests.swift`：SHA256 `6baf2524729b8c89840092a9864f1fb99ef8d3de39a9254ec7dcc6e6a1f73ada`。

Xcode27／iPhone17／iOS27 Simulator，三個精確suite實際**22/22通過，failure／skip／expected failure皆0**：新增diagnostic7、既有runner10、真TCP／HTTP loopback5。外層77.53秒、exit0、source_changed=false；heavy.sh序列化，兩個原授權containers恢復。

新增案經production runner檢查返回旗標／非object、工具資源讀取、HTTP／RPC數字碼與不確定性、惡意結果內metadata不能升為host診斷、同指令不重放、三次拋錯停止、工具錯誤重置失敗streak，以及實際task.cancel後無遲到completed step。內部instance observer只供測試，production為nil，沒有全域hook或額外await。

實際Simulator unified log可讀**222事件／111組完整started→returned或failed**，UUID均配對。Parent逐行allowlist核對固定六欄，沒有payload欄位；returned中result61、toolError5、protocolFailure12，failed33。HTTP401／500與RPC -32602／-32603／-32000及unknown旗標實際出現在OS日誌，不只依賴observer斷言。這是fixture／loopback事件數，不是商用工具成功次數。

`R=/Users/woowtech/Documents/WOOWTECH-iOS-validation/documents-20261120`；原始log／source／containers為`R/native-303-mcp-result-diagnostic.*`，xcresult為`R/Documents-303-mcp-result-diagnostic.xcresult`。細節、精確command、22項原生結果、原始OS log、獨立validator及Parent收據在`R/testflight-20261122/ios-mcp-result-diagnostic-followup/`。OS log SHA256 `d616041985ebc3c993a7e5f03ede81cc608616dd30fa4ed5290db69d140481c2`。

## 驗收界線

尚未裝原iPhone／呼叫真Apporo，不能追溯補分241兩筆錯誤，也不證原A31卡死已修。此改動晚於已上傳的273來源`4e2c8c64`，不在該包內；要驗真機分類須建立帶新來源的下一build，而非重傳273。原工具結果缺locator／代碼、App模型限流、273可見性與完整商用項目依[缺口矩陣](ACCEPTANCE_GAPS_20261122.md)。
