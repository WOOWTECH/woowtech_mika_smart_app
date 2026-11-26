package com.wangzan101.mika.ui

import com.wangzan101.mika.settings.FeatureFlagsCapsuleTest.MemoryPrefs
import org.junit.Assert.*
import org.junit.Test

class BotUiDraftTest {
    @Test fun legacyDraftMigratesOnceAndConversationsKeepIndependentText() {
        val prefs = MemoryPrefs()
        ChatDraftState(prefs).value = "existing text\n語音"
        assertEquals("existing text\n語音", botUiDraft(prefs, "a").value)
        assertEquals("", botUiDraft(prefs, "b").value)
        botUiDraft(prefs, "b").value = "B draft"
        botUiDraft(prefs, "a").value = "A draft"
        assertEquals("B draft", botUiDraft(prefs, "b").value)
        assertEquals("A draft", botUiDraft(prefs, "a").value)
        botUiDraft(prefs, "b").value = ""
        assertEquals("", botUiDraft(prefs, "b").value)
        assertEquals("A draft", botUiDraft(prefs, "a").value)
        assertEquals("existing text\n語音", ChatDraftState(prefs).value)
    }
}
