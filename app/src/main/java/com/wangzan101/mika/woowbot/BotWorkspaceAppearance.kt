package com.wangzan101.mika.woowbot

import android.content.Context
import com.wangzan101.mika.R
import org.json.JSONObject

/** Two presentation-only actions, never an arbitrary native command or URL. */
internal object BotWorkspaceAppearance {
    fun action(url: String, mainFrame: Boolean, gesture: Boolean, sameOrigin: Boolean): String? {
        if (!mainFrame || !gesture || !sameOrigin) return null
        return when (url) {
            "woowtech-ui://services" -> "services"
            "woowtech-ui://notifications" -> "notifications"
            else -> null
        }
    }
    fun script(context: Context, dark: Boolean): String {
        val config = JSONObject().put("skin", if (dark) "midnight" else "daylight")
            .put("services", context.getString(R.string.bot_ui_services))
            .put("notifications", context.getString(R.string.bot_ui_notifications))
        return context.assets.open("woowtechbot/workspace-controls.js").bufferedReader().use { it.readText() }
            .replace("__WOOW_CONFIGURATION__", config.toString())
    }
}
