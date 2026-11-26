package com.wangzan101.mika.core.woowbot.push

/** Receipt is durable before async authentication starts; neither retries nor duplicates extend TTL. */
data class BotPushEnvelope(val target: BotPushTarget, val profile: String, val expiresAt: Long)
class BotPushInbox(initial: List<BotPushEnvelope> = emptyList(), private val capacity: Int = 64) {
    private val entries = initial.takeLast(capacity).associateByTo(linkedMapOf()) { it.target.deliveryKey }
    fun snapshot() = entries.values.toList()
    fun offer(target: BotPushTarget, profile: String, sentAt: Long, ttlSeconds: Int, now: Long): Boolean {
        if (sentAt <= 0 || sentAt > now + 60_000 || ttlSeconds <= 0) return false
        val expiry = minOf(sentAt + minOf(ttlSeconds, 600) * 1000L, now + 600_000)
        if (expiry <= now) return false
        entries.entries.removeAll { it.value.expiresAt <= now }
        if (target.deliveryKey in entries) return false
        entries[target.deliveryKey] = BotPushEnvelope(target, profile, expiry)
        while (entries.size > capacity) entries.remove(entries.keys.first())
        return true
    }
    fun drain(now: Long, profile: (String) -> String?, ready: (String) -> Boolean, deliver: (BotPushTarget) -> Unit): Boolean {
        for ((key, envelope) in entries.toMap()) {
            if (envelope.expiresAt <= now || profile(envelope.target.serviceId) != envelope.profile) entries.remove(key)
            else if (ready(envelope.target.serviceId)) {
                deliver(envelope.target)
                entries.remove(key)
            }
        }
        return entries.isEmpty()
    }
}
