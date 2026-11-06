<div align="center">

# 渥屋助理（woowtech agent）

**手機上的 AI 助理：說一句話，它在背景的螢幕上替你操作 App 和網頁，直到把事情辦完。**

由 [渥屋科技（WOOW TECH CO., LTD.）](https://aiot.woowtech.io/) 維護與發行，以開源專案 [Mika](https://github.com/wangzan101/Mika)（Apache-2.0）為基礎。
本專案與 Mika 原作者沒有隸屬或背書關係。

繁體中文 · [English](#english)

</div>

> 第一個版本準備中。發佈後會放在本 repo 的 [Releases](https://github.com/WOOWTECH/woowtech_mika_smart_app/releases)，只提供 APK，不上架 Google Play（原因見下方「安裝須知」）。

## 它能做什麼

- **替你操作 App**：在另一塊背景螢幕上開 App、點按、輸入、捲動，你照常用手機；想看時點開小畫面。
- **瀏覽網頁**：內建桌面版瀏覽器，能保持登入、讀網頁、下載和上傳。
- **排程與條件**：「明天早上 9 點提醒我」「每週五幫我做這件事」。
- **檔案與運算**：每段對話有一個 Linux 沙盒，可執行 Python、Node 和 shell（需要 arm64 手機）。
- **台灣在地化**：繁體中文介面，內建 LINE、蝦皮、momo、PChome、foodpanda、渥屋科技 App 等使用知識。
- **從電腦交辦**：電腦上的 AI 工具可以透過 MCP 把任務交給手機。

預設是「詢問模式」：付款、下單前一定先問你，其他動作直接做。也可以切到「自主模式」。

## 安裝須知

| 功能 | 需求 |
|---|---|
| 對話、網頁、檔案 | Android 11 以上 |
| 操作手機上的 App | Android 12 以上，建議 Android 14 以上 |
| Linux 沙盒 | arm64 手機 |

- **為什麼不在 Google Play**：Google Play 的政策禁止 App 用無障礙服務讓 AI 自主規劃並操作其他 App。這是本 App 的核心功能，所以只提供 APK。
- 從網頁下載安裝時，Android 可能顯示安全警告；開啟無障礙權限前，可能要先到「應用程式資訊 › 更多 › 允許受限制的設定」。
- 開啟「進階保護」的手機無法使用操作 App 的功能。
- 第一次使用：到「設定 › 模型」選服務商並輸入 API Key，或用 ChatGPT、OpenRouter、xAI 帳號登入；要操作 App，再照「設定 › 設定手機操作」配對一次無線偵錯。

## 隱私與安全

- 渥屋科技沒有為這個 App 架設伺服器，也不收集你的資料。你說的話、螢幕內容和截圖，只會送到你自己設定的模型服務商。
- API Key 和記憶加密存在手機上；對話與執行紀錄留在手機裡；檢查更新只連線 GitHub。
- 自動操作第三方 App 或網站可能違反它們的服務條款（例如 LINE、蝦皮都禁止機器人操作），帳號風險由使用者自行承擔。重要的事請用詢問模式，並檢查結果。
- 本版本拿掉了中國廠商的模型預設、微信通道和豆包語音。

## 原始碼與授權

- 授權：[Apache-2.0](../LICENSE)，著作權聲明見 [NOTICE](../NOTICE)；第三方元件見 [licenses/THIRD_PARTY_NOTICES.md](../licenses/THIRD_PARTY_NOTICES.md)。
- APK 內含 GPL／LGPL 元件（PRoot、talloc、Alpine Linux 套件）。每個版本的 Release 頁都會附上對應的原始碼包。
- 跟上游 Mika 的差異、同步方式：[docs-woowtech/FORK.md](../docs-woowtech/FORK.md)。根目錄的 [README.md](../README.md) 和 `docs/` 是上游 Mika 的原文。

## 聯絡

- 問題回報：[GitHub Issues](https://github.com/WOOWTECH/woowtech_mika_smart_app/issues)
- 客服信箱：woowtech@designsmart.com.tw
- 官網：https://aiot.woowtech.io/

---

## English

**woowtech agent** is an AI assistant for Android phones: say what you need and it works your apps and the web on a hidden background screen until the job is done. It is maintained and distributed by [WOOW TECH CO., LTD.](https://aiot.woowtech.io/) (Taiwan) and based on the open-source project [Mika](https://github.com/wangzan101/Mika) (Apache-2.0); it is not affiliated with or endorsed by the Mika author.

- **Download**: APKs only, from this repository's [Releases](https://github.com/WOOWTECH/woowtech_mika_smart_app/releases) (first release in preparation). Google Play does not allow apps that use the Accessibility API to let an AI plan and operate other apps, which is the core of this app.
- **Differences from Mika**: WOOWTECH brand and update channel; English and Traditional Chinese UI; Taiwan app knowledge (LINE, Shopee, momo, PChome, foodpanda, woowtech aiot); China-based model presets, the WeChat channel and Doubao speech removed. Details: [docs-woowtech/FORK.md](../docs-woowtech/FORK.md).
- **Privacy**: WOOW TECH runs no servers for this app and collects no data; what you send goes only to the model provider you choose.
- **License**: Apache-2.0 ([LICENSE](../LICENSE), [NOTICE](../NOTICE)). GPL/LGPL components (PRoot, talloc, Alpine packages) ship with their corresponding source on every release page.
- **Contact**: [issues](https://github.com/WOOWTECH/woowtech_mika_smart_app/issues) · woowtech@designsmart.com.tw
