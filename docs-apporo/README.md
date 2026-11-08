# Apporo Assistant

An English-first Android assistant for your spaces, your work and your next step, built on Mika and the WOOWTECH shared engine.

- [Research and capability map (繁體中文)](RESEARCH.zh-TW.md)
- [Connect a computer](agent-quickstart.en.md)
- [MCP setup](mcp.en.md)
- [WOOWTECH woow.4 alignment](PARITY-WOOW4-20261108.zh-TW.md)
- [Emulator wave4: upgrade, notifications, shopping and product integrations](EMULATOR-WAVE4-20261108.zh-TW.md)

Build: `./gradlew :app:assembleApporoDebug :app:assembleApporoRelease`.
Package: `com.apporo.assistant`. Release APKs are unsigned; use a separately provisioned Apporo Assistant signing key before distribution. Never reuse another product's release credentials.

The Apporo aiot, platform and smart examples require those apps, their configured servers and the user's access. This development branch does not provision them or add native building-management services. English is selected on first launch; Traditional Chinese and follow-system remain available.

Source licensing remains Apache-2.0 with upstream attribution. Bundled components retain their own licenses; distribute corresponding GPL sources with a release. The reserved Apporo update channel has not been provisioned yet.

Product decisions confirmed by the owner on 2026-11-08: serve both space/workplace management and everyday tasks; share the engine with an independently installed brand; default to English with optional Traditional Chinese; name Apporo Assistant, package `com.apporo.assistant`. Four emulator rounds distinguish Assistant tasks from manual product checks. The latest round covers apporo.2 upgrades, notifications, shopping, smart and aiot; platform login, Shopee product access and physical-device audio remain unverified.

The apporo.2 direct APK matches woow.4's exact-alarm permission split: Android 13+ uses USE_EXACT_ALARM, while Android 12/12L retain SCHEDULE_EXACT_ALARM. This is not a Google Play release configuration approval. Review that distribution channel's requirements before submitting to a store.
