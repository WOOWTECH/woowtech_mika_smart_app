# 渥屋助理 Google Play 版本（開發中）

這是渥屋助理的獨立商店版分支，套件名稱 `io.woowtech.assistant`。它可與 [GitHub APK 版（main）](https://github.com/WOOWTECH/woowtech_mika_smart_app/tree/main) 共存；兩者本機資料分開。**尚未送交 Google Play 審核，也尚未達到公開上架條件。**

## 功能範圍

- 使用者自備模型帳號或 API Key 的 AI 對話
- 語音輸入、內建瀏覽器與記憶
- 手機在線時的遠端對話

商店版不提供跨 App 自動操作、無障礙服務、ADB 手機助手、遠端喚醒或解鎖、背景定時操控、App 內 APK 自我更新。手機在線時可遠端唯讀存取對話與附件；離線同步尚未完成。AI 回覆檢舉已在分支實作，但正式收件端尚未部署與驗收；資料安全揭露與實機功能驗收仍待完成。詳細程式盤點與測試界線見 [商店版研究報告](docs-woowtech/PLAY_STORE_RESEARCH_2026-11-11.md)。

渥屋科技（WOOW TECH CO., LTD.）維護此專案，以 [Mika](https://github.com/wangzan101/Mika)（Apache-2.0）為基礎；與 Mika 原作者沒有隸屬或背書關係。[授權](LICENSE) · [著作權聲明](NOTICE) · [第三方聲明](licenses/THIRD_PARTY_NOTICES.md)

## English

This is the separate Google Play edition branch of woowtech agent, package ID `io.woowtech.assistant`. It can coexist with the [direct APK edition on main](https://github.com/WOOWTECH/woowtech_mika_smart_app/tree/main); local data is separate. **This edition has not been submitted to Google Play and is not ready for public store release.**

The intended features are AI chat using a user supplied model account or API key, voice input, an in-app browser, memory, and remote chat while the phone is online. Cross-app automation, AccessibilityService, ADB phone control, remote wake/unlock, scheduled phone tasks, and in-app APK self-updates are excluded. Online read-only conversation and attachment access is implemented; offline sync remains open. The AI response report action is implemented in this branch, but its production receiver has not been deployed or verified. Data disclosures and device acceptance testing remain open. See the [research and status report](docs-woowtech/PLAY_STORE_RESEARCH_2026-11-11.md).

Maintained by WOOW TECH CO., LTD. and based on [Mika](https://github.com/wangzan101/Mika) under Apache-2.0. This project is not affiliated with or endorsed by the Mika author.
