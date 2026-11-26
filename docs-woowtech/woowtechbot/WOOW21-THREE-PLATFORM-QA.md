# woow.21 three-platform device QA — 2026-11-26

## Device identity and control boundary

User supplied a new HTTPS task API and reported installing woow.21. Authenticated `mika connect` returned server_version=0.1.37-woow.21/api_version1. `doctor` reported interactive, unlocked, helper available and ready. Device model, package signature and installed APK hash have not yet been independently obtained from this handset.

At the initial remote-handset checkpoint, USB POCO ZHO7GIKRHYNRKZRC reported versionCode3820/versionName0.1.37-woow.20 and firstInstallTime2026-11-09 13:12:33; it is not substituted for the new handset. Earlier HA/PaaS acceptance remains 3820 evidence.

Read-only inspection task6b3a4094-080c-4b41-b7e6-2a0344b2be68 returned waiting_on_phone/access_blocked: phone agent cannot operate its own running app. Cancellation accepted. No service list, new profile, pairing or registration has been verified. Independent USB/wireless ADB requested from user. Do not bypass the self-operation restriction; task API disconnection is not evidence of process death. No credentials or private relay route are stored in this document.

## Current endpoint baseline

Independent workstation requests with normal browser UA: each listed origin /api/health and /pair returned200 without redirect. This is workstation reachability, not handset WebView or FCM acceptance.

| Platform | Origin | Server-side readiness | New handset registration |
|---|---|---|---|
| HA | https://woowtechbot-ha.woowtech.io | HA reports rc23 healthy, push enabled/ready, QA Codex authenticated snapshot | Not established; existing binding belongs to3820 |
| Podman | https://woowtechbot-openclaw.woowtech.io | Podman reports rc22-2 healthy, push disabled/not ready; candidate deployment in progress | Not established |
| PaaS lab43 | https://paas-cs-671d61b1-e823b18c.woowtech.io | Awaiting current authenticated capability/binding review | Not established |
| PaaS lab53 | https://paas-cs-21bb5dd5-f28b74d7.woowtech.io | Awaiting current authenticated capability/binding review | Not established |

HA QA bot e6763931-993b-4e56-80d9-e87705f2d929 / seed5c288d5b-ade1-40ca-ab16-9f7a2477762b. Podman QA bot5f51f80d-afdb-4e44-b310-fc0798170a66 / seed7cb1b6b6-8ee0-4af2-8d83-787369ff75d6. Preserve all existing profiles, sessions, data and registrations. Backend model availability snapshots do not establish a successful new model turn.

## Acceptance matrix — incremental execution

Run each platform with its own profile, local service UUID, client session and corroborated server/relay registration. Recheck preserved registrations after upgrade; do not count older event acceptance as woow.21 receipt.

| Area | Required evidence |
|---|---|
| Identity / upgrade | Version, signature/hash where accessible, preserved existing profiles/data |
| Pairing | Dedicated profile; short-lived client-only code, same-origin validation; real camera QR separately |
| UI / persistence | Bot and exact thread, composer, keyboard, rotation, back/reopen, cross-service login/draft isolation |
| Notification setup | System permission, local consent, per-service capability and PUT ACK, server/relay baseline |
| FCM foreground / background | Unique event, exact active tag, visible appropriate reason, source app; FCM accepted is not receipt |
| Notification click | Actual body tap, exact origin/bot/thread; independent picker or clearly bounded tag/metadata corroboration |
| Cold process | Independent controller verifies PID absent/stopped=false immediately before send, continuous monitor, FCM wake-up evidence |
| Offline / reconnect | Explicit network loss and restoration within event TTL; deferred receipt and dedup; Wi-Fi is not cellular |
| Natural completion | One harmless unique-marker model request via normal API, provider success, natural done event, phone receipt and marker |
| Permission / question | Harmless QA card, actual native touch and resulting task state; no external/destructive permission granted |
| Token rotation / isolation | Serialize rotation with coordinators, boolean changed only, all intended registrations ACK, old revocations retained |
| Logout / removal | Dedicated disposable profile, real DELETE/logout cascade and other profiles unaffected; never use original login for destructive test |
| Duplicates / invalid targets | Controlled backend fixture agreement, no manual Android notification injection, expected rejection/dedup |
| Files / camera | Harmless fixture selection, attachment open/download, capture and getUserMedia separately; no personal photos/files |
| Lock / return | Independent recovery access; do not lock or kill sole control transport without a recovery path |

Each event requires handset readiness and its own authorization to the designated backend sender; all senders currently HOLD. Manual fixtures, natural model events, synthetic tokens and backend-only tests are separate records. Unavailable hardware/control capabilities are limitations, never PASS.

## User-directed POCO continuation — 15:05–15:10 UTC

User explicitly selected POCO instead of the blocked remote handset. Published signed arm64 APK installed with ordinary `adb install -r`, Success; no uninstall, data clearing or Play Protect disable. Package now versionCode3821/versionName0.1.37-woow.21, firstInstallTime2026-11-09 13:12:33 unchanged, lastUpdateTime2026-11-26 23:05:33 local. Installed APK SHA256 matches published artifact `a93da5d6a45ef34d853e4a98be233375053201a42eb4761f71eb79f421a0eca4`. This ADB upgrade does not resolve or prove success of the previously blocked in-App package-installer flow.

Original HA profile opens the exact HA origin, QA bot and composer; previous harmless marker remains visible. This proves retained UI/login content, not a new natural completion. HA coordinator 15:07:36Z independently confirmed original client session live, service6a0f26fa-c49f-4350-983b-1f52592b72a8 / registration1957f5aa-c83f-4fa9-996d-c7dd41318f80 rev1 registered, relay live/tokenPresent and outbox0. Persisted state confirms existing ACK remains valid, not a new PUT on21.

Podman coordinator15:07Z confirmed original client session and QA bot/thread retained; formal rc22-2 lacks push capability, enabled/ready false, no formal device registration or ACK. Candidate deployment remains pending. Synthetic relay tests do not establish POCO registration.

15:09:59.347838Z: POCO Home foreground, App PID12928 still running; explicitly ordinary background, not cold. Coordinated one new HA attention fixture with HA as sole sender and PaaS oversight. Actual event/receipt/click still pending; other senders HOLD.

### HA background attention — woow.21 PASS

New event `c6cb2499-f881-4f02-a371-8a1bf99cfea3`, HA sender15:11:49.754Z / ACK15:11:50.863Z. PaaS independently persisted sent and exact six-field fingerprint at15:13:04.712Z. Phone first observed15:11:57.754352Z, unique exact service|bot|seed|event tag, channel woowtechbot_attention, SECRET. Visible “機器人需要您的注意，請開啟查看。” Group expanded, then actual notification body tapped; resumed BotServiceActivity, exact HA origin and QA bot/composer visible. Single seed has no picker; tag plus backend metadata corroborates target, no independent internal selected-ID claim. Screenshot [HA body tap](evidence/woow21-poco/poco21-ha-attention-tap.png), [active record](evidence/woow21-poco/poco21-ha-event.json). Manual attention, not natural or cold.

PaaS15:09:23–24Z also confirmed retained live client sessions and registered/rev1 for lab43 registration2fda634c-5055-44cb-8f1e-38799ea1d89a and lab53 registration146dafe7-fe08-4862-b8b5-1aba9f424e08; exact relay bindings match, pending/outbox0. This is retained ACK, not proof of new PUT. Lab model snapshots unauthenticated, natural completion pending model login. Formal PaaS461 remains pushOFF and is not covered by lab acceptance.

### HA offline natural completion — in progress

15:13:52.649548Z independently controlled via USB: Home, WiFi0, mobile_data0, Active default network:none. Previously WiFi1/mobile_data0/airplane0; restore WiFi1 after sender ACK. Original profile/registration unchanged, no force-stop. Requested one normal model turn with harmless marker android-qa-ha-woow21-offline-1514 and no tools/file/network actions; only HA sender after coordinated sendId. No synthetic completion or notification injection. Await provider/event/ACK then reconnect within TTL. This does not test cellular or cold process.

### HA offline natural completion — woow.21 PASS

Normal sendId428be23a-0bff-4f37-b52a-3ed599801f35, true provider succeeded15:16:06.211Z, natural finished eventd25bf5cf-6f2b-4c12-90e9-e75c9915bd48, expiry15:26:05.909Z. PaaS independently confirmed persisted sent and expected data fingerprint15:17:26.192Z. USB observation15:16:52.115225Z still network:none, event count0. Original WiFi restored15:16:52.511019Z;15:17:07.031529Z network113, exact unique event notification in woowtechbot_results/SECRET. Visible completed text; group expanded then actual body tapped into BotServiceActivity / exact HA origin / QA bot / composer / assistant answer android-qa-ha-woow21-offline-1514. [Network/event record](evidence/woow21-poco/poco21-ha-offline-result.json), [target and marker](evidence/woow21-poco/poco21-ha-offline-tap.png). HA15:18:15.319Z final seed/session/registered rev1/jobs0 corroboration. Not cold, force-stop or cellular; no picker/internal selected-thread ID claim. No resend.

### Podman and UI follow-up

Formal origin now runs explicitly local candidate rc23-0, not published HA release image. Podman App and PaaS15:16:01.680Z relay independently confirm true retained-phone registrationb2da04c9-2149-4323-b433-113b69974ff3 / service21c51aff-99fc-46ec-a970-f75b96658059 / sessione7a016cf-55ab-41a3-8b63-e4ff6cad6127 / rev1 live, no events. Phone reopened original Podman profile, correct QA bot and composer visible. No Podman notification yet. Native global notification page still says registration/removal pending despite four backend registered bindings; record UI unresolved, not four-platform success.

User subsequently directed alignment with design conversation80c93a025eff4cdaa6f47913b33f0684 preview06 and both light/dark themes. All three coordinators notified to HOLD every artificial event and model call while UI work proceeds. Original profiles retained, WiFi restored, mobile data remains0.
