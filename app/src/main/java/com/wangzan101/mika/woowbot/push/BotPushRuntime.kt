package com.wangzan101.mika.woowbot.push

import android.content.Context
import com.wangzan101.mika.core.woowbot.push.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/** No Firebase linkage in main. The WOOWTECH application installs the flavor implementation. */
interface BotPushTokenSource {
    val configured: Boolean
    suspend fun token(): String
    suspend fun disableAndDelete()
}

object DisabledBotPushTokens : BotPushTokenSource {
    override val configured = false
    override suspend fun token(): String = error("Own Firebase configuration is absent")
    override suspend fun disableAndDelete() = Unit
}

/** Install during Application.onCreate, including cold starts into the messaging service. */
object BotPushRuntime {
    val epoch = java.util.concurrent.atomic.AtomicLong()
    @Volatile var controller: BotPushController? = null
    @Volatile var notifications: BotPushNotifications? = null
}

enum class BotPushState { OFF, NOT_CONFIGURED, PERMISSION_REQUIRED, NO_SERVICES, PENDING, SERVER_NOT_READY, REGISTERED }

class BotPushController(
    context: Context,
    private val tokens: BotPushTokenSource,
    api: BotPushDeviceApi,
    /** Includes only known, paired, direct services explicitly enabled by the user. */
    private val bindings: () -> Set<BotPushBinding>,
    private val permissionGranted: () -> Boolean,
    private val serverReady: () -> Boolean = { false },
    private val prepare: suspend () -> Unit = {},
    private val stillCurrent: () -> Boolean = { true },
) {
    private val prefs = context.getSharedPreferences("woowbot_push_consent", Context.MODE_PRIVATE)
    private val lifecycle = BotPushLifecycle(api, BotPushPreferencesLedger(context))
    private val lock = Mutex()
    private val mutableState = MutableStateFlow(BotPushState.OFF)
    val state: StateFlow<BotPushState> = mutableState
    val optedIn get() = prefs.getBoolean("enabled", false)
    val configured get() = tokens.configured
    fun accepts(serviceId: String) = optedIn && configured && serverReady() && permissionGranted() &&
        bindings().any { it.serviceId == serviceId }

    /** Call after permission result, login, foreground/network retry, and onNewToken.
     * Token callbacks are hints: fetch the current token under the lock, never register stale callback values.
     */
    suspend fun refresh(): Boolean = lock.withLock { reconcile() }
    suspend fun setOptIn(enabled: Boolean): Boolean = lock.withLock {
        check(prefs.edit().putBoolean("enabled", enabled).commit())
        reconcile()
    }
    private suspend fun reconcile(): Boolean {
        mutableState.value = BotPushState.PENDING
        prepare()
        if (!stillCurrent()) return false
        val enabled = optedIn && configured && permissionGranted() && serverReady()
        val desired = if (enabled) bindings() else emptySet()
        var token: String? = null
        var tokenOk = true
        try {
            if (enabled && desired.isNotEmpty()) token = tokens.token()
            else tokens.disableAndDelete()
        } catch (e: kotlinx.coroutines.CancellationException) { throw e }
        catch (_: Exception) { tokenOk = false }
        if (!stillCurrent()) return false
        val complete = lifecycle.reconcile(token, desired) && tokenOk
        mutableState.value = when {
            !complete && lifecycle.serverNotReady -> BotPushState.SERVER_NOT_READY
            !complete -> BotPushState.PENDING
            !configured -> BotPushState.NOT_CONFIGURED
            !optedIn -> BotPushState.OFF
            !permissionGranted() -> BotPushState.PERMISSION_REQUIRED
            !serverReady() -> BotPushState.SERVER_NOT_READY
            desired.isEmpty() -> BotPushState.NO_SERVICES
            else -> BotPushState.REGISTERED
        }
        return complete
    }
}
