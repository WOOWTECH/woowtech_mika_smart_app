package com.wangzan101.mika.core.remote

import com.wangzan101.mika.core.mcp.FakeRemoteTasks
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import org.junit.Assert.*
import org.junit.Test
import java.net.InetAddress

class RemoteConversationApiTest {
    private val id = "123e4567-e89b-12d3-a456-426614174000"
    private val source = object : RemoteConversationData {
        override fun list(offset: Int, limit: Int) = 1 to listOf(buildJsonObject { put("id", id) }).drop(offset).take(limit)
        override fun get(id: String, offset: Int, limit: Int): JsonObject? =
            if (id == this@RemoteConversationApiTest.id) buildJsonObject {
                put("id", id); put("total", 1); put("offset", offset)
            } else null
        override fun attachment(id: String, turn: Int, file: Int, offset: Long, maxBytes: Int): ByteArray? =
            if (id == this@RemoteConversationApiTest.id && turn == 0 && file == 0) byteArrayOf(1, 2, 3).drop(offset.toInt()).take(maxBytes).toByteArray() else null
    }
    private val loopback = InetAddress.getLoopbackAddress()
    private val host = RemoteHost(FakeRemoteTasks(), { "secret" }, 0, false, "play",
        endpoints = RemoteEndpoints(FakeRemoteTasks(), "play", device = null, conversations = source))

    private fun call(path: String, token: String = "secret", method: String = "GET", accept: String = "application/json"): HttpResponse =
        host.handle(HttpRequest(method, path.substringBefore('?'), mapOf("authorization" to "Bearer $token", "accept" to accept),
            ByteArray(0), loopback, path.substringAfter('?', "")))

    @Test fun authenticatedReadOnlyHistoryAndChunks() {
        assertEquals(401, call("/api/v1/conversations", "wrong").status)
        val index = call("/api/v1/conversations?offset=0&limit=1")
        assertEquals(200, index.status)
        assertEquals(id, Json.parseToJsonElement(index.body.decodeToString()).jsonObject["conversations"]!!.jsonArray[0].jsonObject["id"]!!.jsonPrimitive.content)
        assertEquals(200, call("/api/v1/conversations/$id").status)
        val chunk = call("/api/v1/conversations/$id/attachments/0/0?offset=1", accept = "application/octet-stream")
        assertEquals(200, chunk.status)
        assertArrayEquals(byteArrayOf(2, 3), chunk.body)
        assertEquals(404, call("/api/v1/conversations/$id/attachments/0/1?offset=0").status)
        assertEquals(400, call("/api/v1/conversations/$id/attachments/0/0?offset=-1").status)
        assertEquals(405, call("/api/v1/conversations", method = "POST").status)
    }

    @Test fun capabilityIsExplicitAndDeviceControlIsAbsent() {
        val info = Json.parseToJsonElement(call("/api/v1").body.decodeToString()).jsonObject
        val caps = info["capabilities"]!!.jsonArray.map { it.jsonPrimitive.content }
        assertTrue("conversation_read" in caps)
        assertFalse("device_state" in caps)
        assertEquals(503, call("/api/v1/device").status)
        val without = RemoteTaskApi(RemoteTaskService(FakeRemoteTasks()), "play")
        assertEquals(404, without.handle(HttpRequest("GET", "/api/v1/conversations", emptyMap(), ByteArray(0), loopback)).status)
    }
}
