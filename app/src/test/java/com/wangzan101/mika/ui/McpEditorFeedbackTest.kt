package com.wangzan101.mika.ui

import com.wangzan101.mika.R
import com.wangzan101.mika.settings.KeyCipher
import com.wangzan101.mika.settings.McpServerConfig
import com.wangzan101.mika.settings.McpServerStore
import okhttp3.OkHttpClient
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class McpEditorFeedbackTest {
    @get:Rule val tmp = TemporaryFolder()

    @Test fun actualStoreRejectionsHaveLocalizedUiMessagesWithoutChangingValidation() {
        val cipher = object : KeyCipher {
            override fun encrypt(plain: ByteArray) = plain
            override fun decrypt(data: ByteArray) = data
        }
        val store = McpServerStore(tmp.root, cipher, OkHttpClient())
        val valid = McpServerConfig(name = "Echo", url = "https://example.com/mcp")
        val stdio = valid.copy(transport = "stdio", command = "echo")
        val rejected = listOf(
            valid.copy(name = " ") to R.string.mcp_validation_name_required,
            stdio.copy(command = " ") to R.string.mcp_validation_command_required,
            stdio.copy(command = "a".repeat(4001)) to R.string.mcp_validation_command_too_long,
            stdio.copy(command = "echo\nhello") to R.string.mcp_validation_command_one_line,
            stdio.copy(command = "echo\u0000hello") to R.string.mcp_validation_command_one_line,
            valid.copy(url = "not-a-url") to R.string.mcp_validation_invalid_url,
            valid.copy(url = "https://user:password@example.com") to R.string.mcp_validation_url_user_info,
            valid.copy(url = "https://169.254.169.254") to R.string.mcp_validation_blocked_host,
            valid.copy(url = "http://127.0.0.1") to R.string.mcp_validation_http_opt_in,
            valid.copy(url = "http://example.com", allowLocalHttp = true) to R.string.mcp_validation_http_local_only,
        )
        for ((config, resource) in rejected) {
            val error = store.validate(config)
            assertNotNull(error)
            assertEquals(resource.toString(), mcpValidationMessage(error) { it.toString() })
            assertTrue(store.add(config).isFailure)
        }
        assertTrue(store.servers.value.isEmpty())
        assertNull(store.validate(valid))
        assertNull(store.validate(stdio.copy(command = "a".repeat(4000))))
        assertNull(store.validate(valid.copy(url = "http://127.0.0.1", allowLocalHttp = true)))
        // OkHttp currently rejects non-HTTP schemes before the store's defensive scheme branch.
        assertEquals(R.string.mcp_validation_https_required.toString(),
            mcpValidationMessage("URL must be https (or http for a local server)") { it.toString() })
    }

    @Test fun unknownBackendDiagnosticsAreNotRewritten() {
        val diagnostic = "upstream: invalid URL (request 42)"
        assertEquals(diagnostic, mcpValidationMessage(diagnostic) { error("not a store validation") })
        assertNull(mcpValidationMessage(null) { error("no message") })
    }

    @Test fun editingOrSwitchingTransportClearsFeedbackAndRejectsLateOldResults() {
        val feedback = McpEditorFeedback()
        val httpRequest = feedback.revision
        feedback.publish(httpRequest, "invalid URL")
        assertEquals("invalid URL", feedback.message)
        feedback.edited() // HTTP -> stdio
        assertNull(feedback.message)
        feedback.publish(httpRequest, "old HTTP test finished")
        assertNull(feedback.message)
        val stdioRequest = feedback.revision
        feedback.publish(stdioRequest, "command is required")
        assertEquals("command is required", feedback.message)
        feedback.edited() // command edited
        feedback.edited() // switch back to HTTP: old HTTP result is still stale
        feedback.publish(httpRequest, "old HTTP result")
        feedback.publish(stdioRequest, "old stdio result")
        assertNull(feedback.message)
        feedback.publish(feedback.revision, "current result")
        assertEquals("current result", feedback.message)
    }
}
