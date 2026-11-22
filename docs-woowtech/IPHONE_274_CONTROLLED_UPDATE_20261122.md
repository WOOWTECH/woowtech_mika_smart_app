# 274受控原地更新：簽章與資料延續性證據

**受控Development簽章的Release274已實際原地安裝；首次啟動前及限定UI完成後45個持久檔案全部保留。** 單次空白字級還原、正常四行草稿／淺深色／鍵盤、原圖及一頁PDF有真機證據；本階段保留15秒畫面讀取逾時、最大字級內部捲動未測及警告日誌未知。後續[首末捲動補驗](IPHONE_274_ACCESSIBILITY_SCROLL_20261122.md)及[Settings返回對照](IPHONE_274_SETTINGS_RETURN_CONTROLS_20261122.md)另立收據，未回填本階段。它不是TestFlight版，也沒有重建或重新上傳274。[官方274發佈](TESTFLIGHT_274_RELEASE.md)保留19:12仍未顯示新包的獨立結果。

## 既存簽章與公開版本證據

原Mac有一份既存development profile SHA256 `7cfaeab3c9fb820d3fa7c2c6c5f34dbcadd8be186f367611740196103d583c78`，Team `W4UWZ8NP2P`、wildcard App ID可匹配此App、原配對iPhone已列入、到期2027-11-18T07:32:06Z，與既存有效identity匹配。沒有新增裝置／Portal／憑證或匯出私鑰。Parent archive另一份profile不含此機，已在傳輸前明確棄用，未拿來安裝。

最初InstallationProxy回傳已裝272的fully qualified App ID `W4UWZ8NP2P.io.woowtech.assistant`，但沒有keychain groups欄，操作者正確列unknown。後續Parent補取**實際已發布272的Store IPA**公開簽章：source`21a884b8`、8,150,699 bytes／SHA `ca91194cfd3a166973a76966585cfd01db3cd74d9a73fa2809d861324f317708`，與舊Upload／VALID／內測及實裝鏈關聯。272／274的實際公開signature plist各409 bytes且逐byte相同（SHA `d5ba780a73f26ba6d3679728c8fb5e70877ba1229a590c7af34cf61da82cef18`）；兩者keychain/app-group keys確實缺省，不是由API缺欄推定。

Apple的[群組排列規則](https://developer.apple.com/documentation/Security/sharing-access-to-keychain-items-among-a-collection-of-apps)以顯式keychain groups、application identifier及app groups依序組成；本例沒有兩種顯式群組，default為同一`W4UWZ8NP2P.io.woowtech.assistant`。來源亦未使用`kSecAttrAccessGroup`。舊恢復後stack的App3358 image UUID另實際匹配已發布272的`9141F3D2-C65C-3FA0-A594-AC71DAB753B9`，只用於binary身份，不用來解釋故障。沒有讀取Keychain秘密或聲稱Apple處理後整包byte相同。

## 具體產物與獨立核驗

| 項目 | 真結果 |
| --- | --- |
| 原Store274輸入 | 8,156,199 bytes，SHA `d72102f5d992bc2458aaff7c15ff0e8cdae8061eeee79d0dad15a6111b79dcf0`，source`611d6bfa75ec46d39fd9654ac97ff2de6291a1a0` |
| 傳輸 | 10,874,932-byte base64及公開證據傳到原會話私密輸入目錄，Parent逐檔完整raw讀回相同；transfer manifest SHA `d466a9853c9a124ea6ca934bf5fc696ff1ff3bba4e38ebe935f5a430b4d0a1ff` |
| 新Development簽章Release IPA | **4,111,178 bytes**，SHA `578cb8a1ff733173fc6aa959b7bd9357aed682362deb211e535cd66f8058175c`。Store原包的Symbols仍保留，裝機包只含Payload，非程式碼遺漏 |
| UUID／內容 | 主UUID `7CE1BB7D-7066-3E04-B2F8-8280E33F5B05`及十個Mach-O UUID、全部非簽章bytes／sections／資源與輸入相同，沒有重新編譯或加入DEBUG fixture |
| 實際entitlements | 只有同application-identifier、Team及get-task-allow=true；移除Store專用beta flag，不新增token／共享群組／其他能力。群組keys仍缺省，default identity保持 |
| 簽章 | 十個節點strict／Team／public leaf identity符合；App deep strict及重新解包deep strict通過，embedded profile為上述確切合格SHA |

Parent實際下載新4.1MB IPA、核size／SHA、解包驗codesign deep strict、三個實際entitlements、profile exactSHA／Team／AppID／期限、leaf certificate DER確在profile DeveloperCertificates及主UUID／build274，不只轉述操作者。團隊另靜態審查新簽章／封裝helper的來源pin、ZIP安全、非簽章不變、default group及沒有install／uninstall／私鑰匯出，未指出具體阻擋。

首次本機簽完後的公開憑證擷取optional argument寫法失敗保留，改為`--extract-certificates=prefix`後只重新核驗／封裝，未再次簽章，也不是手機安裝失敗。工具19項安全檢查不當成實機通過數。

## 真機執行界線

Parent已在12:14 UTC沿原授權指示：先新取原A31全22、空draft／pending0、原圖／兩memory／設定及完整必要持久資料／附件備份；指定原單一RSD手機、僅此確切SHA的新包原地更新，禁止卸載／清除資料／換Team或新WDA。安裝結果未知時先讀已裝版號核對，不能盲重送。首次啟動前後核原檔／prefix／記憶／設定，再驗字級還原、四行草稿、Done／Return／原縮圖、代表淺深色及39字PDF，全部0模型／業務請求。

### 實際安裝與資料讀回

12:23:00–24 UTC完成45檔／9,186,234 bytes私密備份及第二次完整讀回一致；原手機當時為272／TestFlight。備份只留原Mac，沒有傳Parent或讀取Keychain秘密。

唯一一次原地安裝在12:24:04 UTC因進度callback的TypeError回報`INSTALL_RESULT_UNKNOWN`，**沒有重送**。12:24:43直接讀回已裝版本為**0.1.0(274)、Apple Development、同Team與App ID**，已證明實際安裝成功。首次啟動前核原45檔：無缺漏／異動／新增，三個必要原檔metadata亦與備份完全相同。原callback未留trace，後續純本機重現相容性錯誤只屬一致線索，不能宣稱原例外原因已證實。

20:26–28台北時間，原對話全24則顯示hash與安裝前逐項相同，原22前綴完整，空draft／pending0，兩筆記憶、模型選擇metadata及外觀選項與安裝前相同。能讀本機加密資料是實際延續證據；沒有讀出Keychain秘密，也不代表線上憑證或MCP已可用。

**24則在20:17安裝前已存在，19:19最後快照為22則。額外一對user／assistant的顯示hash符合之前的提問／限流錯誤，但找不到對應intent或dispatch，來源／精確時間仍未知。** 保留全部24，不把它們自動計成新成功對話，也不能把相同錯誤顯示當成新HTTP回覆。初次啟動的錯誤畫面斷言／`07-stopped.json`仍留原件，不能用後續成功覆寫失敗。獨立來源審查未找到restore自行追加完整一對訊息的具體機制；這不構成歷史發起者判定。

Parent核對45檔比對收據及公開的三個必要檔bytes／SHA，另獨立比較實際24個message hashes與兩記憶／選擇metadata／外觀的保留條件，見`parent-install-and-preservation-verification.json`。完整45檔逐byte比較由原Mac操作者執行，未傳私密index／備份供Parent重做；其20:49收據仍是45檔完全相同、無新增／遺失，不是只核conversation檔案大小。

### 20:51封存的限定UI結果

| 實際案例 | 結果與界線 |
| --- | --- |
| 空白、未聚焦字級循環 | 23pt→最大64pt→首次觀察還原23pt；同process clock後續實際6.2344／16.2317／31.2318秒仍23pt，無focus／輸字／導航促成還原。本輪未再現272殘留64pt；首次觀察不是精確還原完成時刻 |
| 四行草稿 | 47字hash正常→最大／鍵盤→還原相同；正常及還原89pt，最大／鍵盤109pt。正常字級淺深色四行可讀，Done可用 |
| 最大字級 | 僅前段可見，提示最後一行有部分字形位於邊界；未驗內部捲動／caret末端。來源本來就有限制可視行數及提示ScrollView，不能由截圖判內容不可達或直接改產品；完整無障礙驗收仍開放 |
| 原圖、回尾 | 原縮圖及正式Quick Look可讀，返回後可操作；Return在獨立列並實際回到最新 |
| PDF及鍵盤 | 正式既有39字來源產生19,434 bytes／1頁PDF，SHA `ebc4f00af8f011fdffe75595bfe1b3ea23dc0b95bb37e677c4c2f35e3ac0eb56`；PDFKit核完整來源，關閉後鍵盤開／收及Return可用。Parent另在macOS PDFKit抽得66字，與原抽字hash `f6bb32fbe63ad942d84c17fce38879f4b684021b0860f8793055f858a6741c7a`一致。不是多頁、外部儲存或接收端驗收 |
| 限定清理 | 唯一本輪QA PDF刪前hash吻合、刪後不存在，其他檔未刪；自己的草稿清空／pending0，外觀system／原字級／reduceTransparency0還原 |

**實際失敗保留**：20:48:19由Settings正常返回後，唯一`/source`在waiting headers **15.00646025秒**逾時，無當窗CPU／stack；`/status`ready、45檔一致，之後一次有界source自然恢復、全24及空draft可讀。未重啟App／WDA。這不是模型或相簿請求，USB／App／XCTest根因仍未知。Publishing管線雖有416,095行流入，缺指定控制事件且未保存原始行，**警告驗證UNKNOWN**，不是零警告。

本UI階段0模型／0MCP／0Send／0新對話。report／result／manifest SHA依序`2c00b7dbb3403aaa6cce2ad2ee288b44247e38ce3d7483c995ea797c9affe492`、`ad34852e0727e0f57476a4b68e70cd04b04ee15eb5ebd4f29f8967c1e8a4dfb2`、`740c7c539f6850424a3201ec2580fd46ac0d595156669d14dead6ea74739d6c3`。Parent取完整manifest、核1132個unique安全相對路徑，實際下載／核49項選定原件bytes／SHA，未聲稱全部1132項下載。後續模型／Photos／瀏覽各立收據，不能回填本階段或宣稱商用全項通過。

證據根`T=/Users/woowtech/Documents/WOOWTECH-iOS-validation/documents-20261120/testflight-20261122`。Parent資料在`T/resume-20261122/resign274-reviewed-source-20261122/`（含實際新IPA與`parent-install-artifact-verification.json`）、`release272-274-public-entitlements-provenance.json`及`resign274-parent-review/INSTALL_REVIEW.md`。手機原資料／私鑰未傳Parent；收到的mobileprovision只在安裝包內作必要公開簽章核對，未列出UDID或個人CN。原兩個UserProfile未提交修改始終保留。
