package com.wangzan101.mika.ui

import com.wangzan101.mika.settings.FeatureFlagsCapsuleTest.MemoryPrefs
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ChatDraftTest {
    @Test fun editsAndCompletedTranscriptionSurviveNewStateWithoutTrimming() {
        val prefs = MemoryPrefs()
        val draft = ChatDraftState(prefs)
        draft.value = "  typed draft\n"
        draft.value = com.wangzan101.mika.voice.HoldToTalk.join(draft.value, "中文語音 123")
        assertEquals(draft.value, ChatDraftState(prefs).value)
        assertTrue(ChatDraftState(prefs).value.startsWith("  typed draft\n"))
    }

    @Test fun clearingAfterSendDoesNotResurrectAnEarlierDraft() {
        val prefs = MemoryPrefs()
        val draft = ChatDraftState(prefs)
        draft.value = "first edit"
        draft.value = "last edit"
        draft.value = ""
        assertEquals("", ChatDraftState(prefs).value)
        assertTrue("Do not retain sent text in preferences", prefs.all.isEmpty())
    }

    @Test fun whitespaceAndLongMultilineUnicodeDraftAreKeptExactly() {
        val prefs = MemoryPrefs()
        val text = "\n  " + "測試 🙂 draft\n".repeat(2_000) + " \n"
        ChatDraftState(prefs).value = text
        assertEquals(text, ChatDraftState(prefs).value)
        ChatDraftState(prefs).value = "  \n"
        assertEquals("  \n", ChatDraftState(prefs).value)
    }
}
