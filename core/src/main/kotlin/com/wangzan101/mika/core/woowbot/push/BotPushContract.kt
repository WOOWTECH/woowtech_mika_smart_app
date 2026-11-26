package com.wangzan101.mika.core.woowbot.push

/** Proposed WOOWTECH bot v1 data-only payload. No URLs, names or message content. */
object BotPushContract {
    const val DEVICE_PATH = "/api/push/device"
    val kinds = setOf("finished", "permission", "attention")
    private val id = Regex("[A-Za-z0-9][A-Za-z0-9_.:-]{0,127}")
    private val fields = setOf("v", "serviceId", "botId", "threadId", "eventId", "reason")
    fun validId(value: String) = id.matches(value)
    fun parse(data: Map<String, String>): BotPushTarget? {
        if (data.keys != fields || data["v"] != "1") return null
        val ids = listOf("serviceId", "botId", "threadId", "eventId").map { data.getValue(it) }
        if (ids.any { !validId(it) } || data["reason"] !in kinds) return null
        return BotPushTarget(ids[0], ids[1], ids[2], ids[3], data.getValue("reason"))
    }
}

data class BotPushTarget(val serviceId: String, val botId: String, val threadId: String,
                         val eventId: String, val reason: String) {
    fun data() = mapOf("v" to "1", "serviceId" to serviceId,
        "botId" to botId, "threadId" to threadId, "eventId" to eventId, "reason" to reason)
    // Event identity, never thread identity alone. IDs cannot contain this separator.
    val deliveryKey get() = "$serviceId|$botId|$threadId|$eventId"
}

/** Bounded FIFO dedup. Separate instances for receipt and tap so delivery does not swallow its tap. */
interface BotPushHistory {
    fun contains(key: String): Boolean
    fun remember(key: String): Boolean
}

class BotPushDedup(private val capacity: Int = 128) : BotPushHistory {
    init { require(capacity > 0) }
    private val keys = linkedSetOf<String>()
    @Synchronized override fun contains(key: String) = key in keys
    @Synchronized override fun remember(key: String): Boolean {
        if (!keys.add(key)) return false
        while (keys.size > capacity) keys.remove(keys.first())
        return true
    }
}

/** Keep a bounded queue until navigation AND service authentication are ready. */
class BotPushRouter(
    private val knownService: (String) -> Boolean,
    private val capacity: Int = 16,
    private val handled: BotPushHistory = BotPushDedup(),
) {
    init { require(capacity > 0) }
    private val pending = linkedMapOf<String, BotPushTarget>()
    @Synchronized fun offer(data: Map<String, String>): Boolean {
        val target = BotPushContract.parse(data) ?: return false
        if (!knownService(target.serviceId) || handled.contains(target.deliveryKey)) return false
        pending[target.deliveryKey] = target
        while (pending.size > capacity) pending.remove(pending.keys.first())
        return true
    }
    /** open returns true only after navigation accepted the target; never executes approval/sign-in. */
    @Synchronized fun drain(ready: (String) -> Boolean, open: (BotPushTarget) -> Boolean) {
        for ((key, target) in pending.toMap()) {
            if (!knownService(target.serviceId)) pending.remove(key)
            else if (ready(target.serviceId) && open(target)) {
                pending.remove(key)
                handled.remember(key)
            }
        }
    }
    @Synchronized fun forgetService(serviceId: String) {
        pending.entries.removeAll { it.value.serviceId == serviceId }
    }
}
