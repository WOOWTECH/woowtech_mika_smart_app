# Play edition: iOS parity follow-ups (2026-11-28)

The owner accepted every recommendation of the iOS parity form on 2026-11-28 ("都照建議去做"). The Direct edition took them in PR #68 (woow.30). The same evening the owner decided that the store versions follow too:

- Android Play edition: this branch.
- iOS App Store edition: the iOS line.

Each is shown to the owner before it goes to review. The owner also decided that on a phone set to Simplified Chinese, the Play edition shows Traditional Chinese, like iOS and the Direct edition. This overrides the 11/13 rule that the Play edition is always English there.

| Item | Before | Now |
| --- | --- | --- |
| Q14 Phone set to Simplified Chinese or Cantonese | English | Traditional Chinese (the first phone language with a UI decides) |
| Q24 Punctuation | 231 Traditional Chinese strings with half-width `, : ; ? ! ( )` | Full-width `，：；？！（）` |
| q6 "看看" on a learning note | Memory page on 技能 | Memory page on 待確認, where the skill draft is |
| k4 Dialog buttons | Only the label pressable | The whole capsule pressable |
| k9 Transparent avatar on 名稱與圖示 | Black background | White background |

Two items do not apply here:

- Q18: the Play edition has no woowtechbot services.
- k13: the Play edition has no xAI preset.

## How

The code is the same as the Direct edition's. See `docs-woowtech/woowtechbot/IOS-PARITY-FOLLOWUPS.md` on main.

- **Q14:**
  - `brand.properties` sets `ui.chinese=zh-Hant-TW`.
  - `app/brand.gradle.kts` copies the brand's final Traditional strings into `values-b+zh+Hans` and `values-b+yue`. This applies to the `woowtech` flavor (io.woowtech.assistant) only. Apporo Play is unchanged.
  - The woowtech `resourceConfigurations` gains `b+zh+Hans` and `b+yue`.
  - `AppLanguage.followSystem` gives the app's screens `zh-Hant-TW`.
  - `woowtech/tools/brand-check.sh` accepts the two copies, and checks that their labels are 渥屋助理.
- **Q24:** the iOS line's rule (`q24-scan.py`), applied by script.
  - Kept half-width on purpose: the literal 「使用者:密碼@」 in `net_proxy_hint` and `net_proxy_invalid`. It is the `user:password@` the user types before the proxy host.
  - Also left untouched: format codes, entities, tags, URLs, numbers and English-only text.
- **k4:** `MikaDialog`'s button slot gets the capsule's size (`propagateMinConstraints`). The two-button sign-in dialog gives each button the full width.
- **k9:** `botUiImportAvatar` draws the picture on white before the JPEG is saved.

## Tests

- **Unit tests:**
  - `StringResourcesTest.followSystemShowsTraditionalChineseForChinesePhones`
  - `BrandValuesTest`, which checks `ui.chinese`
  - `ConfirmationNotificationCopyTest`, which now expects full-width colons
- **Device tests:** the same code is tested on the Direct edition's GitHub emulators (API 35 and 36): `BotChineseUiDeviceTest` and `BotParityFollowupsDeviceTest`. This branch has no emulator workflow.
