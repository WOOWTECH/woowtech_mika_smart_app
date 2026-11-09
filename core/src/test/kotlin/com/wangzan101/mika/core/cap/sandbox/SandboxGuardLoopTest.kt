package com.wangzan101.mika.core.cap.sandbox

import com.wangzan101.mika.core.agent.AgentLoop
import com.wangzan101.mika.core.agent.FailKind
import com.wangzan101.mika.core.agent.FakeModel
import com.wangzan101.mika.core.agent.TaskBudget
import com.wangzan101.mika.core.agent.TaskState
import com.wangzan101.mika.core.assembly.toolDispatcher
import com.wangzan101.mika.core.model.ModelReply
import com.wangzan101.mika.core.model.Part
import com.wangzan101.mika.core.model.StopReason
import com.wangzan101.mika.core.tool.FakeScreen
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class SandboxGuardLoopTest {
    @Test fun repeatedSuccessfulReadChainStopsLoopWithoutAnEighthExecution() = runTest {
        val sandbox = FakeSandbox()
        try {
            sandbox.next = {
                check(sandbox.runs.size <= 7) { "Command executed again after no-progress stop threshold" }
                CommandResult(0, false, false, sandbox.runs.size.toLong(),
                    "/workspace\n-rw-r--r-- 1 user user 12 Nov 9 12:00 report.txt\n", 0, false)
            }
            val args = buildJsonObject { put("command", "pwd; ls -lah /workspace") }
            val model = FakeModel(ModelReply(
                listOf(Part.ToolCall("read", "run_command", args.toString())), StopReason.ToolUse, null),
                repeatLast = true)
            // Exercise the opt-in task-delivery path used by the branded app.
            val result = AgentLoop(model, toolDispatcher(FakeScreen(), sandbox = sandbox), "BASE",
                taskBudget = TaskBudget())
                .run("Inspect /workspace and produce the report")

            assertTrue(result.toString(), result is TaskState.Failed)
            result as TaskState.Failed
            assertEquals(result.reason, FailKind.GaveUp, result.kind)
            assertTrue(result.reason, result.reason.contains("Repeated reads"))
            assertEquals(7, sandbox.runs.size)
            // The last reply still proposes a command, but the tool-free delivery call cannot run it.
            assertEquals(8, model.requests.size)
            assertTrue(model.offeredTools.last().isEmpty())
            // Delivery flattens evidence into text; inspect the final exploration request instead.
            val results = model.requests[6].flatMap { it.parts }.filterIsInstance<Part.ToolResult>()
                .map { Json.parseToJsonElement(it.content).jsonObject }
            val warning = results[3]["guard"]!!.jsonArray.single().jsonObject
            assertEquals("sandbox_no_progress", warning["code"]!!.jsonPrimitive.content)
            assertEquals("warn", warning["severity"]!!.jsonPrimitive.content)
        } finally {
            sandbox.root.deleteRecursively()
        }
    }
}
