package com.wangzan101.mika.woowbot

import android.app.UiAutomation
import android.graphics.Bitmap
import android.os.SystemClock
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertWidthIsEqualTo
import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.unit.dp
import androidx.test.core.app.ActivityScenario
import androidx.test.espresso.Espresso
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.wangzan101.mika.BuildConfig
import com.wangzan101.mika.R
import com.wangzan101.mika.cap.phone.PhoneServices
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
 */
@RunWith(AndroidJUnit4::class)
class BotTabletLayoutDeviceTest {
    @get:Rule val compose = createEmptyComposeRule()
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context = instrumentation.targetContext
    private var service: BotService? = null
    private var scenario: ActivityScenario<MainActivity>? = null
    private val shots by lazy { File(context.getExternalFilesDir(null), "tablet-shots").apply { mkdirs() } }

    @Before fun setUp() {
        assumeTrue(BuildConfig.WOOWTECHBOT_ENABLED)
        assumeTrue("not a tablet", context.resources.configuration.smallestScreenWidthDp >= 600)
        // A saved service skips the welcome page (Q18) and a seen guide skips the phone step: the app opens on the inbox.
        service = BotServices.registry(context).add("Tablet QA", "https://tablet-qa.example.com")
        PhoneServices.of(context).setupPrompt.markGuideSeen()
    }

    @After fun tearDown() {
        scenario?.close()
        instrumentation.uiAutomation.setRotation(UiAutomation.ROTATION_UNFREEZE)
        service?.let { s -> runCatching { BotServices.registry(context).remove(s.id) } }
    }

    private fun settle() {
        instrumentation.waitForIdleSync()
        SystemClock.sleep(1200)
    }

    private fun shot(name: String) {
        settle()
        val bitmap = instrumentation.uiAutomation.takeScreenshot() ?: return
        File(shots, "$name.png").outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
    }

    private fun rotate(rotation: Int) {
        instrumentation.uiAutomation.setRotation(rotation)
        settle()
    }

    private fun windowWidthDp(): Int {
        var width = 0
        scenario!!.onActivity { width = it.resources.configuration.screenWidthDp }
        return width
    }

    private fun awaitTag(tag: String) =
        compose.waitUntil(20_000) { compose.onAllNodesWithTag(tag).fetchSemanticsNodes().isNotEmpty() }

    private fun awaitText(text: String) =
        compose.waitUntil(20_000) { compose.onAllNodesWithText(text, substring = true).fetchSemanticsNodes().isNotEmpty() }

    @Test fun inboxDocksInLandscapeAndTheOtherPagesFollowTheTabletRules() {
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
        settle()
        shot("3-landscape-add-service-dialog")
        Espresso.pressBackUnconditionally()
        settle()
        Espresso.pressBackUnconditionally()
        settle()

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
        shot("5-portrait-inbox")
        compose.onNodeWithContentDescription(context.getString(R.string.settings_title)).performClick()
        settle()
        compose.onNodeWithText(context.getString(R.string.settings_title)).performClick()
        settle()
        shot("6-portrait-settings")
        rotate(UiAutomation.ROTATION_FREEZE_0)
        shot("7-landscape-settings")
    }
}
