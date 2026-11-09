package com.wangzan101.mika.core.usage

import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import org.junit.Assert.assertEquals
import org.junit.Test

class TaskUsageBudgetTest {
    @Test fun startsEmptyAndClampsEachNegativeComponent() {
        val ledger = TaskUsageBudget()
        assertEquals(0L, ledger.totalTokens)
        ledger.add(-100, 20)
        ledger.add(10, -200)
        ledger.add(Long.MIN_VALUE, Long.MIN_VALUE)
        assertEquals(30L, ledger.totalTokens)
    }

    @Test fun saturatesBothSingleReplyAndAccumulatedTotal() {
        val single = TaskUsageBudget()
        single.add(Long.MAX_VALUE, 1)
        assertEquals(Long.MAX_VALUE, single.totalTokens)
        single.add(1, 1)
        assertEquals(Long.MAX_VALUE, single.totalTokens)

        val accumulated = TaskUsageBudget()
        accumulated.add(Long.MAX_VALUE - 10, 0)
        accumulated.add(5, 6)
        assertEquals(Long.MAX_VALUE, accumulated.totalTokens)
        accumulated.add(-100, -100)
        assertEquals(Long.MAX_VALUE, accumulated.totalTokens)
    }

    @Test fun concurrentWritersDoNotLoseTokens() {
        val ledger = TaskUsageBudget()
        val pool = Executors.newFixedThreadPool(4)
        try {
            val writers = (1..8).map {
                pool.submit { repeat(1_000) { ledger.add(2, 3) } }
            }
            writers.forEach { it.get(5, TimeUnit.SECONDS) }
            assertEquals(40_000L, ledger.totalTokens)
        } finally {
            pool.shutdownNow()
        }
    }
}
