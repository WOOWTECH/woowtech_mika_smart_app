package com.wangzan101.mika.woowbot.push

import androidx.webkit.ProfileStore
import com.wangzan101.mika.core.woowbot.push.*
import com.wangzan101.mika.woowbot.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.util.concurrent.ConcurrentHashMap

/** Only cookies in process memory; durable ledger remains identity-only. All profile reads run on main. */
internal class BotPushConnections(private val registry: BotServiceRegistry, private val pending: () -> Set<BotPushBinding>) {
    private val sessions = ConcurrentHashMap<BotPushBinding, BotPushSession>()
    @Volatile private var eligible: Set<BotPushBinding> = emptySet()
    @Volatile private var epoch = -1L
    val api = BotPushHttpApi(BotPushOkHttpTransport(), { sessions[it] }, ::current) {
        epoch == BotPushRuntime.epoch.get()
    }
    fun bindings(): Set<BotPushBinding> = eligible.filterTo(mutableSetOf()) { binding ->
        val saved = sessions[binding] ?: return@filterTo false
        val now = registry.find(binding.serviceId)
        now?.enabled == true && now.profileId == saved.credentials.profileEpoch && now.origin == saved.credentials.origin
    }
    fun ready() = valid() && bindings().isNotEmpty()
    fun valid() = epoch == BotPushRuntime.epoch.get()
    private fun capture(service: BotService): BotPushCredentials? {
        if (!BotServices.supportsIsolation() || !service.origin.startsWith("https://")) return null
        val store = ProfileStore.getInstance()
        if (service.profileName !in store.allProfileNames) return null
        val cookie = store.getOrCreateProfile(service.profileName).cookieManager
            .getCookie(service.origin + "/api/auth/session") ?: return null
        // Require one same cookie for discovery and the device route (reject path-scoped mismatches).
        val deviceCookie = store.getOrCreateProfile(service.profileName).cookieManager
            .getCookie(service.origin + BotPushHttpApi.PATH)
        if (cookie != deviceCookie) return null
        return BotPushCredentials(service.id, service.profileId, service.origin, cookie)
    }
    private suspend fun current(credentials: BotPushCredentials): Boolean = withContext(Dispatchers.Main.immediate) {
        val service = registry.find(credentials.serviceId)
        if (service?.enabled != true || service.profileId != credentials.profileEpoch || service.origin != credentials.origin) false
        else runCatching { capture(service)?.cookie == credentials.cookie }.getOrDefault(false)
    }
    /** Serialized by the controller, including discovery, token retrieval, registration and cleanup. */
    suspend fun prepare() {
        epoch = BotPushRuntime.epoch.get()
        eligible = emptySet() // Never treat an unverified cached session as authorization for a notification.
        val next = mutableSetOf<BotPushBinding>()
        val recorded = pending()
        var unresolvedRegistration = false
        for (service in registry.state.value.services.filter { it.enabled }) {
            val hasRegistration = recorded.any { it.serviceId == service.id }
            val credentials = withContext(Dispatchers.Main.immediate) { runCatching { capture(service) }.getOrNull() }
            if (credentials == null) {
                if (hasRegistration) unresolvedRegistration = true
                continue
            }
            try {
                val session = api.discover(credentials)
                if (!valid() || !current(credentials)) {
                    if (hasRegistration) unresolvedRegistration = true
                    continue
                }
                sessions[session.binding] = session
                if (session.ready) next.add(session.binding)
                else if (hasRegistration) unresolvedRegistration = true
            } catch (e: kotlinx.coroutines.CancellationException) { throw e }
            catch (_: Exception) {
                // Missing discovery is not a user request to revoke a previously registered service.
                if (hasRegistration) unresolvedRegistration = true
            }
        }
        check(!unresolvedRegistration) { "Registered service discovery is temporarily unavailable" }
        if (valid()) eligible = next
        val retain = pending() + next
        sessions.keys.retainAll(retain)
    }
    /** Main-thread page/resume hint: invalidate immediately when its profile cookie changed. */
    fun sessionHint(service: BotService) {
        val old = eligible.mapNotNull { sessions[it] }.filter { it.credentials.serviceId == service.id }
        if (old.isNotEmpty() && old.any { runCatching { capture(service)?.cookie != it.credentials.cookie }.getOrDefault(true) }) {
            BotPushRuntime.epoch.incrementAndGet()
            eligible = eligible.filterNot { it.serviceId == service.id }.toSet()
        }
    }
    /** Called synchronously before cookies are cleared. Existing snapshots retain the original cookie. */
    fun retiring(service: BotService) {
        BotPushRuntime.epoch.incrementAndGet()
        eligible = eligible.filterNot { it.serviceId == service.id }.toSet()
    }
}
