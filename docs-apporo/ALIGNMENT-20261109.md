# Apporo Assistant apporo.4 alignment

Apporo Assistant `0.1.37-apporo.4` / `3804` adds the shared accessibility and speech fixes tested by the WOOWTECH work on 2026-11-09. It retains Apporo's English default, visual identity, package, data directory, release certificate and separate update channel.

## Source scope

The base is Apporo's public apporo.3 source `ef0fcf07`, which already includes woow.4. The additional WOOWTECH work is integrated from `28c07dd4` (the `fix/accessibility-install-guide` branch), including implementation commits `f1b94ba7` and `b1593e39`, voice regression tests `dec944b2`, and the associated evidence. That work was locally validated, but was not yet a new public WOOWTECH release when this integration began.

| Area | apporo.4 behavior |
| --- | --- |
| Accessibility setup | Settings → Phone operations provides Pixel and Xiaomi/POCO App info instructions even when Android's restriction probe misses the OEM restriction. Initial onboarding shows the help when its restriction probe reports a restriction. Opening App info or allowing restricted settings does not mark the accessibility service as running. |
| Speech fallback | If the on-device recognizer rejects the language before producing text, the existing one-time fallback explicitly clears the offline preference. The system's selected recognizer decides whether online recognition is available. |
| Speech error | Language errors no longer claim that the entire recognition service is absent. Guidance distinguishes microphone permission from language support and explicitly selected transcription providers. |
| Speech wording | Built-in recognition is no longer labelled offline solely because the device exposes an on-device recognizer. Offline availability depends on the language pack. |
| Data and provider choices | No model change, paid-provider switch, permission auto-grant, data clearing or automatic message submission is introduced. |
| Earlier woow.4 fixes | Notification amounts, complete approval-card navigation, exact-alarm permission split, localized channel names, helper lifecycle and payment gates remain in the shared engine. |

The shared files `SystemSpeech.kt`, `SpeechResolver.kt`, `VoiceHold.kt` and `AlertGroup.kt` match the integrated WOOWTECH source. `AccessibilityInstallHelp.kt` additionally allows button labels to wrap, consistent with Apporo's larger-font fixes. Apporo's subsequent screen, capsule, form and branding fixes remain present; the older WOOWTECH branch was merged rather than substituted for the Apporo tree.

## Deliberately outside this release

PR #11's research-progress/task-budget proposal remains separate. In particular, this release does **not** introduce a fixed 15-minute / 2-million-token task cutoff or a new model-request deadline. Original-app real-phone comparison has not established a fair three-way long-context benchmark. Those proposed limits require the separate evaluation requested by the user.

The upstream v0.1.38 preparation branch is also separate. This release continues to identify its upstream base as 0.1.37.

## Validation and limits

The WOOWTECH POCO test report records successful built-in speech fallback, release-to-fill, repeated dictation, cancellation preserving the draft, retry after cancellation, and manual send with an assistant response. This is shared-engine evidence, **not an Apporo-branded real-microphone test**. See [the source report](../docs-woowtech/poco-install-and-speech-test.md).

Apporo's dedicated cloud Android tests use a fake speech source to verify the real branded Compose UI, English setup copy, draft preservation and absence of automatic submission. They do not measure Google recognition accuracy, physical microphone behavior, speaker volume, or paid model latency. The existing API 30/32/35/36 startup jobs remain startup checks. Actual run results belong in the release notes and provenance, not assumptions based on source similarity.

On the POCO Android 15 phone, Play Protect blocked the public apporo.3 APK after scanning it. The corresponding public WOOWTECH APK was also blocked in that branch's test. Signed APK integrity and matching permissions do not establish the reason or prove a false positive. The apporo.4 release does not claim to resolve that verdict. No disabling of Play Protect or replacement signing identity is part of this release. If an installation is blocked, retain the installed app and its data; do not uninstall to force an update.

## Updating

Public apporo.3 and apporo.4 use `com.apporo.assistant` and the same dedicated Apporo release certificate. Version code increases from 3803 to 3804. Use the APK offered by Apporo's own [release channel](https://github.com/WOOWTECH/apporo-assistant-releases/releases/latest); WOOWTECH and Mika APKs are different applications. Internal test-certificate installations cannot be updated by the public certificate.

Publish the arm64 and universal APKs together with corresponding GPL component sources, checksums, the public certificate and build provenance. Universal availability does not imply that the arm64-only sandbox works on every architecture.
