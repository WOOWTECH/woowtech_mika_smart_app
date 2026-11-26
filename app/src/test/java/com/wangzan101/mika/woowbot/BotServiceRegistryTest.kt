package com.wangzan101.mika.woowbot

import org.junit.Assert.*
import org.junit.Test

class BotServiceRegistryTest {
    private class Memory : BotServiceRegistry.Storage {
        var value: String? = null
        var fail = false
        override fun read() = value
        override fun write(value: String) { check(!fail); this.value = value }
    }
    @Test fun sameOriginServicesKeepDifferentProfilesAcrossRestart() {
        val memory = Memory()
        val registry = BotServiceRegistry(memory)
        val first = registry.add("Work", "https://bot.example")
        val second = registry.add("Other account", "https://bot.example")
        assertNotEquals(first.profileName, second.profileName)
        assertEquals(registry.state.value, BotServiceRegistry(memory).state.value)
    }
    @Test fun disconnectKeepsSessionAndLogoutRotatesOnlySelectedService() {
        val registry = BotServiceRegistry(Memory())
        val first = registry.add("Work", "https://work.example")
        val second = registry.add("Home", "https://home.example")
        registry.setEnabled(first.id, false)
        assertEquals(first.profileName, registry.find(first.id)!!.profileName)
        registry.setEnabled(first.id, true)
        registry.logout(first.id)
        assertFalse(registry.find(first.id)!!.enabled)
        assertNotEquals(first.profileName, registry.find(first.id)!!.profileName)
        assertEquals(second, registry.find(second.id))
        assertEquals(listOf(first.profileName), registry.state.value.retiredProfiles)
    }
    @Test fun persistenceFailureDoesNotPublishMutation() {
        val memory = Memory()
        val registry = BotServiceRegistry(memory)
        val first = registry.add("Work", "https://work.example")
        memory.fail = true
        assertThrows(IllegalStateException::class.java) { registry.logout(first.id) }
        assertEquals(first, registry.find(first.id))
        assertTrue(registry.state.value.retiredProfiles.isEmpty())
    }
    @Test fun limitsServicesAndRetiredProfilesWithoutDroppingDeletionQueue() {
        val registry = BotServiceRegistry(Memory())
        repeat(BotServiceRegistry.MAX_SERVICES) { registry.add("Service $it", "https://bot.example") }
        assertThrows(IllegalArgumentException::class.java) { registry.add("Too many", "https://bot.example") }
        val first = registry.state.value.services.first()
        repeat(BotServiceRegistry.MAX_RETIRED) { registry.logout(first.id) }
        val before = registry.state.value
        assertThrows(IllegalArgumentException::class.java) { registry.logout(first.id) }
        assertEquals(before, registry.state.value)
        registry.acknowledgeDeleted(before.retiredProfiles.first())
        registry.logout(first.id)
        assertEquals(BotServiceRegistry.MAX_RETIRED, registry.state.value.retiredProfiles.size)
    }
    @Test fun removalRetiresProfileAndBoundsStoredData() {
        val memory = Memory()
        val registry = BotServiceRegistry(memory)
        val service = registry.add("Work", "https://bot.example")
        registry.remove(service.id)
        assertNull(registry.find(service.id))
        assertEquals(listOf(service.profileName), registry.state.value.retiredProfiles)
        memory.value = "x".repeat(BotServiceRegistry.MAX_STORAGE + 1)
        assertThrows(IllegalArgumentException::class.java) { BotServiceRegistry(memory) }
    }
    @Test fun notificationTargetNeverAcceptsAnOriginOrScriptFromPayload() {
        val service = BotServiceRegistry(Memory()).add("Work", "https://bot.example")
        assertEquals("https://bot.example/?thread=t-123&bot=b_2", BotWebTarget.url(service, "b_2", "t-123"))
        assertEquals("https://bot.example/?thread=thread:2.1&bot=bot:1", BotWebTarget.url(service, "bot:1", "thread:2.1"))
        listOf("../admin", "x&url=https://evil", "javascript:alert(1)", "a".repeat(129), "").forEach {
            assertThrows(IllegalArgumentException::class.java) { BotWebTarget.url(service, it, "thread") }
        }
    }
}
