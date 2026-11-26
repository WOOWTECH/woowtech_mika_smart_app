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

Final native header refinements and return-to-history behavior require the final candidate rebuild/reinstall. Screenshots in `evidence/woow22-ui` currently describe the initial candidate. woow.22 is not yet published to GitHub Releases/in-app update.
