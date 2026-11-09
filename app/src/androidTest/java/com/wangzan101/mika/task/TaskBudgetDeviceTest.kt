package com.wangzan101.mika.task

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.wangzan101.mika.core.agent.*
import com.wangzan101.mika.core.assembly.toolDispatcher
import com.wangzan101.mika.core.model.*
import com.wangzan101.mika.core.record.RunEvent
import com.wangzan101.mika.core.record.RunSink
import com.wangzan101.mika.core.run.*
import com.wangzan101.mika.core.uistate.*
import kotlinx.coroutines.*
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import android.os.SystemClock

/** Real Android runtime, deterministic model. No credentials, purchases, or physical phone control. */
@RunWith(AndroidJUnit4::class)
class TaskBudgetDeviceTest {
    private abstract class Model : ChatModel {
        override val capabilities = Capabilities(toolCalls = true, vision = false, contextTokens = 128_000, reasoning = false)
    }
    private fun answer(s: String) = ModelReply(listOf(Part.Text(s)), StopReason.EndTurn, Usage(10, 5))

    @Test fun elapsedDeadlineAlsoBoundsAnUnresponsiveSummary() = runBlocking {
        val model = object : Model() {
            override suspend fun complete(system: String, messages: List<Message>, tools: List<ToolSpec>): ModelReply = awaitCancellation()
        }
        val start = SystemClock.elapsedRealtime()
        val end = AgentLoop(model, toolDispatcher(BudgetScreen()), "BASE", taskBudget = TaskBudget(1500, 1000, 500)).run("Read a document")
        val elapsed = SystemClock.elapsedRealtime() - start
        assertTrue(end is TaskState.Failed)
        assertTrue("elapsed=$elapsed", elapsed < 6000)
        assertTrue((end as TaskState.Failed).reason.contains("Existing workspace files"))
    }

    @Test fun tokenLimitDoesNotExecuteProposedAction() = runBlocking {
        var calls = 0
        val events = mutableListOf<RunEvent>()
        val model = object : Model() {
            override suspend fun complete(system: String, messages: List<Message>, tools: List<ToolSpec>): ModelReply {
                calls++
                return if (calls == 1) ModelReply(listOf(Part.ToolCall("c", "phone_list_apps", "{}")), StopReason.ToolUse, Usage(100, 20))
                else { assertTrue(tools.isEmpty()); answer("No action was executed.") }
            }
        }
        val end = AgentLoop(model, toolDispatcher(BudgetScreen()), "BASE", taskBudget = TaskBudget(tokens = 100),
            sink = object : RunSink { override fun event(e: RunEvent) { events += e } }).run("List apps")
        assertTrue(end is TaskState.Failed)
        assertEquals(2, calls)
        assertFalse(events.any { it is RunEvent.ToolResult })
    }

    @Test fun deliveryDuringUserQuestionDoesNotGrantOrAnswerIt() = runBlocking {
        val inbox = RunInbox()
        var calls = 0
        val model = object : Model() {
            override suspend fun complete(system: String, messages: List<Message>, tools: List<ToolSpec>): ModelReply {
                calls++
                return if (calls == 1) ModelReply(listOf(Part.ToolCall("q", "ask_user", """{"prompt":"Which file?"}""")), StopReason.ToolUse, Usage(20, 10))
                else { assertTrue(tools.isEmpty()); answer("Selection remains unanswered.") }
            }
        }
        val loop = AgentLoop(model, toolDispatcher(BudgetScreen()), "BASE", taskBudget = TaskBudget())
        val job = async { loop.run(RunSpec(RunId("device-question"), "Read a file", "thread"), inbox) }
        withTimeout(5000) { while (loop.state.value !is TaskState.WaitingInput) delay(20) }
        inbox.steer("deliver", "give me the results so far")
        val end = withTimeout(5000) { job.await() }
        assertTrue(end is TaskState.Failed)
        assertEquals(2, calls)
    }

    @Test fun brandPackageAndSharedFileSurviveToolFreeDelivery() = runBlocking {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        assertTrue(context.packageName in setOf("com.apporo.assistant", "io.woowtech.agent", "com.wangzan101.mika"))
        val file = java.io.File(context.cacheDir, "budget-existing-result.html")
        file.writeText("<h1>Existing result</h1>")
        try {
            val model = object : Model() {
                override suspend fun complete(system: String, messages: List<Message>, tools: List<ToolSpec>): ModelReply {
                    assertTrue(tools.isEmpty())
                    return answer("No additional work performed.")
                }
            }
            assertTrue(AgentLoop(model, toolDispatcher(BudgetScreen()), "BASE", taskBudget = TaskBudget()).run("先給我目前結果") is TaskState.Failed)
            assertEquals("<h1>Existing result</h1>", file.readText())
        } finally { file.delete() }
    }
}

private class BudgetScreen : ScreenPort {
    override suspend fun snapshot() = ScreenSnapshot("s", "test", emptyList(), 100, 100)
    override suspend fun peek() = snapshot()
    override suspend fun screenshotPng(): ByteArray? = null
    override suspend fun tapRef(ref: String, snapshotId: String): ActionResult = error("Unexpected action")
    override suspend fun tapXY(x: Int, y: Int): ActionResult = error("Unexpected action")
    override suspend fun typeText(ref: String?, snapshotId: String?, text: String): ActionResult = error("Unexpected action")
    override suspend fun clearText(ref: String?, snapshotId: String?): ActionResult = error("Unexpected action")
    override suspend fun scroll(ref: String?, snapshotId: String?, down: Boolean): ActionResult = error("Unexpected action")
    override suspend fun swipe(x1: Int, y1: Int, x2: Int, y2: Int, durationMs: Long): ActionResult = error("Unexpected action")
    override suspend fun back(): ActionResult = error("Unexpected action")
    override suspend fun pressKey(keyCode: Int): ActionResult = error("Unexpected action")
    override suspend fun openApp(packageName: String, cold: Boolean): ActionResult = error("Unexpected action")
    override suspend fun waitStable(timeoutMs: Long) = true
    override suspend fun listApps(): List<Pair<String, String>> = error("Budget must stop tool execution")
}
