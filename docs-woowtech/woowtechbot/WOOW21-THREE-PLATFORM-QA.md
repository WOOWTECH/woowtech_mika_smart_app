# woow.21 three-platform device QA — 2026-11-26

## Device identity and control boundary

User supplied a new HTTPS task API and reported installing woow.21. Authenticated `mika connect` returned server_version=0.1.37-woow.21/api_version1. `doctor` reported interactive, unlocked, helper available and ready. Device model, package signature and installed APK hash have not yet been independently obtained from this handset.

USB POCO ZHO7GIKRHYNRKZRC still reports versionCode3820/versionName0.1.37-woow.20 and firstInstallTime2026-11-09 13:12:33; it is not substituted for the new handset. Earlier HA/PaaS acceptance remains 3820 evidence.

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

## Acceptance matrix — all device rows pending

Run each platform with its own profile, local service UUID, client session and corroborated server/relay registration. Never reuse the old device baseline.

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
