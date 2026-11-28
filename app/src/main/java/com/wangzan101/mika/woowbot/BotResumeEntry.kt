package com.wangzan101.mika.woowbot

import android.app.Activity
import android.content.Context
import android.content.Intent
import com.wangzan101.mika.BuildConfig

/**
 * Owner 2026-11-28: leaving the app while a bot page is open and opening it again returns to that bot page, not to the
 * local history. MainActivity is singleTask, so the launcher intent clears the service screen above it; this reopens it.
 * Only the service ID is kept, and only while the user is away from that screen.
 */
object BotResumeEntry {
    private const val PREFS = "bot_resume"
    private const val KEY = "serviceId"
    private fun prefs(context: Context) = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    /** The service screen went out of sight without the user closing it; it stays recorded while it is open. */
    fun left(context: Context, serviceId: String) { prefs(context).edit().putString(KEY, serviceId).apply() }
    /** The user closed the service screen. */
    fun returned(context: Context) { prefs(context).edit().remove(KEY).apply() }

    /** Call for the launch intent and onNewIntent of the launcher activity. */
    fun handle(activity: Activity, intent: Intent?) {
        if (!BuildConfig.WOOWTECHBOT_ENABLED || intent?.action != Intent.ACTION_MAIN || !intent.hasCategory(Intent.CATEGORY_LAUNCHER)) return
        val id = prefs(activity).getString(KEY, null) ?: return
        val service = runCatching { BotServices.registry(activity).find(id) }.getOrNull()
        if (service?.enabled != true) { returned(activity); return }
        runCatching { activity.startActivity(BotServiceActivity.resumeIntent(activity, id)) }.onFailure { returned(activity) }
    }
}
