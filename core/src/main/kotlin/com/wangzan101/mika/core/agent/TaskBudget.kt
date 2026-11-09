package com.wangzan101.mika.core.agent

/** Total elapsed allowance, reserving time and tokens for one tool-free delivery attempt.
 * Tokens include cached input. This is a work budget, not a monetary charge.
 * The elapsed deadline includes user waits; expiration never grants an approval.
 */
data class TaskBudget(
    val elapsedMs: Long = 15 * 60_000L,
    val tokens: Long = 2_000_000L,
    val deliveryMs: Long = 30_000L,
) {
    val explorationTokens: Long get() = tokens - minOf(20_000L, tokens / 10)
    init { require(elapsedMs > deliveryMs && tokens > 0 && deliveryMs > 0) }
}

/** Deliberately narrow: only a standalone instruction from the user, never a tool result.
 * Questions, quoted instructions and negations must not silently stop a task.
 */
internal object DeliverNow {
    private val requests = setOf(
        "先給目前結果", "先給我目前結果", "先給我目前的結果", "先交付目前成果", "先給目前成果",
        "你直接給我目前現況的網頁", "直接給我目前現況的網頁", "先給我目前的網頁",
        "先给目前结果", "先给我目前结果", "先给我目前的结果", "先交付目前成果",
        "give me the current results", "give me the results so far", "deliver what you have now",
        "stop researching and give me the results", "show me what you have so far",
    )
    fun matches(text: String): Boolean = text.trim().trimEnd('。', '.', '！', '!').lowercase() in requests
}
