# Google Play asset inventory — io.woowtech.assistant

Prepared 2026-11-12 from existing Woowtech artwork. These files are local candidates for the Play listing; the final release and localized listing should be reviewed before upload. No screenshots or simulated app UI were made.

## Existing artwork reviewed

| Source | Finding | Store use |
| --- | --- | --- |
| `app/src/woowtech/res/drawable/woow_launcher_foreground.xml` | Ten-path official WOOW symbol, brand blue `#6183FC`. | Source for both assets below. |
| `app/src/woowtech/res/mipmap-anydpi-v26/ic_launcher.xml`, `app/src/woowtech/res/values/colors_woowtech.xml` | Adaptive icon on charcoal `#212121`; Android resource XML, not directly uploadable. | Color and placement reference for the Play icon. |
| `app/src/woowtech/res/drawable-nodpi/mika_launcher_art.xml` | Full-bleed Woowtech splash artwork using the same symbol. | Placement reference; no upload of an Android vector XML. |
| `app/src/main/res/drawable-nodpi/mika_launcher_art.png`, `docs/media/logo.png`, `tools/mika/scripts/mika_desk/mika-logo.png` | Upstream Mika artwork. | Excluded from Woowtech Play assets. |
| `docs/media/job-greet.jpg`, `docs/media/food-order.jpg`, `docs/media/music-vip.jpg` | Earlier direct-edition examples, including functionality outside the Play scope. | Excluded from Play screenshots. |

No existing feature graphic or final-build Woowtech Play screenshots were found in the repository's tracked image files.

## Prepared upload files

| File | Format and size | Alt text draft |
| --- | --- | --- |
| `icon-512.png` | 512 × 512, 8-bit RGBA PNG (32-bit), embedded sRGB, under 1024 KB. Full-square background; no pre-rounded corners or shadow. | Blue WOOW symbol on a charcoal square. |
| `feature-graphic-1024x500.jpg` | 1024 × 500, JPEG, 24-bit RGB, embedded sRGB. | Woowtech agent name and its AI chat, voice, browser and memory features on a blue-charcoal background. |

`icon.svg` and `feature-graphic.svg` are editable source files, not Play upload files. They use the ten path shapes and colors already present in the Android brand vector. The graphic is promotional artwork, not an app screenshot. The English text matches `PLAY_STORE_LISTING_DRAFT.md`; a Traditional Chinese graphic should be rendered from the same source if a localized graphic is supplied.

The render uses `rsvg-convert`; the icon PNG was converted to RGBA with `ffmpeg` and tagged with the system sRGB ICC profile using `sips`. The JPEG feature graphic was converted from a rendered PNG with `sips`. Re-render and check profile, dimensions, alpha, and file size after source edits.

## Screenshot capture deferred

Capture from the **final installed `io.woowtech.assistant` release build**, after the model, voice, browser, memory, and disclosure flows have been verified. Use real in-app views with test data and no personal identifiers. Suggested sequence: model setup, a completed chat, the user-operated browser, and saved memory. Capture separately in English and Traditional Chinese where listing localization is used. Do not present a mock-up, an older `io.woowtech.agent` screen, cross-app automation, remote sync, or an unfinished feature as a Play screenshot.

The [official Play preview-asset guidance](https://support.google.com/googleplay/android-developer/answer/9866151?hl=en) currently requires at least two screenshots across device types, JPEG or 24-bit PNG without alpha, a minimum dimension of 320 px, a maximum dimension of 3840 px, and a longest dimension at most twice the shortest. For stronger app placement it recommends at least four screenshots at 1080 px or greater, in 9:16 portrait or 16:9 landscape. Capture an appropriate device resolution or crop only unneeded system edges from a genuine capture; keep the app UI itself authentic. Add alt text for each final image. If a final capture is edited for privacy or system-bar cleanup, retain the unedited original locally for comparison.

The same [Play guidance](https://support.google.com/googleplay/android-developer/answer/9866151?hl=en) requires a 512 × 512 32-bit PNG icon (max 1024 KB) and a 1024 × 500 JPEG or 24-bit PNG feature graphic. The [icon specification](https://developer.android.com/distribute/google-play/resources/icon-design-specifications) calls for sRGB, a full square, and no pre-applied rounded corners or outer shadow.
