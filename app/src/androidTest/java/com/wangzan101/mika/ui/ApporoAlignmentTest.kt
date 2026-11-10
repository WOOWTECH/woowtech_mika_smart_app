package com.wangzan101.mika.ui

import android.Manifest
import android.app.LocaleManager
import android.app.UiAutomation
import android.content.ComponentName
import android.graphics.Bitmap
import android.os.Build
import android.os.LocaleList
import android.os.SystemClock
import android.provider.Settings
import androidx.activity.ComponentActivity
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.wangzan101.mika.R
import com.wangzan101.mika.a11y.MikaAccessibilityService
import com.wangzan101.mika.cap.phone.PhoneServices
import com.wangzan101.mika.cap.phone.a11y.ScreenAccessibility
import com.wangzan101.mika.settings.AccessibilityState
import com.wangzan101.mika.settings.SystemStatusMonitor
import com.wangzan101.mika.ui.theme.MikaTheme
import com.wangzan101.mika.voice.HoldToTalk
import com.wangzan101.mika.voice.SpeechEngineSpec
import com.wangzan101.mika.voice.SpeechEvent
import com.wangzan101.mika.voice.SpeechFailure
import com.wangzan101.mika.voice.SpeechSession
import com.wangzan101.mika.voice.VoiceSource
import java.io.File
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.receiveAsFlow
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Assume.assumeTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TestRule
import org.junit.runner.Description
import org.junit.runner.RunWith
import org.junit.runners.model.Statement

/** Real Compose/Android/service lifecycle; voice events are fake, never microphone or model I/O. */
@RunWith(AndroidJUnit4::class)
class ApporoAlignmentTest {
    @get:Rule(order = Int.MIN_VALUE) val english: TestRule = ApporoEnglishUi()
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val context get() = instrumentation.targetContext
    private var automationFlags = 0
    private val automation get() = instrumentation.getUiAutomation(automationFlags)
    private val evidence get() = File(context.filesDir, "apporo-alignment").apply { mkdirs() }
    private val voice = AlignmentVoice()
    private var draft by mutableStateOf("")
    private var sent = 0

    @Before fun requireEnglishApporoOnSupportedAndroid() {
        assertEquals("com.apporo.assistant", context.packageName)
        assertTrue("API 35/36 only", Build.VERSION.SDK_INT in 35..36)
        assertEquals("en", context.resources.configuration.locales[0].language)
        assertEquals("en", context.getString(R.string.ui_locale))
        assertEquals(3807L, context.packageManager.getPackageInfo(context.packageName, 0).longVersionCode)
        val identity = com.wangzan101.mika.core.agent.SystemPrompt.identity(context.packageName)
        assertTrue(identity, identity.contains("Android package com.apporo.assistant"))
        assertFalse(identity, identity.contains("Android package io.woowtech.agent"))
        assertFalse(identity, identity.contains("Android package com.wangzan101.mika"))
        assertEquals("Forget a memory", context.getString(R.string.tool_forget_memory))
        automation.grantRuntimePermission(context.packageName, Manifest.permission.RECORD_AUDIO)
    }

    @After fun closeFakeVoiceSessions() {
        voice.sessions.forEach { it.out.close() }
    }

    @Test fun englishHelpPersistsUntilRealAccessibilityServiceIsOn() {
        val ids = listOf(R.string.a11y_install_title, R.string.a11y_install_steps,
            R.string.a11y_install_missing, R.string.a11y_install_app_info, R.string.a11y_install_open)
        val copy = ids.map { context.getString(it) }
        assertEquals("Can’t enable accessibility?", copy[0])
        assertEquals("Open App info", copy[3])
        assertEquals("Open accessibility settings", copy[4])
        assertTrue(copy[1], copy[1].contains("Apporo Assistant"))
        assertTrue(copy[2], copy[2].contains("Apporo Assistant"))
        assertFalse(copy.joinToString("\n"), Regex("\\b(Mika|WOOW|WOOWTECH)\\b", RegexOption.IGNORE_CASE)
            .containsMatchIn(copy.joinToString("\n")))
        File(evidence, "english-help.txt").writeText(copy.joinToString("\n\n"))

        val resolver = context.contentResolver
        val servicesKey = Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
        val enabledKey = Settings.Secure.ACCESSIBILITY_ENABLED
        val beforeServices = Settings.Secure.getString(resolver, servicesKey)
        val beforeEnabled = Settings.Secure.getString(resolver, enabledKey)
        val component = ComponentName(context, MikaAccessibilityService::class.java).flattenToString()
        val monitor = SystemStatusMonitor(context, PhoneServices.of(context).shellControl)
        val fixes = mutableListOf<Fix>()
        try {
            // UiAutomation suppresses services while their enabled setting remains readable.
            secure(servicesKey, "")
            secure(enabledKey, "0")
            compose.runOnIdle { monitor.start() }
            compose.setContent {
                MikaTheme {
                    val status by monitor.status.collectAsState()
                    PhoneOpsScreen(status, Build.VERSION.RELEASE, {}, {}, {}, {}, onFix = { fixes += it })
                }
            }
            waitAccessibility(monitor, AccessibilityState.Off)
            compose.onNodeWithTag("accessibility-install-help").assertExists()
            compose.onNodeWithText(copy[0]).performScrollTo().assertIsDisplayed()
            shot("help-off")
            compose.onNodeWithTag("setup-app-info").performScrollTo().performClick()
            compose.onNodeWithTag("a11y-install-open").performScrollTo().performClick()
            compose.runOnIdle { assertEquals(listOf(Fix.OpenAppInfo, Fix.OpenAccessibility), fixes) }
            compose.onNodeWithTag("accessibility-install-help").assertExists()

            secure(servicesKey, component)
            secure(enabledKey, "1")
            waitAccessibility(monitor, AccessibilityState.EnabledNotRunning)
            assertNull("Enabled setting alone must not mean connected", ScreenAccessibility.instance.value)
            compose.onNodeWithTag("accessibility-install-help").assertExists()
            compose.onNodeWithText(copy[0]).performScrollTo()
            shot("help-enabled-not-running")

            automationFlags = UiAutomation.FLAG_DONT_SUPPRESS_ACCESSIBILITY_SERVICES
            automation // Reconnect the real service; no fabricated AccessibilityState.On.
            waitAccessibility(monitor, AccessibilityState.On)
            assertNotNull(ScreenAccessibility.instance.value)
            compose.onNodeWithTag("accessibility-install-help").assertDoesNotExist()
            shot("help-on")
            receipt("accessibility", "Off -> EnabledNotRunning -> real connected On; English Apporo help and button callbacks")
        } finally {
            secure(servicesKey, beforeServices)
            secure(enabledKey, beforeEnabled)
            compose.runOnIdle { monitor.stop() }
            automationFlags = UiAutomation.FLAG_DONT_SUPPRESS_ACCESSIBILITY_SERVICES
            automation
        }
    }

    @Test fun narrowHelpButtonsWrapAtDoubleFontScaleWithoutEllipsis() {
        compose.setContent {
            MikaTheme {
                val density = LocalDensity.current.density
                CompositionLocalProvider(LocalDensity provides Density(density, fontScale = 2f)) {
                    Column(Modifier.width(220.dp).systemBarsPadding().verticalScroll(rememberScrollState())) {
                        AccessibilityInstallHelp({}, {})
                    }
                }
            }
        }
        for ((id, tag) in listOf(R.string.a11y_install_app_info to "setup-app-info",
                R.string.a11y_install_open to "a11y-install-open")) {
            compose.onNodeWithTag(tag).performScrollTo().assertIsDisplayed()
            val label = compose.onNodeWithText(context.getString(id), useUnmergedTree = true)
            label.performScrollTo().assertIsDisplayed()
            val layouts = mutableListOf<TextLayoutResult>()
            label.performSemanticsAction(SemanticsActions.GetTextLayoutResult) { it(layouts) }
            val layout = layouts.single()
            assertFalse("Help label overflowed at 2x font scale", layout.hasVisualOverflow)
            assertTrue((0 until layout.lineCount).none(layout::isLineEllipsized))
            if (id == R.string.a11y_install_open) assertTrue("Long label must wrap", layout.lineCount > 1)
            val button = compose.onNodeWithTag(tag).fetchSemanticsNode().boundsInRoot
            assertTrue("Button must grow to fit its label", button.height >= layout.size.height)
            val root = compose.onRoot().fetchSemanticsNode().boundsInRoot
            assertTrue("Help button must be inside the captured Compose surface",
                button.left >= root.left && button.right <= root.right &&
                    button.top >= root.top && button.bottom <= root.bottom)
        }
        shot("help-large-font")
        receipt("large-font", "220dp help width, 2x font scale: labels fit, long label wraps, no ellipsis")
    }

    @Test fun releaseAppendsEnglishTranscriptionWithoutSending() {
        composer("Draft")
        val session = press()
        session.out.trySend(SpeechEvent.Partial("add", " details"))
        compose.runOnIdle { assertEquals("Draft", draft); assertEquals(0, sent) }
        release(session, "add details")
        compose.onNodeWithTag("composer-field").assertTextEquals("Draft add details")
        assertEquals(0, sent)
        shot("voice-released")
        receipt("release", "Transcription appended to existing English draft on release; no automatic send")
    }

    @Test fun cancelPreservesDraftIgnoresLateTextAndAllowsRetry() {
        composer("Keep draft")
        val cancelled = press()
        cancelled.out.trySend(SpeechEvent.Partial("discard", " this"))
        SystemClock.sleep(700)
        compose.onNodeWithTag("composer-field").performTouchInput { moveBy(Offset(0f, -400f)) }
        waitTag("voice-cancel-hint")
        compose.onNodeWithTag("composer-field").performTouchInput { up() }
        compose.waitUntil(5_000) { cancelled.cancelled == 1 }
        // Keep the fake transport open so this is a genuinely delivered late event, not a closed-channel no-op.
        assertTrue(cancelled.out.trySend(SpeechEvent.Final("late discarded text")).isSuccess)
        waitNoTag("voice-listen")
        compose.onNodeWithTag("composer-field").assertTextEquals("Keep draft")
        assertEquals(0, cancelled.released)
        assertEquals(0, sent)
        shot("voice-cancelled")
        val retry = press()
        assertNotSame(cancelled, retry)
        assertEquals(2, voice.sessions.size)
        release(retry, "retry works")
        compose.onNodeWithTag("composer-field").assertTextEquals("Keep draft retry works")
        assertEquals(0, sent)
        shot("voice-cancel-retry")
        receipt("cancel", "Cancellation preserved draft and ignored late final; new session retried without sending")
    }

    @Test fun microphoneErrorKeepsDraftAndAllowsRetryWithoutSending() {
        composer("Keep draft")
        val failed = press()
        failed.out.trySend(SpeechEvent.Failed(SpeechFailure.MicUnavailable))
        compose.onNodeWithTag("composer-field").performTouchInput { up() }
        waitNoTag("voice-listen")
        waitTag("voice-toast")
        compose.onNodeWithTag("composer-field").assertTextEquals("Keep draft")
        assertEquals(0, sent)
        shot("voice-error")
        val retry = press()
        assertNotSame(failed, retry)
        assertEquals(2, voice.sessions.size)
        release(retry, "recovered")
        compose.onNodeWithTag("composer-field").assertTextEquals("Keep draft recovered")
        assertEquals(0, sent)
        shot("voice-error-retry")
        receipt("error", "Fake microphone error preserved draft; new session recovered without sending")
    }

    private fun composer(initial: String) {
        draft = initial
        compose.setContent {
            MikaTheme {
                Box(Modifier.fillMaxSize()) {
                    Composer(Modifier.align(Alignment.BottomCenter), draft, { draft = it }, ComposerMode.Idle,
                        hasHistory = false, onSend = { sent++ }, onStop = {}, voice = voice,
                        onVoiceText = { draft = HoldToTalk.join(draft, it) })
                }
            }
        }
    }

    private fun press(): AlignmentSession {
        compose.onNodeWithTag("composer-field").performTouchInput { down(center) }
        waitTag("voice-listen")
        return compose.runOnIdle { voice.sessions.last() }
    }

    private fun release(session: AlignmentSession, text: String) {
        SystemClock.sleep(700) // HoldToTalk uses real Android uptime, not the Compose animation clock.
        compose.onNodeWithTag("composer-field").performTouchInput { up() }
        compose.waitUntil(5_000) { session.released == 1 }
        session.out.trySend(SpeechEvent.Final(text))
        session.out.close()
        waitNoTag("voice-listen")
    }

    private fun waitTag(tag: String) = compose.waitUntil(5_000) {
        compose.onAllNodesWithTag(tag).fetchSemanticsNodes().isNotEmpty()
    }
    private fun waitNoTag(tag: String) = compose.waitUntil(5_000) {
        compose.onAllNodesWithTag(tag).fetchSemanticsNodes().isEmpty()
    }

    private fun waitAccessibility(monitor: SystemStatusMonitor, expected: AccessibilityState) {
        compose.waitUntil(10_000) {
            monitor.refresh()
            monitor.status.value.accessibility == expected
        }
        compose.waitForIdle()
        assertEquals(expected, monitor.status.value.accessibility)
    }

    private fun secure(key: String, value: String?) {
        val ui = automation
        ui.adoptShellPermissionIdentity(Manifest.permission.WRITE_SECURE_SETTINGS)
        try { assertTrue(Settings.Secure.putString(context.contentResolver, key, value)) }
        finally { ui.dropShellPermissionIdentity() }
    }

    private fun shot(name: String) {
        compose.waitForIdle()
        // Capture this Compose surface directly, not whichever window UiAutomation sees first.
        val bitmap = compose.onRoot().captureToImage().asAndroidBitmap()
        try { File(evidence, "$name.png").outputStream().use { assertTrue(bitmap.compress(Bitmap.CompressFormat.PNG, 100, it)) } }
        finally { bitmap.recycle() }
    }

    private fun receipt(name: String, checked: String) {
        File(evidence, "$name.json").writeText(JSONObject().put("status", "PASS")
            .put("package", context.packageName).put("api", Build.VERSION.SDK_INT).put("locale", "en")
            .put("checked", checked).put("voice", "fake events only; no live mic/model")
            .put("screenshot_scope", "App Compose surface; excludes system bars and other windows")
            .put("automatic_sends", sent).toString(2))
    }

    private class AlignmentSession : SpeechSession {
        val out = Channel<SpeechEvent>(Channel.UNLIMITED)
        override val events: Flow<SpeechEvent> = out.receiveAsFlow()
        override val live = true
        @Volatile var released = 0
        @Volatile var cancelled = 0
        override fun release() { released++ }
        override fun cancel() { cancelled++ }
    }
    private class AlignmentVoice : VoiceSource {
        val sessions = mutableListOf<AlignmentSession>()
        override fun spec(): SpeechEngineSpec = SpeechEngineSpec.System(onDevice = true)
        override fun start(language: String?): SpeechSession = AlignmentSession().also { sessions += it }
    }
}

/** Apporo has no simplified-Chinese resources; set English before the activity rule launches. */
private class ApporoEnglishUi : TestRule {
    override fun apply(base: Statement, description: Description): Statement = object : Statement() {
        override fun evaluate() {
            val context = InstrumentationRegistry.getInstrumentation().targetContext
            assumeTrue("Apporo alignment acceptance requires Apporo on API 35/36",
                context.packageName == "com.apporo.assistant" && Build.VERSION.SDK_INT in 35..36)
            val manager = context.getSystemService(LocaleManager::class.java)
            val before = manager.applicationLocales
            try {
                manager.applicationLocales = LocaleList.forLanguageTags("en-US")
                val deadline = SystemClock.uptimeMillis() + 5_000
                while (context.resources.configuration.locales[0].language != "en" && SystemClock.uptimeMillis() < deadline) {
                    SystemClock.sleep(50)
                }
                assertEquals("en", context.resources.configuration.locales[0].language)
                base.evaluate()
            } finally { manager.applicationLocales = before }
        }
    }
}
