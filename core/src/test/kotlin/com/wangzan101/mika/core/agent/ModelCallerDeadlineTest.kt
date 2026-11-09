package com.wangzan101.mika.core.agent

import com.wangzan101.mika.core.assembly.toolDispatcher
import com.wangzan101.mika.core.model.Author
import com.wangzan101.mika.core.model.Part
import com.wangzan101.mika.core.model.Role
import com.wangzan101.mika.core.model.Usage
import com.wangzan101.mika.core.model.Capabilities
import com.wangzan101.mika.core.model.ChatModel
import com.wangzan101.mika.core.model.Message
import com.wangzan101.mika.core.model.ModelError
import com.wangzan101.mika.core.model.ModelReply
import com.wangzan101.mika.core.model.StreamingChatModel
import com.wangzan101.mika.core.model.ToolSpec
import com.wangzan101.mika.core.record.RunEvent
import com.wangzan101.mika.core.testing.answerReply
import com.wangzan101.mika.core.tool.FakeScreen
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.withTimeout
import org.junit.Assert.*
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class ModelCallerDeadlineTest {
    private class Model(private val respond: suspend (Int) -> ModelReply) : ChatModel {
        override val capabilities = Capabilities(true, false, 128_000, false)
        var calls = 0
        override suspend fun complete(system: String, messages: List<Message>, tools: List<ToolSpec>): ModelReply =
            respond(++calls)
    }

    private fun TestScope.caller(
        model: ChatModel,
        budgetMs: Long = 1_000,
        events: MutableList<RunEvent> = mutableListOf(),
        retry: RetryPolicy = RetryPolicy(maxRetries = 100, baseMs = 200, jitter = { 1.0 }),
        light: ChatModel? = null,
        usage: (ModelReply, Int) -> Unit = { _, _ -> },
        mayResearch: () -> Boolean = { true },
    ) = ModelCaller(
        model, toolDispatcher(FakeScreen()), light?.let { ModelRouter(model, it) },
        SpeedFlags(lightSteps = light != null), retry, { events.add(it) }, { testScheduler.currentTime },
        callBudgetMs = budgetMs, onReplyUsage = usage, mayResearch = mayResearch,
    )

    private suspend fun deadline(block: suspend () -> Unit): ModelCallDeadlineExceeded {
        try {
            block()
        } catch (e: ModelCallDeadlineExceeded) {
            return e
        }
        error("Expected model call deadline")
    }

    private fun lightTrack() = StepTrack().apply {
        repeat(2) { after(null, true, false, null, false, "same.app") }
    }

    @Test fun slowFirstResponseTimesOutWithoutRetryOrUsage() = runTest {
        var cancelled = false
        val model = Model {
            try { delay(10_000); answerReply("too late") } finally { cancelled = true }
        }
        val events = mutableListOf<RunEvent>()
        var replies = 0
        val caller = caller(model, events = events, usage = { _, _ -> replies++ })
        val error = deadline { caller.ask(emptyList(), emptyList(), 1) }
        assertEquals(1_000L, testScheduler.currentTime)
        assertEquals(1_000L, error.budgetMs)
        assertEquals(1, model.calls)
        assertEquals(0, replies)
        assertTrue(cancelled)
        assertFalse(RetryPolicy.transient(error))
        assertNull(RetryPolicy().delayFor(error, 0))
        assertEquals("call_deadline", RetryPolicy.label(error))
        assertEquals(FailKind.Model, StopRules.modelFailed(error).kind)
        assertEquals(error.message, StopRules.modelFailed(error).reason)
        assertEquals(listOf("model_retry_stopped"), events.filterIsInstance<RunEvent.State>().map { it.name })
        assertEquals("call_deadline 1000ms", events.filterIsInstance<RunEvent.State>().single().detail)
    }

    @Test fun neverEndingStreamIsBoundedEvenWhileTextKeepsArriving() = runTest {
        var cancelled = false
        var chunks = 0
        val model = object : StreamingChatModel {
            override val capabilities = Capabilities(true, false, 128_000, false)
            override suspend fun complete(system: String, messages: List<Message>, tools: List<ToolSpec>): ModelReply =
                error("Must use streaming")
            override suspend fun completeStreaming(
                system: String, messages: List<Message>, tools: List<ToolSpec>, onText: (String) -> Unit,
            ): ModelReply {
                try {
                    while (true) { delay(100); onText("partial") }
                } finally { cancelled = true }
            }
        }
        deadline { caller(model).ask(emptyList(), emptyList(), 1, onText = { chunks++ }) }
        assertEquals(1_000L, testScheduler.currentTime)
        assertTrue(chunks > 0)
        assertTrue(cancelled)
    }

    @Test fun attemptsAndBackoffConsumeOneBudget() = runTest {
        val events = mutableListOf<RunEvent>()
        val model = Model { delay(300); throw ModelError.Network() }
        deadline { caller(model, events = events).ask(emptyList(), emptyList(), 1) }
        // Attempt 1: 0..300, backoff: 300..500, attempt 2: 500..800, backoff cut at 1000.
        assertEquals(1_000L, testScheduler.currentTime)
        assertEquals(2, model.calls)
        val states = events.filterIsInstance<RunEvent.State>()
        assertEquals(listOf("model_retry", "model_retry", "model_retry_stopped"), states.map { it.name })
        assertEquals("main network #1 200ms", states[0].detail)
        assertEquals("main network #2 400ms", states[1].detail)
    }

    @Test fun longRetryAfterIsInterruptedByDeadline() = runTest {
        val model = Model { throw ModelError.RateLimited(30_000) }
        deadline { caller(model).ask(emptyList(), emptyList(), 1) }
        assertEquals(1_000L, testScheduler.currentTime)
        assertEquals(1, model.calls)
    }

    @Test fun parentCancellationRemainsCancellationDuringResponseAndRetryWait() = runTest {
        for (waitingToRetry in listOf(false, true)) {
            val events = mutableListOf<RunEvent>()
            val model = Model {
                if (waitingToRetry) throw ModelError.RateLimited(30_000)
                awaitCancellation()
            }
            val caller = caller(model, events = events)
            val cause = CancellationException("parent stopped")
            var observed: Throwable? = null
            val job = launch {
                try { caller.ask(emptyList(), emptyList(), 1) }
                catch (e: Throwable) { observed = e }
            }
            runCurrent()
            advanceTimeBy(100)
            job.cancel(cause)
            job.join()
            // Coroutine stack-trace recovery may copy the exception across a suspension boundary.
            assertEquals(cause.javaClass, observed?.javaClass)
            assertEquals(cause.message, observed?.message)
            assertTrue(job.isCancelled)
            assertFalse(events.filterIsInstance<RunEvent.State>().any { it.name == "model_retry_stopped" })
            assertEquals(1, model.calls)
        }
    }

    @Test fun parentTimeoutIsNotReclassifiedAsModelDeadline() = runTest {
        val events = mutableListOf<RunEvent>()
        val model = Model { awaitCancellation() }
        try {
            withTimeout(100) { caller(model, events = events).ask(emptyList(), emptyList(), 1) }
            fail("Expected parent timeout")
        } catch (_: TimeoutCancellationException) {
            assertEquals(100L, testScheduler.currentTime)
        }
        assertTrue(events.isEmpty())
    }

    @Test fun successfulReplyCountsOnceAfterRetriesAndEachCallGetsFreshBudget() = runTest {
        val expected = answerReply("done")
        val model = Model { call ->
            delay(100)
            if (call == 1) throw ModelError.Network()
            expected
        }
        val recorded = mutableListOf<Pair<ModelReply, Int>>()
        val caller = caller(model, usage = { reply, estimate -> recorded += reply to estimate })
        caller.reset("system prompt")
        assertSame(expected, caller.ask(emptyList(), emptyList(), 1))
        delay(2_000)
        assertSame(expected, caller.ask(emptyList(), emptyList(), 2))
        assertEquals(3, model.calls)
        assertEquals(2, recorded.size)
        assertTrue(recorded.all { it.first === expected && it.second == TokenEstimate.of("system prompt") })
    }

    @Test fun rejectedLightReplyAndMainReplyBothCountUsage() = runTest {
        val lightReply = answerReply("light answer cannot finish task")
        val mainReply = answerReply("main answer")
        val light = Model { delay(200); lightReply }
        val main = Model { delay(300); mainReply }
        val recorded = mutableListOf<ModelReply>()
        val caller = caller(main, light = light, usage = { reply, _ -> recorded += reply })
        val (reply, used) = caller.routed(emptyList(), emptyList(), lightTrack(), 3, {})
        assertSame(mainReply, reply)
        assertSame(main, used)
        assertEquals(listOf(lightReply, mainReply), recorded)
        assertEquals(500L, testScheduler.currentTime)
    }

    @Test fun fallbackSharesRemainingDeadlineAndRetainsSuccessfulLightUsage() = runTest {
        val lightReply = answerReply("rejected light answer")
        val light = Model { delay(700); lightReply }
        val main = Model { delay(700); answerReply("too late") }
        val recorded = mutableListOf<ModelReply>()
        val caller = caller(main, light = light, usage = { reply, _ -> recorded += reply })
        deadline { caller.routed(emptyList(), emptyList(), lightTrack(), 3, {}) }
        assertEquals(1_000L, testScheduler.currentTime)
        assertEquals(1, main.calls)
        assertEquals(listOf(lightReply), recorded)
    }

    @Test fun deadlineDuringLightCallDoesNotFallBack() = runTest {
        val light = Model { awaitCancellation() }
        val main = Model { answerReply("must not run") }
        deadline { caller(main, light = light).routed(emptyList(), emptyList(), lightTrack(), 3, {}) }
        assertEquals(1, light.calls)
        assertEquals(0, main.calls)
        assertEquals(1_000L, testScheduler.currentTime)
    }

    @Test fun usageCallbackIncludesWholeInputAndPreservesProviderUsage() = runTest {
        val reply = answerReply("output").copy(usage = Usage(500, 40, 100, 20))
        val history = listOf(Message(Role.User, listOf(Part.Text("user request")), Author.User))
        val specs = listOf(ToolSpec("tool", "tool description", "{}"))
        val recorded = mutableListOf<Pair<ModelReply, Int>>()
        val caller = caller(Model { reply }, usage = { result, estimate -> recorded += result to estimate })
        caller.reset("system prompt")
        caller.ask(history, specs, 1)
        val expected = TokenEstimate.of(history) + TokenEstimate.of("system prompt") +
            specs.sumOf { TokenEstimate.of(it.name + it.description + it.parametersJsonSchema) }
        assertEquals(listOf(reply to expected), recorded)
        assertSame(reply, recorded.single().first)
    }

    @Test fun explicitProductBudgetIsThreeMinutes() = runTest {
        val model = Model { awaitCancellation() }
        val caller = ModelCaller(model, toolDispatcher(FakeScreen()), null, SpeedFlags.OFF,
            RetryPolicy.NONE, {}, { testScheduler.currentTime }, callBudgetMs = 180_000)
        val error = deadline { caller.ask(emptyList(), emptyList(), 1) }
        assertEquals(180_000L, error.budgetMs)
        assertEquals(180_000L, testScheduler.currentTime)
    }

    @Test fun defaultHasNoDeadlineForLegacyEmbedding() = runTest {
        val reply = answerReply("legacy reply")
        val model = Model { delay(180_001); reply }
        val events = mutableListOf<RunEvent>()
        val caller = ModelCaller(model, toolDispatcher(FakeScreen()), null, SpeedFlags.OFF,
            RetryPolicy.NONE, { events.add(it) }, { testScheduler.currentTime })
        assertSame(reply, caller.ask(emptyList(), emptyList(), 1))
        assertEquals(180_001L, testScheduler.currentTime)
        assertSame(reply, caller.routed(emptyList(), emptyList(), lightTrack(), 3, {}).first)
        assertEquals(360_002L, testScheduler.currentTime)
        assertFalse(events.filterIsInstance<RunEvent.State>().any { it.name == "model_retry_stopped" })
    }

    private suspend fun workBudgetExceeded(block: suspend () -> Unit) {
        try { block(); fail("Expected exhausted work budget") }
        catch (_: TaskWorkBudgetExceeded) { }
    }

    @Test fun successfulLightReplyExhaustsBudgetBeforeMainFallback() = runTest {
        var allowed = true
        val light = Model { answerReply("light answer") }
        val main = Model { answerReply("must not run") }
        var replies = 0
        val caller = caller(main, light = light, mayResearch = { allowed }, usage = { _, _ ->
            replies++
            allowed = false
        })
        workBudgetExceeded { caller.routed(emptyList(), emptyList(), lightTrack(), 3, {}) }
        assertEquals(1, light.calls)
        assertEquals(0, main.calls)
        assertEquals(1, replies)
    }

    @Test fun exhaustedBudgetBeforeLightAttemptPropagatesWithoutFallback() = runTest {
        val light = Model { answerReply("must not run") }
        val main = Model { answerReply("must not run") }
        var checks = 0
        val caller = caller(main, light = light, mayResearch = { checks++; false })
        workBudgetExceeded { caller.routed(emptyList(), emptyList(), lightTrack(), 3, {}) }
        assertEquals(0, light.calls)
        assertEquals(0, main.calls)
        assertEquals(1, checks)
    }

    @Test fun exhaustedBudgetAfterFailureDoesNotScheduleRetry() = runTest {
        var allowed = true
        val events = mutableListOf<RunEvent>()
        val model = Model { allowed = false; throw ModelError.Network() }
        val caller = caller(model, events = events, mayResearch = { allowed })
        workBudgetExceeded { caller.ask(emptyList(), emptyList(), 1) }
        assertEquals(1, model.calls)
        assertEquals(0L, testScheduler.currentTime)
        assertFalse(events.filterIsInstance<RunEvent.State>().any { it.name == "model_retry" })
    }

    @Test fun budgetExhaustedDuringRetryWaitPreventsNextRequest() = runTest {
        var allowed = true
        val model = Model { throw ModelError.Network() }
        val caller = caller(model, mayResearch = { allowed })
        launch { delay(100); allowed = false }
        workBudgetExceeded { caller.ask(emptyList(), emptyList(), 1) }
        assertEquals(1, model.calls)
        assertEquals(200L, testScheduler.currentTime)
    }

    @Test fun budgetMustBePositive() = runTest {
        for (budget in listOf(0L, -1L)) {
            try { caller(Model { answerReply("unused") }, budgetMs = budget); fail("Invalid budget") }
            catch (_: IllegalArgumentException) { }
        }
    }
}
