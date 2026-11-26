package com.wangzan101.mika.core.woowbot.push

import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/** Identity includes service AND paired account/session epoch; never use the currently selected service. */
data class BotPushBinding(val serviceId: String, val authIdentity: String)

/** Adapter must resolve credentials for this exact binding, reject redirects, and use the saved direct origin.
 * PUT replaces the authenticated phone's token atomically; DELETE is idempotent.
 * Before PUT require the woowtechAndroidPush v1 capability and the dedicated device route.
 * Capture session identity, profile epoch and exact origin; abort if any changes. True cookieOnly
 * is accepted only on this dedicated route. Throw BotPushNotReadyException only for preflight rejection.
 * Registration success means the server acknowledged the token AND routing alias, not real delivery.
 */
interface BotPushDeviceApi {
    suspend fun register(binding: BotPushBinding, token: String)
    suspend fun revoke(binding: BotPushBinding)
}

/** Preflight failure only: adapter guarantees no registration mutation was attempted. */
class BotPushNotReadyException : Exception("WOOWTECH push registration capability is unavailable")

/** Safe default while server capability and scoped session adapter are not integrated. */
object UnavailableBotPushDeviceApi : BotPushDeviceApi {
    override suspend fun register(binding: BotPushBinding, token: String): Unit = throw BotPushNotReadyException()
    override suspend fun revoke(binding: BotPushBinding): Unit = throw BotPushNotReadyException()
}

/** Durable ledger contains identities only, never credentials or tokens. Persist before each PUT. */
interface BotPushLedger {
    fun read(): Set<BotPushBinding>
    fun write(bindings: Set<BotPushBinding>)
}

/** One controller per installation. All retries re-read the latest token and desired bindings.
 * A failed/ambiguous PUT remains in the ledger; opt-out will still DELETE it. Never silently drop revokes.
 */
class BotPushLifecycle(private val api: BotPushDeviceApi, private val ledger: BotPushLedger) {
    private val mutex = Mutex()
    var serverNotReady: Boolean = false
        private set
    suspend fun reconcile(token: String?, desired: Set<BotPushBinding>): Boolean = mutex.withLock {
        serverNotReady = false
        val recorded = ledger.read().toMutableSet()
        var complete = true
        for (binding in recorded.toSet() - desired) {
            try {
                api.revoke(binding)
                recorded.remove(binding)
                ledger.write(recorded.toSet())
            } catch (e: kotlinx.coroutines.CancellationException) { throw e }
            catch (e: Exception) {
                if (e is BotPushNotReadyException) serverNotReady = true
                complete = false
            }
        }
        // Never bind a new identity at a service while revocation of its previous identity is pending.
        for (binding in desired) {
            if (token.isNullOrBlank()) { complete = false; continue }
            if (recorded.any { it.serviceId == binding.serviceId && it != binding }) {
                complete = false; continue
            }
            val wasRecorded = binding in recorded
            recorded.add(binding)
            ledger.write(recorded.toSet())
            try { api.register(binding, token) }
            catch (e: kotlinx.coroutines.CancellationException) { throw e }
            catch (e: Exception) {
                if (e is BotPushNotReadyException) {
                    serverNotReady = true
                    // A known preflight rejection needs no revoke; ambiguous network failures still do.
                    if (!wasRecorded) { recorded.remove(binding); ledger.write(recorded.toSet()) }
                }
                complete = false
            }
        }
        complete
    }
}
