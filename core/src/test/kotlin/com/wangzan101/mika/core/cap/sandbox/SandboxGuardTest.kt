package com.wangzan101.mika.core.cap.sandbox

import com.wangzan101.mika.core.guard.Severity
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class SandboxGuardTest {
    private fun command(command: String = "ls /workspace") = buildJsonObject { put("command", command) }
    private fun output(text: String = "report.txt\n", duration: Long = 1) = buildJsonObject {
        put("ok", true); put("exitCode", 0); put("output", text)
        put("durationMs", duration); put("outputTruncated", false)
    }
    private fun file(path: String = "report.txt", offset: Int = 0) = buildJsonObject {
        put("path", path); put("offset", offset)
    }
    private fun fileContent(text: String = "report", offset: Int = 0) = buildJsonObject {
        put("ok", true); put("path", "/workspace/report.txt"); put("content", text)
        put("offset", offset); put("size", 100); put("eof", false); put("nextOffset", offset + text.length)
    }
    private fun SandboxGuard.read(args: JsonObject = command(), result: JsonObject = output()) =
        this.result("run_command", args, result)

    @Test fun identicalSuccessfulReadsWarnBeforeStoppingDespiteVariableDurations() {
        val guard = SandboxGuard()
        repeat(3) { assertTrue(guard.read(result = output(duration = it.toLong())).isEmpty()) }
        val warning = guard.read(result = output(duration = 44)).single()
        assertEquals("sandbox_no_progress", warning.code)
        assertEquals(Severity.Warn, warning.severity)
        assertNotNull(warning.nudge)
        assertNull(guard.stop)
        repeat(2) { assertEquals(Severity.Warn, guard.read().single().severity) }
        val stop = guard.read().single()
        assertEquals(Severity.Stop, stop.severity)
        assertEquals(stop, guard.stop)
        assertTrue(stop.evidence["hint"]!!.jsonPrimitive.content.contains("end_not_done"))
        assertTrue(stop.evidence.toString().contains("report.txt").not())
    }

    @Test fun alternatingPreviouslySeenReadsAlsoStop() {
        val guard = SandboxGuard()
        repeat(8) {
            val name = if (it % 2 == 0) "a.txt" else "b.txt"
            guard.read(command("cat $name"), output(name))
        }
        assertEquals("sandbox_no_progress", guard.stop?.code)
    }

    @Test fun genuinelyChangingOutputNeverStops() {
        val guard = SandboxGuard()
        repeat(30) { assertTrue(guard.read(result = output("row $it")).isEmpty()) }
        assertNull(guard.stop)
    }

    @Test fun listingTimestampsAreEvidenceNotNoiseToStrip() {
        val guard = SandboxGuard()
        repeat(20) {
            assertTrue(guard.read(command("ls -l /workspace"),
                output("-rw-r--r-- 1 user user 12 Nov 9 12:${it.toString().padStart(2, '0')} result.txt\n")).isEmpty())
        }
        assertNull(guard.stop)
    }

    @Test fun changedOutputResetsEvenAnAlreadyWarnedStreak() {
        val guard = SandboxGuard()
        repeat(4) { guard.read() }
        assertTrue(guard.read(result = output("new.txt")).isEmpty())
        repeat(3) { assertTrue(guard.read().isEmpty()) }
        assertNull(guard.stop)
    }

    @Test fun uncertainShellCommandsAndPollingDoNotAccumulateEvidence() {
        for (cmd in listOf("echo done", "python3 build.py", "touch report.txt", "cat a > b",
            "ls; touch b", "ls && echo ok", "ls $(touch b)", "ls `touch b`", "ls\ntouch b",
            "find . -exec touch {} +", "tail -f progress.txt", "sleep 1", "watch ls",
            "cat /proc/uptime", "cat /workspace/status.json", "ls /workspace/logs")) {
            val guard = SandboxGuard()
            repeat(12) { assertTrue(cmd, guard.read(command(cmd)).isEmpty()) }
            assertNull(cmd, guard.stop)
        }
    }

    @Test fun pureReadChainsWarnAndStopIncludingScreenshotCommand() {
        for (cmd in listOf("pwd; ls -lah /workspace", "pwd&&ls -lah /workspace",
            "pwd && ls /workspace; head -n 5 report.txt && wc -l report.txt",
            "\tpwd ;\tls -lah /workspace\t")) {
            val guard = SandboxGuard()
            repeat(3) { assertTrue(cmd, guard.read(command(cmd)).isEmpty()) }
            assertEquals(cmd, Severity.Warn, guard.read(command(cmd)).single().severity)
            assertNull(cmd, guard.stop)
            repeat(3) { guard.read(command(cmd)) }
            assertEquals(cmd, "sandbox_no_progress", guard.stop?.code)
        }
    }

    @Test fun chainsRejectWritesPollingAndAllOtherShellSyntax() {
        for (cmd in listOf("pwd; touch report.txt; ls", "pwd && rm report.txt && ls",
            "pwd; ls | cat", "pwd && ls > report.txt", "pwd; cat < report.txt",
            "pwd; ls 2>&1", "pwd; ls $(pwd)", "pwd && ls `pwd`", "pwd; cat <(ls)",
            "pwd || ls", "pwd & ls", "pwd &&& ls", "pwd;;ls", ";pwd", "pwd;",
            "pwd &&", "pwd && ; ls", "pwd;\nls", "pwd\n", "pwd; ls # comment",
            "pwd; 'ls'", "pwd; cat \"report.txt\"", "pwd; ls \\; touch report.txt",
            "pwd; sleep 1; ls", "pwd && cat /workspace/status.json", "pwd; ls /proc")) {
            val guard = SandboxGuard()
            repeat(8) { assertTrue(cmd, guard.read(command(cmd)).isEmpty()) }
            assertNull(cmd, guard.stop)
        }
    }

    @Test fun readChainsStillRequireIdenticalOutputToStop() {
        val guard = SandboxGuard()
        repeat(20) {
            assertTrue(guard.read(command("pwd; ls -lah /workspace"), output("/workspace\nfile$it.txt")).isEmpty())
        }
        assertNull(guard.stop)
    }

    @Test fun writesScriptsAndWaitsBreakAReadStreak() {
        val operations = listOf(
            "write_file" to buildJsonObject { put("path", "a"); put("content", "new") },
            "run_bundled_script" to buildJsonObject { put("script", "build.py") },
            "run_command" to command("python3 build.py"),
            "run_command" to command("sleep 1"),
            "wait" to buildJsonObject { put("seconds", 1) },
        )
        for ((tool, args) in operations) {
            val guard = SandboxGuard()
            repeat(4) { guard.read() }
            assertTrue(guard.result(tool, args, output()).isEmpty())
            repeat(3) { assertTrue(tool, guard.read().isEmpty()) }
            assertNull(guard.stop)
        }
    }

    @Test fun clippedOrDroppedOutputCannotProveNoProgress() {
        for (flag in listOf("outputTruncated", "truncated", "droppedBytes")) {
            val guard = SandboxGuard()
            val result = JsonObject(output() + (flag to if (flag == "droppedBytes") JsonPrimitive(1) else JsonPrimitive(true)))
            repeat(12) { assertTrue(guard.read(result = result).isEmpty()) }
            assertNull(guard.stop)
        }
    }

    @Test fun fileReadsCountButNewRangesAndContentAreProgress() {
        val guard = SandboxGuard()
        repeat(20) {
            assertTrue(guard.result("read_file", file(offset = it * 6), fileContent(offset = it * 6)).isEmpty())
        }
        repeat(20) {
            assertTrue(guard.result("read_file", file(), fileContent("value $it")).isEmpty())
        }
        repeat(7) { guard.result("read_file", file(), fileContent()) }
        assertEquals("sandbox_no_progress", guard.stop?.code)
        // Native file reads do not spend the command runtime budget.
        assertNull(guard.exhausted("run_command"))
    }

    @Test fun imageMetadataAndPollingFilesAreNotContentEvidence() {
        val image = buildJsonObject { put("ok", true); put("path", "/workspace/a.png"); put("size", 10) }
        val guard = SandboxGuard()
        repeat(12) { assertTrue(guard.result("read_file", file("a.png"), image).isEmpty()) }
        repeat(12) { assertTrue(guard.result("read_file", file("progress.json"), fileContent()).isEmpty()) }
        assertNull(guard.stop)
    }

    @Test fun fingerprintsAreEvictedAfterSixteenDistinctReads() {
        val guard = SandboxGuard()
        // Every revisit has fallen out of the window; an unbounded history would warn and stop.
        repeat(4) {
            repeat(17) { n -> assertTrue(guard.read(command("cat file$n"), output("$n")).isEmpty()) }
        }
        assertNull(guard.stop)
    }

    @Test fun timeoutChangesAndArgumentOrderCannotHideIdenticalReads() {
        val guard = SandboxGuard()
        repeat(7) {
            val args = if (it % 2 == 0) buildJsonObject {
                put("command", "ls /workspace"); put("cwd", "/workspace"); put("timeoutSec", it + 1)
            } else buildJsonObject {
                put("timeoutSec", it + 1); put("cwd", "/workspace"); put("command", "ls /workspace")
            }
            guard.read(args)
        }
        assertEquals("sandbox_no_progress", guard.stop?.code)
    }

    @Test fun completeSearchResultsCountButTruncatedSearchesDoNot() {
        val args = buildJsonObject { put("pattern", "invoice") }
        val complete = buildJsonObject {
            put("ok", true); put("matches", JsonArray(emptyList())); put("truncated", false)
        }
        val guard = SandboxGuard()
        repeat(7) { guard.result("search_files", args, complete) }
        assertEquals("sandbox_no_progress", guard.stop?.code)
        val partialGuard = SandboxGuard()
        repeat(12) {
            assertTrue(partialGuard.result("search_files", args,
                JsonObject(complete + ("truncated" to JsonPrimitive(true)))).isEmpty())
        }
        assertNull(partialGuard.stop)
    }

    @Test fun unknownSuccessAndMissingOutputAreNotEvidence() {
        val guard = SandboxGuard()
        repeat(12) {
            assertTrue(guard.read(result = buildJsonObject { put("output", "same") }).isEmpty())
            assertTrue(guard.read(result = buildJsonObject { put("ok", true) }).isEmpty())
        }
        assertNull(guard.stop)
    }

    @Test fun failureGuardStillWarnsAtThreeAndStopsAtFive() {
        val guard = SandboxGuard()
        val failed = buildJsonObject { put("ok", false); put("output", "missing"); put("durationMs", 1) }
        repeat(2) { assertTrue(guard.read(result = failed).isEmpty()) }
        assertEquals(Severity.Warn, guard.read(result = failed).single().severity)
        guard.read(result = failed)
        val stop = guard.read(result = failed).single()
        assertEquals("sandbox_loop", stop.code)
        assertEquals(Severity.Stop, stop.severity)
        assertEquals(stop, guard.stop)
    }

    @Test fun successResetsFailureStreakAndFailuresResetReadEvidence() {
        val guard = SandboxGuard()
        val failed = buildJsonObject { put("ok", false) }
        repeat(2) { guard.read(result = failed) }
        assertTrue(guard.read().isEmpty())
        repeat(2) { assertTrue(guard.read(result = failed).isEmpty()) }
        repeat(3) { assertTrue(guard.read().isEmpty()) }
        assertNull(guard.stop)
    }

    @Test fun runtimeBudgetStillIncludesSuccessfulReads() {
        val guard = SandboxGuard(budgetMs = 100)
        guard.read(result = output(duration = 100))
        assertEquals("sandbox_budget_exhausted", guard.exhausted("run_command")?.get("error")?.jsonPrimitive?.content)
        assertNull(guard.exhausted("read_file"))
    }
}
