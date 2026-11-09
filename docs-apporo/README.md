# Apporo Assistant

An English-first Android assistant for your spaces, your work and your next step, built on Mika and the WOOWTECH shared engine.

- [Research and capability map (繁體中文)](RESEARCH.zh-TW.md)
- [Connect a computer](agent-quickstart.en.md)
- [MCP setup](mcp.en.md)
- [WOOWTECH woow.4 alignment](PARITY-WOOW4-20261108.zh-TW.md)
- [apporo.4 accessibility and speech alignment](ALIGNMENT-20261109.md)
- [Emulator wave5: accessibility, system panels, shopping quantities and remote control](EMULATOR-WAVE5-20261108.zh-TW.md)
- [Emulator wave6: remaining screens and notification regression](EMULATOR-WAVE6-20261108.zh-TW.md) (recorded scope and remaining limits)
- [Remaining emulator acceptance matrix](WAVE6-REMAINING-PLAN.zh-TW.md) (plan, not test results)
- [Cloud Android startup checks](../apporo/tools/startup-smoke.md) (API 30/32/35/36, startup scope only)
- [Emulator wave4: upgrade, notifications, shopping and product integrations](EMULATOR-WAVE4-20261108.zh-TW.md)

Build: `./gradlew :app:assembleApporoDebug :app:assembleApporoRelease`.
Package: `com.apporo.assistant`. CI release APKs are unsigned; public downloads are signed with the dedicated Apporo Assistant release certificate. [Download the latest public release](https://github.com/WOOWTECH/apporo-assistant-releases/releases/latest). Keep the same package and release certificate when updating to preserve app data.

The Apporo aiot, platform and smart examples require those apps, their configured servers and the user's access. This development branch does not provision them or add native building-management services. English is selected on first launch; Traditional Chinese and follow-system remain available.

Source licensing remains Apache-2.0 with upstream attribution. Bundled components retain their own licenses; corresponding GPL sources and checksums are attached to each public release in the independent Apporo update channel.

Product decisions confirmed by the owner on 2026-11-08: serve both space/workplace management and everyday tasks; share the engine with an independently installed brand; default to English with optional Traditional Chinese; name Apporo Assistant, package `com.apporo.assistant`. The emulator reports distinguish Assistant tasks from manual product checks. Wave4 covers apporo.2 upgrades, notifications, shopping, smart and aiot. Wave5 covers apporo.3 accessibility and system-panel fixes, shopping quantities, coexistence and remote-control acceptance. Notifications open the corresponding full decision card for approval, and enlarged decision cards temporarily hide the live preview. Wave6 adds English/Traditional Chinese and light/dark screen-state checks, larger-font form fixes, notification navigation, outbound HTTP/stdio MCP execution and fresh permission flows. Platform login, Shopee product access and physical-device audio remain unverified.

Since apporo.2, the direct APK matches woow.4's exact-alarm permission split: Android 13+ uses USE_EXACT_ALARM, while Android 12/12L retain SCHEDULE_EXACT_ALARM. This is not a Google Play release configuration approval. Review that distribution channel's requirements before submitting to a store.
