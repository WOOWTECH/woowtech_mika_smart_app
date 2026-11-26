package com.wangzan101.mika.woowbot.push

import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage

/** Data-only messages required. Notification payloads bypass client checks when app is backgrounded. */
class BotFirebaseMessagingService : FirebaseMessagingService() {
    override fun onMessageReceived(message: RemoteMessage) {
        if (message.notification != null) return
        BotPushRuntime.notifications?.receive(message.data)
    }
    override fun onNewToken(token: String) {
        BotPushRuntime.epoch.incrementAndGet()
        // Persist/schedule work through the application-owned scheduler; do not perform network work here.
        BotPushRefreshJob.schedule(this)
    }
}
