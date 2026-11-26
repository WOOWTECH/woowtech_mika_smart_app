package com.wangzan101.mika.woowbot

/** Notification payloads may name a saved service and IDs, never supply a URL or script. */
object BotWebTarget {
    fun url(service: BotService, botId: String? = null, threadId: String? = null): String {
        require(botId == null || com.wangzan101.mika.core.woowbot.push.BotPushContract.validId(botId))
        require(threadId == null || com.wangzan101.mika.core.woowbot.push.BotPushContract.validId(threadId))
        val query = listOfNotNull(threadId?.let { "thread=$it" }, botId?.let { "bot=$it" }).joinToString("&")
        return service.policy.value + "/" + if (query.isEmpty()) "" else "?$query"
    }
}
