package com.wangzan101.mika.woowbot

import android.app.UiAutomation
import android.graphics.Bitmap
import android.os.SystemClock
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertWidthIsEqualTo
import androidx.compose.ui.test.isRoot
import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.printToLog
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.wangzan101.mika.BuildConfig
import com.wangzan101.mika.MikaApp
import com.wangzan101.mika.R
import com.wangzan101.mika.cap.phone.PhoneServices
import com.wangzan101.mika.core.agent.Turn
import com.wangzan101.mika.ui.MainActivity
import com.wangzan101.mika.ui.components.Adaptive
import org.junit.After
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

/**
 * Owner 2026-11-28: tablets follow the iPad rules. On a tablet emulator (the workflow's Pixel Tablet run) this checks that the
 * inbox docks beside the chat in landscape and not in portrait, and saves screenshots of the inbox, the services sheet, a
 * dialog, portrait and the settings page for the owner (pulled from files/tablet-shots into the run's evidence).
 *
 * The compose test clock only moves while the test synchronises, so every step waits for what it expects through the compose
 * rule (a plain sleep left a click's dialog unshown and the sheet's exit motion unplayed). Only resumed activities count as
 * compose roots: while the services sheet is up, the main activity's nodes are not found.
 */
@RunWith(AndroidJUnit4::class)
class BotTabletLayoutDeviceTest {
    @get:Rule val compose = createEmptyComposeRule()
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context = instrumentation.targetContext
    private var service: BotService? = null
    private var scenario: ActivityScenario<MainActivity>? = null
    private val shots by lazy { File(context.getExternalFilesDir(null), "tablet-shots").apply { mkdirs() } }
    private val store by lazy { (context.applicationContext as MikaApp).conversations }
    // A few conversations, so the inbox shows rows as it does in use.
    private val samples = listOf(
        "tablet-qa-trip" to "整理本週行程",
        "tablet-qa-lights" to "關掉客廳的燈",
        "tablet-qa-report" to "整理月報重點",
    )

    @Before fun setUp() {
        assumeTrue(BuildConfig.WOOWTECHBOT_ENABLED)
        assumeTrue("not a tablet", context.resources.configuration.smallestScreenWidthDp >= 600)
        // A saved service skips the welcome page (Q18) and a seen guide skips the phone step: the app opens on the inbox.
        service = BotServices.registry(context).add("Tablet QA", "https://tablet-qa.example.com")
        PhoneServices.of(context).setupPrompt.markGuideSeen()
        samples.forEach { (id, title) ->
            store.append(id, Turn(title, "好的。", "succeeded"))
            store.rename(id, title)
        }
    }

    @After fun tearDown() {
        scenario?.close()
        instrumentation.uiAutomation.setRotation(UiAutomation.ROTATION_UNFREEZE)
        service?.let { s -> runCatching { BotServices.registry(context).remove(s.id) } }
        samples.forEach { (id, _) -> runCatching { store.delete(id) } }
    }

    private fun settle() {
        runCatching { compose.waitForIdle() }
        instrumentation.waitForIdleSync()
        // The CI tablet emulator draws about one frame a second at 2560 x 1600.
        SystemClock.sleep(1500)
    }

    private fun shot(name: String) {
        settle()
        val bitmap = instrumentation.uiAutomation.takeScreenshot() ?: return
        File(shots, "$name.png").outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
    }

    private fun gone(text: String) =
        compose.waitUntil(20_000) { compose.onAllNodesWithText(text).fetchSemanticsNodes(atLeastOneRootRequired = false).isEmpty() }

    private fun rotate(rotation: Int) {
        instrumentation.uiAutomation.setRotation(rotation)
        settle()
    }

    private fun windowWidthDp(): Int {
        var width = 0
        scenario!!.onActivity { width = it.resources.configuration.screenWidthDp }
        return width
    }

    // While activities swap or relaunch there can be no resumed compose root at all; that is "not yet", not a failure.
    private fun awaitTag(tag: String) =
        compose.waitUntil(20_000) { compose.onAllNodesWithTag(tag).fetchSemanticsNodes(atLeastOneRootRequired = false).isNotEmpty() }

    private fun awaitText(text: String) =
        compose.waitUntil(20_000) { compose.onAllNodesWithText(text, substring = true).fetchSemanticsNodes(atLeastOneRootRequired = false).isNotEmpty() }

    @Test fun inboxDocksInLandscapeAndTheOtherPagesFollowTheTabletRules() {
        try {
            walk()
        } catch (t: Throwable) {
            // What was on screen and in the tree when it failed, for the run's evidence.
            runCatching { shot("fail") }
            runCatching { compose.onAllNodes(isRoot()).printToLog("TabletLayout") }
            throw t
        }
    }

    private fun walk() {
        // The Pixel Tablet's natural orientation is landscape.
        rotate(UiAutomation.ROTATION_FREEZE_0)
        scenario = ActivityScenario.launch(MainActivity::class.java)
        awaitTag("bot_ui_history")
        val landscape = windowWidthDp()
        if (landscape >= Adaptive.DockMin.value) {
            // Docked: the 360 dp inbox and the chat's composer are on screen together.
            compose.onNodeWithTag("bot_ui_history").assertIsDisplayed().assertWidthIsEqualTo(Adaptive.DockWidth)
            awaitTag("composer-field")
            compose.onNodeWithTag("composer-field").assertIsDisplayed()
        }
        shot("1-landscape-inbox-and-chat")

        // The services sheet (⇄) is a centred window on a tablet, not a full-screen sheet.
        compose.onNodeWithContentDescription(context.getString(R.string.bot_ui_services)).performClick()
        awaitText(context.getString(R.string.bot_services_add))
        shot("2-landscape-services-window")
        // Its add-service dialog: centred.
        compose.onNodeWithText(context.getString(R.string.bot_services_add)).performClick()
        awaitText(context.getString(R.string.bot_services_cancel))
        shot("3-landscape-add-service-dialog")
        compose.onNodeWithText(context.getString(R.string.bot_services_cancel)).performClick()
        gone(context.getString(R.string.bot_services_cancel))
        // Closing the sheet finishes its activity after the exit motion; the docked inbox is in front again.
        compose.onNodeWithContentDescription(context.getString(R.string.bot_ui_close)).performClick()
        awaitTag("bot_ui_history")

        // Portrait: no longer docked; coming from docked the chat shows, not the inbox.
        rotate(UiAutomation.ROTATION_FREEZE_90)
        awaitTag("composer-field")
        val portrait = windowWidthDp()
        assertTrue("portrait $portrait dp should be narrower than the dock threshold", portrait < Adaptive.DockMin.value)
        assertTrue("the inbox should not stay on screen in portrait", compose.onAllNodesWithTag("bot_ui_history").fetchSemanticsNodes().isEmpty())
        shot("4-portrait-chat")

        // The inbox page in portrait, then settings from its gear: a centred 720 dp column.
        compose.onNodeWithContentDescription(context.getString(R.string.bot_ui_history)).performClick()
        awaitTag("bot_ui_history")
        awaitText(samples.first().second)
        shot("5-portrait-inbox")
        // The gear's menu, then its Settings item.
        compose.onNodeWithContentDescription(context.getString(R.string.settings_title)).performClick()
        awaitText(context.getString(R.string.settings_title))
        compose.onNodeWithText(context.getString(R.string.settings_title)).performClick()
        compose.waitUntil(20_000) { compose.onAllNodesWithTag("bot_ui_history").fetchSemanticsNodes(atLeastOneRootRequired = false).isEmpty() }
        shot("6-portrait-settings")
        rotate(UiAutomation.ROTATION_FREEZE_0)
        shot("7-landscape-settings")
    }
}
