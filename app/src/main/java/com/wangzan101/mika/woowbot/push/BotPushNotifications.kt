package com.wangzan101.mika.woowbot.push

import android.Manifest
import android.app.Activity
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import com.wangzan101.mika.R
import com.wangzan101.mika.i18n.tr
import com.wangzan101.mika.core.woowbot.push.*

class BotPushNotifications(
    private val context: Context,
    private val activity: Class<out Activity>,
    private val accepts: (String) -> Boolean,
    private val received: BotPushHistory = BotPushPersistentHistory(context, "received"),
) {
    private val manager = context.getSystemService(NotificationManager::class.java)
    @Synchronized fun receive(data: Map<String, String>) {
        val target = BotPushContract.parse(data) ?: return
        if (!accepts(target.serviceId) || !manager.areNotificationsEnabled()) return
        if (Build.VERSION.SDK_INT >= 33 && context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) return
        val channel = if (target.reason == "finished") DONE else ACTION
        manager.createNotificationChannels(listOf(
            NotificationChannel(ACTION, tr(R.string.bot_push_channel_action), NotificationManager.IMPORTANCE_DEFAULT),
            NotificationChannel(DONE, tr(R.string.bot_push_channel_done), NotificationManager.IMPORTANCE_DEFAULT),
        ))
        if (manager.getNotificationChannel(channel)?.importance == NotificationManager.IMPORTANCE_NONE) return
        if (received.contains(target.deliveryKey)) return
        val intent = Intent(context, activity).apply {
            action = TAP_ACTION
            // Explicit activity + internal identity URI. Never treat this URI as a browser destination.
            setData(Uri.Builder().scheme("woowbot-push").authority("tap").appendPath(target.deliveryKey).build())
            flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
            target.data().forEach { (key, value) -> putExtra(PREFIX + key, value) }
        }
        val tap = PendingIntent.getActivity(context, 0, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val notification = Notification.Builder(context, channel)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(tr(R.string.bot_push_title))
            .setContentText(tr(if (target.reason == "finished") R.string.bot_push_done else R.string.bot_push_action))
            .addExtras(android.os.Bundle().apply { putString(SERVICE_EXTRA, target.serviceId) })
            .setVisibility(Notification.VISIBILITY_SECRET)
            .setContentIntent(tap).setAutoCancel(true).build()
        try {
            // Exact event tag prevents same-thread events replacing each other's tap extras.
            if (!accepts(target.serviceId)) return
            manager.notify(target.deliveryKey, 0, notification)
            received.remember(target.deliveryKey)
        } catch (_: SecurityException) { /* permission revoked between check and notify */ }
    }
    /** Cancel only bot channels, preserving the local assistant's existing notifications. */
    @Synchronized fun cancelStale(allowed: (String) -> Boolean = accepts) {
        manager.activeNotifications.filter { it.notification.channelId == ACTION || it.notification.channelId == DONE }
            .filter { !allowed(it.notification.extras.getString(SERVICE_EXTRA).orEmpty()) }
            .forEach { manager.cancel(it.tag, it.id) }
    }
    fun cancelService(serviceId: String) = cancelStale { it != serviceId }
    companion object {
        private const val SERVICE_EXTRA = "woowbot.push.service"
        const val ACTION = "woowtechbot_attention"
        const val DONE = "woowtechbot_results"
        const val TAP_ACTION = "com.wangzan101.mika.woowbot.PUSH_TAP"
        private const val PREFIX = "woowbot.push."
        /** Call for launch intent AND onNewIntent; drain router once registry/auth/navigation are ready.
         * Activity intents are untrusted. Router validates identifiers and service; UI authorizes fetched targets.
         */
        fun capture(intent: Intent?, router: BotPushRouter): Boolean {
            if (intent?.action != TAP_ACTION) return false
            val data = mutableMapOf<String, String>()
            for (key in listOf("v", "serviceId", "botId", "threadId", "eventId", "reason")) {
                val value = intent.getStringExtra(PREFIX + key)
                if (value != null) data[key] = value
                intent.removeExtra(PREFIX + key)
            }
            intent.action = null
            intent.data = null
            return router.offer(data)
        }
    }
}
