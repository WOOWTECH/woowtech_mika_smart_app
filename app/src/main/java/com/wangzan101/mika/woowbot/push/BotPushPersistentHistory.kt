package com.wangzan101.mika.woowbot.push

import android.content.Context
import com.wangzan101.mika.core.woowbot.push.BotPushHistory
import org.json.JSONArray

/** Bounded FIFO across process restarts. Contains opaque delivery IDs, never content or credentials.
 * App backup is disabled. Receipt and tap histories MUST use different names.
 */
class BotPushPersistentHistory(context: Context, name: String, private val capacity: Int = 128) : BotPushHistory {
    init { require(capacity > 0) }
    private val prefs = context.applicationContext.getSharedPreferences("woowbot_push_history_$name", Context.MODE_PRIVATE)
    private fun keys(): LinkedHashSet<String> = runCatching {
        val array = JSONArray(prefs.getString("keys", "[]"))
        (0 until array.length()).map { array.getString(it) }.takeLast(capacity).toCollection(linkedSetOf())
    }.getOrDefault(linkedSetOf())
    override fun contains(key: String): Boolean = synchronized(LOCK) { key in keys() }
    override fun remember(key: String): Boolean = synchronized(LOCK) {
        val keys = keys()
        if (!keys.add(key)) return@synchronized false
        while (keys.size > capacity) keys.remove(keys.first())
        // Notification rendering remains safe even if disk is unavailable; the same event tag replaces itself.
        prefs.edit().putString("keys", JSONArray(keys.toList()).toString()).commit()
        true
    }
    companion object { private val LOCK = Any() }
}
