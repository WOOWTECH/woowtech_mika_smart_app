# Google Play asset inventory — io.woowtech.assistant

Prepared 2026-11-12 from existing Woowtech artwork and genuine Play-edition app captures. These files are candidates for the Play listing and foreground-service declarations; review them against the final signed AAB before upload. No simulated app UI was used.

## Existing artwork reviewed

| Source | Finding | Store use |
| --- | --- | --- |
| `app/src/woowtech/res/drawable/woow_launcher_foreground.xml` | Ten-path official WOOW symbol, brand blue `#6183FC`. | Source for both assets below. |
| `app/src/woowtech/res/mipmap-anydpi-v26/ic_launcher.xml`, `app/src/woowtech/res/values/colors_woowtech.xml` | Adaptive icon on charcoal `#212121`; Android resource XML, not directly uploadable. | Color and placement reference for the Play icon. |
| `app/src/woowtech/res/drawable-nodpi/mika_launcher_art.xml` | Full-bleed Woowtech splash artwork using the same symbol. | Placement reference; no upload of an Android vector XML. |
| `app/src/main/res/drawable-nodpi/mika_launcher_art.png`, `docs/media/logo.png`, `tools/mika/scripts/mika_desk/mika-logo.png` | Upstream Mika artwork. | Excluded from Woowtech Play assets. |
| `docs/media/job-greet.jpg`, `docs/media/food-order.jpg`, `docs/media/music-vip.jpg` | Earlier direct-edition examples, including functionality outside the Play scope. | Excluded from Play screenshots. |

No feature graphic or Play-edition screenshots were present before this asset work.

## Prepared upload files

| File | Format and size | Alt text draft |
| --- | --- | --- |
| `icon-512.png` | 512 × 512, 8-bit RGBA PNG (32-bit), embedded sRGB, under 1024 KB. Full-square background; no pre-rounded corners or shadow. | Blue WOOW symbol on a charcoal square. |
| `feature-graphic-1024x500.jpg` | 1024 × 500, JPEG, 24-bit RGB, embedded sRGB. | Woowtech agent name and its AI chat, voice, browser and memory features on a blue-charcoal background. |
| `screenshot-en-01-welcome.png`, `screenshot-zh-02-welcome.png` | Genuine Android 36 AAB-derived install, English and Traditional Chinese. | Welcome screen with chat, voice, browser and memory. |
| `screenshot-en-02-model-setup.png`, `screenshot-zh-03-model-setup.png` | Genuine Android 36 AAB-derived install, English and Traditional Chinese. | Model setup shows ChatGPT and the three official API providers. |
| `screenshot-zh-01-settings.png` | Genuine POCO Play Debug capture. | Settings screen with connected model, memory and privacy-policy entry. |
| `fgs-task-demo-redacted.mp4` | Genuine user-started AI task recording, notification body redacted. | Foreground task progress and user-visible notification. |
| `fgs-chatgpt-signin-demo.mp4` | Genuine Android 36 AAB-derived install recording. | ChatGPT sign-in starts from the app, opens the browser and shows the foreground notification with a Cancel control. |

`icon.svg` and `feature-graphic.svg` are editable source files, not Play upload files. They use the ten path shapes and colors already present in the Android brand vector. The graphic is promotional artwork, not an app screenshot. The English text matches `PLAY_STORE_LISTING_DRAFT.md`; a Traditional Chinese graphic should be rendered from the same source if a localized graphic is supplied.

The render uses `rsvg-convert`; the icon PNG was converted to RGBA with `ffmpeg` and tagged with the system sRGB ICC profile using `sips`. The JPEG feature graphic was converted from a rendered PNG with `sips`. Re-render and check profile, dimensions, alpha, and file size after source edits.

## Screenshot and video follow-up

The welcome and model-setup captures were refreshed after installing split APKs generated from the signed Play AAB. All screenshots were converted from Android's RGBA capture format to 24-bit RGB PNG; decoded RGB pixels were compared before and after conversion and matched exactly. The settings image predates the final AAB but shows the same Play package on POCO. Add genuine chat, browser and memory captures from the **Play-installed** release during internal testing if the listing needs more coverage. Use test data and no personal identifiers. Do not present a mock-up, an older `io.woowtech.agent` screen, cross-app automation, remote sync, or an unfinished feature as a Play screenshot. The ChatGPT sign-in video shows the Cancel control but ends before the user taps it; the cancellation was tested separately. Confirm whether this video satisfies the Console declaration before submission.

The [official Play preview-asset guidance](https://support.google.com/googleplay/android-developer/answer/9866151?hl=en) currently requires at least two screenshots across device types, JPEG or 24-bit PNG without alpha, a minimum dimension of 320 px, a maximum dimension of 3840 px, and a longest dimension at most twice the shortest. For stronger app placement it recommends at least four screenshots at 1080 px or greater, in 9:16 portrait or 16:9 landscape. Capture an appropriate device resolution or crop only unneeded system edges from a genuine capture; keep the app UI itself authentic. Add alt text for each final image. If a final capture is edited for privacy or system-bar cleanup, retain the unedited original locally for comparison.

The same [Play guidance](https://support.google.com/googleplay/android-developer/answer/9866151?hl=en) requires a 512 × 512 32-bit PNG icon (max 1024 KB) and a 1024 × 500 JPEG or 24-bit PNG feature graphic. The [icon specification](https://developer.android.com/distribute/google-play/resources/icon-design-specifications) calls for sRGB, a full square, and no pre-applied rounded corners or outer shadow.
