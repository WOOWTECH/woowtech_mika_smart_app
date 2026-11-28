package com.wangzan101.mika.woowbot.push

import androidx.webkit.ProfileStore
import com.wangzan101.mika.core.woowbot.push.*
import com.wangzan101.mika.woowbot.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import java.util.concurrent.ConcurrentHashMap

/** Only cookies in process memory; durable ledger remains identity-only. All profile reads run on main. */
internal class BotPushConnections(private val registry: BotServiceRegistry, private val pending: () -> Set<BotPushBinding>,
    transport: BotPushHttpTransport = BotPushOkHttpTransport()) {
    val discovery = kotlinx.coroutines.flow.MutableStateFlow<Map<String, BotPushDiscovery>>(emptyMap())
    private fun report(id: String, state: BotPushDiscovery) { discovery.value = discovery.value + (id to state) }
    private val sessions = ConcurrentHashMap<BotPushBinding, BotPushSession>()
    private val retiringCredentials = ConcurrentHashMap<String, BotPushCredentials>()
    @Volatile private var eligible: Set<BotPushBinding> = emptySet()
    @Volatile private var epoch = -1L
    val api = BotPushHttpApi(transport, { sessions[it] }, ::current) {
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
        val enabled = registry.state.value.services.filter { it.enabled }
        discovery.value = enabled.associate { it.id to BotPushDiscovery.CHECKING }
        // Services are asked side by side, each within its own time limit (see the transport), so one unreachable service
        // holds back the others' notifications by seconds, not by the sum of every timeout.
        val checked = coroutineScope {
            enabled.map { service ->
                val credentials = withContext(Dispatchers.Main.immediate) { runCatching { capture(service) }.getOrNull() }
                Triple(service, credentials, credentials?.let { async { discover(it) } })
            }.map { (service, credentials, found) -> Triple(service, credentials, found?.await()) }
        }
        for ((service, credentials, session) in checked) {
            val hasRegistration = recorded.any { it.serviceId == service.id }
            if (credentials == null) {
                report(service.id, BotPushDiscovery.SIGN_IN_REQUIRED)
                if (hasRegistration) unresolvedRegistration = true
                continue
            }
            if (session == null) {
                report(service.id, BotPushDiscovery.UNAVAILABLE)
                // Missing discovery is not a user request to revoke a previously registered service.
                if (hasRegistration) unresolvedRegistration = true
                continue
            }
            if (!valid() || !current(credentials)) {
                report(service.id, BotPushDiscovery.IDENTITY_CHANGED)
                if (hasRegistration) unresolvedRegistration = true
                continue
            }
            report(service.id, if (session.ready) BotPushDiscovery.READY else BotPushDiscovery.SERVER_NOT_READY)
            sessions[session.binding] = session
            if (session.ready) next.add(session.binding)
            else if (hasRegistration) unresolvedRegistration = true
        }
        // 2026-11-28: one unreachable registered service used to leave every service without notifications. The services
        // verified now keep taking them; the unresolved one keeps its registration (the check below stops any cleanup or
        // revocation) and takes none until it answers again.
        if (valid()) eligible = next
        check(!unresolvedRegistration) { "Registered service discovery is temporarily unavailable" }
        val retain = pending() + next
        sessions.keys.retainAll(retain)
    }
    private suspend fun discover(credentials: BotPushCredentials): BotPushSession? = try { api.discover(credentials) }
        catch (e: kotlinx.coroutines.CancellationException) { throw e }
        catch (_: Exception) { null }

    /** The bot's name and an excerpt for a notification already accepted, read with that service's verified session. */
    suspend fun preview(target: BotPushTarget): BotPushPreview? {
        val binding = bindings().firstOrNull { it.serviceId == target.serviceId } ?: return null
        val credentials = sessions[binding]?.credentials ?: return null
        if (!current(credentials)) return null
        return try { withTimeout(8_000L) { api.preview(credentials, target.botId, target.threadId) } }
        catch (_: kotlinx.coroutines.TimeoutCancellationException) { null }
        catch (e: kotlinx.coroutines.CancellationException) { throw e }
        catch (_: Exception) { null }
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
        runCatching { capture(service) }.getOrNull()?.let { retiringCredentials[service.profileId] = it }
        BotPushRuntime.epoch.incrementAndGet()
        eligible = eligible.filterNot { it.serviceId == service.id }.toSet()
    }
    suspend fun retiredBindings(service: BotService): Set<BotPushBinding> {
        val recorded = pending().filter { it.serviceId == service.id }.toSet()
        if (recorded.isEmpty()) return emptySet()
        val cached = sessions.values.filter { it.credentials.serviceId == service.id &&
            it.credentials.profileEpoch == service.profileId && it.credentials.origin == service.origin }
            .map { it.binding }.toSet().intersect(recorded)
        if (cached.isNotEmpty()) return cached
        val credentials = retiringCredentials[service.profileId] ?: throw BotPushStaleException()
        val session = api.discover(credentials)
        if (session.binding !in recorded) return emptySet()
        sessions[session.binding] = session
        return setOf(session.binding)
    }
    fun forgetRetiring(service: BotService) { retiringCredentials.remove(service.profileId) }
}
