package com.wangzan101.mika.woowbot.push

import android.app.Activity
import android.content.Intent
import com.wangzan101.mika.BuildConfig
import com.wangzan101.mika.core.woowbot.push.BotPushRouter
import com.wangzan101.mika.woowbot.BotServiceActivity
import com.wangzan101.mika.woowbot.BotServices
import com.wangzan101.mika.woowbot.BotWebTarget

/** MainActivity calls only this helper; local conversation notification actions/extras are untouched. */
object BotPushTapEntry {
    @Volatile private var router: BotPushRouter? = null
    fun forgetService(serviceId: String) { router?.forgetService(serviceId) }
    fun handle(activity: Activity, intent: Intent?) {
        if (!BuildConfig.WOOWTECHBOT_ENABLED) return
        if (intent?.action != BotPushNotifications.TAP_ACTION && router == null) return
        val registry = runCatching { BotServices.registry(activity.applicationContext) }.getOrNull() ?: return
        val queue = router ?: BotPushRouter({ registry.find(it)?.enabled == true }, handled = BotPushPersistentHistory(activity.applicationContext, "tapped")).also { router = it }
        if (intent?.action == BotPushNotifications.TAP_ACTION) BotPushNotifications.capture(intent, queue)
        // Defer until onCreate content is installed; web activity owns service-scoped sign-in/target auth.
        activity.window.decorView.post {
            if (activity.isFinishing || activity.isDestroyed) return@post
            queue.drain(ready = { registry.find(it)?.enabled == true && BotServices.supportsIsolation() }) { target ->
                val service = registry.find(target.serviceId) ?: return@drain false
                val deep = runCatching { BotWebTarget.url(service, target.botId, target.threadId) }.isSuccess
                runCatching {
                    activity.startActivity(BotServiceActivity.intent(activity, service.id,
                        target.botId.takeIf { deep }, target.threadId.takeIf { deep }))
                }.isSuccess
            }
        }
    }
}
