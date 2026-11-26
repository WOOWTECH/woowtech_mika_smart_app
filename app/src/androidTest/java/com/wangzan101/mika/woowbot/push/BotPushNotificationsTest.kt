package com.wangzan101.mika.woowbot.push

import android.Manifest
import android.app.Notification
import android.app.NotificationManager
import android.content.Context
import android.os.Build
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.wangzan101.mika.core.woowbot.push.*
import com.wangzan101.mika.ui.MainActivity
import org.junit.*
import org.junit.Assert.*
import org.junit.runner.RunWith
import java.util.UUID

/** No Firebase initialization/config/network. Acceptance is injected at the Android notification boundary. */
@RunWith(AndroidJUnit4::class)
class BotPushNotificationsTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context: Context get() = instrumentation.targetContext
    private val manager get() = context.getSystemService(NotificationManager::class.java)
    private val service = "test_${UUID.randomUUID()}"
    private fun target(event: String = "event_1") = BotPushTarget(service, "bot_1", "thread_1", event, "finished")
    private fun renderer(accept: (String) -> Boolean = { it == service }, history: BotPushHistory = BotPushDedup()) =
        BotPushNotifications(context, MainActivity::class.java, accept, history)
    private fun own() = manager.activeNotifications.filter { it.tag?.startsWith("$service|") == true }

    @Before fun grant() {
        if (Build.VERSION.SDK_INT >= 33) {
            android.os.ParcelFileDescriptor.AutoCloseInputStream(instrumentation.uiAutomation.executeShellCommand("pm grant ${context.packageName} ${Manifest.permission.POST_NOTIFICATIONS}")).use { it.readBytes() }
        }
        renderer().cancelService(service)
    }
    @After fun clean() { renderer().cancelService(service) }
    private fun awaitCount(expected: Int) {
        val deadline = android.os.SystemClock.elapsedRealtime() + 3000
        while (own().size != expected && android.os.SystemClock.elapsedRealtime() < deadline) Thread.sleep(20)
        assertEquals(expected, own().size)
    }
    @Test fun injectedAcceptanceRendersGenericSecretNotificationWithoutFirebase() {
        val renderer = renderer()
        renderer.receive(target().data())
        awaitCount(1)
        val notification = own().single().notification
        assertEquals(BotPushNotifications.DONE, notification.channelId)
        assertEquals(Notification.VISIBILITY_SECRET, notification.visibility)
        assertNotNull(notification.contentIntent)
        assertFalse(notification.extras.getCharSequence(Notification.EXTRA_TEXT).toString().contains("thread_1"))
        renderer.receive(target().data())
        awaitCount(1)
        renderer.receive(target("event_2").data())
        awaitCount(2)
        assertEquals(2, own().map { it.notification.contentIntent }.distinct().size)
        renderer.receive(target("event_3").copy(reason = "permission").data())
        awaitCount(3)
        assertEquals(1, own().count { it.notification.channelId == BotPushNotifications.ACTION })
    }
    @Test fun rejectedServiceAndContentNeverProduceNotification() {
        renderer({ false }).receive(target().data())
        renderer().receive(target().data() + ("url" to "https://example.invalid"))
        awaitCount(0)
    }
    @Test fun profileLogoutCancellationAndRestartDedup() {
        val name = "test_${UUID.randomUUID()}"
        renderer(history = BotPushPersistentHistory(context, name)).receive(target().data())
        awaitCount(1)
        renderer().cancelService(service)
        awaitCount(0)
        // New renderer/history object models a cold process reading the durable receipt ledger.
        renderer(history = BotPushPersistentHistory(context, name)).receive(target().data())
        awaitCount(0)
        context.getSharedPreferences("woowbot_push_history_$name", Context.MODE_PRIVATE).edit().clear().commit()
    }
    @Test fun handledTapDoesNotReplayAfterRouterRecreationButNextEventStillRoutes() {
        val name = "test_${UUID.randomUUID()}"
        val first = BotPushRouter({ it == service }, handled = BotPushPersistentHistory(context, name))
        assertTrue(first.offer(target().data()))
        first.drain({ true }) { true }
        val reopened = BotPushRouter({ it == service }, handled = BotPushPersistentHistory(context, name))
        assertFalse(reopened.offer(target().data()))
        assertTrue(reopened.offer(target("next_event").data()))
        context.getSharedPreferences("woowbot_push_history_$name", Context.MODE_PRIVATE).edit().clear().commit()
    }
    @Test fun persistentHistoryEvictsOldestAndSeparatesTapFromReceipt() {
        val name = "test_${UUID.randomUUID()}"
        val first = BotPushPersistentHistory(context, name, 2)
        first.remember("1"); first.remember("2"); first.remember("3")
        val reopened = BotPushPersistentHistory(context, name, 2)
        assertFalse(reopened.contains("1")); assertTrue(reopened.contains("2")); assertTrue(reopened.contains("3"))
        assertFalse(BotPushPersistentHistory(context, "${name}_tap", 2).contains("3"))
        context.getSharedPreferences("woowbot_push_history_$name", Context.MODE_PRIVATE).edit().clear().commit()
    }
}
