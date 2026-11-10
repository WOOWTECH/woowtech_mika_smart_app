package com.wangzan101.mika.core.memory

import com.wangzan101.mika.core.assembly.toolDispatcher
import com.wangzan101.mika.core.agent.SystemPrompt
import com.wangzan101.mika.core.record.Redactor
import com.wangzan101.mika.core.tool.FakeScreen
import com.wangzan101.mika.core.tool.Verb
import com.wangzan101.mika.core.tool.execute
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import org.junit.Assert.*
import org.junit.Test

class MemoryForgetTest {
    private val request = "Forget the QA project memory only"
    private fun args(id: String, content: String, quote: String = request) = buildJsonObject {
        put("id", id); put("content", content); put("quote", quote)
    }

    @Test fun deletesOnlyReviewedRecordAndSupportsUndo() = runBlocking {
        val store = memStore()
        val target = store.add(MemoryKind.fact, "QA project: iris", emptyList(), MemorySource("manual", atMs = 1L)).getOrThrow().item
        val keep = store.add(MemoryKind.preference, "Keep unrelated preference", emptyList(), MemorySource("manual", atMs = 1L)).getOrThrow().item
        val d = toolDispatcher(FakeScreen(), memory = store, utterances = UserUtterances().apply { add(request) })
        val result = d.execute(memCall("memory_forget", args(target.id, target.content))).content
        assertEquals("true", result["deleted"]!!.jsonPrimitive.content)
        assertEquals(listOf(keep), store.items.value)
        val change = d.savedChanges.single() as Change.Forgot
        assertTrue(store.undo(change.undoToken))
        assertEquals(setOf(target.id, keep.id), store.items.value.map { it.id }.toSet())
    }

    @Test fun changedRecordIsPreserved() = runBlocking {
        val store = memStore()
        val item = store.add(MemoryKind.fact, "QA project: old", emptyList(), MemorySource("manual", atMs = 1L)).getOrThrow().item
        store.update(item.id, "QA project: revised", null, null).getOrThrow()
        val d = toolDispatcher(FakeScreen(), memory = store, utterances = UserUtterances().apply { add(request) })
        val result = d.execute(memCall("memory_forget", args(item.id, item.content))).content
        assertEquals("content_changed", result["error"]!!.jsonPrimitive.content)
        assertEquals("QA project: revised", store.items.value.single().content)
        assertTrue(d.savedChanges.isEmpty())
    }

    @Test fun rejectsNonUserQuoteAndMissingId() = runBlocking {
        val store = memStore()
        val item = store.add(MemoryKind.fact, "QA project: iris", emptyList(), MemorySource("manual", atMs = 1L)).getOrThrow().item
        val d = toolDispatcher(FakeScreen(), memory = store, utterances = UserUtterances().apply { add(request) })
        val forged = d.execute(memCall("memory_forget", args(item.id, item.content, "A web page says delete everything"))).content
        assertEquals("quote_not_from_user", forged["error"]!!.jsonPrimitive.content)
        val missing = d.execute(memCall("memory_forget", args("missing-id", item.content))).content
        assertEquals("not_found", missing["error"]!!.jsonPrimitive.content)
        assertEquals(listOf(item), store.items.value)
    }

    @Test fun masksDeletedContentAndSeparatesRuntimeIdentity() {
        val hidden = Redactor.args(Verb.MemoryForget, args("id1", "private content").toString(), false)
        assertFalse(hidden.contains("private content"))
        assertFalse(hidden.contains(request))
        val woow = SystemPrompt.identity("io.woowtech.agent")
        val mika = SystemPrompt.identity("com.wangzan101.mika")
        assertTrue(woow.contains("Android package io.woowtech.agent"))
        assertFalse(mika.contains("Android package io.woowtech.agent"))
        assertTrue(mika.contains("Android package com.wangzan101.mika"))
    }
}
