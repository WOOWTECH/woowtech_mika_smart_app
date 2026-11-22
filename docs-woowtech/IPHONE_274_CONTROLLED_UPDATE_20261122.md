# 274受控原地更新：簽章與資料延續性證據

**受控Development簽章的Release274已完成雙重核驗，已沿原使用者授權交唯一操作者執行原地安裝／保留驗證；尚未取得裝機結果。** 它不是TestFlight版，也沒有重建或重新上傳274。[官方274發佈](TESTFLIGHT_274_RELEASE.md)保留19:12仍未顯示新包的獨立結果。

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

目前僅簽章／產物核驗PASS，**安裝／Keychain實際可用／資料保留及274 UI仍未驗收**。新手機結果須另封存`release274-development-install-validation-20261122`，不以同群組公開metadata代替真資料讀回。實際OS解鎖／信任提示或新拒絕才精確記錄需人工條件，不把已授權安裝再次轉成許可問題。

證據根`T=/Users/woowtech/Documents/WOOWTECH-iOS-validation/documents-20261120/testflight-20261122`。Parent資料在`T/resume-20261122/resign274-reviewed-source-20261122/`（含實際新IPA與`parent-install-artifact-verification.json`）、`release272-274-public-entitlements-provenance.json`及`resign274-parent-review/INSTALL_REVIEW.md`。手機原資料／私鑰未傳Parent；收到的mobileprovision只在安裝包內作必要公開簽章核對，未列出UDID或個人CN。原兩個UserProfile未提交修改始終保留。
