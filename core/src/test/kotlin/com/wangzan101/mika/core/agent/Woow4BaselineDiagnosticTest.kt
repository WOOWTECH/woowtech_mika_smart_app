package com.wangzan101.mika.core.agent

import com.wangzan101.mika.core.assembly.toolDispatcher
import com.wangzan101.mika.core.cap.sandbox.CommandResult
import com.wangzan101.mika.core.cap.sandbox.FakeSandbox
import com.wangzan101.mika.core.model.ModelReply
import com.wangzan101.mika.core.model.Part
import com.wangzan101.mika.core.model.StopReason
import com.wangzan101.mika.core.model.ChatModel
import com.wangzan101.mika.core.model.Capabilities
import com.wangzan101.mika.core.model.Message
import com.wangzan101.mika.core.model.ToolSpec
import com.wangzan101.mika.core.model.ModelError
import com.wangzan101.mika.core.model.Usage
import com.wangzan101.mika.core.tool.FakeScreen
import kotlinx.coroutines.delay
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.currentTime
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Diagnostic against the unmodified published woow.4 source; not a product fix. */
class Woow4BaselineDiagnosticTest {
    @Test fun successfulIdenticalReadsContinueUntilStepLimit() = runTest {
        val sandbox = FakeSandbox()
        sandbox.next = { CommandResult(0, false, false, 10, "same file content", 0, false) }
        val model = FakeModel(
            ModelReply(listOf(Part.ToolCall("read", "run_command", """{"command":"cat /workspace/a.txt"}""")), StopReason.ToolUse, null),
            repeatLast = true,
        )
        val end = AgentLoop(model, toolDispatcher(FakeScreen(), sandbox = sandbox), "BASE", maxSteps = 8)
            .run("Read the file and summarize it")
        assertTrue(end.toString(), end is TaskState.Failed)
        assertEquals(FailKind.StepLimit, (end as TaskState.Failed).kind)
        assertEquals(8, sandbox.runs.size)
    }

    @Test fun longModelWaitHasNoTaskDeadline() = runTest {
        val model = object : ChatModel {
            override val capabilities = Capabilities(toolCalls = true, vision = false, contextTokens = 128_000, reasoning = false)
            override suspend fun complete(system: String, messages: List<Message>, tools: List<ToolSpec>): ModelReply {
                delay(16 * 60_000L)
                return ModelReply(listOf(Part.Text("Done")), StopReason.EndTurn, null)
            }
        }
        val end = AgentLoop(model, toolDispatcher(FakeScreen()), "BASE").run("Answer")
        assertTrue(end.toString(), end is TaskState.Succeeded)
        assertTrue(currentTime >= 16 * 60_000L)
    }

    @Test fun initialDeliverNowRequestCanStillExecuteARead() = runTest {
        val sandbox = FakeSandbox()
        sandbox.next = { CommandResult(0, false, false, 10, "old data", 0, false) }
        val model = FakeModel(ModelReply(listOf(Part.ToolCall("read", "run_command", """{"command":"cat /workspace/a.txt"}""")), StopReason.ToolUse, null),
            ModelReply(listOf(Part.Text("Result")), StopReason.EndTurn, null))
        AgentLoop(model, toolDispatcher(FakeScreen(), sandbox = sandbox), "BASE").run("先給我目前結果")
        assertEquals(1, sandbox.runs.size)
    }

    @Test fun retryDeadlineCountsWaitOnly() = runTest {
        var calls = 0
        val model = object : ChatModel {
            override val capabilities = Capabilities(toolCalls = true, vision = false, contextTokens = 128_000, reasoning = false)
            override suspend fun complete(system: String, messages: List<Message>, tools: List<ToolSpec>): ModelReply {
                calls++
                delay(90_000)
                throw ModelError.Network(java.io.IOException("simulated timeout"))
            }
        }
        val end = AgentLoop(model, toolDispatcher(FakeScreen()), "BASE", retry = RetryPolicy(maxRetries = 3,
            baseMs = 1000, maxBackoffMs = 8000, jitter = { 0.0 })).run("Answer")
        assertTrue(end.toString(), end is TaskState.Failed)
        assertEquals(4, calls)
        assertTrue(currentTime > 4 * 90_000L)
    }

    @Test fun tokenUsageDoesNotStopNextRead() = runTest {
        val sandbox = FakeSandbox()
        sandbox.next = { CommandResult(0, false, false, 10, "same", 0, false) }
        val read = ModelReply(listOf(Part.ToolCall("read", "run_command", """{"command":"cat /workspace/a.txt"}""")),
            StopReason.ToolUse, Usage(1_200_000, 100))
        val model = FakeModel(read, read, ModelReply(listOf(Part.Text("Result")), StopReason.EndTurn, null))
        AgentLoop(model, toolDispatcher(FakeScreen(), sandbox = sandbox), "BASE").run("Read and answer")
        assertEquals(2, sandbox.runs.size)
    }
}
