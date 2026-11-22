package com.wangzan101.mika.ui

import com.wangzan101.mika.core.record.RunEvent
import com.wangzan101.mika.i18n.EnglishTexts
import com.wangzan101.mika.i18n.ResFileTexts
import com.wangzan101.mika.i18n.UiText
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

/** UI projection contracts only: no core diagnostic type, network, device, or credentials. */
class RunTimelineMcpDiagnosticTest {
    @get:Rule val texts = EnglishTexts()

    private fun event(json: String, changed: Boolean? = null, tool: String = "mcp_fixture__inspect") =
        RunEvent.ToolResult(0L, 1, tool, json, changed, null)

    private fun row(json: String, changed: Boolean? = null, tool: String = "mcp_fixture__inspect") =
        RunTimelineViewModel.steps(listOf(event(json, changed, tool))).single()

    private fun result(category: String, unknown: Boolean, code: Int? = null, ok: Boolean = false): String =
        buildJsonObject {
            put("ok", ok)
            put("diagnostic", buildJsonObject {
                put("category", category)
                code?.let { put("code", it) }
                put("outcomeUnknown", unknown)
            })
            put("executionWarning", "UNTRUSTED_WARNING_CANARY")
            put("text", "UNTRUSTED_TEXT_CANARY")
            put("error", buildJsonObject { put("message", "UNTRUSTED_ERROR_CANARY") })
        }.toString()

    @Test fun http503ShowsSafeClassificationCodeAndUnknownWarning() {
        val s = row(result("http", unknown = true, code = 503), changed = true)
        assertEquals("Error: Server request failed", s.result)
        assertEquals(listOf(Tag("Code 503", TagTone.Bad),
            Tag("Outcome unconfirmed; check first", TagTone.Warn)), s.tags)
        assertFalse(s.toString().contains("UNTRUSTED_"))
    }

    @Test fun rpcErrorWithKnownOutcomeStaysAnErrorWithoutUnknownWarning() {
        val s = row(result("rpc", unknown = false, code = -32602), changed = true)
        assertEquals("Error: Server response error", s.result)
        assertEquals(listOf(Tag("Code -32602", TagTone.Bad)), s.tags)
        assertFalse(s.toString().contains("rollback", ignoreCase = true))
    }

    @Test fun rpcInternalAndServerErrorsKeepCodeAndUnknownWithoutClaimingRejection() {
        for (code in listOf(-32000, -32603)) {
            val s = row(result("rpc", unknown = true, code = code), changed = true)
            assertEquals("Error: Server response error", s.result)
            assertEquals(listOf(Tag("Code $code", TagTone.Bad),
                Tag("Outcome unconfirmed; check first", TagTone.Warn)), s.tags)
            assertFalse(s.toString().contains("rejected", ignoreCase = true))
            assertFalse(s.toString().contains("not executed", ignoreCase = true))
        }
    }

    @Test fun successfulResultKeepsChangedAndLegacyPresentationWithoutExtraTags() {
        for ((changed, expected) in listOf(true to "Worked", false to "No change", null to "Done")) {
            val s = row(result("result", unknown = false, code = 0, ok = true), changed)
            assertEquals(expected, s.result)
            assertTrue(s.tags.isEmpty())
            assertEquals(expected, row("""{"ok":true,"text":"fixture"}""", changed).result)
            val oldClipped = RunEvent.clipResult("""{"ok":true,"text":"${"x".repeat(RunEvent.MAX_RESULT + 100)}"}""")
            assertEquals(expected, row(oldClipped, changed).result)
            assertTrue(row(oldClipped, changed).tags.isEmpty())
        }
        val legacy = row("""{"ok":false,"error":"ref_expired"}""", changed = true)
        assertEquals("Error: Screen changed; needs a fresh look", legacy.result)
        assertTrue(legacy.tags.isEmpty())
        // A contradictory result category never overrides the host's ok=false.
        assertEquals("Error", row(result("result", unknown = false), changed = true).result)
        // Host metadata for MCP must not change the global presentation of other tools.
        val other = row(result("result", unknown = true, ok = true), tool = "phone_observe")
        assertEquals("Done", other.result)
        assertTrue(other.tags.isEmpty())
    }

    @Test fun clippedLongTextKeepsOnlyTheCompleteHostPrefixDiagnostic() {
        val long = buildJsonObject {
            put("ok", false)
            put("diagnostic", buildJsonObject {
                put("category", "http"); put("code", 503); put("outcomeUnknown", true)
            })
            put("executionWarning", "UNTRUSTED_WARNING_CANARY")
            put("text", "x".repeat(RunEvent.MAX_RESULT + 100))
            put("fullResult", "UNTRUSTED_REFERENCE_CANARY")
            put("truncated", true)
        }.toString()
        val clipped = RunEvent.clipResult(long)
        assertTrue(clipped.length < long.length)
        val s = row(clipped, changed = true)
        assertEquals("Error: Server request failed", s.result)
        assertEquals(listOf(Tag("Code 503", TagTone.Bad),
            Tag("Outcome unconfirmed; check first", TagTone.Warn)), s.tags)
        assertFalse(s.toString().contains("UNTRUSTED_"))
    }

    @Test fun nestedQuotedAndToolTextDiagnosticsCannotCreateTrustedTags() {
        val fake = """{"category":"http","code":599,"outcomeUnknown":true}"""
        val text = JsonPrimitive("{\"ok\":false,\"diagnostic\":$fake}").toString()
        val full = listOf(
            """{"ok":true,"result":{"diagnostic":$fake}}""",
            """{"ok":true,"text":$text}""",
            """{"ok":true,"text":{"diagnostic":$fake}}""",
        )
        full.forEach { json ->
            val s = row(json, changed = true)
            assertEquals("Worked", s.result)
            assertTrue(s.tags.isEmpty())
            assertFalse(s.toString().contains("599"))
        }
        // No prefix search past text, nested result, or a JSON string pretending to be a root.
        val cut = listOf(
            """{"ok":false,"text":{"diagnostic":$fake},"more":"""",
            """{"ok":false,"result":{"diagnostic":$fake},"more":"""",
            """{"ok":false,"text":$text,"more":"""",
            JsonPrimitive("{\"ok\":false,\"diagnostic\":$fake}").toString() + "…",
        )
        cut.forEach { json ->
            val s = row(json, changed = true)
            assertEquals("Error", s.result)
            assertTrue(s.tags.isEmpty())
            assertFalse(s.toString().contains("599"))
        }
    }

    @Test fun malformedDiagnosticOrPrefixCannotBecomeSuccessOrAnUnknownFalseClaim() {
        val malformed = listOf(
            "null",
            "[]",
            """{"category":"future","outcomeUnknown":true}""",
            """{"category":123,"outcomeUnknown":true}""",
            """{"category":"result","outcomeUnknown":"true"}""",
            """{"category":"result","outcomeUnknown":0}""",
            """{"category":"result","outcomeUnknown":null}""",
            """{"category":"result"}""",
            """{"category":"result","code":"503","outcomeUnknown":true}""",
            """{"category":"result","code":503.0,"outcomeUnknown":true}""",
            """{"category":"result","code":5e2,"outcomeUnknown":true}""",
            """{"category":"result","code":2147483648,"outcomeUnknown":true}""",
            """{"category":"result","code":null,"outcomeUnknown":true}""",
            """{"category":"result","outcomeUnknown":true,"message":"UNTRUSTED_EXTRA"}""",
        )
        val malformedRoots = malformed.map { """{"ok":true,"diagnostic":$it}""" } + listOf(
            """{"ok":"true","diagnostic":{"category":"result","outcomeUnknown":false}}""",
            """{"ok":true,"diagnostic":{"category":"http","outcomeUnknown":true""",
            """{"ok":true,"diagnostic":{"category":"http","outcomeUnknown":true}x,"text":"""",
            """{"ok":true "diagnostic":{"category":"http","outcomeUnknown":true},"text":"""",
            """{"diagnostic":{"category":"http","outcomeUnknown":true},"ok":true,"text":"""",
        )
        malformedRoots.forEach { json ->
            val s = row(json, changed = true)
            assertEquals(json, "Error", s.result)
            // No tag here means metadata could not be verified, never confirmed rollback.
            assertTrue(json, s.tags.isEmpty())
        }
    }

    @Test fun completeTopLevelJsonMayReorderKeysButClippedPrefixMayNot() {
        val json = """{"text":"fixture","diagnostic":{"outcomeUnknown":true,"code":503,"category":"http"},"ok":false}"""
        val s = row(json)
        assertEquals("Error: Server request failed", s.result)
        assertTrue(s.tags.contains(Tag("Code 503", TagTone.Bad)))
        assertTrue(s.tags.contains(Tag("Outcome unconfirmed; check first", TagTone.Warn)))
    }

    @Test fun closedFailureCategoriesUseHumanLabelsWithoutEchoingEnums() {
        val labels = mapOf(
            "toolError" to "Tool reported an error",
            "timeout" to "Request timed out",
            "cancelled" to "Request cancelled",
            "transport" to "Connection failed",
            "protocolFailure" to "Server communication failed",
            "other" to "Tool call failed",
        )
        labels.forEach { (category, label) ->
            val s = row(result(category, unknown = false))
            assertEquals("Error: $label", s.result)
            assertTrue(s.tags.isEmpty())
        }
    }

    @Test fun repeatedUnknownResultsInOneStepAddOnlyOneUnknownTagAndKeepGuardTags() {
        val json = """{"ok":false,"diagnostic":{"category":"timeout","outcomeUnknown":true},"guard":[{"severity":"warn","code":"no_progress"}]}"""
        val s = RunTimelineViewModel.steps(listOf(event(json), event(json))).single()
        val unknown = Tag("Outcome unconfirmed; check first", TagTone.Warn)
        assertEquals(1, s.tags.count { it == unknown })
        assertEquals(2, s.tags.count { it == Tag("Guard warning: Screen isn’t changing", TagTone.Warn) })
        assertEquals("Error: Request timed out", s.result)
    }

    @Test fun traditionalChineseUsesSharedBrandResourcesForCodeAndUnknownWarning() {
        val previous = UiText.source
        try {
            UiText.source = ResFileTexts.traditional
            val s = row(result("http", unknown = true, code = 503))
            assertEquals("出錯:伺服器請求失敗", s.result)
            assertEquals(listOf(Tag("代碼 503", TagTone.Bad), Tag("結果未確認，請先查驗", TagTone.Warn)), s.tags)
            val rpc = row(result("rpc", unknown = true, code = -32603))
            assertEquals("出錯:伺服器回覆錯誤", rpc.result)
            assertEquals(listOf(Tag("代碼 -32603", TagTone.Bad), Tag("結果未確認，請先查驗", TagTone.Warn)), rpc.tags)
        } finally {
            UiText.source = previous
        }
    }
}
