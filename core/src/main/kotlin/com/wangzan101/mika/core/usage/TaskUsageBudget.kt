package com.wangzan101.mika.core.usage

import java.util.concurrent.atomic.AtomicLong
import kotlin.coroutines.AbstractCoroutineContextElement
import kotlin.coroutines.CoroutineContext

/**
 * Shared token ledger for a task and its child coroutines, inherited through coroutine context.
 * Metered models add successful replies once; limits and stopping decisions belong to AgentLoop.
 * Cached input and reasoning tokens are already included in input/output totals, respectively.
 */
class TaskUsageBudget : AbstractCoroutineContextElement(Key) {
    companion object Key : CoroutineContext.Key<TaskUsageBudget>

    private val tokens = AtomicLong()
    val totalTokens: Long get() = tokens.get()

    /** Negative provider counts cannot reduce usage; overflow saturates instead of wrapping. */
    internal fun add(inputTokens: Long, outputTokens: Long) {
        val amount = saturatedAdd(inputTokens.coerceAtLeast(0), outputTokens.coerceAtLeast(0))
        tokens.updateAndGet { current -> saturatedAdd(current, amount) }
    }

    private fun saturatedAdd(a: Long, b: Long): Long =
        if (a > Long.MAX_VALUE - b) Long.MAX_VALUE else a + b
}
