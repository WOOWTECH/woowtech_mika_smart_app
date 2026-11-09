# POCO Play Protect 攔截調查（2026-11-09）

## 目前結論

問題尚未解除。公開版與語音修正版都重現 Google Play Protect 有害應用程式警告。最新修正版透過 Files 安裝時，Google 即時掃描回傳：

```text
15:09:32.485 JIT scan response:
{"verdict":"POTENTIALLY_UNWANTED","moreInfo":{"description":"此应用可能有害。","threatType":"generic_malware"},"upload":true}
```

畫面顯示「已封鎖有害的應用程式」「此应用可能有害」。這不是僅有未知來源授權提示，也不是「允許受限制的設定」未開；不能宣稱為誤判，亦不能據 generic_malware 指出某段程式就是惡意程式。

## 兩個版本的證據

| 項目 | 公開 woow.4 | 本機語音修正版 |
| --- | --- | --- |
| 套件 | io.woowtech.agent | io.woowtech.agent |
| versionCode | 3804 | 3804 |
| APK SHA-256 | 2da75046061ca0f23c94a076b8f405abf1c13554dc46bf789505193afbe13442 | 169407a72c1e5ed22e7218a70b4dccb90cc490e36ff0dc1bf3582c131f8e7d2c |
| 正式簽章 | 通過 | 通過，與公開版相同 |
| ZIP CRC／重複項目 | 無 CRC 錯誤、無重複 entry | 無 CRC 錯誤、無重複 entry |
| Files 安裝 | 先前已見有害 App 攔截 | 本次重新掃描後見有害 App 攔截 |

簽章 SHA-256：`806b3db808ecbb4d2d032b34624baa7e193802f17a07afbde2a03e78da9474c8`。

簽章／ZIP 正確只驗證身分與封裝，不能證明應用程式沒有惡意行為。Google 本次亦記錄 `APK is not malformed`。

## 安裝成功不代表改判

本次先允許 Files 作為安裝來源、點同一份修正版 APK 更新，選擇 Google 建議的安全掃描。掃描判定後查看更多詳情期間，後續日誌記錄：

```text
15:09:48.450 VerifyApps: User selected ALLOW for id=129
15:09:48.807 VerifyApps: Returning package verification result id=129, result=ALLOW
```

手機 lastUpdateTime 因而更新為 15:09:48。這是互動選擇允許之後安裝，不能列為無警告通過。已詢問使用者是否在手機上繼續安裝；尚未確認該互動由使用者或遠端座標操作造成。沒有證據顯示 Google 將掃描結果改判安全。

另讀到 `verifier_verify_adb_installs=0`；本次沒有修改此值。此前 ADB 安裝成功不能證明一般下載安裝可通過。Files 的 REQUEST_INSTALL_PACKAGES 已恢復 deny。未關閉 Play Protect。已裝 App 可啟動，installed=true、hidden=false、suspended=false、quarantined=false，無障礙受限制設定仍為 allow。

## 已檢查的可能因素與界線

- merged release manifest 未宣告 READ_SMS、RECEIVE_SMS、BIND_NOTIFICATION_LISTENER_SERVICE 或 QUERY_ALL_PACKAGES。
- Accessibility service 確實具有畫面讀取、手勢及截圖能力；沒有宣告 isAccessibilityTool=true。不能因此歸因於 Google 所說的「虛報障礙輔助工具」類別。
- REQUEST_INSTALL_PACKAGES 用於下載新版後交給系統安裝器；WRITE_SECURE_SETTINGS 與 shell helper 是高權限功能，值得安全審查，但現有掃描未將它們列為具體原因。
- MCP 預設來源碼使用 token；高權限匯出元件有系統權限限制。這只是檢查範圍紀錄，不是完整安全稽核或所有依賴的無惡意保證。
- 本次沒有透過換包名、換憑證、改混淆、移除偵測特徵來宣稱修復，也沒有把「仍要安裝」列為正常發布驗收方法。

## 使用影響

1. GitHub APK 下載後透過瀏覽器／Files 安裝，以及 App 更新後交系統安裝器，可能被掃描攔下。已在這支 POCO 的 Files 覆蓋更新路徑重現，不能推定所有手機都完全相同。
2. 已安裝版本目前可用，但 Play Protect 會持續掃描；依判定可能警告、停用或移除。此手機目前未觀察到停用／移除，不應混寫為已發生。
3. 換用 ADB 或選擇允許不能消除 Google 分類，也不能作為一般使用者分發問題已解決的證據。
4. 與語音 bug、Android 無障礙受限制設定是不同層的問題。解除受限制設定不會替 APK 解除 Play Protect 分類。
5. 警告直接影響安裝完成率、更新可用性與使用者信任；若未解決，不宜宣稱一般下載安裝已完整通過。

## 下一步處理

已準備 [英文複核草稿](play-protect-appeal-draft.md)。Google 表單要求聯絡 email、package name、已上傳 VirusTotal 檔案的 SHA-256，以及補充說明。目前沒有確認上述兩個檔案已上傳 VirusTotal，不能把「搜尋不到」寫成「掃描正常」。送出前需要確認外部提交授權、聯絡信箱與待送的確切 APK。

若得到可重現的具體安全問題，修正實際行為並重跑功能及安全驗證；若經檢查仍認為分類有誤，再提交複核。表單說明判定為最終且不保證回覆，因此不能承諾幾天內解封或一定會得到詳細原因。複核後仍須在開啟 Play Protect 的實機上，以同一 SHA-256 重新做一般來源安裝與更新驗收。

## 官方參考

- [各類警告與開發者處理方式](https://developers.google.com/android/play-protect/warning-dev-guidance)
- [Play Protect 複核表單](https://support.google.com/googleplay/android-developer/contact/protectappeals)
- [應用程式驗證與申訴](https://support.google.com/googleplay/android-developer/answer/2992033)
- [裝置端持續保護與停用](https://developers.google.com/android/play-protect/client-protections)
- [警告字串分類](https://developers.google.com/android/play-protect/warning-strings)

本機已保存只含相關掃描結果的證據：`~/.local/share/woowtech-mika/artifacts/playprotect-20261109/scan-evidence.txt`。完整 logcat 不對外提交，以免包含無關 App／裝置資訊。
