package com.wangzan101.mika.core.woowbot.push

import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test

class BotPushHttpTest {
    private val service = "b91482c6-8dd0-46b3-a2de-13a8c3932762"
    private val registration = "4ed74558-5f97-424a-bfa6-70965405c611"
    private val token = "opaque-without-colon-123456789"
    private fun session(ready: Boolean = true, cookieOnly: Boolean = false, id: String = "session-a") = """
        {"kind":"session","id":"$id","environmentId":"env-a","via":"cookie","scopes":["client"],
        "cookieOnly":$cookieOnly,"capabilities":{"woowtechAndroidPush":1},"woowtechAndroidPush":{
        "devicePath":"/api/woowtech/android-push/device","payloadVersion":"1","auth":"cookie",
        "acceptsCookieOnly":true,"enabled":$ready,"ready":$ready}}
    """.trimIndent()
    private fun registered(alias: String = service) = """{"v":1,"serviceId":"$alias","registrationId":"$registration","state":"registered","registered":true}"""
    private val absent = """{"v":1,"serviceId":null,"registrationId":null,"state":"absent","registered":false}"""
    private class Ledger : BotPushLedger {
        var entries = emptySet<BotPushBinding>()
        override fun read() = entries
        override fun write(bindings: Set<BotPushBinding>) { entries = bindings }
    }
    private inner class Fixture {
        val credentials = BotPushCredentials(service, "profile-a", "https://lab.example", "session=fixture")
        var auth = session()
        var result = BotPushHttpResponse(200, registered())
        var current = true
        var freshToken = true
        var afterAuth: () -> Unit = {}
        var beforeDevice: () -> Unit = {}
        var afterDevice: () -> Unit = {}
        var saved: BotPushSession? = null
        val methods = mutableListOf<String>()
        val bodies = mutableListOf<String?>()
        val cookies = mutableListOf<String>()
        val headers = mutableListOf<String?>()
        val api = BotPushHttpApi(BotPushHttpTransport { c, method, path, id, body, beforeSend ->
            if (path != "/api/auth/session") beforeDevice()
            beforeSend()
            methods.add("$method $path"); bodies.add(body); cookies.add(c.cookie); headers.add(id)
            if (path == "/api/auth/session") { afterAuth(); BotPushHttpResponse(200, auth) } else { afterDevice(); result }
        }, { binding -> saved?.takeIf { it.binding == binding } }, { current }, { freshToken })
        suspend fun init(): BotPushBinding {
            saved = api.discover(credentials)
            methods.clear(); bodies.clear(); cookies.clear(); headers.clear()
            return saved!!.binding
        }
    }
    @Test fun ordinaryAndTrueCookieOnlyUseSameDedicatedFourFieldProtocol() = runBlocking {
        for (cookieOnly in listOf(false, true)) {
            val f = Fixture(); f.auth = session(cookieOnly = cookieOnly)
            val binding = f.init(); assertEquals(cookieOnly, f.saved!!.cookieOnly)
            f.api.register(binding, token)
            assertEquals(listOf("GET /api/auth/session", "PUT ${BotPushHttpApi.PATH}"), f.methods)
            val json = Json.parseToJsonElement(f.bodies.last()!!).jsonObject
            assertEquals(setOf("v", "platform", "serviceId", "token"), json.keys)
            assertEquals(JsonPrimitive(1), json["v"])
            assertEquals(listOf("session=fixture", "session=fixture"), f.cookies)
            assertEquals(listOf(null, "session-a"), f.headers)
        }
    }
    @Test fun disabledCapabilityPreflightNeverPutsOrLeavesNewLedger() = runBlocking {
        val f = Fixture(); val binding = f.init(); f.auth = session(ready = false)
        val ledger = Ledger(); val lifecycle = BotPushLifecycle(f.api, ledger)
        assertFalse(lifecycle.reconcile(token, setOf(binding)))
        assertTrue(lifecycle.serverNotReady); assertTrue(ledger.entries.isEmpty())
        assertEquals(listOf("GET /api/auth/session"), f.methods)
    }
    @Test fun missingCapabilityWrongVersionKindScopeAndRouteRejected() = runBlocking {
        for (auth in listOf(session().replace("\"woowtechAndroidPush\":1", "\"woowtechAndroidPush\":2"),
            session().replace("\"kind\":\"session\"", "\"kind\":\"owner\""),
            session().replace("[\"client\"]", "[]"), session().replace("\"via\":\"cookie\"", "\"via\":\"bearer\""),
            session().replace("/api/woowtech/android-push/device", "/api/push/device"),
            session().replace("\"cookieOnly\":false,", ""))) {
            val f = Fixture(); f.auth = auth
            try { f.init(); fail("Invalid session accepted") } catch (_: BotPushNotReadyException) { }
        }
    }
    @Test fun staleProfileOrTokenAfterDiscoveryNeverPuts() = runBlocking {
        for (profile in listOf(true, false)) {
            val f = Fixture(); val binding = f.init()
            f.afterAuth = { if (profile) f.current = false else f.freshToken = false }
            try { f.api.register(binding, token); fail("Stale PUT") } catch (_: BotPushStaleException) { }
            assertEquals(listOf("GET /api/auth/session"), f.methods)
        }
    }
    @Test fun changedSessionCannotUseNewIdentityToRegisterOrRevokeOldLedger() = runBlocking {
        val f = Fixture(); val binding = f.init(); f.auth = session(id = "new-session")
        for (delete in listOf(false, true)) {
            try { if (delete) f.api.revoke(binding) else f.api.register(binding, token); fail("Identity replaced") }
            catch (_: BotPushStaleException) { }
        }
        assertTrue(f.methods.all { it == "GET /api/auth/session" })
    }
    @Test fun ambiguous503AndOtherFailuresRetainLedger() = runBlocking {
        for (status in listOf(301, 400, 401, 403, 404, 409, 429, 503)) {
            val f = Fixture(); val binding = f.init()
            f.result = BotPushHttpResponse(status, """{"code":"relay_unavailable"}""")
            val ledger = Ledger(); val lifecycle = BotPushLifecycle(f.api, ledger)
            assertFalse(lifecycle.reconcile(token, setOf(binding)))
            assertEquals(setOf(binding), ledger.entries)
            assertFalse(lifecycle.reconcile(null, emptySet()))
            assertEquals(setOf(binding), ledger.entries)
        }
    }
    @Test fun explicitPushNotReady503RemovesOnlyNewLedger() = runBlocking {
        val f = Fixture(); val binding = f.init()
        val ledger = Ledger(); val lifecycle = BotPushLifecycle(f.api, ledger)
        f.result = BotPushHttpResponse(503, """{"code":"push_not_ready"}""")
        assertFalse(lifecycle.reconcile(token, setOf(binding))); assertTrue(ledger.entries.isEmpty())
        ledger.entries = setOf(binding)
        assertFalse(lifecycle.reconcile(token, setOf(binding))); assertEquals(setOf(binding), ledger.entries)
    }
    @Test fun disabledAndRetiredProfileCanDeleteOnlyCapturedIdentity() = runBlocking {
        val f = Fixture(); val binding = f.init(); f.auth = session(ready = false)
        f.current = false; f.freshToken = false; f.result = BotPushHttpResponse(200, absent)
        f.api.revoke(binding)
        assertEquals("DELETE ${BotPushHttpApi.PATH}?serviceId=$service", f.methods.last())
        assertNull(f.bodies.last()); assertEquals("session-a", f.headers.last())
        assertEquals("session=fixture", f.cookies.last())
    }
    @Test fun badAckCannotClearLedgerOrDeclareRegistration() = runBlocking {
        for (body in listOf(registered("another-alias"), absent, registered().replace("true", "false"))) {
            val f = Fixture(); val binding = f.init(); f.result = BotPushHttpResponse(200, body)
            val ledger = Ledger(); assertFalse(BotPushLifecycle(f.api, ledger).reconcile(token, setOf(binding)))
            assertEquals(setOf(binding), ledger.entries)
        }
    }
    @Test fun invalidTokensFailBeforeAnyNetworkAndOpaqueAsciiAllowed() = runBlocking {
        val f = Fixture(); val binding = f.init()
        for (bad in listOf("short", "x".repeat(4097), "x".repeat(20) + " ", "x".repeat(20) + "\n")) {
            try { f.api.register(binding, bad); fail("Invalid token accepted") } catch (_: IllegalArgumentException) { }
        }
        assertTrue(f.methods.isEmpty())
        f.api.register(binding, token)
    }
    @Test fun pendingGetIsReadOnlyAndNotReportedRegistered() = runBlocking {
        val f = Fixture(); val binding = f.init()
        f.result = BotPushHttpResponse(200, registered().replace("\"registered\",", "\"pending\",").replace(":true", ":false"))
        assertEquals(JsonPrimitive(false), f.api.get(binding)["registered"])
        assertEquals(listOf("GET /api/auth/session", "GET ${BotPushHttpApi.PATH}"), f.methods)
    }
    @Test fun tokenChangeAtTransportDispatchBlocksPut() = runBlocking {
        val f = Fixture(); val binding = f.init(); f.beforeDevice = { f.freshToken = false }
        try { f.api.register(binding, token); fail("Stale token sent") } catch (_: BotPushStaleException) { }
        assertEquals(listOf("GET /api/auth/session"), f.methods)
    }
    @Test fun profileChangeDuringSuccessfulPutKeepsAmbiguousLedger() = runBlocking {
        val f = Fixture(); val binding = f.init(); f.afterDevice = { f.current = false }
        val ledger = Ledger()
        assertFalse(BotPushLifecycle(f.api, ledger).reconcile(token, setOf(binding)))
        assertEquals(setOf(binding), ledger.entries)
    }
    @Test fun nonHttpsAndNonExactOriginsRejected() {
        for (origin in listOf("http://lab.example", "https://lab.example/", "https://lab.example/path", "https://name@lab.example")) {
            try { BotPushCredentials(service, "p", origin, "fixture=cookie"); fail("Invalid origin") }
            catch (_: IllegalArgumentException) { }
        }
    }
}
