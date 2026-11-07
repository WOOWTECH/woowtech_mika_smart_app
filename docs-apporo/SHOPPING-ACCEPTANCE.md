# Taiwan shopping acceptance

Run these cases with Apporo Assistant, using the same search terms as the WOOWTECH baseline. The older build's successful momo task is a comparison point, not an Apporo PASS. Keep the Assistant response in English and preserve original Chinese product names.

| ID | Route | Task | Acceptance |
| --- | --- | --- | --- |
| SHOP-01 | momo Android | Search 無線藍牙耳機 and read the first three results | Independently compare names, prices and advertisement labels with screenshots; handle update/tutorial prompts; do not add to cart. |
| SHOP-02 | momo web | Search 象印 保溫瓶 480ml | Record official page URL, visible first three results and observation time. |
| SHOP-03 | Shopee web | Same bottle search | Record visible results, or the actual login/challenge screen. Never invent prices when blocked. |
| SHOP-04 | Shopee Android | Same bottle search | Requires a verified arm64 APK. A 32-bit-only APK is an environment block, not an Assistant failure. |
| SHOP-05 | PChome web | Same bottle search | Record visible names/prices/variant details. |
| SHOP-06 | Comparison | Compare only successfully observed matching variants | Distinguish capacity, pack count, starting price, shipping and conditional discounts; explicitly identify missing information. |
| SHOP-07 | Handoff | Encounter login or verification | Stop and explain the actual screen; give the user the official URL if sign-in is needed. Never put credentials in evidence. |
| SHOP-08 | Knowledge | Inspect the task timeline | Record whether relevant shopping knowledge was used. The current app knowledge has empty `sites` associations; do not claim known web routes from it. |

Use this prompt template for web cases:

> Use your built-in browser to open {official site}. Search for 象印 保溫瓶 480ml and report the first three visible product names and prices in English, preserving the original product names. Mark sponsored results and any price conditions you can actually see. Do not sign in, add anything to a cart, place an order or pay. If login or verification prevents reading results, stop and explain what you see. Do not fill missing prices from memory.

For SHOP-01, use the momo Android app and replace the query with 無線藍牙耳機. For comparison, use only results collected in this run; old prices are not current observations.

Capture screenshot + task timeline + final answer + official URL + installed version. During active agent work or handoff cards, use screenshots/dumpsys rather than uiautomator. A login/challenge handoff can pass SHOP-07 while the underlying product search remains BLOCKED. HTTP 200 alone never passes a shopping case.

## Preparation and preflight — 2026-11-08

Evidence directory: `~/.local/share/apporo-assistant/test-evidence/shopping-20261108/`.

- The momo baseline XAPK was downloaded again from the previously recorded source because only the old verification receipt remained locally. It is version 2502.2.0, not a claim about the latest store version. See `momo-artifact.json` for archive and split checks. Installation and Apporo task execution are pending.
- The previous Shopee receipt documents an armeabi-v7a-only artifact. It is unsuitable for this arm64 emulator. No new compatible APK has been verified. The [official download guidance](https://help.shopee.tw/portal/4/article/137034) points Android users to Google Play and also lists Huawei AppGallery; this emulator has no Play Store.
- `web-preflight.json`: this Mac's HTTP client received 403 from momo, 200 from Shopee search, and 200 from PChome search (with a canonical-path redirect). These are HTTP observations, not JavaScript rendering or product-price verification. A separate web fetch could read momo's search-page shell, illustrating that access differs by client.
- None of SHOP-01 through SHOP-08 is marked PASS in this preparation run. The emulator remains owned by `release-woowtech-agent-followup-1108`; do not install or send UI input into that run. Assistant model execution also needs a replacement for the previously exposed key.
