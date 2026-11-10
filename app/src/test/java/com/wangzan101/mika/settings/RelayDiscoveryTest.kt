package com.wangzan101.mika.settings

import com.wangzan101.mika.core.remote.RelayConnectionInfo
import com.wangzan101.mika.core.remote.RelayGateway
import com.wangzan101.mika.core.remote.RelayPairing
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.async
import kotlinx.coroutines.test.runTest
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import javax.crypto.KeyGenerator

class RelayDiscoveryTest {
    @get:Rule val tmp = TemporaryFolder()
    private val key = KeyGenerator.getInstance("AES").apply { init(256) }.generateKey()
    private fun settings() = RelaySettings(tmp.root, AesGcmKeyCipher { key })
    private fun pair(token: String = "a") = RelayPairing("https://relay.example/", token.repeat(43))
    private fun info(tenant: String = "A") = RelayConnectionInfo.checked(RelayGateway.parse("https://relay.example/"),
        "https://relay.example/r/${tenant.repeat(22)}/mcp", "https://relay.example/r/${tenant.repeat(22)}/api/v1")

    @Test fun oldEncryptedPairingUpgradesWithoutChangingCredentialsOrPermissions() = runTest {
        val store = settings(); store.save(pair()); store.setEnabled(true); store.setDeviceAccess(true)
        assertNull(settings().config.value.connectionInfo)
        val discovery = RelayDiscovery(store, { expected -> assertEquals(pair().deviceToken, expected.deviceToken); info() })
        discovery.refresh()
        val restored = settings()
        assertEquals(info(), restored.config.value.connectionInfo)
        assertEquals(pair().deviceToken, restored.pairing()!!.deviceToken)
        assertTrue(restored.config.value.enabled); assertTrue(restored.config.value.deviceAccess)
        val raw = tmp.root.resolve("remote-relay.bin").readText(Charsets.ISO_8859_1)
        assertFalse(raw.contains(info().mcpUrl)); assertFalse(raw.contains(pair().deviceToken))
    }

    @Test fun newPairingDiscoveryDoesNotEnableRemoteOrWakeAccess() = runTest {
        val store = settings(); store.save(pair())
        RelayDiscovery(store, { info() }).refresh()
        assertNotNull(store.config.value.connectionInfo)
        assertFalse(store.config.value.enabled); assertFalse(store.config.value.deviceAccess)
    }

    @Test fun lateAccountAResponseCannotOverwriteAccountBOrResurrectUnpairedSettings() = runTest {
        val store = settings(); store.save(pair())
        val started = CompletableDeferred<Unit>(); val response = CompletableDeferred<RelayConnectionInfo>()
        val discovery = RelayDiscovery(store, { started.complete(Unit); response.await() })
        val request = async { discovery.refresh() }; started.await()
        store.clear(); store.save(pair("b")); store.updateConnectionInfo(pair("b"), info("B"))
        response.complete(info()); request.await()
        assertEquals(info("B"), store.config.value.connectionInfo)
        assertEquals(pair("b").deviceToken, store.pairing()!!.deviceToken)
        assertEquals(RelayInfoState.Idle, discovery.state.value)
        store.clear(); assertFalse(store.updateConnectionInfo(pair("b"), info("B")))
        assertNull(settings().pairing())
    }

    @Test fun permissionChangeDuringDiscoveryIsPreserved() = runTest {
        val store = settings(); store.save(pair()); store.setEnabled(true); store.setDeviceAccess(true)
        RelayDiscovery(store, { store.setEnabled(false); store.setDeviceAccess(false); info() }).refresh()
        assertFalse(store.config.value.enabled); assertFalse(store.config.value.deviceAccess)
        assertEquals(info(), store.config.value.connectionInfo)
    }

    @Test fun temporaryFailureRetainsLastVerifiedInfoAndNeverUnpairs() = runTest {
        val store = settings(); store.save(pair()); store.updateConnectionInfo(pair(), info()); store.setEnabled(true)
        val discovery = RelayDiscovery(store, { throw RelayGateway.Failure(status = 503) })
        discovery.refresh()
        assertEquals(RelayInfoState.Unavailable, discovery.state.value)
        assertEquals(info(), settings().config.value.connectionInfo); assertTrue(store.config.value.enabled)
    }

    @Test fun revokedOrUnsafeResponseStopsUsingOldInfoWithoutLosingPairing() = runTest {
        for (status in listOf(401, 403, 200, 302)) {
            val store = settings(); store.save(pair()); store.updateConnectionInfo(pair(), info())
            val discovery = RelayDiscovery(store, { throw RelayGateway.Failure(status == 401, status) })
            discovery.refresh()
            assertNull(store.config.value.connectionInfo); assertNotNull(store.pairing())
            assertEquals(if (status == 401) RelayInfoState.Unauthorized else RelayInfoState.Invalid, discovery.state.value)
        }
    }

    @Test fun unsupportedDiscoveryDoesNotInventPersonalAddressOrRePair() = runTest {
        val store = settings(); store.save(pair())
        val discovery = RelayDiscovery(store, { throw RelayGateway.Failure(status = 404) })
        discovery.refresh()
        assertEquals(RelayInfoState.Unsupported, discovery.state.value)
        assertNull(store.config.value.connectionInfo); assertNotNull(store.pairing())

    }

    @Test fun rateLimitWaitsAMinuteWithoutPollingAndDifferentPairingCanRefresh() = runTest {
        val store = settings(); store.save(pair()); var now = 1000L; var calls = 0
        val discovery = RelayDiscovery(store, { calls++; throw RelayGateway.Failure(status = 429) }, { now })
        discovery.refresh(); discovery.refresh(); now += 59_999; discovery.refresh()
        assertEquals(1, calls)
        now++; discovery.refresh(); assertEquals(2, calls)
        store.clear(); store.save(pair("b")); discovery.refresh(); assertEquals(3, calls)
    }
    @Test fun copiedMcpConfigurationUsesPersonalAddressAndPhoneAccessToken() = runTest {
        val store = settings(); store.save(pair())
        RelayDiscovery(store, { info() }).refresh()
        val phoneToken = "phone-access-token"
        val config = com.wangzan101.mika.mcp.McpRuntime.clientConfig(store.pairing()!!.connectionInfo!!.mcpUrl, phoneToken)
        val root = kotlinx.serialization.json.Json.parseToJsonElement(config) as kotlinx.serialization.json.JsonObject
        val servers = root["mcpServers"] as kotlinx.serialization.json.JsonObject
        val client = servers["mika"] as kotlinx.serialization.json.JsonObject
        assertEquals(info().mcpUrl, (client["url"] as kotlinx.serialization.json.JsonPrimitive).content)
        val headers = client["headers"] as kotlinx.serialization.json.JsonObject
        assertEquals("Bearer $phoneToken", (headers["Authorization"] as kotlinx.serialization.json.JsonPrimitive).content)
        assertFalse(config.contains(pair().deviceToken))
    }

    @Test fun offlineExceptionKeepsPairingAndAllowsManualRecovery() = runTest {
        val store = settings(); store.save(pair()); var online = false
        val discovery = RelayDiscovery(store, { if (!online) throw java.io.IOException(); info() })
        discovery.refresh()
        assertEquals(RelayInfoState.Unavailable, discovery.state.value)
        assertNotNull(store.pairing()); assertNull(store.config.value.connectionInfo)
        online = true; discovery.refresh()
        assertEquals(RelayInfoState.Ready, discovery.state.value)
        assertEquals(info(), store.config.value.connectionInfo)
    }

}
