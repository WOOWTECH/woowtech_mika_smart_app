package com.wangzan101.mika.ui

import android.content.Context
import androidx.activity.ComponentActivity
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.assertTextEquals
import androidx.compose.ui.test.junit4.StateRestorationTester
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performTextReplacement
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.After
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/** Component restoration plus disk-backed preference writes; actual process death is tested by adb. */
@RunWith(AndroidJUnit4::class)
class ChatDraftRestorationTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()
    @get:Rule(order = Int.MAX_VALUE) val closeActivity = com.wangzan101.mika.CloseComposeActivity(compose)
    private val prefs get() = InstrumentationRegistry.getInstrumentation().targetContext
        .getSharedPreferences("test_chat_draft", Context.MODE_PRIVATE)

    @Before fun clearBefore() { prefs.edit().clear().commit() }
    @After fun clearAfter() { prefs.edit().clear().commit() }

    @Test fun recreationRestoresEditsAndNeverRevivesClearedText() {
        val restoration = StateRestorationTester(compose)
        restoration.setContent {
            var draft by rememberChatDraft(prefs)
            BasicTextField(draft, { draft = it }, Modifier.testTag("draft"))
        }
        val text = "Draft before permission change\n中文語音 123"
        compose.onNodeWithTag("draft").performTextReplacement(text)
        // A synchronous empty commit waits for earlier apply() writes too.
        prefs.edit().commit()
        restoration.emulateSavedInstanceStateRestore()
        compose.onNodeWithTag("draft").assertTextEquals(text)
        compose.onNodeWithTag("draft").performTextReplacement("")
        prefs.edit().commit()
        restoration.emulateSavedInstanceStateRestore()
        compose.onNodeWithTag("draft").assertTextEquals("")
    }
}
