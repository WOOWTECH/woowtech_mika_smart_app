# iOS parity follow-ups on Android (2026-11-28)

The iOS line compared the iOS bot app with Android woow.27 screen by screen and listed 67 decisions in a form (artifact
HoNFBTNrqgLNoR2crLZkpB). On 2026-11-28 the owner said "都照建議去做": every recommendation is taken. Seven of them change
Android; the iOS line sent the iOS details for each (iOS→Android #5) and Android follows them.

| Item | Android before | Android now | Where |
| --- | --- | --- | --- |
| Q14 Phone set to Simplified Chinese | English (upstream's Simplified UI is not shipped) | Traditional Chinese, as on iOS | `app/brand.gradle.kts`, `AppLanguage.followSystem`, `brand.properties` `ui.chinese` |
| Q18 Welcome page and model setup | Shown on every start until a main model is set | Not shown when at least one woowtechbot service is saved | `Onboarding.start` |
| Q24 Punctuation | 235 Traditional Chinese strings used `, : ; ? ! ( )` | Full-width `，：；？！（）` | `values-b+zh+Hant` |
| q6 "看看" on a learning note | Opened the memory page on 技能 | Opens it on 待確認, where the new skill draft is | `MainActivity` |
| k4 Dialog buttons | Only the label inside the capsule could be pressed | The whole capsule is the button | `MikaDialog` |
| k9 Transparent avatar | Saved as JPEG with a black background | Laid on white first, then saved | `botUiImportAvatar` |
| k13 xAI model name example | "例如 mistral-large-latest" | "例如 grok-4" | `ProviderPresets.exampleKind` |

## Q14: which language the app shows

This applies only when the app language is "跟隨系統". The phone's languages are read in order, and the first one the app has a UI for decides:

- English: English.
- Chinese of any script or region (zh-Hant, zh-TW, zh-HK, zh-MO, zh-Hans, zh-CN, zh-SG, plain zh) and Cantonese (yue): Traditional Chinese.
- Other languages: skipped.
- No match at all: English.

| Phone languages | App shows |
| --- | --- |
| ja, zh-Hans | Traditional Chinese |
| fr | English |
| en, zh-Hans | English |

How it is done:

- **Build:** the final Traditional strings are copied into `values-b+zh+Hans` and `values-b+yue` of the woowtech flavor's generated resources.
  - The copy is built from `src/main/res`, then the generated brand strings, then `src/woowtech/res`, later ones winning.
  - So whatever the system shows by itself is Chinese too: the launcher name, notification channels and the accessibility service.
  - This matches the iOS app, which keeps Traditional strings in `zh-Hans.lproj`.
- **Runtime:** `AppLanguage.followSystem` sets the app's own screens, the overlay, texts outside the UI and the process default locale to `zh-Hant-TW`.
  - Library texts follow, including screen reader labels.
  - CJK glyphs, full-width punctuation and number formats also follow.
- **Android quirk:** once a WebView has loaded, Android counts the WebView's own languages as the app's.
  - For a list such as "ja, zh-Hans", text Android picks by itself can then be English, for example a notification built outside the app's screens.
  - The app's own screens still follow the rule above.
- **Not changed:** prompts, user data, model output, and the language list in settings (跟隨系統 / 繁體中文 / English).
  - No woowtech release ever offered Simplified Chinese, so there is no saved choice to migrate.

## Q18: welcome page

`Onboarding.start` is checked once when the app opens:

- **With at least one saved woowtechbot service:** the welcome page and model setup do not appear. The service can be paired by QR or added by hand, and whether it is reachable or signed in does not matter.
- **The phone-control guide:** still appears once, as before.
- **With no service:** the old rule applies. The welcome page appears when there is no main model and model setup was never finished.
- **Pairing during use:** the welcome page does not open then.
- **After removing every service:** the next start without a main model shows the welcome page again.

## Tests

- **Unit tests:**
  - `StringResourcesTest.followSystemShowsTraditionalChineseForChinesePhones`
  - `OnboardingTest.savedBotServiceSkipsWelcomeAndModel`
  - `ProviderPresetsTest.xaiPresetGivesTheGrokExample`, plus an xAI case in `ModelSetupViewModelTest`
  - `BrandValuesTest`, which checks that `ui.chinese` is set
- **Device tests** (GitHub emulator workflow `woowtechbot-device.yml`, API 35 and 36):
  - `BotChineseUiDeviceTest`: the APK resolves zh-Hans-CN, zh-CN, zh-SG, zh and yue-HK to the Traditional strings. `AppLanguage` gives the app's screens Traditional Chinese for these and for "ja, zh-Hans". It covers the brand's own strings, brand-renamed upstream strings, upstream strings and the woowtechbot screens' strings. English, French, Japanese and "en, zh-Hans" stay English.
  - `BotParityFollowupsDeviceTest`:
    - A transparent PNG avatar comes back as a 320 × 320 JPEG with white corners and its red centre.
    - Both dialog buttons are at least 44 dp × 100 dp, and a tap near the edge of each presses it.
- **Q24:** the iOS line's scanner (`q24-scan.py`) finds nothing left in either Traditional Chinese folder.
