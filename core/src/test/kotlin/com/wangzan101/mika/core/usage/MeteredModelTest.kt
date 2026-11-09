package com.wangzan101.mika.core.usage

import com.wangzan101.mika.core.agent.TokenEstimate
import com.wangzan101.mika.core.model.Author
import com.wangzan101.mika.core.model.Capabilities
import com.wangzan101.mika.core.model.ChatModel
import com.wangzan101.mika.core.model.Message
import com.wangzan101.mika.core.model.ModelError
import com.wangzan101.mika.core.model.ModelReply
import com.wangzan101.mika.core.model.ModelRole
import com.wangzan101.mika.core.model.Part
import com.wangzan101.mika.core.model.Role
import com.wangzan101.mika.core.model.StopReason
import com.wangzan101.mika.core.model.StreamingChatModel
import com.wangzan101.mika.core.model.ToolSpec
import com.wangzan101.mika.core.model.Usage
import kotlinx.coroutines.CoroutineName
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

class MeteredModelTest {
    private val user = listOf(Message(Role.User, listOf(Part.Text("hi")), Author.User))
    private val source = UsageSource("p1", "服务商甲", "m1", UsagePurpose.of(ModelRole.Light))
    private val recorded = mutableListOf<Pair<UsageSource, Usage?>>()
    private val attempts = mutableListOf<Int>()
    private val sink = object : UsageSink {
        override fun record(s: UsageSource, u: Usage?) = record(s, u, 1)
        override fun record(s: UsageSource, u: Usage?, httpAttempts: Int) {
            recorded += s to u
            attempts += httpAttempts
        }
    }

    private class Plain(val reply: () -> ModelReply) : ChatModel {
        override val capabilities = Capabilities(toolCalls = true, vision = false, contextTokens = 64000, reasoning = false)
        override val name = "plain-model"
        override suspend fun complete(system: String, messages: List<Message>, tools: List<ToolSpec>) = reply()
    }

    private class Streaming(val reply: ModelReply) : StreamingChatModel {
        override val capabilities = Capabilities(toolCalls = true, vision = true, contextTokens = 8000, reasoning = true)
        override suspend fun complete(system: String, messages: List<Message>, tools: List<ToolSpec>) = reply
        override suspend fun completeStreaming(
            system: String, messages: List<Message>, tools: List<ToolSpec>, onText: (String) -> Unit,
        ): ModelReply {
            onText("一"); onText("一二")
            return reply
        }
    }

    private fun reply(usage: Usage?) = ModelReply(listOf(Part.Text("ok")), StopReason.EndTurn, usage)

    @Test fun recordsReportedUsageAndPassesReplyThrough() = runTest {
        val r = reply(Usage(100, 20, 60))
        val m = Plain { r }.metered(source, sink)
        assertSame(r, m.complete("s", user, emptyList()))
        assertEquals(listOf(source to Usage(100, 20, 60)), recorded)
    }

    @Test fun keepsNameAndCapabilities() {
        val inner = Plain { reply(null) }
        val m = inner.metered(source, sink)
        assertEquals("plain-model", m.name)
        assertEquals(inner.capabilities, m.capabilities)
        assertFalse("不支持逐段文字的套上后也不支持", m is StreamingChatModel)
        assertTrue("没调用就不记", recorded.isEmpty())
    }

    @Test fun nonHttpReplyDoesNotInventARequest() = runTest {
        Plain { reply(null) }.metered(source, sink).complete("s", user, emptyList())
        assertEquals(listOf<Pair<UsageSource, Usage?>>(source to null), recorded)
        assertEquals(listOf(0), attempts)
    }

    @Test fun localFailureIsRethrownWithoutAnHttpAttempt() = runTest {
        val err = ModelError.RateLimited(1000)
        val m = Plain { throw err }.metered(source, sink)
        try {
            m.complete("s", user, emptyList()); fail()
        } catch (e: ModelError.RateLimited) {
            assertSame(err, e)
        }
        assertEquals(listOf<Pair<UsageSource, Usage?>>(source to null), recorded)
        assertEquals(listOf(0), attempts)
    }

    @Test fun cancellationBeforeHttpIsRethrownWithoutAnAttempt() = runTest {
        val m = Plain { throw CancellationException("stop") }.metered(source, sink)
        try {
            m.complete("s", user, emptyList()); fail()
        } catch (e: CancellationException) {
            assertEquals("stop", e.message)
        }
        assertEquals(listOf<Pair<UsageSource, Usage?>>(source to null), recorded)
        assertEquals(listOf(0), attempts)
    }

    @Test fun streamingStaysStreamingAndForwardsText() = runTest {
        val m = Streaming(reply(Usage(5, 6))).metered(source, sink)
        assertTrue(m is StreamingChatModel)
        assertTrue(m.capabilities.vision)
        val texts = mutableListOf<String>()
        val r = (m as StreamingChatModel).completeStreaming("s", user, emptyList(), texts::add)
        assertEquals(listOf("一", "一二"), texts)
        assertEquals(Usage(5, 6), r.usage)
        assertEquals(listOf(source to Usage(5, 6)), recorded)
    }

    @Test fun brokenSinkDoesNotBreakTheCall() = runTest {
        val r = reply(Usage(1, 1))
        val m = Plain { r }.metered(source) { _, _ -> error("disk full") }
        assertSame(r, m.complete("s", user, emptyList()))
    }

    // 非 HTTP 模型仍记逻辑调用和最终用量,但不能凭空增加实际请求;不在运行上下文里的调用不算
    @Test fun callsInsideARunAreTalliedForThatRun() = runTest {
        val tally = RunUsageTally()
        val ok = Plain { reply(Usage(100, 20, 60)) }.metered(source, sink)
        val silent = Plain { reply(null) }.metered(source, sink)
        val failing = Plain { throw ModelError.RateLimited(1000) }.metered(source, sink)
        kotlinx.coroutines.withContext(tally) {
            ok.complete("s", user, emptyList())
            silent.complete("s", user, emptyList())
            runCatching { failing.complete("s", user, emptyList()) }
        }
        ok.complete("s", user, emptyList())
        val e = tally.event(7)
        assertEquals(3, e.calls)
        assertEquals(0, e.httpCalls)
        assertEquals(2, e.unreported)
        assertEquals(0, e.httpUnreported)
        assertEquals(100L, e.inputTokens)
        assertEquals(20L, e.outputTokens)
        assertEquals(60L, e.cachedTokens)
        // 总账照记每一次
        assertEquals(4, recorded.size)
    }

    @Test fun taskLedgerIsSharedByChildrenAndAcrossModelPurposes() = runTest {
        val ledger = TaskUsageBudget()
        val r = reply(Usage(100, 20, cachedInputTokens = 60, reasoningTokens = 10))
        val main = Plain { r }.metered(source.copy(purpose = UsagePurpose.Main), sink)
        val verifier = Plain { r }.metered(source.copy(purpose = UsagePurpose.Other), sink)
        withContext(ledger) {
            main.complete("s", user, emptyList())
            withContext(CoroutineName("verifier")) {
                assertSame(ledger, currentCoroutineContext()[TaskUsageBudget])
                verifier.complete("s", user, emptyList())
                launch(CoroutineName("child task")) {
                    assertSame(ledger, currentCoroutineContext()[TaskUsageBudget])
                    main.complete("s", user, emptyList())
                }
            }
        }
        // Cached/reasoning tokens are subsets, not extra charges. Outside calls do not enter this ledger.
        main.complete("s", user, emptyList())
        assertEquals(360L, ledger.totalTokens)
        assertEquals(4, recorded.size)
    }

    @Test fun nullUsageEstimatesActualRequestAndReplyOnBothPaths() = runTest {
        val ledger = TaskUsageBudget()
        val tally = RunUsageTally()
        val r = ModelReply(listOf(Part.Thinking("reasoning"), Part.Text("answer"),
            Part.ToolCall("id", "tool", "{}")), StopReason.ToolUse, null)
        val specs = listOf(ToolSpec("tool", "description", "{}"))
        val expected = TokenEstimate.of("system prompt").toLong() + TokenEstimate.of(user) +
            specs.sumOf { TokenEstimate.of(it.name + it.description + it.parametersJsonSchema).toLong() } +
            TokenEstimate.of(listOf(Message(Role.Assistant, r.parts, Author.Mika)))
        withContext(ledger + tally) {
            assertSame(r, Plain { r }.metered(source, sink).complete("system prompt", user, specs))
            assertEquals(expected, ledger.totalTokens)
            val streaming = Streaming(r).metered(source, sink) as StreamingChatModel
            assertSame(r, streaming.completeStreaming("system prompt", user, specs) {})
        }
        assertEquals(expected * 2, ledger.totalTokens)
        // Estimates are only for the task guard; persistent usage still reports missing usage as null.
        assertEquals(listOf(source to null, source to null), recorded)
        assertEquals(2, tally.event(1).unreported)
        assertEquals(0L, tally.event(1).inputTokens)
    }

    @Test fun taskLedgerIgnoresFailuresAndCancellation() = runTest {
        val ledger = TaskUsageBudget()
        withContext(ledger) {
            for (failure in listOf(ModelError.Network(), CancellationException("cancelled"))) {
                val model = Plain { throw failure }.metered(source, sink)
                try { model.complete("system", user, emptyList()); fail("Expected failure") }
                catch (caught: Exception) {
                    // Stack-trace recovery may copy exceptions thrown through withContext.
                    assertEquals(failure.javaClass, caught.javaClass)
                    assertEquals(failure.message, caught.message)
                }
            }
        }
        assertEquals(0L, ledger.totalTokens)
    }

    @Test fun reportedUsageIsClampedAndNotReplacedByAnEstimate() = runTest {
        val ledger = TaskUsageBudget()
        withContext(ledger) {
            Plain { reply(Usage(-100, 5)) }.metered(source, sink).complete("large input", user, emptyList())
            val streaming = Streaming(reply(Usage(7, -50))).metered(source, sink) as StreamingChatModel
            streaming.completeStreaming("large input", user, emptyList()) {}
            Plain { reply(Usage(0, 0)) }.metered(source, sink).complete("large input", user, emptyList())
        }
        assertEquals(12L, ledger.totalTokens)
    }

    @Test fun brokenPersistentSinkDoesNotPreventTaskAccounting() = runTest {
        val ledger = TaskUsageBudget()
        val model = Plain { reply(Usage(10, 2)) }.metered(source) { _, _ -> error("disk full") }
        withContext(ledger) { model.complete("s", user, emptyList()) }
        assertEquals(12L, ledger.totalTokens)
    }

}
