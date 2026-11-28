package com.wangzan101.mika.woowbot

import android.app.Activity
import android.content.Intent
import android.os.ParcelFileDescriptor
import android.os.SystemClock
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.runner.lifecycle.ActivityLifecycleMonitorRegistry
import androidx.test.runner.lifecycle.Stage
import com.wangzan101.mika.BuildConfig
import com.wangzan101.mika.ui.MainActivity
import org.junit.After
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Owner 2026-11-28: leaving the app on a bot page and opening it again from the launcher returned to the local history.
 * The launcher, Home and Back go through the shell exactly as a person's taps do.
 */
@RunWith(AndroidJUnit4::class)
class BotResumeDeviceTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context = instrumentation.targetContext
    private lateinit var service: BotService

    @Before fun setUp() {
        assumeTrue(BuildConfig.WOOWTECHBOT_ENABLED)
        BotResumeEntry.returned(context)
        service = BotServices.registry(context).add("Resume QA", "https://resume-qa.invalid")
    }

    @After fun tearDown() {
        shell("input keyevent KEYCODE_HOME")
        if (::service.isInitialized) runCatching { BotServices.registry(context).remove(service.id) }
        BotResumeEntry.returned(context)
    }

    private fun shell(command: String) {
        ParcelFileDescriptor.AutoCloseInputStream(instrumentation.uiAutomation.executeShellCommand(command)).use { it.readBytes() }
    }
    /** What the launcher sends for the app icon. */
    private fun launcher() = shell("am start -a android.intent.action.MAIN -c android.intent.category.LAUNCHER -f 0x10200000 " +
        "-n ${context.packageName}/com.wangzan101.mika.ui.MainActivity")
    private fun resumed(): Activity? {
        var found: Activity? = null
        instrumentation.runOnMainSync {
            found = ActivityLifecycleMonitorRegistry.getInstance().getActivitiesInStage(Stage.RESUMED).firstOrNull()
        }
        return found
    }
    private fun await(what: String, test: (Activity?) -> Boolean) {
        val end = SystemClock.elapsedRealtime() + 30_000
        while (SystemClock.elapsedRealtime() < end) {
            if (test(resumed())) return
            SystemClock.sleep(200)
        }
        fail("Timed out waiting for $what; in front: ${resumed()}")
    }

    @Test fun theLauncherReturnsToTheBotPageTheUserLeftButNotToOneTheyClosed() {
        launcher()
        await("the history") { it is MainActivity }
        val history = resumed()!!
        instrumentation.runOnMainSync { history.startActivity(BotServiceActivity.intent(history, service.id)) }
        await("the service screen") { it is BotServiceActivity }

        shell("input keyevent KEYCODE_HOME")
        await("the home screen") { it == null }
        launcher()
        await("the service screen again") { it is BotServiceActivity }

        // Closed with Back: the history again, and the launcher keeps it.
        shell("input keyevent KEYCODE_BACK")
        await("the history after Back") { it is MainActivity }
        shell("input keyevent KEYCODE_HOME")
        await("the home screen") { it == null }
        launcher()
        await("the history") { it is MainActivity }
        SystemClock.sleep(2_000)
        assertTrue("A service screen the user closed came back", resumed() is MainActivity)
    }

    @Test fun aRemovedServiceIsNotReopened() {
        launcher()
        await("the history") { it is MainActivity }
        val history = resumed()!!
        instrumentation.runOnMainSync { history.startActivity(BotServiceActivity.intent(history, service.id)) }
        await("the service screen") { it is BotServiceActivity }
        shell("input keyevent KEYCODE_HOME")
        await("the home screen") { it == null }
        BotServices.registry(context).remove(service.id)
        launcher()
        await("the history") { it is MainActivity }
        SystemClock.sleep(2_000)
        assertTrue("A removed service was reopened", resumed() !is BotServiceActivity)
    }
}
