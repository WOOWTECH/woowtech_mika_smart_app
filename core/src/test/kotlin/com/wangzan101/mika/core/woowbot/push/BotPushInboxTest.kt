package com.wangzan101.mika.core.woowbot.push

import org.junit.Assert.*
import org.junit.Test

class BotPushInboxTest {
    private val target = BotPushTarget("service", "bot", "thread", "event", "finished")
    @Test fun coldReceiptSurvivesRestartAndWaitsForAuthentication() {
        val first = BotPushInbox()
        assertTrue(first.offer(target, "profile", 1000, 600, 1000))
        val restored = BotPushInbox(first.snapshot())
        assertFalse(restored.drain(2000, { "profile" }, { false }) { fail("Not authenticated") })
        var delivered = 0
        assertTrue(restored.drain(3000, { "profile" }, { true }) { delivered++ })
        assertEquals(1, delivered)
        restored.drain(4000, { "profile" }, { true }) { fail("Duplicate") }
    }
    @Test fun duplicateCannotExtendExpiryAndOriginalTtlIsHonored() {
        val inbox = BotPushInbox()
        assertTrue(inbox.offer(target, "p", 1000, 10, 1000))
        assertFalse(inbox.offer(target, "p", 9000, 600, 9000))
        assertTrue(inbox.drain(11000, { "p" }, { true }) { fail("Expired") })
        assertFalse(inbox.offer(target, "p", 1000, 10, 12000))
    }
    @Test fun logoutRemovalAndProfileChangeDiscardQueuedEvents() {
        for (profile in listOf(null, "new-profile")) {
            val inbox = BotPushInbox()
            inbox.offer(target, "old-profile", 1000, 600, 1000)
            assertTrue(inbox.drain(2000, { profile }, { true }) { fail("Old identity") })
        }
    }
    @Test fun queueIsBoundedAndDoesNotMergeDifferentEventsInSameThread() {
        val inbox = BotPushInbox(capacity = 2)
        for (i in 1..3) inbox.offer(target.copy(eventId = "event$i"), "p", 1000, 600, 1000)
        assertEquals(listOf("event2", "event3"), inbox.snapshot().map { it.target.eventId })
        val events = mutableListOf<String>()
        inbox.drain(2000, { "p" }, { true }) { events.add(it.eventId) }
        assertEquals(listOf("event2", "event3"), events)
    }
    @Test fun invalidClockAndTtlAreRejectedAndLifetimeIsCapped() {
        val inbox = BotPushInbox()
        assertFalse(inbox.offer(target, "p", 0, 600, 1000))
        assertFalse(inbox.offer(target, "p", 1000, 0, 1000))
        assertFalse(inbox.offer(target, "p", 100000, 600, 1000))
        assertTrue(inbox.offer(target, "p", 1000, 3600, 1000))
        assertEquals(601000L, inbox.snapshot().single().expiresAt)
    }
}
