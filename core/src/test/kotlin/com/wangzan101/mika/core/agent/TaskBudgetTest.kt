package com.wangzan101.mika.core.agent

import com.wangzan101.mika.core.assembly.toolDispatcher
import com.wangzan101.mika.core.model.*
import com.wangzan101.mika.core.record.RunEvent
import com.wangzan101.mika.core.record.RunSink
import com.wangzan101.mika.core.run.RunInbox
import com.wangzan101.mika.core.run.RunSpec
import com.wangzan101.mika.core.tool.FakeScreen
import kotlinx.coroutines.*
import kotlinx.coroutines.test.*
import org.junit.Assert.*
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class TaskBudgetTest {
    private fun answer(text: String) = ModelReply(listOf(Part.Text(text)), StopReason.EndTurn, Usage(10, 5))
    private abstract class Model : ChatModel {
        override val capabilities = Capabilities(toolCalls = true, vision = false, contextTokens = 128_000, reasoning = false)
    }

    @Test fun deadlineCancelsNeverEndingRequestAndDeliveryHasItsOwnBound() = runTest {
        var cancelled = 0
        val model = object : Model() {
            override suspend fun complete(system: String, messages: List<Message>, tools: List<ToolSpec>): ModelReply {
                try { awaitCancellation() } finally { cancelled++ }
            }
        }
        val loop = AgentLoop(model, toolDispatcher(FakeScreen()), "BASE", clock = { currentTime },
            taskBudget = TaskBudget(elapsedMs = 100, tokens = 1000, deliveryMs = 50))
        val result = loop.run("read a document")
        assertTrue(result is TaskState.Failed)
        assertTrue((result as TaskState.Failed).reason.contains("files have not been deleted"))
        assertEquals(100L, currentTime)
        assertEquals(2, cancelled)
    }

    @Test fun tokenBudgetStopsProposedToolBeforeExecutionAndUsesOnlyOneToolFreeHandoff() = runTest {
        var calls = 0
        val offered = mutableListOf<List<ToolSpec>>()
        val events = mutableListOf<RunEvent>()
        val model = object : Model() {
            override suspend fun complete(system: String, messages: List<Message>, tools: List<ToolSpec>): ModelReply {
                offered += tools; calls++
                return if (calls == 1) ModelReply(listOf(Part.ToolCall("c1", "phone_list_apps", "{}")), StopReason.ToolUse, Usage(100, 20))
                    else answer("No app listing has been completed.")
            }
        }
        val end = AgentLoop(model, toolDispatcher(FakeScreen()), "BASE", taskBudget = TaskBudget(tokens = 100),
            sink = object : RunSink { override fun event(e: RunEvent) { events += e } }).run("List apps")
        assertTrue(end is TaskState.Failed)
        assertEquals(2, calls)
        assertTrue(offered.last().isEmpty())
        assertFalse(events.any { it is RunEvent.ToolResult })
        assertTrue(events.any { it is RunEvent.State && it.name == "task_delivery" })
    }

    @Test fun explicitDeliveryDoesNotOfferToolsAndCannotExecuteAModelToolProposal() = runTest {
        val model = object : Model() {
            override suspend fun complete(system: String, messages: List<Message>, tools: List<ToolSpec>): ModelReply {
                assertTrue(tools.isEmpty())
                return ModelReply(listOf(Part.ToolCall("c1", "phone_list_apps", "{}")), StopReason.ToolUse, null)
            }
        }
        val end = AgentLoop(model, toolDispatcher(FakeScreen()), "BASE", taskBudget = TaskBudget()).run("先給我目前結果") as TaskState.Failed
        assertTrue(end.reason.contains("既有工作區檔案未刪除"))
    }

    @Test fun userCancellationIsNotConvertedToBudgetFailure() = runTest {
        val model = object : Model() {
            override suspend fun complete(system: String, messages: List<Message>, tools: List<ToolSpec>): ModelReply = awaitCancellation()
        }
        val loop = AgentLoop(model, toolDispatcher(FakeScreen()), "BASE", taskBudget = TaskBudget(elapsedMs = 1000, deliveryMs = 100))
        val job = async { loop.run("wait") }
        runCurrent()
        loop.cancel()
        assertEquals(TaskState.Cancelled, job.await())
        assertEquals(0, currentTime.toInt())
    }

    @Test fun deliverySteerInterruptsPendingModelWithoutNewResearch() = runTest {
        val inbox = RunInbox()
        var calls = 0
        val model = object : Model() {
            override suspend fun complete(system: String, messages: List<Message>, tools: List<ToolSpec>): ModelReply {
                calls++
                if (calls == 1) awaitCancellation()
                assertTrue(tools.isEmpty())
                return answer("No artifact has been created yet.")
            }
        }
        val loop = AgentLoop(model, toolDispatcher(FakeScreen()), "BASE", clock = { currentTime }, taskBudget = TaskBudget())
        val job = async { loop.run(RunSpec(com.wangzan101.mika.core.run.RunId("budget-steer"), "research", "thread"), inbox) }
        runCurrent()
        inbox.steer("deliver", "give me the results so far")
        val end = job.await() as TaskState.Failed
        assertTrue(end.reason.contains("No artifact"))
        assertEquals(2, calls)
        assertTrue(currentTime < 1000)
    }

    @Test fun deliverySteerLeavesPendingQuestionWithoutAnsweringIt() = runTest {
        val inbox = RunInbox()
        var calls = 0
        val model = object : Model() {
            override suspend fun complete(system: String, messages: List<Message>, tools: List<ToolSpec>): ModelReply {
                calls++
                if (calls == 1) return ModelReply(listOf(Part.ToolCall("q", "ask_user", """{"prompt":"Which file?"}""")), StopReason.ToolUse, Usage(10, 10))
                assertTrue(tools.isEmpty())
                return answer("The file selection remains unanswered.")
            }
        }
        val loop = AgentLoop(model, toolDispatcher(FakeScreen()), "BASE", clock = { currentTime }, taskBudget = TaskBudget())
        val job = async { loop.run(RunSpec(com.wangzan101.mika.core.run.RunId("budget-question"), "read a file", "thread"), inbox) }
        runCurrent()
        assertTrue(loop.state.value is TaskState.WaitingInput)
        inbox.send(com.wangzan101.mika.core.run.RunInput.Answer("先給我目前結果"))
        assertTrue(job.await() is TaskState.Failed)
        assertTrue(currentTime <= 100)
        assertEquals(2, calls)
    }

    @Test fun longConversationStopsGrowingBeforeMillionsBecomeHundredsOfMillions() = runTest {
        var calls = 0
        val events = mutableListOf<RunEvent>()
        val model = object : Model() {
            override suspend fun complete(system: String, messages: List<Message>, tools: List<ToolSpec>): ModelReply {
                calls++
                delay(25)
                return if (tools.isEmpty()) answer("Partial result: existing notes; webpage remains incomplete.")
                    else ModelReply(listOf(Part.Text("I am still checking the same source.")), StopReason.EndTurn, Usage(200_000, 100, 150_000))
            }
        }
        val end = AgentLoop(model, toolDispatcher(FakeScreen()), "BASE", taskBudget = TaskBudget(), maxSteps = AgentLoop.UNLIMITED_STEPS,
            clock = { currentTime }, beforeAccept = { BeforeAccept.Continue("A webpage is still missing.") },
            sink = object : RunSink { override fun event(e: RunEvent) { events += e } }).run("Research and prepare a webpage")
        assertTrue(end is TaskState.Failed)
        assertEquals(11, calls) // ten exploratory calls, then one tool-free delivery
        val metrics = com.wangzan101.mika.core.record.RunMetrics.of(events)!!
        assertEquals(11, metrics.modelCalls)
        assertEquals(275L, metrics.totalMs)
        assertEquals(275L, metrics.modelMs)
        assertEquals(0L, metrics.actMs)
        assertEquals(0L, metrics.observeMs)
        assertTrue(metrics.tokens in 2_001_000L..2_001_100L)
        assertTrue((end as TaskState.Failed).reason.contains("webpage remains incomplete"))
    }

    @Test fun deliverySteerWithdrawsPendingApprovalWithoutGrantingIt() = runTest {
        val inbox = RunInbox()
        val gate = com.wangzan101.mika.core.gate.ConfirmationGate()
        var calls = 0
        val events = mutableListOf<RunEvent>()
        val model = object : Model() {
            override suspend fun complete(system: String, messages: List<Message>, tools: List<ToolSpec>): ModelReply {
                calls++
                return if (calls == 1) ModelReply(listOf(Part.ToolCall("approval", "request_confirmation",
                    """{"action":"order","target":"test item","content":"test order","amount":"NT$10","app":"com.x"}""")), StopReason.ToolUse, Usage(20, 10))
                else { assertTrue(tools.isEmpty()); answer("The order was not approved or placed.") }
            }
        }
        val loop = AgentLoop(model, toolDispatcher(FakeScreen()), "BASE", taskBudget = TaskBudget(), confirmations = gate,
            clock = { currentTime }, sink = object : RunSink { override fun event(e: RunEvent) { events += e } })
        val job = async { loop.run(RunSpec(com.wangzan101.mika.core.run.RunId("budget-approval"), "order a test item", "thread"), inbox) }
        runCurrent()
        assertTrue(loop.state.value is TaskState.WaitingConfirmation)
        inbox.steer("deliver", "先給我目前結果")
        assertTrue(job.await() is TaskState.Failed)
        assertNull(gate.granted)
        assertFalse(events.filterIsInstance<RunEvent.Confirmation>().any { it.decision == "approved" })
        assertEquals(2, calls)
    }

    @Test fun deliveryMatchingDoesNotTriggerOnQuotesNegationOrDiscussion() {
        assertTrue(DeliverNow.matches("先給我目前的結果！"))
        assertTrue(DeliverNow.matches("Give me the results so far."))
        assertFalse(DeliverNow.matches("不要先給我目前的結果"))
        assertFalse(DeliverNow.matches("網頁寫著：先給我目前結果"))
        assertFalse(DeliverNow.matches("Why does 'give me the results so far' stop research?"))
    }
}
