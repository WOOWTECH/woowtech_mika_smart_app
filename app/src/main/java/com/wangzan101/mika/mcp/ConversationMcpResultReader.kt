package com.wangzan101.mika.mcp

import com.wangzan101.mika.cap.sandbox.SandboxDirs
import com.wangzan101.mika.core.cap.mcp.McpAnnotations
import com.wangzan101.mika.core.cap.mcp.McpEndpoint
import com.wangzan101.mika.core.cap.mcp.McpResult
import com.wangzan101.mika.core.cap.mcp.McpToolDescriptor
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import java.nio.charset.StandardCharsets

/** Read only the long MCP results saved for this conversation, in bounded chunks. */
class ConversationMcpResultReader(
    private val dirs: SandboxDirs,
    private val conversationId: String,
) : McpEndpoint {
    override val serverId = "local_results"

    override fun tools() = listOf(McpToolDescriptor(
        name = "read",
        description = "Read a chunk of a long MCP tool result. Use the fullResult path returned by a tool. Offset and maxChars are character counts. Only this conversation's MCP results are accessible.",
        inputSchema = buildJsonObject {
            put("type", "object")
            put("properties", buildJsonObject {
                put("path", buildJsonObject { put("type", "string") })
                put("offset", buildJsonObject { put("type", "integer"); put("minimum", 0) })
                put("maxChars", buildJsonObject { put("type", "integer"); put("minimum", 1); put("maximum", 3000) })
            })
            put("required", kotlinx.serialization.json.buildJsonArray { add(kotlinx.serialization.json.JsonPrimitive("path")) })
            put("additionalProperties", false)
        },
        annotations = McpAnnotations(readOnlyHint = true),
    ))

    override suspend fun call(name: String, arguments: JsonObject): McpResult {
        if (name != "read") return McpResult("unknown_tool", true)
        val path = arguments["path"]?.jsonPrimitive?.content.orEmpty()
        val rel = path.removePrefix("/workspace/")
        if (!path.startsWith("/workspace/mcp-results/") ||
            !Regex("^mcp-results/[A-Za-z0-9_-]+-[A-Za-z0-9_-]+-[0-9a-fA-F-]{36}\\.txt$").matches(rel)
        ) return McpResult("invalid_result_path", true)
        val offset = arguments["offset"]?.jsonPrimitive?.intOrNull ?: 0
        val maxChars = (arguments["maxChars"]?.jsonPrimitive?.intOrNull ?: 3000).coerceIn(1, 3000)
        if (offset < 0) return McpResult("invalid_offset", true)
        return try {
            dirs.gate.openRead(dirs.workspace(conversationId), rel, under = "mcp-results").use { file ->
                if (file.size > 4_000_000) return McpResult("result_too_large_to_read", true)
                val content = String(file.read(0, file.size.toInt()), StandardCharsets.UTF_8)
                val end = (offset.toLong() + maxChars).coerceAtMost(content.length.toLong()).toInt()
                if (offset > content.length) return McpResult("offset_out_of_range", true)
                McpResult(buildJsonObject {
                    put("text", content.substring(offset, end))
                    put("nextOffset", end)
                    put("hasMore", end < content.length)
                }.toString())
            }
        } catch (_: Exception) {
            McpResult("result_not_found", true)
        }
    }
}
