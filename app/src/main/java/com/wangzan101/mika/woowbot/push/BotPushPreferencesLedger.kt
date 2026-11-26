package com.wangzan101.mika.woowbot.push

import android.content.Context
import com.wangzan101.mika.core.woowbot.push.BotPushBinding
import com.wangzan101.mika.core.woowbot.push.BotPushLedger
import org.json.JSONArray
import org.json.JSONObject

/** Private durable revocation ledger. Do not include it in cloud backup/device transfer. */
class BotPushPreferencesLedger(context: Context) : BotPushLedger {
    private val prefs = context.getSharedPreferences("woowbot_push_ledger", Context.MODE_PRIVATE)
    override fun read(): Set<BotPushBinding> {
        val array = JSONArray(prefs.getString("bindings", "[]"))
        return (0 until array.length()).map { index ->
            val item = array.getJSONObject(index)
            BotPushBinding(item.getString("service"), item.getString("identity"))
        }.toSet()
    }
    override fun write(bindings: Set<BotPushBinding>) {
        val array = JSONArray()
        bindings.forEach { array.put(JSONObject().put("service", it.serviceId).put("identity", it.authIdentity)) }
        check(prefs.edit().putString("bindings", array.toString()).commit())
    }
}
