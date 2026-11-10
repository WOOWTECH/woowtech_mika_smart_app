package com.wangzan101.mika.core.remote

import kotlinx.coroutines.runBlocking
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.Assert.*
import org.junit.Test

class RelayDiscoveryProtocolTest {
    private val tenant = "A".repeat(22)
    private fun info(base: String, path: String = "/r/$tenant", extra: String = "") =
        """{"schemaVersion":1,"gatewayUrl":"$base","mcpUrl":"${base.removeSuffix("/")}$path/mcp","apiBaseUrl":"${base.removeSuffix("/")}$path/api/v1","relayProtocol":"mika-relay.v2"$extra}"""

    @Test fun existingPairingDiscoversPersonalChannelWithoutPairingOrMcpToken() = runBlocking {
        MockWebServer().use { server ->
            server.start(); server.enqueue(MockResponse().setBody(info(server.url("/").toString(), extra = ",\"futureField\":true")))
            val result = RelayGateway(server.url("/"), RelayGateway.http()).connectionInfo("d".repeat(43))
            assertEquals(server.url("/r/$tenant/mcp").toString(), result.mcpUrl)
            val request = server.takeRequest()
            assertEquals("GET", request.method); assertEquals("/device/info", request.path)
            assertEquals("Bearer ${"d".repeat(43)}", request.getHeader("Authorization"))
            assertEquals("application/json", request.getHeader("Accept"))
            assertNull(request.getHeader("Origin")); assertEquals(0L, request.bodySize)
            assertEquals(1, server.requestCount)
        }
    }

    @Test fun newPairingKeepsLegacyPairResponseThenDiscoversPersonalEndpoint() = runBlocking {
        MockWebServer().use { server ->
            server.start()
            val token = "d".repeat(43)
            server.enqueue(MockResponse().setBody("""{"deviceToken":"$token","mcpUrl":"${server.url("/mcp")}"}"""))
            server.enqueue(MockResponse().setBody(info(server.url("/").toString())))
            val gateway = RelayGateway(server.url("/"), RelayGateway.http())
            val pairing = gateway.pair("one-time-test-code")
            assertNull(pairing.connectionInfo)
            assertTrue(gateway.connectionInfo(pairing.deviceToken).personal)
            assertEquals("/pair", server.takeRequest().path)
            val discovery = server.takeRequest()
            assertEquals("/device/info", discovery.path)
            assertEquals("Bearer $token", discovery.getHeader("Authorization"))
            assertEquals(2, server.requestCount)
        }
    }

    @Test fun stalledDiscoveryHasABoundedDeadlineWithoutRetrying() = runBlocking {
        MockWebServer().use { server ->
            server.start()
            server.enqueue(MockResponse().setSocketPolicy(okhttp3.mockwebserver.SocketPolicy.NO_RESPONSE))
            val http = RelayGateway.http().newBuilder().callTimeout(java.time.Duration.ofMillis(150)).build()
            try { RelayGateway(server.url("/"), http).connectionInfo("d".repeat(43)); fail() }
            catch (e: RelayGateway.Failure) { assertFalse(e.unauthorized) }
            assertEquals(1, server.requestCount)
        }
    }

    @Test fun serverVerifiedSinglePhoneGatewayRemainsCompatible() = runBlocking {
        MockWebServer().use { server ->
            server.start(); server.enqueue(MockResponse().setBody(info(server.url("/").toString(), path = "")))
            val result = RelayGateway(server.url("/"), RelayGateway.http()).connectionInfo("d".repeat(43))
            assertEquals(server.url("/api/v1").toString(), result.apiBaseUrl)
        }
    }

    @Test fun redirectsNeverForwardDeviceCredential() = runBlocking {
        MockWebServer().use { server -> MockWebServer().use { other ->
            server.start(); other.start()
            server.enqueue(MockResponse().setResponseCode(302).setHeader("Location", other.url("/device/info")))
            try { RelayGateway(server.url("/"), RelayGateway.http()).connectionInfo("d".repeat(43)); fail() }
            catch (e: RelayGateway.Failure) { assertEquals(302, e.status) }
            assertEquals(0, other.requestCount)
        } }
    }

    @Test fun errorsRemainTypedAndDoNotExposeResponseOrCredentials() = runBlocking {
        MockWebServer().use { server ->
            server.start()
            for (status in listOf(401, 403, 404, 405, 429, 503)) {
                server.enqueue(MockResponse().setResponseCode(status).setBody("private response"))
                try { RelayGateway(server.url("/"), RelayGateway.http()).connectionInfo("d".repeat(43)); fail() }
                catch (e: RelayGateway.Failure) {
                    assertEquals(status, e.status); assertEquals(status == 401, e.unauthorized)
                    assertFalse(e.toString().contains("private response")); assertFalse(e.toString().contains("d".repeat(43)))
                }
            }
        }
    }

    @Test fun malformedVersionProtocolAndOversizedResponsesAreRejected() = runBlocking {
        MockWebServer().use { server ->
            server.start(); val valid = info(server.url("/").toString())
            for (body in listOf("{}", "broken", valid.replace("schemaVersion\":1", "schemaVersion\":2"),
                valid.replace("mika-relay.v2", "mika-relay.v3"), " ".repeat(16_385))) {
                server.enqueue(MockResponse().setBody(body))
                try { RelayGateway(server.url("/"), RelayGateway.http()).connectionInfo("d".repeat(43)); fail() }
                catch (_: RelayGateway.Failure) { }
            }
        }
    }

    @Test fun addressesRequireSameOriginAndExactMatchingChannel() {
        val gateway = RelayGateway.parse("https://relay.example:8443/")
        val mcp = "https://relay.example:8443/r/$tenant/mcp"
        val api = "https://relay.example:8443/r/$tenant/api/v1"
        assertEquals(api, RelayConnectionInfo.checked(gateway, mcp, api).apiBaseUrl)
        for ((a,b) in listOf(
            mcp.replace("relay.example", "evil.example") to api,
            mcp.replace(":8443", "") to api,
            mcp.replace("https:", "http:") to api,
            mcp.replace("relay.example", "user:pass@relay.example") to api,
            "$mcp?token=x" to api, "$mcp#x" to api,
            mcp to api.replace(tenant, "B".repeat(22)), mcp to "$api?x=1",
            mcp.replace(tenant, "short") to api,
            mcp.replace(tenant, "%41" + tenant.drop(1)) to api,
            mcp.replace("/r/", "/x/../r/") to api,
            mcp.replace("/r/", "/r//") to api,
        )) {
            try { RelayConnectionInfo.checked(gateway, a,b); fail("unsafe endpoints accepted") }
            catch (_: IllegalArgumentException) { }
        }
    }
}
