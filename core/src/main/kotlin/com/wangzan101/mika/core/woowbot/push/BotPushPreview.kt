package com.wangzan101.mika.core.woowbot.push

import kotlinx.serialization.json.*

/**
 * What a bot notification shows (owner 2026-11-28): the bot that replied and the start of its reply. The phone reads them
 * from the service with its own verified session after the push arrives; the push itself still carries IDs only.
 */
class BotPushPreview(val botName: String?, val excerpt: String?)

/** Pure parsing of the website's own API answers. Anything unexpected gives null, so the generic text is shown. */
object BotPushPreviewText {
    const val NAME_MAX = 64
    const val EXCERPT_MAX = 400

    /** `GET /api/bots?messages=1`: `{bots:[{id,name}], groups:[{id,name}]}`; rooms are groups. */
    fun name(botsJson: String, botId: String): String? = runCatching {
        val root = Json.parseToJsonElement(botsJson).jsonObject
        val all = (root["bots"] as? JsonArray).orEmpty() + (root["groups"] as? JsonArray).orEmpty()
        all.mapNotNull { it as? JsonObject }.firstOrNull { it.string("id") == botId }?.string("name")
            ?.let { clean(it, NAME_MAX, singleLine = true) }
    }.getOrNull()?.takeIf { it.isNotEmpty() }

    /**
     * `GET /api/threads/{thread}/messages?limit=8`: `{messages:[{role,kind,text}]}`, oldest first. The reply is every bot
     * text after the last user message, as the website's own inbox shows it; without one, the last bot text.
     */
    fun excerpt(messagesJson: String): String? = runCatching {
        val messages = (Json.parseToJsonElement(messagesJson).jsonObject["messages"] as? JsonArray).orEmpty()
            .mapNotNull { it as? JsonObject }
        val lastUser = messages.indexOfLast { it.string("role") == "user" }
        val reply = messages.drop(lastUser + 1).filter { it.string("role") == "bot" }.mapNotNull { it.text() }
        val chosen = reply.ifEmpty { listOfNotNull(messages.lastOrNull { it.string("role") == "bot" && it.text() != null }?.text()) }
        clean(chosen.joinToString("\n"), EXCERPT_MAX, singleLine = false)
    }.getOrNull()?.takeIf { it.isNotEmpty() }

    /** Plain text for a notification: no Markdown marks, control or direction-override characters, bounded length. */
    fun clean(raw: String, max: Int, singleLine: Boolean): String {
        var text = raw
            .replace(Regex("```[^\\n]*\\n?"), "")
            .replace(Regex("!?\\[([^\\]\\n]*)\\]\\([^)\\n]*\\)"), "$1")
            .replace(Regex("(?m)^[ \\t]{0,3}(#{1,6}|>|[-*+]|\\d{1,3}[.)])[ \\t]+"), "")
            .replace(Regex("\\*\\*|__|~~|`"), "")
        text = text.filter { it == '\n' || !(it.isISOControl() || it in '‪'..'‮' || it in '⁦'..'⁩' ||
            it == '‎' || it == '‏') }
        text = if (singleLine) text.replace(Regex("\\s+"), " ")
            else text.replace(Regex("[ \\t]+"), " ").replace(Regex(" ?\\n[ \\n]*"), "\n")
        text = text.trim()
        if (text.length <= max) return text
        var cut = text.take(max - 1).trimEnd()
        if (cut.isNotEmpty() && cut.last().isHighSurrogate()) cut = cut.dropLast(1)
        return "$cut…"
    }

    private fun JsonObject.string(key: String) = (this[key] as? JsonPrimitive)?.takeIf { it.isString }?.content
    private fun JsonObject.text() = string("text")?.takeIf { it.isNotBlank() }
}
