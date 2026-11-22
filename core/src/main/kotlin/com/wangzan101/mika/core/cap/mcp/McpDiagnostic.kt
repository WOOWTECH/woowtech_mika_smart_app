package com.wangzan101.mika.core.cap.mcp

import kotlinx.coroutines.CancellationException
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonObjectBuilder
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.put
import java.io.IOException
import java.net.SocketTimeoutException

/** Host metadata only; no server text or exceptions. unknown=false never promises rollback. */
data class McpDiagnostic(val category: Category, val code: Int? = null, val outcomeUnknown: Boolean) {
    enum class Category { result, toolError, http, rpc, timeout, cancelled, transport, protocolFailure, other }

    internal fun json(): JsonObject = buildJsonObject {
        put("category", category.name)
        code?.let { put("code", it) }
        put("outcomeUnknown", outcomeUnknown)
    }

    internal fun failureText(): String = when (category) {
        Category.http -> "MCP request failed: HTTP $code."
        Category.rpc -> "MCP request failed: JSON-RPC error $code."
        Category.timeout -> "MCP request timed out before a usable result arrived."
        Category.cancelled -> "MCP request was cancelled before a usable result arrived."
        Category.transport -> "MCP transport failed before a usable result arrived."
        Category.protocolFailure -> "MCP server returned an invalid protocol response."
        else -> "MCP request failed before a usable result arrived."
    }

    companion object {
        internal const val EXECUTION_WARNING = "結果未知，勿重送會改資料的呼叫，先唯讀查驗或告知使用者。"
        internal fun returned(isError: Boolean) = McpDiagnostic(
            if (isError) Category.toolError else Category.result, outcomeUnknown = isError,
        )
        internal fun localRefusal() = McpDiagnostic(Category.other, outcomeUnknown = false)
        internal fun failed(error: Exception): McpDiagnostic = when (error) {
            is CancellationException -> throw error
            is McpClientException -> error.diagnostic ?: McpDiagnostic(Category.other, outcomeUnknown = true)
            is SocketTimeoutException -> McpDiagnostic(Category.timeout, outcomeUnknown = true)
            is IOException -> McpDiagnostic(Category.transport, outcomeUnknown = true)
            else -> McpDiagnostic(Category.other, outcomeUnknown = true)
        }
    }
}

internal fun JsonObjectBuilder.mcpDiagnostic(diagnostic: McpDiagnostic) {
    put("diagnostic", diagnostic.json())
    if (diagnostic.outcomeUnknown) put("executionWarning", McpDiagnostic.EXECUTION_WARNING)
}

internal fun mcpFailureException(error: Exception): McpClientException {
    val diagnostic = McpDiagnostic.failed(error)
    return McpClientException(diagnostic.failureText(), diagnostic = diagnostic)
}

internal fun mcpHttpFailure(code: Int) = McpDiagnostic(McpDiagnostic.Category.http, code, true).asException()
internal fun mcpTimeoutFailure() = McpDiagnostic(McpDiagnostic.Category.timeout, outcomeUnknown = true).asException()
internal fun mcpProtocolFailure() = McpDiagnostic(McpDiagnostic.Category.protocolFailure, outcomeUnknown = true).asException()

internal fun mcpRpcFailure(error: JsonElement): McpClientException {
    val code = ((error as? JsonObject)?.get("code") as? JsonPrimitive)?.takeUnless { it.isString }?.intOrNull
        ?: return mcpProtocolFailure()
    return McpDiagnostic(McpDiagnostic.Category.rpc, code, code !in listOf(-32600, -32601, -32602)).asException()
}

private fun McpDiagnostic.asException() = McpClientException(failureText(), diagnostic = this)

internal fun mcpFailureResult(error: Exception): McpResult {
    val diagnostic = McpDiagnostic.failed(error)
    return McpResult(diagnostic.failureText(), isError = true, diagnostic = diagnostic)
}

internal fun mcpLocalRefusal(): McpResult = McpResult(
    "MCP operation is not available; no request was dispatched.", isError = true,
    diagnostic = McpDiagnostic.localRefusal(),
)

internal suspend fun mcpRequestResult(request: suspend () -> McpResult): McpResult = try {
    request()
} catch (e: CancellationException) {
    throw e
} catch (e: Exception) {
    mcpFailureResult(e)
}

internal suspend fun <T> mcpConnect(request: suspend () -> T): Result<T> = try {
    Result.success(request())
} catch (e: CancellationException) {
    throw e
} catch (e: Exception) {
    Result.failure(mcpFailureException(e))
}
