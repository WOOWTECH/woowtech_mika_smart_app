package com.wangzan101.mika.ui

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.wangzan101.mika.R

/** Exact store validation messages only; backend diagnostics must remain intact. */
internal fun mcpValidationMessage(message: String?, text: (Int) -> String): String? = when (message) {
    "name is required" -> text(R.string.mcp_validation_name_required)
    "command is required" -> text(R.string.mcp_validation_command_required)
    "command is too long" -> text(R.string.mcp_validation_command_too_long)
    "command must be one line" -> text(R.string.mcp_validation_command_one_line)
    "invalid URL" -> text(R.string.mcp_validation_invalid_url)
    "URL must not contain user info" -> text(R.string.mcp_validation_url_user_info)
    "this host is not allowed" -> text(R.string.mcp_validation_blocked_host)
    "HTTP is only allowed for local/private servers after enabling it" -> text(R.string.mcp_validation_http_opt_in)
    "HTTP is only allowed for local/private hosts" -> text(R.string.mcp_validation_http_local_only)
    "URL must be https (or http for a local server)" -> text(R.string.mcp_validation_https_required)
    else -> message
}

/** Edits invalidate displayed feedback and any in-flight result for the old fields. */
internal class McpEditorFeedback {
    var revision: Long = 0
        private set
    var message: String? by mutableStateOf(null)
        private set

    fun edited() {
        revision++
        message = null
    }

    fun publish(requestRevision: Long, value: String?) {
        if (requestRevision == revision) message = value
    }
}
