# Android MCP 單次送出及錯誤旗標修補

本輪確認並修補兩個現行缺口：OkHttp特定408／503回應可隱式重送tools/call POST；非布林isError可被當成成功。修補前以真正loopback HTTP/SSE請求重現，修補後62個core案例通過。**沒有Android實機、真Apporo或商業寫入驗收；category／code／outcomeUnknown及完整UI契約仍未移植。**

來源為 `c53acdb0cc1d3405214a4034e1980328a5c9b2ef` 加本提交五個Kotlin檔；不在已上傳的iOS273包內。審查與測試證據根目錄 `R=/Users/woowtech/Documents/WOOWTECH-iOS-validation/documents-20261120`，`T=R/testflight-20261122`。

## 實際行為及修補

- 現用OkHttp4.12.0的503＋Retry-After0與408無Retry-After可follow-up同一可重播POST，沒有application retry loop也不能保證單次送出。HTTP及legacy SSE現在只對tools/call使用one-shot request body與retryOnConnectionFailure=false；原body type／length／bytes委派不變，握手、目錄及其他操作維持原策略。
- 共用mcpToolResult只接受缺省或真正JSON boolean。present null、object、string或number拋固定協定形狀錯誤，經現有transport處理成失敗；缺省／false仍正常，true仍工具錯誤。沒有把錯誤當rollback、沒有吞使用者取消。
- 新測試透過真HTTP→McpCapability→ToolDispatcher觀察ok，另以MockWebServer實數HTTP及legacy SSE的tools/call POST，不只計client方法呼叫。這是loopback／合成資料，沒有業務寫入。

## 逐輪結果

| 輪次 | 實際執行 |
| --- | --- |
| red-initial／android-mcp-contract-red-20261122-01 | 11案、8 failure、error0、skip0；25.48秒。HTTP重送及4個不合法旗標已揭露，SSE兩案有fixture hostname不一致，不能當產品紅燈。原失敗保留。 |
| red-confirmed／android-mcp-contract-red-20261122-02 | 只修fixture同主機地址，production未改；11案、8 failure、error0、skip0；14.83秒。HTTP/SSE×408/503各收到2個同RPC ID的POST並回正常；4個不合法旗標ok=true，3個合法語意通過。 |
| green／android-mcp-contract-green-20261122-01 | 62案、failure0、error0、skip0；29.81秒。上述4案各只有1個POST且保留錯誤，不合法旗標ok=false；confirmed-red到green測試檔逐byte相同。 |

綠燈涵蓋HTTP13、legacy SSE3、stdio3、McpClient20、新replay4、新旗標7、NetProxy12，包含既有session／headers／redirect、body-read取消與close、目錄、ID、結果截斷／fullResult及allow-list。每輪source-before／after相同；heavy.sh序列化、offline、workers2，原兩個批准containers恢復。Parent另由JUnit XML重算三輪數字、核原始log與五個受測source hash，見 `T/android-mcp-contract-fix/parent-verification.json`。

完整實作／來源／JUnit／commands：`T/android-mcp-contract-fix/HANDOFF.md`、`RESULT.json`、`final-source-hashes.json`。每輪R同label的log／json／source-before／source-after／containers收據均保留。Patch SHA256 `8411538ceba447d0dd28702a47e486bb6961bcb528dfa6c7cd033bfa6ed6c3e3`。

## 相容性與未完成項

one-shot也阻止已送body後的401／407自動重播；預先設定的headers、proxy、timeouts與取消程式未改，既有一般NetProxy測試通過。這不等於已驗MCP經認證proxy的完整HTTPS CONNECT／重新認證流程，也不承諾任意caller自訂Authenticator仍可重播。

本修補限制OkHttp上述隱式follow-up，不是server交易冪等或模型後續重新決策的host硬阻擋。現行Android仍缺iOS的host-derived固定category／numeric code／outcomeUnknown、安全failure回饋與UI未知結果提示；一般合法錯誤原本即ok=false，不概括為所有工具錯誤都誤報成功。現行差異審查見 `T/android-mcp-contract-current-review/REVIEW.md`；實機、真Apporo與完整商用條件依[驗收矩陣](ACCEPTANCE_GAPS_20261122.md)。
