# Apporo Assistant acceptance matrix

This matrix is for the Apporo package, not evidence copied from the WOOWTECH build. A check is only PASS when its own artifact or observation is recorded.

The [cloud startup checks](../apporo/tools/startup-smoke.md) use fresh AOSP x86_64 images on API 30/32/35/36. Their scope is installation, the English welcome screen, force-stop/relaunch and startup crash/ANR detection. Each run must retain its own screenshots and receipt; this does not replace the arm64 assistant tasks, permission flows or sandbox acceptance below.

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
| Shopping | momo, Shopee and PChome | Run [shopping acceptance](SHOPPING-ACCEPTANCE.md); independently verify visible prices and distinguish blocked searches from successful handoffs |
| Files | Compute and export | Calculate known values, export to Apporo Assistant Downloads folder, reopen file |
| Memory | Learn and remove | Confirm a harmless preference, observe reuse, remove it |
| Schedule | Permissions | On Android 13+ direct APK, verify USE_EXACT_ALARM on fresh install and upgrade; test denial/regrant of SCHEDULE_EXACT_ALARM on Android 12/12L separately. Report due and delivery times |
| Notify | Background approval | Existing result notification remains; approval banner appears. View opens the corresponding task without approval, including when another conversation is shown; full-card approval remains explicit. Decline is available directly. Check enlarged fonts and lockscreen authentication |
| Notify | Reminder | Capture event log and screen recording; device audio still needs physical testing |
| Gate | Decline | Local fixture only; decline produces zero final submissions and correct step label |
| Gate | Approve once | Local fixture only; one approval results in exactly one final submission |
| Gate | Payment | Local fixture only; payment requires user takeover, not a model click |
| Remote | CLI and MCP | Explicit Apporo package; inspect response identity and request time on phone |
| Remote | Cancel and revoke | Cancel task; disable access; old token no longer authorizes calls |
| Update | Channel isolation | Never offer a WOOWTECH APK; reserved Apporo endpoint is not yet a release |
| Update | Signed upgrade | Same test certificate: preserve data during Apporo-to-Apporo upgrade; distinguish USB helper recovery from data retention. Official update-channel acceptance remains separate |
| Cleanup | Test environment | Stop fake shop, remove forwards, restore IME, remove test data, confirm host state |

Recorded device acceptance and remaining limits: see [wave6 results](EMULATOR-WAVE6-20261108.zh-TW.md), [wave5 results](EMULATOR-WAVE5-20261108.zh-TW.md), [wave4 results](EMULATOR-WAVE4-20261108.zh-TW.md) and [baseline alignment](PARITY-WOOW4-20261108.zh-TW.md). The [remaining matrix](WAVE6-REMAINING-PLAN.zh-TW.md) separates English/Traditional Chinese and light/dark screen states, outbound MCP, voice entry and form validation; it is a plan, not a passing test report. Actual Assistant tasks for aiot, smart, momo Android and PChome desktop passed within the documented visibility limits. Platform and Shopee product access remain blocked. Screen-state coverage and targeted larger-font regressions are recorded separately from complete functional, physical-device and other-version acceptance. Do not infer results from the source contract checks. Use screenshots and dumpsys during agent tasks; uiautomator dumps can interrupt the accessibility service. The user authorized reusing existing WOOWTECH test data and environments. Use the established demo services below; do not operate production equipment as a test fixture.

The [second emulator wave](EMULATOR-WAVE2-20261108.zh-TW.md) covers all three installed Apporo products' connection entry points, the initial capsule position, English UI inspection and the background approval banner. The [service reuse checks](SERVICE-REUSE-20261108.zh-TW.md) establish usable aiot and smart demo backends; these API results do not establish Android UI or Assistant task acceptance. Use MAIN + LAUNCHER when starting the aiot activity on Android 16, and explicitly use `adb shell input -d 0` for the main display. Fill credentials by verified password-field identity, never by coordinates retained across keyboard/layout changes; do not dump an unverified form containing secrets.

| Integration | Existing fixture | Next device acceptance |
| --- | --- | --- |
| aiot | Established family demo; backend login and entity read passed | Wave4 authenticated and autonomously read Overview; temporary registration cleaned up. Further device-control tests require an explicit demo target and reversible expected state. |
| platform | Existing demo111 review server/database; old review account returns AccessDenied | Obtain a working replacement credential through a private file, complete app sign-in, read permitted records. Do not report an empty result as successful authentication. |
| smart | Existing Apporo review demo and protected pairing link; relay project/agent listing passed | Wave4 paired and autonomously read projects and README; pending requests preserved and local connection removed. Counts may change; take a new backend snapshot for further comparisons. |

Keep credentials, refresh tokens and pairing links out of evidence and repository files. Revoke temporary aiot tokens after backend checks. Retain the shared smart review pairing identity. Use the emulator only after the existing owner releases the heavy slot; do not share UI input between runs.
