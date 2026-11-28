package com.wangzan101.mika.core.woowbot.push

import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test

class BotPushPreviewTest {
    private val bots = """{"bots":[{"id":"bot_1","name":"Podman QA","threadId":"t"},{"id":"bot_2","name":7}],
        "groups":[{"id":"room_1","name":"Research room"}],"sections":[]}"""

    @Test fun nameComesFromBotsOrRoomsOnly() {
        assertEquals("Podman QA", BotPushPreviewText.name(bots, "bot_1"))
        assertEquals("Research room", BotPushPreviewText.name(bots, "room_1"))
        assertNull(BotPushPreviewText.name(bots, "bot_2"))
        assertNull(BotPushPreviewText.name(bots, "missing"))
        assertNull(BotPushPreviewText.name("not json", "bot_1"))
        assertNull(BotPushPreviewText.name("""{"bots":{}}""", "bot_1"))
        val long = BotPushPreviewText.name("""{"bots":[{"id":"b","name":"${"n".repeat(200)}"}]}""", "b")!!
        assertEquals(BotPushPreviewText.NAME_MAX, long.length)
        assertEquals("A B", BotPushPreviewText.name("""{"bots":[{"id":"b","name":"A‮\n B"}]}""", "b"))
    }

    @Test fun excerptIsTheReplyAfterTheLastUserMessage() {
        val thread = """{"messages":[
            {"role":"bot","kind":"text","text":"Earlier answer"},
            {"role":"user","kind":"text","text":"Question"},
            {"role":"bot","kind":"activity","text":""},
            {"role":"bot","kind":"text","text":"## Result\n**Done**: see [the file](https://x.example/f)."},
            {"role":"bot","kind":"text","text":"Second   part"}],"hasMore":true}"""
        assertEquals("Result\nDone: see the file.\nSecond part", BotPushPreviewText.excerpt(thread))
    }

    @Test fun excerptFallsBackToTheLastBotTextAndRejectsEmptyOrMalformed() {
        assertEquals("Hi", BotPushPreviewText.excerpt("""{"messages":[{"role":"bot","text":"Hi"},{"role":"user","text":"Q"}]}"""))
        assertNull(BotPushPreviewText.excerpt("""{"messages":[{"role":"user","text":"Q"}]}"""))
        assertNull(BotPushPreviewText.excerpt("""{"messages":[]}"""))
        assertNull(BotPushPreviewText.excerpt("""{"messages":"x"}"""))
        assertNull(BotPushPreviewText.excerpt("<html>"))
    }

    @Test fun cleanBoundsLengthWithoutSplittingCharacters() {
        val text = BotPushPreviewText.clean("a".repeat(398) + "😀😀", 400, singleLine = false)
        assertTrue(text.endsWith("…"))
        assertTrue(text.length <= 400)
        assertFalse(text.dropLast(1).last().isHighSurrogate())
        assertEquals("x y", BotPushPreviewText.clean("```kotlin\nx\n```\n\n\n> y", 400, singleLine = true))
    }

    @Test fun onlyTheTwoFixedPreviewPathsAreAllowed() {
        assertTrue(BotPushHttpApi.isPreviewPath("/api/bots?messages=1"))
        assertTrue(BotPushHttpApi.isPreviewPath(BotPushHttpApi.messagesPath("thread_1:a.b-c")))
        listOf("/api/bots", "/api/bots?messages=200", "/api/threads/../messages?limit=8", "/api/threads/a/messages?limit=200",
            "/api/threads/a/messages?limit=8&before=x", "/api/threads/a/b/messages?limit=8", "/api/threads//messages?limit=8")
            .forEach { assertFalse(it, BotPushHttpApi.isPreviewPath(it)) }
    }

    @Test fun previewReadsBothPartsAndKeepsWhatAnswered() = runBlocking {
        val credentials = BotPushCredentials("b91482c6-8dd0-46b3-a2de-13a8c3932762", "1", "https://bot.example.com", "c=1")
        val seen = mutableListOf<String>()
        fun api(messages: Int) = BotPushHttpApi(BotPushHttpTransport { _, method, path, _, _, _ ->
            seen.add("$method $path")
            if (path == BotPushHttpApi.BOTS_PATH) BotPushHttpResponse(200, bots)
            else BotPushHttpResponse(messages, """{"messages":[{"role":"user","text":"Q"},{"role":"bot","text":"Answer"}]}""")
        }, { null }, { true }, { true })
        val full = api(200).preview(credentials, "bot_1", "thread_1")!!
        assertEquals("Podman QA", full.botName)
        assertEquals("Answer", full.excerpt)
        assertEquals(setOf("GET /api/bots?messages=1", "GET /api/threads/thread_1/messages?limit=8"), seen.toSet())
        val nameOnly = api(500).preview(credentials, "bot_1", "thread_1")!!
        assertEquals("Podman QA", nameOnly.botName)
        assertNull(nameOnly.excerpt)
        assertNull(api(500).preview(credentials, "missing", "thread_1"))
        assertTrue(runCatching { api(200).preview(credentials, "../x", "thread_1") }.isFailure)
    }
}
