# Preview 06 Android Direct alignment

Scope: WOOWTECH Direct Android only. Preserve existing native tools, isolated service profiles and push ledger. Backend events and model requests remain HOLD during UI QA.

## Reference and research

Design worktree `assistant-woowtechbot-design-20261126`, canonical preview06 commit `bc65d7b2`, conversation interaction reference `23809aed`. The outer preview/device frame is not product UI. Remote services retain their website, including original bot-specific themes and all website controls.

Craft Anything CLI 0.6.1 was used for a static app map and a 390×844 browser walkthrough of the local integration preview. Static-map evidence: `ev_12a9a04ecb5954dcf1e453ab421f2207a5ba8ee5dc1493c5e4eb4b88fc438cfa`. Craft is a research/validation tool, not an Android runtime dependency. Preview has incomplete light-mode treatment, so native and remote light-mode behavior is independently tested on the phone.

## Implementation

- Direct-brand midnight/daylight palette across native surfaces, text, composer, sheets and dialogs; follow the existing System/Light/Dark setting. Other brand palettes are unchanged.
- Local history uses four circular top controls, per-conversation identity, search and shortcut menu. Existing tasks, tools, profile editor, attachments and conversation storage remain wired to real native features.
- Remote chat no longer gets an extra permanent native header. Add only Services and Notifications to the existing website sidebar slot. Native fallback controls remain for pairing/load failure or unsupported page layouts.
- Exact, gesture-gated, same-origin main-frame presentation actions; no native JavaScript interface and no cookie/storage/content reads in the injected script.
- Service picker and management sheet share native appearance. Cached WebViews retain their DOM while switching remote services within the activity. Process death/activity destruction remains subject to website draft persistence and existing safe history restoration; live DOM retention is not promised across process death.
- Push discovery exposes only safe per-service result categories. READY means identity/capability discovery, not a PUT ACK or delivery. Failed/stale/incomplete reconciliation ends in RETRY_REQUIRED with explicit retry, retaining ledger and consent. No 401/403/404 is treated as successful revocation, and no synthetic REGISTERED state is introduced.

## Validation so far

- Kotlin compilation and signed release assembly/lint passed for the initial candidate.
- `BotWorkspaceAppearanceTest`: 2 tests passed (origin/frame/gesture boundary and rejection of extra command/URL parameters).
- `tools/woowtechbot-ui/workspace-controls-test.cjs`: isolated Chrome fixture passed repeat injection, original controls, draft retention, both skins, React slot replacement and fallback. No live service credentials used.
- POCO C85, Android15, normal candidate `0.1.37-woow.22`/3822, diagnostics=false; same package/signature and firstInstallTime preserved by `adb install -r`.
- HA/Podman existing profiles open successfully. Real website sidebar Services control opens native picker. HA dark chat and light list, native light picker and local light chat visually checked.
- Four service discovery results became READY; global state settled to REGISTERED on the initial 3822 candidate. This does not establish the historical 3821 PENDING root cause, nor constitute new-version push delivery verification.
- Podman unsent `UI22-DRAFT-NOT-SENT` survived remote service switching and light/dark change. It was cleared without sending. Existing main thread restored; Podman independently verified at 15:45:28Z that threadId/mainThreadId both remain `7cb1b6b6-8ee0-4af2-8d83-787369ff75d6`, busy=false.
- No notification fixtures, model requests, global consent toggles, re-pairing or profile removal during this UI pass.

## Installed UI QA candidate — source 9e0382d2

Source `9e0382d2`: signed release build and lint passed, 30 push core tests and 2 host-action tests passed. Final APK installed with matching SHA-256 (see `evidence/woow22-ui/build.json`). Final phone checks: four circular local-history controls, return from notification settings stays on history, System light/dark switching, light/dark service picker, and lab43/lab53 original chat/composer with no duplicate native header. Four discovery results and global registration state settled successfully again. System night mode restored to its original enabled state, auto-rotation restored, Wi-Fi and mobile-data settings unchanged.

Final screenshots are prefixed `final-`; earlier images remain labeled by page. The exact historical cause of 3821 PENDING is still unproven. At that UI-only checkpoint, new-version FCM delivery tests were on hold. Subsequent separately authorized device results are recorded in WOOW22-PUSH-QA.md. Activity/process destruction draft recovery is not independently proven by the live-view switch test.

GitHub CI for PR50 head `97c345b0` completed successfully for all applicable checks after the initial Gradle asset HTTP403 retry (GPL sources was skipped for this PR). The follow-up head `0a78edb249900e7bd85d3b69c87b5a6949aeed01` includes the sidebar fallback correction and woow.22 release notes. At the 2026-11-26 16:53 UTC check, its brand-source checks and release-plan job had passed; remaining applicable jobs were still running, and GPL sources was skipped. This is distinct from the completed checks on the earlier head. Local assembly does not establish completion of remote CI.

The installed UI QA results, screenshots and `evidence/woow22-ui/build.json` above belong to source `9e0382d2`; they are not installation evidence for the corrected `0a78edb2` APK. woow.22 publication/in-app update acceptance is not established by these UI checks. Separate natural-push QA is coordinated outside this build task and is not changed or claimed PASS here.

Backend evidence clarification (coordinator report): HA rc23 authenticated amd64 OCI manifest exists at digest `141b49b5f31db33e4b5de01b910dcb74ba4cef6deeae388f4da75be203451912`; GitHub tag/release and anonymous pull were not established by the 15:25Z check. Podman later deployed its separate rc23-1 derivative while preserving the original phone binding. Neither change authorizes automatic event sends.

## Corrected APK — source 0a78edb2 (build-only)

Source `0a78edb249900e7bd85d3b69c87b5a6949aeed01`, version `0.1.37-woow.22` / `3822`. Gradle completed successfully in 2m 13s, including release vital lint (60 tasks: 12 executed, 48 up-to-date). Built with the authorized existing signing/Firebase property paths using Java 17 and `:app:assembleWoowtechRelease --offline --console=plain`. No JS regression rerun, device operation, installation, commit, merge or publication was performed by this build task. The existing offline Chrome fixture PASS belongs to the fallback correction review.

Artifacts under `app/build/outputs/apk/woowtech/release/`:

| APK | SHA-256 |
| --- | --- |
| `app-woowtech-arm64-v8a-release.apk` | `177b980a36b4d6099873149d0f684c421c926bf5b39587e4845462e71008ae05` |
| `app-woowtech-universal-release.apk` | `5d20612e1e27546e150538476fc1e2d3c474e2b771585af9e32bbd8347442e1c` |

Both APKs pass `apksigner verify` and match the established release certificate SHA-256 `806b3db808ecbb4d2d032b34624baa7e193802f17a07afbde2a03e78da9474c8`. APK metadata confirms `io.woowtech.agent`, versionCode 3822 and non-debuggable packaging. The arm64 APK's DEX explicitly contains `BOT_VIEWPORT_DIAGNOSTICS=false` and `DEBUG=false`; every DEX entry is byte-identical between arm64 and universal. The corrected workspace-controls asset in each APK matches the checked-out source. These checks establish artifact identity/configuration, not installation or notification delivery acceptance. The parent coordinator owns any later installation and device QA.

Remote CI rechecked after local build (2026-11-26 16:56 UTC): at head `0a78edb2`, brand-source checks, release-plan and CLI checks passed; remaining reported applicable jobs were still in progress, with no reported failures. GPL sources remained skipped for the PR. No CI rerun was triggered.

## Corrected APK installed and checked — source 0a78edb2

After the original9e0382d2 HA/Podman event checks finished, the parent installed the corrected arm64 APK with adb install -r (Success). Independent installed APK SHA-256 exactly matches177b980a36b4d6099873149d0f684c421c926bf5b39587e4845462e71008ae05; version3822 and firstInstallTime2026-11-09 13:12:33 retained, lastUpdateTime2026-11-27 01:04:15 local. No profile, token, consent or session was deleted.

Device checks: notification page settles to registered with all four original services' identity/capability ready; original HA chat and latest reply remain accessible. Dark/light HA chat has a single website header; its list has both injected actions, and actual service-switch tap opens the native picker with all four profiles and HA selected. Screenshots prefixed corrected22 under evidence/woow22-ui. Original system dark mode and automatic rotation restored, network settings unchanged. Existing missing-slot behavior is covered by the isolated browser regression; the actual healthy HA page verifies normal chat does not gain a duplicate toolbar. These installation/UI checks do not turn earlier-source delivery evidence into new-source FCM evidence.
