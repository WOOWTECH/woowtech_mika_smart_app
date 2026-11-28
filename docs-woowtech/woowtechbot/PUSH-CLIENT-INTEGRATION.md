# Android push client integration (2026-11-26)

Implemented core contracts/tests, Android lifecycle/notifications and the dedicated v1 HTTP adapter. Actual delivery is **not verified**: WIF provisioning, backend deployment and device/FCM testing are still required. Firebase project `woowtech-assistant` / number `795023111689` and Android app `io.woowtech.agent` exist; client config stays external to the repository. No foreign Firebase configuration is included. The WOOWTECH flavor contains the manifest entries and Firebase dependency; application startup and notification tap handling are gated by the build flag.

## Exact payload shared with relay

FCM **data only**, all values strings, exactly these six keys:

```json
{"v":"1","serviceId":"b91482c6-8dd0-46b3-a2de-13a8c3932762","botId":"bot_demo","threadId":"thread_demo","eventId":"event_demo_0001","reason":"finished"}
```

Reasons: `finished`, `failed`, `permission`, `attention`. Bot kinds map `done → finished`, `error/failed run → failed` (added 2026-11-27, owner: a run that ends in an error, such as a used-up model quota, also notifies; apps before woow.25 ignore it), `approval → permission`, `question/sign-in → attention`. IDs match `[A-Za-z0-9][A-Za-z0-9_.:-]{0,127}`. `eventId` must be stable across retry and unique across server restarts (e.g. epoch plus sequence). Never dedup on thread alone. Client dedup keys include service, bot, thread, event with an unambiguous separator; 128-entry receipt/tap caches and 16 pending taps. Android receipt and handled-tap dedup use separate bounded persistent histories across process restarts; core defaults remain in-memory for tests. Old entries may repeat after FIFO eviction. Neither names nor conversation content nor URLs are accepted. Relay must omit BOTH top-level notification and android.notification: background notification payloads bypass client validation/consent and generic local rendering. Use high priority, bounded TTL, no thread-wide collapse key.

Channels: `woowtechbot_attention`, `woowtechbot_results`. Local fixed English/Traditional Chinese strings live in `bot_push.xml`. Lockscreen visibility PRIVATE with a generic public version (owner 2026-11-28: the lock screen follows the system setting). Since woow.26 the title is the bot that replied and the text the start of its reply: after a push is accepted the phone reads `GET /api/bots?messages=1` (name) and `GET /api/threads/{threadId}/messages?limit=8` (bot text after the last user message) from that service with its verified session, 5 s each, 1 MiB at most; the payload stays IDs only and nothing of the reply passes through FCM or the relay. Any failure keeps the generic text. Immutable explicit activity PendingIntent uniquely identifies the event. Routing never executes approvals or opens a supplied URL.

## Build and manifest

* Only `woowtechImplementation("com.google.firebase:firebase-messaging:26.0.2")`; Firebase imports live exclusively under `app/src/woowtech/java/.../woowbot/push`.
* Optional external standard resources: `google_app_id`, `google_api_key`, `gcm_defaultSenderId`, `project_id`; build must verify external config `applicationId=io.woowtech.agent`. No resources means NOT_CONFIGURED.
* Remove FirebaseInitProvider in flavor manifest; set `firebase_messaging_auto_init_enabled=false` and `firebase_analytics_collection_enabled=false`. BotFirebaseTokens initializes the default app only during token acquisition AFTER consent, permission and an eligible service. Auto-init stays false even then; refresh fetches current token explicitly.
* Flavor manifest inside application:

```xml
<activity android:name=".woowbot.push.BotPushSettingsActivity" android:exported="false" />
<service android:name=".woowbot.push.BotFirebaseMessagingService" android:exported="false">
  <intent-filter><action android:name="com.google.firebase.MESSAGING_EVENT" /></intent-filter>
</service>
<service android:name=".woowbot.push.BotPushRefreshJob"
  android:permission="android.permission.BIND_JOB_SERVICE" android:exported="false" />
```

POST_NOTIFICATIONS (API33+) and RECEIVE_BOOT_COMPLETED (persisted jobs) are needed; existing main manifest already declares boot permission and disables backup. Keep consent and revocation ledger out of future backup/transfer rules.

## Application/settings/navigation hooks

BotPushBootstrap now installs runtime through the gated MikaApp.onCreate call, including cold starts. Main has no Firebase linkage: reflection loads @Keep BotFirebaseTokens only in WOOWTECH. Bootstrap installs BotPushConnections and BotPushHttpApi. Discovery uses each saved WebView profile on the main thread, capturing one cookie for session and device paths. Missing/disabled/not-ready capability prevents obtaining a new FCM token or sending PUT. Settings Activity is available via BotPushSettingsActivity.intent(context).

```kotlin
val tokens = BotFirebaseTokens(context) // WOOWTECH source set only
val controller = BotPushController(context, tokens, serviceBoundApi,
    bindings = { /* paired, direct, user-enabled exact identities */ },
    permissionGranted = { /* notification permission + app notifications enabled */ },
    serverReady = { /* true ONLY after supported capability/session adapter is installed */ })
BotPushRuntime.controller = controller
BotPushRuntime.notifications = BotPushNotifications(context, MainActivity::class.java, controller::accepts)
```

Settings call suspend `controller.setOptIn(enabled)` after permission handling and collect `controller.state`. States OFF/NOT_CONFIGURED/PERMISSION_REQUIRED/NO_SERVICES/PENDING/SERVER_NOT_READY/REGISTERED distinguish readiness. REGISTERED means API acknowledgment, never verified delivery. Boolean return means reconciliation complete. Show own-project config absence explicitly. `UnavailableBotPushDeviceApi` remains a test/default stub and is no longer wired by Bootstrap.

Call `BotPushRefreshJob.schedule(context)` after consent changes, registration/session changes, network/foreground resume, and failed refresh. `onNewToken` automatically schedules durable unique backoff work; callback token values are not used, avoiding stale queued-token registration. Worker re-fetches latest token under controller mutex. Parent must schedule pending retries before leaving settings and on startup. Opt-out deletes the FCM token locally and DELETEs every recorded server binding. Failed/ambiguous PUTs stay in the durable ledger and are revoked too. Failed DELETEs remain pending across restart. Token PUT replaces the same authenticated phone's prior token atomically.

Maintain one process-scoped `BotPushRouter(knownService=...)`. `knownService` must recognize only allowed saved direct services. Call `BotPushNotifications.capture(intent, router)` in onCreate and onNewIntent; it removes routing extras after queueing. Call router.drain after navigation and the target service's auth are ready. Return true from open only when navigation accepts; resolve a bot/thread through that service's own authenticated state, never interpolate into an arbitrary URL. Call forgetService on removal/logout. Unknown/deleted services are rejected/rechecked. Pending queue survives UI remount only if router is process-scoped; it is not persisted across process death.

## Dedicated v1 service API (supersedes the old extension proposal)

Backend candidate: PaaS PR785, commit `39bf7685f942f51cc0170d7a4137a869db81234d`.
Patch SHA256 `f53bca4f04622d5718fc01f3fcc2b85c7c1de1931aae9be1a7ac0edffdae322a`.
PaaS reports six CI checks green; this is not a deployment or delivery claim.

* Discover `/api/auth/session` using the captured profile cookie. Require kind=session,
  via=cookie, client scope, explicit boolean cookieOnly, capability woowtechAndroidPush=1,
  devicePath=/api/woowtech/android-push/device, payloadVersion="1", auth=cookie,
  acceptsCookieOnly=true. PUT/token acquisition additionally require enabled=true and ready=true.
* Normal cookie and genuine cookieOnly are both supported on this **new route only**.
  Old `/api/push/device`, phoneKey, Smart APIs and store/Apporo builds are not changed.
* Every device operation sends captured Cookie, exact HTTPS Origin and
  X-Woowtech-Session-Id. Dedicated OkHttp client has no interceptors/cookie jar,
  no redirects, no automatic connection retry, a 20-second call timeout and bounded responses.
  HTTP 429 Retry-After (seconds or HTTP date) defers further calls to that origin in this process;
  the existing persisted refresh job also backs off. The Retry-After timestamp itself is not persisted.
* PUT exact JSON: `{ "v":1, "platform":"fcm", "serviceId":"<local UUID>", "token":"<opaque token>" }`.
  Token is 20..4096 printable non-whitespace ASCII; body <=8192 bytes. No Android revision/epoch fields.
* GET has no query. DELETE has only `?serviceId=<local UUID>` and no body.
  GET pending does not imply permission to PUT; cleanup follows the local durable ledger.
* Acknowledgements validate v/state/registered, exact alias and canonical registration UUID.
  DELETE success requires the complete absent shape with both IDs null.
* Only capability preflight failure or explicit 503 push_not_ready can discard a **new** ledger entry.
  relay_unavailable (including an overtaken slow PUT), malformed acknowledgements, redirect,
  401/403/404/409/429 and network ambiguity preserve it. Existing ledger entries are never
  removed merely because a new PUT was rejected before mutation.

Controller Mutex serializes discovery, current-token retrieval and reconciliation. onNewToken
increments an atomic operation epoch and only schedules work; its callback token is never used.
Profile rotation/removal, cookie-change hints and consent changes invalidate old operations.
PUT re-fetches auth/session with the same cookie and checks the saved identity, current profile,
origin, cookie and token epoch before transport, at transport dispatch, and after response.
Binding identity hashes profile epoch + origin + environment + session id; it contains no credentials.

Old snapshots retain their original cookie only in process memory for DELETE after profile retirement.
After restart an unavailable old cookie cannot be recovered from the identity-only ledger: cleanup stays
pending and blocks a new identity at that service. Server expiry/revoke cascade is still required;
Android does not interpret an arbitrary auth failure as evidence of cascade completion. A future
explicit verifiable cascade acknowledgement may resolve such entries; none is invented here.
No installation credential or Google sender key enters Android.

## Verification

Pure Kotlin tests cover strict schema, malformed IDs/URLs/content, unknown/deleted services, deferred taps, successful navigation dedup, repeated thread events, bounded queues, ambiguous registration, rotation, failed revocation/restart, service/session isolation and missing capability. Fourteen additional v1 HTTP fixture tests cover ordinary/true cookieOnly, strict discovery, token/profile/session changes, disabled cleanup, pending GET, opaque tokens, malformed acknowledgements and retained ledgers on HTTP failures. Android release compilation passes; deployed-service/device delivery remains a separate integration gate.

Official Firebase references checked: https://firebase.google.com/docs/cloud-messaging/android/get-started and https://firebase.google.com/docs/cloud-messaging/android/receive-messages .

## Final Android integration additions

BotPushTapEntry owns the process-scoped router and persistent handled history. MainActivity onCreate/onNewIntent each call its helper without changing local-conversation routing. It opens BotServiceActivity, whose own profile controls sign-in and authorized target loading. Registry disable/remove/profile rotation cancels only bot-channel notifications and forgets pending taps; consent withdrawal also cancels stale bot notifications. Existing local assistant notifications are untouched. Deep target validation falls back to service root if the service UI cannot represent an ID.

Instrumentation tests in app/src/androidTest/.../woowbot/push/BotPushNotificationsTest.kt inject acceptance, never initialize Firebase, and cover generic secret notifications, separate events on one thread, rejected services/content, logout cancellation, durable dedup/reopen and bounded history. Direct-flavor instrumentation is enabled with `-PwoowtechbotTests`; use `-PdevInstall` to test the independent `.dev` package. No real FCM test is claimed.
