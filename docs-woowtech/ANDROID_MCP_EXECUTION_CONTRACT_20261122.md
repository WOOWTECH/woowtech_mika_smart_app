# Android MCP 單次送出及錯誤旗標修補

本輪修補OkHttp特定408／503隱式重送及非布林isError成功路徑，初批62個core案例通過；後續安全診斷核心92案、對話步驟提示及資源檢查40案通過，兩品牌Kotlin編譯成功。**沒有Android實機、真Apporo或商業寫入驗收。** 下文分別保留各次受測來源與失敗，不混成同一版本。

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

## 後續核心診斷契約：92案通過，UI待整合

來源為 `84d044190eadf332e06e69d0a30349c5e32460bd` 加本提交12個core source／test檔；前段「仍缺」是初批狀態，由本節補充，不回寫原紅綠紀錄。HTTP、legacy SSE、stdio加入host-owned McpDiagnostic，固定九類與可選numeric code。RPC -32600／-32601／-32602為unknown=false，其餘RPC、HTTP、timeout／transport及不可用結果為true；false不保證rollback。缺省／false工具旗標為result／false，true為toolError／true，malformed為protocolFailure／true。本地未dispatch拒絕可明示other／false。

正常tool內容仍Untrusted；server error.message／data及Exception.message／cause不作host failure文字或診斷，組裝失敗亦改為固定安全文字。Coroutine取消重拋。真正capability輸出固定先ok、完整diagnostic，再未知結果guidance，最後text／reference／truncation；太長或儲存失敗仍保留原診斷。guidance要求未知結果先唯讀查驗，**不是host/server冪等或禁止模型後續呼叫的硬保證**。

| 實際輪次 | JUnit tests／failure／error／skip | 外層秒數 |
| --- | --- | ---: |
| red | 25／24／0／0 | 16.86 |
| 首green | 91／6／0／0 | 33.95 |
| red-confirmed，修正stdio fixture後的真正基線 | 29／28／0／0 | 27.46 |
| green-confirmed | 91／0／0／0 | 34.15 |
| red-assembly，額外host洩漏canary | 1／1／0／0 | 16.73 |
| green-final | 92／0／0／0 | 29.48 |
| green-prefix，新增案JUnit函式回傳Int造成初始化失敗 | 81／1／0／0 | 27.54 |
| green-prefix-final，修正Unit簽名、原斷言保留 | **92／0／0／0** | **27.31** |

八輪均序列化、來源before／after相同、兩個批准containers恢復；沒有把fixture／JUnit簽名錯誤當產品紅燈。最終四個HTTP/SSE×408/503仍各POST1。真McpCapability＋ToolDispatcher長結果以8192字存檔、4096字preview，實際JSON4309字，首71字含完整ok／diagnostic；截在該邊界仍可解析且與原值相同。另一真HTTP RPC -32000＋故障result store同樣保留prefix與原診斷。

證據 `T/android-mcp-diagnostic-core/HANDOFF.md`、`RESULT.json`、`JSON-EXAMPLES.json`、`parent-verification.json`；最終原始log `R/android-mcp-diagnostic-green-20261122-05.log`，JUnit在 `T/android-mcp-diagnostic-core/green-prefix-final/junit/`。Parent重算八輪JUnit、核全artifact與12個現行source hash、18份真測試序列化輸出及prefix順序。Patch SHA256 `9c9244807156b99c2dd3df0eb456df1a83b9f3f1a539e903e564e4ff2114cb7b`。這些是loopback及stdio合成管線，不增加商用／實機通過數；UI clipped consumer、真Apporo、認證proxy重新協商及未知業務效果仍未驗。

## 對話步驟提示及文件語系：40案通過

核心診斷提交 `b9d3c9bb22e6495fc720affe2ad8bad9ebbbffc9` 上再整合本提交App變更。僅MCP namespace的結果採新路徑：完整JSON只讀頂層host diagnostic；截斷只接受固定ok→完整diagnostic前綴，拒絕nested／quoted／tooltext偽造及不合法型別。類別改為本地化人類文字，數字code放既有Tag，unknown加查驗提示；同step未知Tag不重複，保留既有guard累積與成功／舊資料路徑。

RPC未知結果不能暗示未執行，因此審查時將十語系的「伺服器拒絕」改為中性「伺服器回覆錯誤」，並補-32000／-32603 unknown案例；-32602 known仍不加未知Tag。v1、v2候選及base／candidate hash保留在 `T/android-mcp-diagnostic-ui-candidate/`，v2 patch SHA256 `ad66454d34470e319c1c62e2cfc9c51f20af0aa82780c5191802c56f2a03519b`。

| 執行 | 結果與界線 |
| --- | --- |
| UI-red-01 | 環境缺JAVA_HOME，0案，非產品紅燈；原log保留。後續沿用已安裝Homebrew JDK17及Android SDK，沒有安裝新依賴。 |
| UI-red-02 | 只套新測試／資源，舊ViewModel不變；11案／10 failure／error0／skip0，40.56秒，source unchanged。 |
| UI-green-01 | 40案／3 failure／error0／skip0，34.05秒。新增11及原ViewModel20均通過；3個StringResources失敗來自既有document38 keys只具英文／繁中，另8語系缺少，已與base84d靜態逐鍵比對，不能歸因新MCP keys。Apporo compile完成，Woow尚未到，未宣稱兩者皆過。 |
| UI-green-02 | 補齊8語系304個文件項目後，**40案／failure0／error0／skip0，38.29秒**；Apporo與Woowtech Kotlin compile皆成功，source unchanged，原兩containers恢復。 |

單元案例實際執行於既有啟用的 `:app:testUpstreamDebugUnitTest`：新提示11、舊ViewModel20、StringResources9。品牌unit task在專案設定中停用，**不是兩品牌各跑40案，也不是native UI／instrumentation**。Parent由原始JUnit重算四輪並核當次完整source hash，見 `T/android-mcp-diagnostic-ui-verify/parent-verification.json`；各輪同目錄的phase/junit及R原始log／source／containers皆留存。

另發現文件文案原宣稱PDF512頁，但Android實際 `DocumentLimits.MAX_PDF_PAGES=256`，renderer依此拒絕超限。本輪只將十語系文案一致改為256，不提高容量或改PDF行為；前後hash與runtime來源記於 `T/android-document-l10n-repair/pdf-page-limit-correction.json`。文件新增語系的XML／key／參數／分享未確認及本機產檔語意另有兩份worker靜態核對。翻譯尚未經獨立母語者、RTL或實機版面審視，不以資源測試替代。

新UI不新增重試或外部送出動作，不改授權／信任／model client；MCP guidance仍非硬性冪等。真Apporo、POCO及完整商用條件待實際服務與單一操作者時段。
