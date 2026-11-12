package com.wangzan101.mika.core.remote

import kotlinx.serialization.json.JsonObject

/** Phone-owned, read-only chat history. Implementations must never accept a client-supplied URI or file path. */
interface RemoteConversationData {
    fun list(offset: Int, limit: Int): Pair<Int, List<JsonObject>>
    fun get(id: String, offset: Int, limit: Int): JsonObject?
    fun attachment(id: String, turn: Int, file: Int, offset: Long, maxBytes: Int): ByteArray?
}
