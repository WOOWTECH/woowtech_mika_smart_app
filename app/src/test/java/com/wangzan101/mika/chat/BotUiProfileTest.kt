package com.wangzan101.mika.chat

import com.wangzan101.mika.core.agent.Turn
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File

class BotUiProfileTest {
    @get:Rule val tmp = TemporaryFolder()

    @Test fun independentProfilesPersistWithoutRewritingConversationOrMetadata() {
        val dir = tmp.newFolder()
        val store = ConversationStore(dir)
        store.append("a", Turn("first question", "answer", "succeeded"))
        store.append("b", Turn("other question", "other answer", "succeeded"))
        store.setTitle("a", "automatic title")
        store.setPinned("a", true, 123L)
        val original = File(dir, "a.json").readBytes()
        val timestamp = File(dir, "a.json").lastModified()
        val profile = BotUiProfile(robot = 2, color = 4, face = 1)
        assertTrue(store.saveBotUiProfile("a", "  My assistant  ", profile))
        val restored = ConversationStore(dir)
        assertEquals("My assistant", restored.title("a"))
        assertEquals(profile, restored.botUiProfile("a"))
        assertEquals(BotUiProfile(), restored.botUiProfile("b"))
        assertEquals("other question", restored.list().first { it.id == "b" }.title)
        assertEquals(123L, restored.pinnedAt("a"))
        assertArrayEquals(original, File(dir, "a.json").readBytes())
        assertEquals(timestamp, File(dir, "a.json").lastModified())
        assertFalse(restored.setTitle("a", "late automatic title"))
        // Legacy rename remains authoritative, including names edited outside the v06 editor.
        restored.rename("a", "legacy rename")
        assertEquals("legacy rename", restored.title("a"))
        assertEquals(profile, restored.botUiProfile("a"))
    }

    @Test fun invalidAndFailedSavesDoNotChangeProfile() {
        val dir = tmp.newFolder()
        val store = ConversationStore(dir)
        val original = BotUiProfile(color = 2)
        assertTrue(store.saveBotUiProfile("a", "name", original))
        assertFalse(store.saveBotUiProfile("a", "  ", BotUiProfile()))
        assertFalse(store.saveBotUiProfile("a", "invalid", BotUiProfile(robot = -1)))
        assertFalse(store.saveBotUiProfile("a", "invalid", BotUiProfile(image = "not an image")))
        assertEquals("name", store.title("a"))
        assertEquals(original, store.botUiProfile("a"))
        File(dir, "a.title").delete()
        File(dir, "a.title").mkdir() // Force the title write to fail after writing the sidecar.
        assertFalse(store.saveBotUiProfile("a", "fails", BotUiProfile(color = 5)))
        assertEquals(original, store.botUiProfile("a"))
    }

    @Test fun deletionRemovesAvatarAndRejectsLateSaveWithoutTouchingOthers() {
        val dir = tmp.newFolder()
        val store = ConversationStore(dir)
        store.saveBotUiProfile("a", "A", BotUiProfile(color = 1))
        store.saveBotUiProfile("b", "B", BotUiProfile(color = 3))
        store.delete("a")
        assertFalse(File(dir, "a.json.bot_ui_profile").exists())
        assertFalse(store.saveBotUiProfile("a", "late edit", BotUiProfile()))
        assertEquals(BotUiProfile(color = 3), store.botUiProfile("b"))
    }

    @Test fun corruptOrFutureAvatarFallsBackWithoutChangingLegacyTitle() {
        val dir = tmp.newFolder()
        val store = ConversationStore(dir)
        store.rename("a", "Keep me")
        File(dir, "a.json.bot_ui_profile").writeText("broken")
        assertEquals(BotUiProfile(), store.botUiProfile("a"))
        assertEquals("Keep me", store.title("a"))
        File(dir, "a.json.bot_ui_profile").writeText("""{"color":3,"futureField":true}""")
        assertEquals(BotUiProfile(color = 3), store.botUiProfile("a"))
    }

    @Test fun profileBeforeFirstMessageDoesNotCreateFakeHistoryOrLoseTheChosenName() {
        val store = ConversationStore(tmp.newFolder())
        val id = store.newConversation()
        assertTrue(store.saveBotUiProfile(id, "First name", BotUiProfile(face = 2)))
        assertTrue(store.list().isEmpty())
        store.append(id, Turn("hello", "hi", "succeeded"))
        assertEquals("First name", store.list().single().title)
        assertEquals(BotUiProfile(face = 2), store.botUiProfile(id))
    }

    @Test fun elevenColourPaletteValidatesAndLegacyProfilesKeepTheirLook() {
        // Original six-colour profiles map to the closest woowtechbot colour, so no conversation changes colour.
        val legacy = listOf(0 to 1, 1 to 8, 2 to 4, 3 to 3, 4 to 6, 5 to 10)
        legacy.forEach { (old, current) -> assertEquals(current, BotUiProfile(color = old).colorIndex()) }
        assertEquals(0, BotUiProfile(color = 3, face = 2).faceMode())
        val upgraded = BotUiProfile(robot = 1, color = 4, face = 2).upgraded()
        assertEquals(BotUiProfile(robot = 1, color = 6, face = 0, palette = 2), upgraded)
        assertEquals(upgraded, upgraded.upgraded())
        // The new generation allows all eleven colours and the three face modes; the old one still stops at six.
        assertTrue(BotUiProfile(color = 10, face = 2, palette = 2).valid())
        assertFalse(BotUiProfile(color = 11, palette = 2).valid())
        assertFalse(BotUiProfile(color = 6).valid())
        assertFalse(BotUiProfile(palette = 3).valid())
        assertEquals(2, BotUiProfile(color = 7, face = 2, palette = 2).faceMode())
    }

    @Test fun paletteGenerationSurvivesTheSidecarRoundTrip() {
        val dir = tmp.newFolder()
        val store = ConversationStore(dir)
        assertTrue(store.saveBotUiProfile("a", "A", BotUiProfile(robot = 2, color = 9, face = 1, palette = 2)))
        assertEquals(BotUiProfile(robot = 2, color = 9, face = 1, palette = 2), ConversationStore(dir).botUiProfile("a"))
        // A sidecar written before the palette field existed has no "palette" key and reads as the legacy generation.
        File(dir, "b.json").writeText("[]")
        File(dir, "b.json.bot_ui_profile").writeText("{\"robot\":1,\"color\":2}")
        val legacy = ConversationStore(dir).botUiProfile("b")
        assertEquals(1, legacy.palette)
        assertEquals(4, legacy.colorIndex())
    }
}
