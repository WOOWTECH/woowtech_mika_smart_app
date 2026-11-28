package com.wangzan101.mika.ui

import android.content.Context
import android.graphics.Bitmap
import android.net.Uri
import androidx.activity.ComponentActivity
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.StateRestorationTester
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.wangzan101.mika.R
import com.wangzan101.mika.chat.BotUiProfile
import com.wangzan101.mika.chat.ConversationStore
import com.wangzan101.mika.core.agent.TaskState
import com.wangzan101.mika.core.agent.Turn
import com.wangzan101.mika.takeover.Takeover
import com.wangzan101.mika.ui.theme.MikaTheme
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.MutableStateFlow
import org.junit.*
import org.junit.Assert.*
import org.junit.runner.RunWith
import java.io.File
import java.util.UUID

/** Isolated UI/storage fixture. No model, service, network, or real conversation data is used. */
@RunWith(AndroidJUnit4::class)
class BotUiConversationDeviceTest {
    // HyperOS blocks an instrumented app's first background Activity launch. Start the
    // fixture via the shell's ordinary foreground launch before ActivityScenario; no app-op changes.
    @get:Rule(order = Int.MIN_VALUE) val foreground = org.junit.rules.TestRule { base, _ ->
        object : org.junit.runners.model.Statement() {
            override fun evaluate() {
                val instrumentation = InstrumentationRegistry.getInstrumentation()
                val command = "am start -W -n ${instrumentation.targetContext.packageName}/androidx.activity.ComponentActivity"
                android.os.ParcelFileDescriptor.AutoCloseInputStream(instrumentation.uiAutomation.executeShellCommand(command)).use { it.readBytes() }
                base.evaluate()
            }
        }
    }
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()
    @get:Rule(order = Int.MAX_VALUE) val closeActivity = com.wangzan101.mika.CloseComposeActivity(compose)
    private val context = InstrumentationRegistry.getInstrumentation().targetContext
    private val fixtureId = UUID.randomUUID().toString()
    private val dir = File(context.cacheDir, "bot_ui_test_$fixtureId")
    private val store = ConversationStore(dir)
    private val prefs = context.getSharedPreferences("bot_ui_test_$fixtureId", Context.MODE_PRIVATE)
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val actions = object : TaskActions {
        override fun start(goal: String, conversationId: String) = error("This fixture must not start tasks")
        override fun cancel() {}
        override fun resume() {}
        override fun takeOver() {}
        override fun handBack() {}
        override fun finishedMyself() {}
        override fun skip() {}
        override fun answer(text: String) {}
        override fun approve(key: Int) {}
        override fun decline(key: Int) {}
    }
    private lateinit var vm: ChatViewModel
    private fun text(id: Int) = context.getString(id)

    @Before fun prepare() {
        store.append("a", Turn("question A", "answer A", "succeeded"))
        store.append("b", Turn("question B", "answer B", "succeeded"))
        store.saveBotUiProfile("a", "Alpha", BotUiProfile(color = 1))
        store.saveBotUiProfile("b", "Beta", BotUiProfile(color = 4))
        compose.runOnUiThread {
            vm = ChatViewModel(scope, MutableStateFlow(TaskState.Idle), MutableStateFlow(Takeover.Stage.None), actions, store)
            vm.openConversation("a")
        }
    }
    @After fun clean() { scope.cancel(); prefs.edit().clear().commit(); dir.deleteRecursively() }

    @Composable private fun Content() {
        MikaTheme {
            val ui by vm.ui.collectAsState()
            val id = vm.botUiConversationId()
            var draft by rememberBotUiDraft(id, prefs)
            Column {
                BotUiChatHeader(vm, ui, null, onHistory = {})
                BasicTextField(draft, { draft = it }, Modifier.testTag("bot_ui_test_draft"))
            }
        }
    }

    @Test fun profileEditsAreIndependentPersistAndCancelDoesNotWrite() {
        compose.setContent { Content() }
        compose.onNodeWithTag("bot_ui_name_capsule").performClick()
        compose.waitUntil(5_000) { compose.onAllNodes(hasTestTag("bot_ui_profile_name") and isEnabled()).fetchSemanticsNodes().size == 1 }
        compose.onNodeWithTag("bot_ui_profile_name").performTextReplacement("Personal Alpha")
        android.os.ParcelFileDescriptor.AutoCloseInputStream(InstrumentationRegistry.getInstrumentation().uiAutomation.executeShellCommand("input keyevent 4")).use { it.readBytes() }
        compose.waitForIdle()
        compose.onNodeWithTag("bot_ui_avatar_button").performClick()
        compose.onNodeWithTag("bot_ui_shape_9").performScrollTo().performClick()
        compose.onNodeWithTag("bot_ui_expression_5").performScrollTo().performClick()
        compose.onNodeWithContentDescription(text(R.string.save)).performClick()
        compose.waitUntil(5_000) { store.title("a") == "Personal Alpha" }
        compose.waitUntil(5_000) { compose.onAllNodesWithTag("bot_ui_profile_name").fetchSemanticsNodes().isEmpty() }
        val helmet = ConversationStore(dir).botUiProfile("a")
        assertEquals(9, helmet.shape)
        assertEquals(5, helmet.expression)
        assertEquals(BotUiProfile(color = 4), ConversationStore(dir).botUiProfile("b"))
        assertEquals("Beta", ConversationStore(dir).title("b"))
        compose.runOnUiThread { vm.openConversation("b") }
        compose.onNodeWithTag("bot_ui_name_capsule").performClick()
        compose.waitUntil(5_000) { compose.onAllNodes(hasTestTag("bot_ui_profile_name") and isEnabled()).fetchSemanticsNodes().size == 1 }
        compose.onNodeWithTag("bot_ui_profile_name").performTextReplacement("Discard this")
        compose.onNodeWithContentDescription(text(R.string.bot_ui_close)).performClick()
        assertEquals("Beta", ConversationStore(dir).title("b"))
        assertEquals("Personal Alpha", ConversationStore(dir).title("a"))
    }

    @Test fun newChatKeepsOldDraftAndRestorationRetainsBoth() {
        val restoration = StateRestorationTester(compose)
        restoration.setContent { Content() }
        compose.onNodeWithTag("bot_ui_test_draft").performTextReplacement("Alpha unsent 中文")
        compose.onNodeWithContentDescription(text(R.string.bot_ui_more)).performClick()
        // The popover plays its entrance once its own window is on screen, so wait for the item instead of assuming it is there.
        compose.waitUntil(5_000) { compose.onAllNodesWithText(text(R.string.chat_new)).fetchSemanticsNodes().isNotEmpty() }
        compose.onNodeWithText(text(R.string.chat_new)).performClick()
        compose.onNodeWithTag("bot_ui_test_draft").assertTextEquals("")
        compose.onNodeWithTag("bot_ui_test_draft").performTextReplacement("New unsent")
        var newId = ""
        compose.runOnIdle { newId = vm.ui.value.conversationId!! }
        assertNotEquals("a", newId)
        prefs.edit().commit()
        restoration.emulateSavedInstanceStateRestore()
        compose.onNodeWithTag("bot_ui_test_draft").assertTextEquals("New unsent")
        compose.runOnUiThread { vm.openConversation("a") }
        compose.onNodeWithTag("bot_ui_test_draft").assertTextEquals("Alpha unsent 中文")
        assertEquals("New unsent", botUiDraft(prefs, newId).value)
        assertEquals("Alpha", store.title("a"))
    }

    @Test fun uploadedImageIsLocallyCroppedAndPersistsWithoutProviderAccess() {
        dir.mkdirs()
        val source = File(dir, "source.jpg")
        val bitmap = Bitmap.createBitmap(640, 480, Bitmap.Config.ARGB_8888).apply { eraseColor(android.graphics.Color.BLUE) }
        source.outputStream().use { bitmap.compress(Bitmap.CompressFormat.JPEG, 90, it) }
        bitmap.recycle()
        val image = botUiImportAvatar(context, Uri.fromFile(source))
        source.delete()
        assertTrue(store.saveBotUiProfile("a", "Photo Alpha", BotUiProfile(image = image)))
        val saved = ConversationStore(dir).botUiProfile("a")
        val bytes = java.util.Base64.getDecoder().decode(saved.image)
        val decoded = android.graphics.BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
        assertEquals(320, decoded.width); assertEquals(320, decoded.height); decoded.recycle()
        assertNull(ConversationStore(dir).botUiProfile("b").image)
        compose.setContent { Content() }
        compose.onNodeWithTag("bot_ui_name_capsule").assertExists()
    }
}
