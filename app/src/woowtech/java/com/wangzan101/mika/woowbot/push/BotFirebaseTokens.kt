package com.wangzan101.mika.woowbot.push

import android.content.Context
import com.google.android.gms.tasks.Task
import com.google.firebase.FirebaseApp
import com.google.firebase.messaging.FirebaseMessaging
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

/** Optional standard Firebase resources are supplied externally by the WOOWTECH build only.
 * FirebaseInitProvider must be removed in the flavor manifest; initialization happens after consent.
 */
@androidx.annotation.Keep
class BotFirebaseTokens(context: Context) : BotPushTokenSource {
    private val context = context.applicationContext
    override val configured get() = context.packageName == "io.woowtech.agent" &&
        listOf("google_app_id", "google_api_key", "gcm_defaultSenderId", "project_id").all { name ->
            val id = context.resources.getIdentifier(name, "string", context.packageName)
            id != 0 && context.getString(id).isNotBlank()
        }
    override suspend fun token(): String {
        check(configured) { "Own Firebase configuration is absent" }
        checkNotNull(FirebaseApp.initializeApp(context)) { "Own Firebase configuration is absent" }
        val messaging = FirebaseMessaging.getInstance()
        messaging.isAutoInitEnabled = false
        return messaging.token.awaitPush()
    }
    override suspend fun disableAndDelete() {
        if (!configured || runCatching { FirebaseApp.getInstance() }.isFailure) return
        val messaging = FirebaseMessaging.getInstance()
        messaging.isAutoInitEnabled = false
        messaging.deleteToken().awaitPush()
    }
}

private suspend fun <T> Task<T>.awaitPush(): T = suspendCancellableCoroutine { continuation ->
    addOnCompleteListener { task ->
        if (continuation.isActive) {
            if (task.isSuccessful) continuation.resume(task.result)
            else continuation.resumeWithException(task.exception ?: IllegalStateException("Firebase task failed"))
        }
    }
}
