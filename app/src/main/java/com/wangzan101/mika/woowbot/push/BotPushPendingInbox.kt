package com.wangzan101.mika.woowbot.push

import android.content.Context
import com.wangzan101.mika.core.woowbot.push.*
import com.wangzan101.mika.woowbot.BotServices
import org.json.JSONArray
import org.json.JSONObject

/** App-private identifiers only; no token, cookie, content, or external destination is persisted. */
object BotPushPendingInbox {
    private fun load(context: Context): BotPushInbox {
        val array = runCatching { JSONArray(context.getSharedPreferences("bot_push_inbox", 0).getString("items", "[]")) }.getOrDefault(JSONArray())
        val entries = (0 until minOf(array.length(), 64)).mapNotNull { i -> runCatching {
            val item = array.getJSONObject(i)
            val data = item.getJSONObject("data")
            val target = BotPushContract.parse(data.keys().asSequence().associateWith { data.getString(it) }) ?: return@runCatching null
            BotPushEnvelope(target, item.getString("profile"), item.getLong("expiresAt"))
        }.getOrNull() }
        return BotPushInbox(entries)
    }
    private fun save(context: Context, inbox: BotPushInbox) {
        val array = JSONArray()
        inbox.snapshot().forEach { array.put(JSONObject().put("data", JSONObject(it.target.data())).put("profile", it.profile).put("expiresAt", it.expiresAt)) }
        check(context.getSharedPreferences("bot_push_inbox", 0).edit().putString("items", array.toString()).commit())
    }
    @Synchronized fun offer(context: Context, data: Map<String, String>, sentAt: Long, ttl: Int) {
        val target = BotPushContract.parse(data) ?: return
        if (BotPushRuntime.controller?.optedIn != true) return
        val service = BotServices.registry(context).find(target.serviceId)?.takeIf { it.enabled } ?: return
        val binding = BotPushPreferencesLedger(context).read().singleOrNull { it.serviceId == target.serviceId } ?: return
        val inbox = load(context)
        inbox.offer(target, service.profileId + "|" + binding.authIdentity, sentAt, ttl, System.currentTimeMillis())
        save(context, inbox)
        BotPushRefreshJob.schedule(context)
        BotPushBootstrap.refresh(context)
    }
    @Synchronized fun drain(context: Context): Boolean {
        val controller = BotPushRuntime.controller ?: return false
        val inbox = load(context)
        val snapshots = inbox.snapshot().associateBy { it.target.serviceId }
        val ledger = BotPushPreferencesLedger(context).read()
        val complete = inbox.drain(System.currentTimeMillis(), { id ->
            if (!controller.optedIn) null else {
                val service = BotServices.registry(context).find(id)?.takeIf { it.enabled }
                val binding = ledger.singleOrNull { it.serviceId == id }
                if (service == null || binding == null) null else service.profileId + "|" + binding.authIdentity
            }
        }, { id -> controller.acceptsIdentity(id, snapshots[id]?.profile?.substringAfter("|").orEmpty()) }) { target -> BotPushRuntime.notifications?.receive(target.data()) }
        save(context, inbox)
        return complete
    }
}
