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
    /** Reads a verified push's bot name and excerpt from its service; installed with the connections. */
    @Volatile var previews: (suspend (BotPushTarget) -> BotPushPreview?)? = null
}

/** Safe, in-memory discovery results; READY is capability readiness, not a registration ACK. */
enum class BotPushDiscovery { CHECKING, READY, SIGN_IN_REQUIRED, IDENTITY_CHANGED, SERVER_NOT_READY, UNAVAILABLE }

enum class BotPushState { OFF, NOT_CONFIGURED, PERMISSION_REQUIRED, NO_SERVICES, PENDING, RETRY_REQUIRED, SERVER_NOT_READY, REGISTERED }

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
    val discovery: StateFlow<Map<String, BotPushDiscovery>> = MutableStateFlow(emptyMap()),
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

    fun acceptsIdentity(serviceId: String, identity: String) = accepts(serviceId) &&
        bindings().any { it.serviceId == serviceId && it.authIdentity == identity }

    /** Call after permission result, login, foreground/network retry, and onNewToken.
     * Token callbacks are hints: fetch the current token under the lock, never register stale callback values.
     */
    suspend fun refresh(): Boolean = lock.withLock { reconcile() }
    suspend fun retireBindings(resolve: suspend () -> Set<BotPushBinding>): Boolean = lock.withLock {
        lifecycle.revokeBindings(resolve())
    }
    suspend fun setOptIn(enabled: Boolean): Boolean = lock.withLock {
        check(prefs.edit().putBoolean("enabled", enabled).commit())
        reconcile()
    }
    private suspend fun reconcile(): Boolean {
        mutableState.value = BotPushState.PENDING
        return try { reconcilePrepared() }
        catch (e: kotlinx.coroutines.CancellationException) {
            mutableState.value = BotPushState.RETRY_REQUIRED
            throw e
        } catch (_: Exception) {
            // Preserve the durable ledger and consent. A failed discovery is not a revoke request.
            mutableState.value = BotPushState.RETRY_REQUIRED
            false
        } finally {
            // Stale epochs and incomplete work must not leave the UI permanently busy.
            if (mutableState.value == BotPushState.PENDING) mutableState.value = BotPushState.RETRY_REQUIRED
        }
    }
    private suspend fun reconcilePrepared(): Boolean {
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
