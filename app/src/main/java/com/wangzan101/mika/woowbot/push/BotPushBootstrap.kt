package com.wangzan101.mika.woowbot.push

import android.Manifest
import android.app.NotificationManager
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import com.wangzan101.mika.BuildConfig
import com.wangzan101.mika.ui.MainActivity
import com.wangzan101.mika.woowbot.BotServices
import kotlinx.coroutines.*

/** Gated common entry. Reflection keeps Firebase bytecode out of upstream/Apporo. */
object BotPushBootstrap {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    @Synchronized fun install(context: Context) {
        if (!BuildConfig.WOOWTECHBOT_ENABLED || BotPushRuntime.controller != null) return
        val app = context.applicationContext
        val tokens = runCatching {
            Class.forName("com.wangzan101.mika.woowbot.push.BotFirebaseTokens")
                .getConstructor(Context::class.java).newInstance(app) as BotPushTokenSource
        }.getOrDefault(DisabledBotPushTokens)
        val registry = BotServices.registry(app)
        val connections = BotPushConnections(registry, BotPushPreferencesLedger(app)::read)
        val controller = BotPushController(app, tokens, connections.api,
            bindings = connections::bindings, permissionGranted = { permissionGranted(app) },
            serverReady = connections::ready, prepare = connections::prepare, stillCurrent = connections::valid)
        BotServices.onSessionMayHaveChanged = { service -> connections.sessionHint(service); refresh(app) }
        BotServices.beforeSessionCleared = { service -> connections.retiring(service) }
        BotPushRuntime.controller = controller
        BotPushRuntime.notifications = BotPushNotifications(app, MainActivity::class.java, controller::accepts)
        refresh(app)
        scope.launch {
            var previous = registry.state.value.services.associate { it.id to it.profileId }
            registry.state.collect { state ->
                val active = state.services.filter { it.enabled }.associate { it.id to it.profileId }
                (previous.keys - active.keys + previous.keys.filter { active[it] != previous[it] }).forEach { id ->
                    BotPushRuntime.notifications?.cancelService(id)
                    BotPushTapEntry.forgetService(id)
                }
                BotPushRuntime.notifications?.cancelStale()
                if (previous != active) {
                    BotPushRuntime.epoch.incrementAndGet()
                    refresh(app)
                }
                previous = active
            }
        }
    }
    fun permissionGranted(context: Context): Boolean =
        (Build.VERSION.SDK_INT < 33 || context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) &&
            context.getSystemService(NotificationManager::class.java).areNotificationsEnabled()

    /** Application scope survives Activity destruction so consent/revocation work can finish. */
    fun setOptIn(context: Context, enabled: Boolean) {
        install(context)
        BotPushRuntime.epoch.incrementAndGet()
        scope.launch {
            val complete = runCatching { BotPushRuntime.controller?.setOptIn(enabled) ?: false }.getOrDefault(false)
            BotPushRuntime.notifications?.cancelStale()
            if (!complete) runCatching { BotPushRefreshJob.schedule(context.applicationContext) }
        }
    }
    fun refresh(context: Context) {
        install(context)
        scope.launch {
            val complete = runCatching { BotPushRuntime.controller?.refresh() ?: false }.getOrDefault(false)
            BotPushRuntime.notifications?.cancelStale()
            if (!complete) runCatching { BotPushRefreshJob.schedule(context.applicationContext) }
        }
    }
}
