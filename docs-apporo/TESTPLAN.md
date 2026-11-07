# Apporo Assistant acceptance matrix

This matrix is for the Apporo package, not evidence copied from the WOOWTECH build. A check is only PASS when its own artifact or observation is recorded.

| Area | Check | Evidence / expected result |
| --- | --- | --- |
| Source | XML and string arguments | `python3 apporo/tools/check.py`; no unknown keys, placeholder mismatches or product-name leaks |
| Source | Shared brand regression | WOOWTECH source checks remain green |
| Source | CLI contracts | Existing brands and Apporo detection all pass |
| Build | Shared Kotlin / Android tests | Apporo CI and existing CI reports |
| Build | Debug and release APK | Apporo workflow artifacts; release is unsigned |
| Build | Packaged identity | `python3 apporo/tools/check-apk.py APK`; package and every app label are Apporo |
| Install | Coexistence | Apporo and WOOWTECH both installed, separate settings / data / helper identities |
| Language | First launch | English on a Traditional Chinese system; no previous preference |
| Language | User choice persists | Choose Traditional Chinese, restart; choose system, restart; neither reverts to English |
| Appearance | Light and dark | Inspect onboarding, chat, drawer, model settings, notification actions, licenses and About |
| Appearance | Accessibility | Large font / display scale; action names are understandable and nothing overlaps |
| Model | Custom provider | User enters key privately; test connection and complete a simple text task |
| Model | Vision and roles | Confirm correct model selection and observe a screenshot task |
| Phone | Setup and pairing | Complete actual wireless or USB flow; permission denial remains recoverable |
| Phone | Reboot | Helper restores only with the enabled recovery setting and proper permissions |
| Phone | Uninstall | Apporo helper exits; WOOWTECH package and helper remain unaffected |
| Apps | Apporo aiot | Inspect a user-selected test room; no device changes in initial test |
| Apps | Apporo platform | Read assigned tasks using a test account; do not modify records |
| Apps | Apporo smart | Show available paired sessions; no task sent until selected |
| Login | User handoff | Actual target server / app login is shown; no credentials enter logs or reports |
| Browser | Research | Read two sources, compare facts, preserve source links |
| Files | Compute and export | Calculate known values, export to Apporo Assistant Downloads folder, reopen file |
| Memory | Learn and remove | Confirm a harmless preference, observe reuse, remove it |
| Schedule | Permissions | Test granted and denied exact-alarm access; report actual due and delivery times |
| Notify | Background approval | Existing result notification remains; approval banner appears and is actionable |
| Notify | Reminder | Capture event log and screen recording; device audio still needs physical testing |
| Gate | Decline | Local fixture only; decline produces zero final submissions and correct step label |
| Gate | Approve once | Local fixture only; one approval results in exactly one final submission |
| Gate | Payment | Local fixture only; payment requires user takeover, not a model click |
| Remote | CLI and MCP | Explicit Apporo package; inspect response identity and request time on phone |
| Remote | Cancel and revoke | Cancel task; disable access; old token no longer authorizes calls |
| Update | Channel isolation | Never offer a WOOWTECH APK; reserved Apporo endpoint is not yet a release |
| Update | Signed upgrade | After channel / signing provision: preserve data during Apporo-to-Apporo upgrade |
| Cleanup | Test environment | Stop fake shop, remove forwards, restore IME, remove test data, confirm host state |

Device acceptance is in progress; see [2026-11-08 emulator evidence and limitations](EMULATOR-20261108.zh-TW.md). Several cases passed, while real Apporo integrations and complete UI coverage remain unverified. Do not infer results from the source contract checks. Use screenshots and dumpsys during agent tasks; uiautomator dumps can interrupt the accessibility service. Real Apporo servers and credentials must be selected by the user; do not operate production equipment as a test fixture.

The [second emulator wave](EMULATOR-WAVE2-20261108.zh-TW.md) covers all three installed Apporo products' connection entry points, the initial capsule position, English UI inspection and the background approval banner. Authenticated data and paired computer sessions still require an owner-selected server. Use MAIN + LAUNCHER when starting the aiot activity on Android 16, and explicitly use `adb shell input -d 0` for the main display. Fill credentials by verified password-field identity, never by coordinates retained across keyboard/layout changes; do not dump an unverified form containing secrets.
