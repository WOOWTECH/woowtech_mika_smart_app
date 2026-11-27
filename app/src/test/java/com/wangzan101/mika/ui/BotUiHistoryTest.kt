package com.wangzan101.mika.ui

import com.wangzan101.mika.chat.ConversationStore
import com.wangzan101.mika.core.agent.Turn
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class BotUiHistoryTest {
    @get:Rule val tmp = TemporaryFolder()

    @Test fun searchIncludesOlderConversationsRepliesAndSteersNotJustTitles() {
        val store = ConversationStore(tmp.newFolder())
        repeat(60) { store.append("c$it", Turn("question $it", "reply $it", "succeeded")) }
        store.append("special", Turn("ordinary title", "A needle in the answer", "succeeded", steers = listOf("繁體中文"), interruptedReplies = listOf("interrupted evidence")))
        val rows = botUiHistoryRows(store, store.list())
        assertEquals(61, botUiFilterHistory(rows, "").size)
        assertEquals("special", botUiFilterHistory(rows, " NEEDLE ").single().summary.id)
        assertEquals("special", botUiFilterHistory(rows, "繁體").single().summary.id)
        assertEquals("special", botUiFilterHistory(rows, "interrupted evidence").single().summary.id)
        assertTrue(botUiFilterHistory(rows, "not present").isEmpty())
    }

    @Test fun findIncludesCompletedPartialAndCancelledReplies() {
        val messages = botUiMessages(listOf(
            Exchange("hello", emptyList(), ExchangeStatus.Done("reply", null), false),
            Exchange("next", emptyList(), ExchangeStatus.Cancelled("partial result"), false),
            Exchange("live", emptyList(), ExchangeStatus.Working, true, draft = "streaming")
        ))
        assertTrue(messages.containsAll(listOf("hello", "reply", "partial result", "streaming")))
    }
}
