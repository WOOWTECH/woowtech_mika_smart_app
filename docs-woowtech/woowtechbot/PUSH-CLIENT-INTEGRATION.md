# Android push client integration (2026-11-26)

Implemented isolated core contracts/tests and Android lifecycle/notifications. Actual delivery is **not verified**: own Firebase project config, paired-session API extension, relay deployment and device testing are required. No foreign Firebase configuration is included. The WOOWTECH flavor contains the manifest entries and Firebase dependency; application startup and notification tap handling are gated by the build flag.

## Exact payload shared with relay

FCM **data only**, all values strings, exactly these six keys:

```json
{"v":"1","serviceId":"service_demo","botId":"bot_demo","threadId":"thread_demo","eventId":"event_demo_0001","reason":"finished"}
```

Reasons: `finished`, `permission`, `attention`. Bot kinds map `done → finished`, `approval → permission`, `question/sign-in → attention`. IDs match `[A-Za-z0-9][A-Za-z0-9_.:-]{0,127}`. `eventId` must be stable across retry and unique across server restarts (e.g. epoch plus sequence). Never dedup on thread alone. Client dedup keys include service, bot, thread, event with an unambiguous separator; 128-entry receipt/tap caches and 16 pending taps. Android receipt and handled-tap dedup use separate bounded persistent histories across process restarts; core defaults remain in-memory for tests. Old entries may repeat after FIFO eviction. Neither names nor conversation content nor URLs are accepted. Relay must omit BOTH top-level notification and android.notification: background notification payloads bypass client validation/consent and generic local rendering. Use high priority, bounded TTL, no thread-wide collapse key.

Channels: `woowtechbot_attention`, `woowtechbot_results`. Local fixed English/Traditional Chinese strings live in `bot_push.xml`. Lockscreen visibility SECRET. Immutable explicit activity PendingIntent uniquely identifies the event. Routing never executes approvals or opens a supplied URL.

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

BotPushBootstrap now installs runtime through the gated MikaApp.onCreate call, including cold starts. Main has no Firebase linkage: reflection loads @Keep BotFirebaseTokens only in WOOWTECH. Bootstrap intentionally uses empty bindings, serverReady=false and UnavailableBotPushDeviceApi until the service adapter exists; no FCM token is requested in that state. Settings Activity is available via BotPushSettingsActivity.intent(context).

```kotlin
val tokens = BotFirebaseTokens(context) // WOOWTECH source set only
val controller = BotPushController(context, tokens, serviceBoundApi,
    bindings = { /* paired, direct, user-enabled exact identities */ },
    permissionGranted = { /* notification permission + app notifications enabled */ },
    serverReady = { /* true ONLY after supported capability/session adapter is installed */ })
BotPushRuntime.controller = controller
BotPushRuntime.notifications = BotPushNotifications(context, MainActivity::class.java, controller::accepts)
```

Settings call suspend `controller.setOptIn(enabled)` after permission handling and collect `controller.state`. States OFF/NOT_CONFIGURED/PERMISSION_REQUIRED/NO_SERVICES/PENDING/SERVER_NOT_READY/REGISTERED distinguish readiness. REGISTERED means API acknowledgment, never verified delivery. Boolean return means reconciliation complete. Show own-project config absence explicitly. Use `UnavailableBotPushDeviceApi` until a real capability-aware API adapter exists; it always reports server-not-ready.

Call `BotPushRefreshJob.schedule(context)` after consent changes, registration/session changes, network/foreground resume, and failed refresh. `onNewToken` automatically schedules durable unique backoff work; callback token values are not used, avoiding stale queued-token registration. Worker re-fetches latest token under controller mutex. Parent must schedule pending retries before leaving settings and on startup. Opt-out deletes the FCM token locally and DELETEs every recorded server binding. Failed/ambiguous PUTs stay in the durable ledger and are revoked too. Failed DELETEs remain pending across restart. Token PUT replaces the same authenticated phone's prior token atomically.

Maintain one process-scoped `BotPushRouter(knownService=...)`. `knownService` must recognize only allowed saved direct services. Call `BotPushNotifications.capture(intent, router)` in onCreate and onNewIntent; it removes routing extras after queueing. Call router.drain after navigation and the target service's auth are ready. Return true from open only when navigation accepts; resolve a bot/thread through that service's own authenticated state, never interpolate into an arbitrary URL. Call forgetService on removal/logout. Unknown/deleted services are rejected/rechecked. Pending queue survives UI remount only if router is process-scoped; it is not persisted across process death.

## Service API contract and readiness gap

`core...woowbot.push.BotPushDeviceApi` exposes suspend `register(BotPushBinding, token)` and `revoke(BotPushBinding)`. Binding includes `serviceId` and `authIdentity`; encode the profile epoch plus captured server session identity in authIdentity, with no credential material. Keep exact origin and scoped-cookie lookup in adapter metadata. Never resolve by selected service. Never mutate binding identity when credentials rotate. Calls must use explicit saved direct origin, strict timeouts, no redirects, no automatic cross-origin cookie forwarding, no token/cookie logs.

Existing bot `/api/push/device` PUT/GET/DELETE identifies device via request auth. Its strict PUT accepts platform/token/environment/pairing/kinds, NOT serviceId, event schema, or locale. Native pairing with `cookie:true` can supply a paired session; `browser:true` produces cookieOnly auth which phoneKey excludes. Do not treat browser login success as phone-push registration readiness.

Required extension proposal (not presently implemented): authenticated GET `/api/push/device` advertises an explicit `capabilities.woowtechAndroidPush=1`; only then PUT may accept an extension mapping the client's serviceId and negotiated v1 payload contract (plus locale if needed). Server must bind alias to authenticated phone/installation, acknowledge it, and emit stable eventId. Capability absence => throw BotPushNotReadyException, no invented fields sent to upstream. Exact extension schema is a server integration decision; no speculative HTTP adapter is shipped.

Before PUT/DELETE, obtain `/api/auth/session` via the saved profile cookie, capture identity and origin, and confirm profile epoch/service still match. Send using that captured cookie, never re-read current selection midway. Reject redirect and identity changes. Server must reject unpaired/cookieOnly auth itself. On logout/remove, revoke before deleting the old profile cookie or provide a server-side session-revocation cascade; otherwise the retained local revocation ledger cannot authenticate cleanup. Never pretend clearing local metadata has revoked the server. A failed revoke blocks registration of a new identity at the same service; other services remain independent. Parent must coordinate `BotServices.cleanRetired` accordingly.

Smart reference is design guidance only: its wsp1 token envelope and `/api/smart/v1/notify` target schema are NOT bot contracts. Bot's upstream hosted control-plane credentials/endpoint must be replaced/bridged server-side to own relay. Android receives no installation relay secret.

## Verification

Pure Kotlin tests cover strict schema, malformed IDs/URLs/content, unknown/deleted services, deferred taps, successful navigation dedup, repeated thread events, bounded queues, ambiguous registration, rotation, failed revocation/restart, service/session isolation and missing capability. Android build/device delivery validation is a separate integration gate.

Official Firebase references checked: https://firebase.google.com/docs/cloud-messaging/android/get-started and https://firebase.google.com/docs/cloud-messaging/android/receive-messages .

## Final Android integration additions

BotPushTapEntry owns the process-scoped router and persistent handled history. MainActivity onCreate/onNewIntent each call its helper without changing local-conversation routing. It opens BotServiceActivity, whose own profile controls sign-in and authorized target loading. Registry disable/remove/profile rotation cancels only bot-channel notifications and forgets pending taps; consent withdrawal also cancels stale bot notifications. Existing local assistant notifications are untouched. Deep target validation falls back to service root if the service UI cannot represent an ID.

Instrumentation tests in app/src/androidTest/.../woowbot/push/BotPushNotificationsTest.kt inject acceptance, never initialize Firebase, and cover generic secret notifications, separate events on one thread, rejected services/content, logout cancellation, durable dedup/reopen and bounded history. Direct-flavor instrumentation is enabled with `-PwoowtechbotTests`; use `-PdevInstall` to test the independent `.dev` package. No real FCM test is claimed.
