package com.wangzan101.mika.core.woowbot.push

import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test

class BotPushTest {
    private fun target(event: String = "event_1", service: String = "service_1") =
        BotPushTarget(service, "bot_1", "thread_1", event, "finished")

    @Test fun strictPayloadRejectsUrlsContentUnknownVersionAndMissingIds() {
        val data = target().data()
        assertEquals(target(), BotPushContract.parse(data))
        for (key in data.keys) assertNull(BotPushContract.parse(data - key))
        assertNull(BotPushContract.parse(data + ("url" to "https://evil.example")))
        assertNull(BotPushContract.parse(data + ("title" to "private content")))
        assertNull(BotPushContract.parse(data + ("v" to "2")))
        assertNull(BotPushContract.parse(data + ("reason" to "execute")))
        for (id in listOf("", "../a", "https://evil", "a b", "x".repeat(129))) {
            assertNull(BotPushContract.parse(data + ("serviceId" to id)))
        }
    }
    @Test fun unknownServiceRejectedAndQueuedTapRevalidatedAfterRemoval() {
        var known = true
        val router = BotPushRouter({ known && it == "service_1" })
        assertFalse(router.offer(target(service = "evil").data()))
        assertTrue(router.offer(target().data()))
        known = false
        router.drain({ true }) { fail("Removed service routed"); true }
    }
    @Test fun coldTapWaitsForAuthAndSuccessfulNavigationThenDedupsOnlyThatEvent() {
        val router = BotPushRouter({ true })
        assertTrue(router.offer(target().data()))
        router.drain({ false }) { fail("Not ready"); true }
        router.drain({ true }) { false }
        val opened = mutableListOf<String>()
        router.drain({ true }) { opened.add(it.eventId); true }
        assertFalse(router.offer(target().data()))
        assertTrue(router.offer(target("event_2").data()))
        router.drain({ true }) { opened.add(it.eventId); true }
        assertEquals(listOf("event_1", "event_2"), opened)
    }
    @Test fun dedupAndPendingQueueAreBounded() {
        val dedup = BotPushDedup(2)
        assertTrue(dedup.remember("1")); assertFalse(dedup.remember("1"))
        dedup.remember("2"); dedup.remember("3")
        assertTrue(dedup.remember("1"))
        val router = BotPushRouter({ true }, 2)
        (1..3).forEach { router.offer(target("e$it").data()) }
        val opened = mutableListOf<String>()
        router.drain({ true }) { opened.add(it.eventId); true }
        assertEquals(listOf("e2", "e3"), opened)
    }
    @Test fun missingServerCapabilityIsNeverReportedRegistered() = runBlocking {
        val ledger = Ledger()
        val lifecycle = BotPushLifecycle(UnavailableBotPushDeviceApi, ledger)
        assertFalse(lifecycle.reconcile("token", setOf(BotPushBinding("s", "a"))))
        assertTrue(lifecycle.serverNotReady)
        assertTrue(ledger.entries.isEmpty())
    }
    @Test fun separatorInOpaqueIdsCannotCollideAcrossTargets() {
        val first = BotPushTarget("a:b", "c", "d", "e", "attention")
        val second = BotPushTarget("a", "b:c", "d", "e", "attention")
        assertEquals(first, BotPushContract.parse(first.data()))
        assertNotEquals(first.deliveryKey, second.deliveryKey)
    }
    private class Ledger : BotPushLedger {
        var entries = emptySet<BotPushBinding>()
        override fun read() = entries
        override fun write(bindings: Set<BotPushBinding>) { entries = bindings }
    }
    private class Api : BotPushDeviceApi {
        val calls = mutableListOf<String>()
        var failPut = false
        var failDelete = false
        override suspend fun register(binding: BotPushBinding, token: String) {
            calls.add("put:${binding.authIdentity}:$token")
            if (failPut) error("offline")
        }
        override suspend fun revoke(binding: BotPushBinding) {
            calls.add("delete:${binding.authIdentity}")
            if (failDelete) error("offline")
        }
    }
    @Test fun logoutCleanupOnlyRevokesTheCapturedIdentityAndPreservesPeers() = runBlocking {
        val api = Api(); val ledger = Ledger(); val lifecycle = BotPushLifecycle(api, ledger)
        val old = BotPushBinding("service", "old")
        val newer = BotPushBinding("service", "new")
        val peer = BotPushBinding("other", "peer")
        ledger.entries = setOf(old, newer, peer)
        assertTrue(lifecycle.revokeBindings(setOf(old)))
        assertEquals(listOf("delete:old"), api.calls)
        assertEquals(setOf(newer, peer), ledger.entries)
        assertTrue(lifecycle.revokeBindings(setOf(old)))
        assertEquals(1, api.calls.size)
    }
    @Test fun failedLogoutCleanupRetainsLedgerUntilExplicitDeleteAcknowledgement() = runBlocking {
        val api = Api(); val ledger = Ledger(); val lifecycle = BotPushLifecycle(api, ledger)
        val old = BotPushBinding("service", "old")
        ledger.entries = setOf(old)
        api.failDelete = true
        assertFalse(lifecycle.revokeBindings(setOf(old)))
        assertEquals(setOf(old), ledger.entries)
        api.failDelete = false
        assertTrue(lifecycle.revokeBindings(setOf(old)))
        assertTrue(ledger.entries.isEmpty())
    }
    @Test fun rotationReplacesSameBindingAndOptOutRevokesAfterAmbiguousPut() = runBlocking {
        val api = Api(); val ledger = Ledger(); val lifecycle = BotPushLifecycle(api, ledger)
        val binding = BotPushBinding("service", "sessionA")
        assertTrue(lifecycle.reconcile("t1", setOf(binding)))
        assertTrue(lifecycle.reconcile("t2", setOf(binding)))
        api.failPut = true
        assertFalse(lifecycle.reconcile("t3", setOf(binding)))
        assertEquals(setOf(binding), ledger.entries)
        assertTrue(lifecycle.reconcile(null, emptySet()))
        assertEquals(listOf("put:sessionA:t1", "put:sessionA:t2", "put:sessionA:t3", "delete:sessionA"), api.calls)
        assertTrue(ledger.entries.isEmpty())
    }
    @Test fun failedRevokeSurvivesRestartAndBlocksNewIdentityAtSameService() = runBlocking {
        val api = Api(); val ledger = Ledger(); val first = BotPushLifecycle(api, ledger)
        val old = BotPushBinding("service", "old"); val new = BotPushBinding("service", "new")
        first.reconcile("token", setOf(old))
        api.failDelete = true
        assertFalse(BotPushLifecycle(api, ledger).reconcile("token", setOf(new)))
        assertEquals(setOf(old), ledger.entries)
        assertFalse(api.calls.any { it.startsWith("put:new") })
        api.failDelete = false
        assertTrue(BotPushLifecycle(api, ledger).reconcile("token", setOf(new)))
        assertEquals(setOf(new), ledger.entries)
    }
    @Test fun disabledWithoutTokenNeverRegistersAndDifferentServicesRemainIsolated() = runBlocking {
        val api = Api(); val ledger = Ledger(); val lifecycle = BotPushLifecycle(api, ledger)
        val a = BotPushBinding("serviceA", "a"); val b = BotPushBinding("serviceB", "b")
        assertTrue(lifecycle.reconcile(null, emptySet()))
        assertTrue(api.calls.isEmpty())
        assertFalse(lifecycle.reconcile(null, setOf(a)))
        assertTrue(api.calls.isEmpty())
        lifecycle.reconcile("token", setOf(a, b))
        lifecycle.reconcile("token", setOf(b))
        assertEquals(setOf(b), ledger.entries)
        assertEquals(listOf("put:a:token", "put:b:token", "delete:a", "put:b:token"), api.calls)
    }
}
