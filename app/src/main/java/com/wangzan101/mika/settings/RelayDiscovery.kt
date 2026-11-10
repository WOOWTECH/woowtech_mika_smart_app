package com.wangzan101.mika.settings

import com.wangzan101.mika.core.remote.RelayConnectionInfo
import com.wangzan101.mika.core.remote.RelayGateway
import com.wangzan101.mika.core.remote.RelayPairing
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

enum class RelayInfoState { Idle, Loading, Ready, Unsupported, Unavailable, Unauthorized, Invalid, RateLimited }

/** Read-only discovery; never enables access, repairs, or changes the phone access token. */
class RelayDiscovery(
    private val settings: RelaySettings,
    private val fetch: suspend (RelayPairing) -> RelayConnectionInfo = {
        RelayGateway(RelayGateway.parse(it.gateway), RelayGateway.http()).connectionInfo(it.deviceToken)
    },
    private val now: () -> Long = { System.nanoTime() / 1_000_000 },
) {
    private val mutable = MutableStateFlow(RelayInfoState.Idle)
    val state = mutable.asStateFlow()
    private val mutex = Mutex()
    private var retryAfter = 0L
    private var rateLimitedPairing: RelayPairing? = null

    suspend fun refresh() = mutex.withLock {
        val expected = settings.pairing() ?: run { mutable.value = RelayInfoState.Idle; return@withLock }
        val limited = rateLimitedPairing
        if (limited?.gateway == expected.gateway && limited.deviceToken == expected.deviceToken && now() < retryAfter) {
            mutable.value = RelayInfoState.RateLimited
            return@withLock
        }
        mutable.value = RelayInfoState.Loading
        try {
            val info = fetch(expected)
            mutable.value = if (settings.updateConnectionInfo(expected, info)) RelayInfoState.Ready else RelayInfoState.Idle
        } catch (e: CancellationException) {
            mutable.value = RelayInfoState.Idle
            throw e
        } catch (e: Exception) {
            val current = settings.pairing()
            if (current?.gateway != expected.gateway || current.deviceToken != expected.deviceToken) {
                mutable.value = RelayInfoState.Idle
                return@withLock
            }
            val failure = e as? RelayGateway.Failure
            mutable.value = when {
                failure?.unauthorized == true -> {
                    settings.updateConnectionInfo(expected, null)
                    RelayInfoState.Unauthorized
                }
                failure?.status == 404 -> RelayInfoState.Unsupported
                failure?.status == 429 -> {
                    retryAfter = now() + 60_000; rateLimitedPairing = expected
                    RelayInfoState.RateLimited
                }
                failure?.status in listOf(200, 301, 302, 303, 307, 308, 403, 405) -> {
                    settings.updateConnectionInfo(expected, null)
                    RelayInfoState.Invalid
                }
                else -> RelayInfoState.Unavailable
            }
        }
    }

}
