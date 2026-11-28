package com.wangzan101.mika.woowbot.push

import android.os.SystemClock
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.webkit.ProfileStore
import com.wangzan101.mika.BuildConfig
import com.wangzan101.mika.core.woowbot.push.*
import com.wangzan101.mika.woowbot.BotService
import com.wangzan101.mika.woowbot.BotServices
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/**
 * 2026-11-28: one unreachable registered service left every service without notifications (the POCO dropped Podman pushes
 * while two PaaS labs timed out). Real registry, WebView profiles and cookies; only the HTTP transport stands in for the
 * servers.
 */
@RunWith(AndroidJUnit4::class)
class BotPushConnectionsDeviceTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context = instrumentation.targetContext
    private val registry by lazy { BotServices.registry(context) }
    private val added = mutableListOf<BotService>()

    @Before fun setUp() {
        assumeTrue(BuildConfig.WOOWTECHBOT_ENABLED)
        var supported = false
        instrumentation.runOnMainSync { supported = BotServices.supportsIsolation() }
        assumeTrue("WebView provider has no MULTI_PROFILE support", supported)
    }

    @After fun tearDown() { added.forEach { runCatching { registry.remove(it.id) } } }

    private fun service(name: String, address: String): BotService {
        val service = registry.add(name, address).also(added::add)
        val ready = CountDownLatch(1)
        instrumentation.runOnMainSync {
            ProfileStore.getInstance().getOrCreateProfile(service.profileName).cookieManager
                .setCookie(service.origin, "session=qa; Secure; Path=/") { ready.countDown() }
        }
        assertTrue("cookie not stored", ready.await(10, TimeUnit.SECONDS))
        return service
    }

    /** The app's own push runtime reacts to registry changes by moving the epoch; start once it is still. */
    private fun settle() {
        val end = SystemClock.elapsedRealtime() + 10_000
        var last = BotPushRuntime.epoch.get()
        var stillSince = SystemClock.elapsedRealtime()
        while (SystemClock.elapsedRealtime() < end) {
            SystemClock.sleep(100)
            val now = BotPushRuntime.epoch.get()
            if (now != last) { last = now; stillSince = SystemClock.elapsedRealtime() }
            else if (SystemClock.elapsedRealtime() - stillSince > 1_500) return
        }
    }

    private fun session(id: String) = """{"kind":"session","via":"cookie","scopes":["client"],"id":"$id",
        "environmentId":"env-qa","capabilities":{"woowtechAndroidPush":1},"cookieOnly":true,
        "woowtechAndroidPush":{"devicePath":"${BotPushHttpApi.PATH}","payloadVersion":"1","auth":"cookie",
        "acceptsCookieOnly":true,"enabled":true,"ready":true}}"""

    @Test fun aServiceThatCannotBeCheckedDoesNotHoldBackTheOthers() = runBlocking {
        val good = service("Reachable QA", "https://reachable-qa.invalid")
        val down = service("Unreachable QA", "https://unreachable-qa.invalid")
        settle()
        val connections = BotPushConnections(registry, { setOf(BotPushBinding(down.id, "registered-before")) },
            BotPushHttpTransport { credentials, _, path, _, _, _ ->
                check(path == "/api/auth/session")
                if (credentials.origin == good.origin) BotPushHttpResponse(200, session("session-reachable"))
                else throw java.io.IOException("unreachable")
            })
        // The registered service that cannot be checked still stops any cleanup or revocation...
        assertTrue(runCatching { connections.prepare() }.isFailure)
        // ...but the one that answered takes notifications.
        assertEquals(setOf(good.id), connections.bindings().map { it.serviceId }.toSet())
        assertTrue(connections.ready())
        assertEquals(BotPushDiscovery.READY, connections.discovery.value[good.id])
        assertEquals(BotPushDiscovery.UNAVAILABLE, connections.discovery.value[down.id])
    }

    @Test fun servicesAreCheckedSideBySide() = runBlocking {
        val a = service("Slow QA A", "https://slow-a-qa.invalid")
        val b = service("Slow QA B", "https://slow-b-qa.invalid")
        settle()
        val connections = BotPushConnections(registry, { emptySet() }, BotPushHttpTransport { credentials, _, _, _, _, _ ->
            delay(2_000)
            BotPushHttpResponse(200, session("session-" + credentials.serviceId.take(8)))
        })
        val started = SystemClock.elapsedRealtime()
        connections.prepare()
        val took = SystemClock.elapsedRealtime() - started
        assertEquals(setOf(a.id, b.id), connections.bindings().map { it.serviceId }.toSet())
        assertTrue("two 2 s checks took $took ms", took < 3_500)
    }
}
