# Android direct service integration

Implementation: `app/src/main/java/com/wangzan101/mika/woowbot/`, localized resources, and focused tests. Push implementation resides in its `push/` subdirectory.

Add non-exported `com.wangzan101.mika.woowbot.BotServicesActivity` and `com.wangzan101.mika.woowbot.BotServiceActivity` to the enabled WOOWTECH manifest; the latter benefits from `android:windowSoftInputMode="adjustResize"`. Both gate entry on `BuildConfig.WOOWTECHBOT_ENABLED`. The application owns application/package/flavor, cleartext network policy, manifest and main navigation. No Gradle/manifest/main-app/core/push files were edited here.

Entry points:

```kotlin
BotServicesActivity.intent(context)
BotServiceActivity.intent(context, serviceId, botId = null, threadId = null)
BotServices.registry(context) // process singleton
```

Registry `state` is `StateFlow<BotRegistryState>` with `services` and `retiredProfiles`. `BotService` exposes `id`, `name`, normalized `origin`, `enabled`, `allowHttpLan`, `profileId`, `profileName`, and `policy`. `add`, `find`, `setEnabled`, `logout`, `remove` are available. `enabled` is local user intent, **not** authenticated/online readiness. `logout` rotates profile identity and disables opening. Cookie auth remains inside the original site's pairing/email-sign-in UI; native code never interprets pairing-token return values.

## Push adapter integration

Install `BotServices.onSessionMayHaveChanged: (BotService) -> Unit` to enqueue/debounce your session discovery. Invoked on same-origin page finish and every 15 seconds while the activity is resumed, including SPA pairing with no navigation. The callback runs on main and must return promptly. Use that service's `ProfileStore.getInstance().getOrCreateProfile(service.profileName).cookieManager` on main; send authenticated requests only to its exact saved origin. Query `/api/auth/session` to determine the actual server session, rather than using enabled/profileId as proof of authentication. Collect registry state too, to remove disabled/removed bindings even when this screen is closed.

Install `BotServices.beforeSessionCleared: (BotService) -> Unit` if revocation needs to snapshot the old binding/cookie before logout/removal clears it. This is a synchronous main-thread snapshot hook, not a blocking network operation; Activity calls it before metadata rotation and cookie clearing. Direct registry mutations are metadata-only; callers outside the Activity must perform the equivalent auth cleanup/hook. Revocation retries and binding-generation checks belong to the push adapter. Session cookies/tokens must not be logged or placed in Intent extras.

Notification intents accept only saved service ID + bounded bot/thread IDs (`[A-Za-z0-9][A-Za-z0-9_.:-]{0,127}`). Targets become `/?thread=<id>&bot=<id>` on the saved origin, overriding remembered history once. They do not reconnect a disabled service automatically. Intent helpers omit absent extras.

## WebView behavior and limits

Runtime `MULTI_PROFILE` is mandatory; unsupported providers show an update message and never use a shared/default profile. Each service (even two accounts on the same origin) has an independent profile. No native bridge, phone tools, token injection, preview proxy or HTML rewriting. Top-level navigation is pinned to exact origin; external HTTPS links with user gestures require confirmation and open in an external browser. HTTPS subresources remain web content, with no native authority; this is not a DNS or WebSocket firewall. HTTP is allowed only by explicit per-service LAN opt-in (private literal IP/ULA or `.local`); OS network-security policy still applies. Loopback and metadata/link-local literals are refused. The build must ensure the intended direct flavor's cleartext policy permits opted-in LAN origins.

Service switching/configuration recreation restores bounded **process-memory-only** WebView history (256 KiB/profile, max 20 profiles). No history Bundle is written to Activity saved state/disk; framework view-state saving is disabled. Process death reopens the origin. Profile localStorage persists, including drafts only when the original webpage saves them there; WebView history does not promise DOM-only drafts or scroll restoration. Disconnect/logout/remove drop remembered history. Logout rotates immediately, best-effort revokes `/api/auth/logout`, clears old cookies/storage, and queues full profile deletion. WebKit cannot delete already-loaded profiles in this process, so retired profiles are cleaned on a later fresh process; metadata limits prevent unbounded rotation. Logout UI distinguishes unsuccessful server revocation.

Files use the system document picker (content URIs only, up to 16). Downloads use user-chosen document destinations, same-origin cookies, no redirects, 100 MiB max and two-minute timeout. Blob downloads and direct camera/microphone/location access are explicitly unsupported; no permissions silently granted. Sharing sends only the configured origin, never a sign-in link. Failed downloads may leave a partial user-selected file and say so.

## Validation

Nine focused JVM tests passed using cached Kotlin 2.1.20 compiler + serialization plugin + JUnit 4.13.2, independently of Gradle (no Android build started). Covers exact origin, HTTP opt-in, forbidden metadata/secrets, ID validation, profile persistence/isolation identities, logout/disconnect, failed persistence and bounds. Device test `com.wangzan101.mika.woowbot.BotProfileIsolationTest` exercises real provider cookie/localStorage separation for two profiles on the **same origin**, and checks clearing one leaves the other intact. It skips when `MULTI_PROFILE` is unavailable. Device test has been written but not run; release validation coordinates APK compile and device execution.

Profile API contract checked against AndroidX documentation: https://developer.android.com/reference/androidx/webkit/ProfileStore and https://developer.android.com/reference/androidx/webkit/WebViewCompat#setProfile(android.webkit.WebView,java.lang.String).
