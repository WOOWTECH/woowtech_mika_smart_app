package com.wangzan101.mika.core.cap.mcp

import com.wangzan101.mika.core.assembly.toolDispatcher
import com.wangzan101.mika.core.model.Part
import com.wangzan101.mika.core.tool.ActionPass
import com.wangzan101.mika.core.tool.FakeScreen
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import okhttp3.OkHttpClient
import okhttp3.mockwebserver.Dispatcher
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.mockwebserver.RecordedRequest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.junit.runners.Parameterized
import java.io.Closeable
import java.io.OutputStream
import java.net.InetAddress
import java.net.ServerSocket
import java.net.Socket
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.Executors

/** Real HTTP POSTs for both transports; the legacy reply remains on a live SSE stream. */
private class ContractServer(
    private val transport: String,
    private val firstCallStatus: Int? = null,
    private val result: JsonObject = toolResult(),
) : Closeable {
    data class Call(val method: String?, val id: String, val responseStatus: Int)
    val calls = CopyOnWriteArrayList<Call>()
    private val server = MockWebServer().also { it.start() }
    private val sse = if (transport == "sse") {
        EventStream(server.url("/messages").newBuilder().host("127.0.0.1").build().toString())
    } else null
    private var endpoint: McpEndpoint? = null

    init {
        server.dispatcher = object : Dispatcher() {
            override fun dispatch(request: RecordedRequest): MockResponse {
                if (request.method == "DELETE") return MockResponse().setResponseCode(200)
                if (request.method != "POST") return MockResponse().setResponseCode(405)
                val message = Json.parseToJsonElement(request.body.readUtf8()).jsonObject
                val id = message["id"] ?: return MockResponse().setResponseCode(202)
                val payload = when (message.getValue("method").jsonPrimitive.content) {
                    "initialize" -> buildJsonObject {
                        put("protocolVersion", if (sse == null) "2025-03-26" else "2024-11-05")
                        put("capabilities", buildJsonObject { put("tools", buildJsonObject {}) })
                        put("serverInfo", buildJsonObject { put("name", "synthetic contract fixture") })
                    }
                    "tools/list" -> buildJsonObject {
                        put("tools", JsonArray(listOf(buildJsonObject {
                            put("name", "write")
                            put("description", "Synthetic loopback operation; no business data")
                            put("inputSchema", buildJsonObject { put("type", "object") })
                        })))
                    }
                    "tools/call" -> {
                        val status = if (calls.isEmpty()) firstCallStatus ?: 200 else 200
                        calls += Call(request.method, id.toString(), status)
                        if (status != 200) return MockResponse().setResponseCode(status).apply {
                            if (status == 503) setHeader("Retry-After", "0")
                        }
                        result
                    }
                    else -> return MockResponse().setResponseCode(400)
                }
                val reply = buildJsonObject {
                    put("jsonrpc", "2.0"); put("id", id); put("result", payload)
                }
                if (sse != null) {
                    sse.send(reply)
                    return MockResponse().setResponseCode(202)
                }
                return MockResponse().setHeader("Content-Type", "application/json")
                    .setBody(reply.toString())
            }
        }
    }

    suspend fun connect(): McpEndpoint {
        val opened = if (sse == null) {
            HttpMcpEndpoint.connect("contract", server.url("/mcp").toString(), OkHttpClient(), timeoutSec = 5).getOrThrow()
        } else {
            LegacySseMcpEndpoint.connect("contract", sse.url, OkHttpClient(), timeoutSec = 5).getOrThrow()
        }
        endpoint = opened
        return opened
    }

    override fun close() {
        (endpoint as? Closeable)?.close()
        sse?.close()
        server.shutdown()
    }

    /** Only the GET stream needs a socket; all JSON-RPC POSTs use MockWebServer. */
    private class EventStream(private val postUrl: String) : Closeable {
        private val server = ServerSocket(0, 1, InetAddress.getByName("127.0.0.1"))
        private val worker = Executors.newSingleThreadExecutor()
        @Volatile private var socket: Socket? = null
        @Volatile private var output: OutputStream? = null
        val url = "http://127.0.0.1:${server.localPort}/mcp"

        init {
            worker.submit {
                val accepted = server.accept()
                socket = accepted
                accepted.use {
                    val reader = it.getInputStream().bufferedReader(Charsets.ISO_8859_1)
                    while (!reader.readLine().isNullOrEmpty()) Unit
                    val stream = it.getOutputStream()
                    output = stream
                    stream.write(("HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\n\r\n" +
                        "event: endpoint\ndata: $postUrl\n\n").toByteArray(Charsets.UTF_8))
                    stream.flush()
                    // The client cancels/closes this stream at teardown; no timed sleep.
                    while (it.getInputStream().read() >= 0) Unit
                }
            }
        }

        @Synchronized fun send(message: JsonObject) {
            val stream = checkNotNull(output)
            stream.write("event: message\ndata: $message\n\n".toByteArray(Charsets.UTF_8))
            stream.flush()
        }

        override fun close() {
            socket?.close()
            server.close()
            worker.shutdownNow()
        }
    }
}

private fun toolResult(errorFlag: String? = null): JsonObject = buildJsonObject {
    put("content", JsonArray(listOf(buildJsonObject {
        put("type", "text"); put("text", "synthetic tool content")
    })))
    if (errorFlag != null) put("isError", Json.parseToJsonElement(errorFlag))
}

@RunWith(Parameterized::class)
class McpCallReplayTest(private val transport: String, private val status: Int) {
    @Test(timeout = 20_000) fun toolsCallPostIsNotReplayed() = runBlocking {
        ContractServer(transport, firstCallStatus = status).use { server ->
            val result = server.connect().call("write", buildJsonObject {})
            println("MCP_POST_EVIDENCE transport=$transport firstStatus=$status " +
                "posts=${server.calls.size} receipts=${server.calls} isError=${result.isError}")
            assertEquals("Count actual tools/call POSTs, including OkHttp follow-ups", 1, server.calls.size)
            assertEquals("POST", server.calls.single().method)
            assertTrue("The first HTTP error must remain an error", result.isError)
        }
    }

    companion object {
        @JvmStatic @Parameterized.Parameters(name = "{0}-HTTP{1}")
        fun cases(): List<Array<Any>> = listOf(
            arrayOf("http", 503), arrayOf("http", 408),
            arrayOf("sse", 503), arrayOf("sse", 408),
        )
    }
}

@RunWith(Parameterized::class)
class McpCallResultContractTest(
    private val caseName: String,
    private val errorFlag: String?,
    private val expectedOk: Boolean,
) {
    @Test(timeout = 20_000) fun transportResultKeepsErrorSemanticsThroughCapability() = runBlocking {
        ContractServer("http", result = toolResult(errorFlag)).use { server ->
            val tools = toolDispatcher(FakeScreen(), mcpServers = listOf(McpConnection(server.connect())))
            val result = tools.execute(Part.ToolCall("fixture-call", "mcp_contract__write", "{}"), ActionPass())
            println("MCP_FLAG_EVIDENCE case=$caseName posts=${server.calls.size} ok=${result.content["ok"]}")
            assertEquals(1, server.calls.size)
            assertEquals(JsonPrimitive(expectedOk), result.content["ok"])
        }
    }

    companion object {
        @JvmStatic @Parameterized.Parameters(name = "{0}")
        fun cases(): List<Array<Any?>> = listOf(
            arrayOf("object", "{}", false), arrayOf("null", "null", false),
            arrayOf("quoted-false", "\"false\"", false), arrayOf("number", "0", false),
            arrayOf("missing", null, true), arrayOf("boolean-false", "false", true),
            arrayOf("boolean-true", "true", false),
        )
    }
}
