package com.wangzan101.mika.mcp

import android.content.Context
import android.net.Uri
import com.wangzan101.mika.chat.ConversationStore
import com.wangzan101.mika.core.remote.RemoteConversationData
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.add
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonArray

/** Read-only view of phone conversations for an authenticated, online remote client. */
internal class PhoneConversationData(private val context: Context) : RemoteConversationData {
    private val store get() = ConversationStore.shared(context)

    override fun list(offset: Int, limit: Int): Pair<Int, List<JsonObject>> {
        val all = store.list()
        return all.size to all.drop(offset).take(limit).map { c ->
            buildJsonObject {
                put("id", c.id); put("title", c.title); put("updated_at_ms", c.updatedAt)
                c.pinnedAt?.let { put("pinned_at_ms", it) }
            }
        }
    }

    override fun get(id: String, offset: Int, limit: Int): JsonObject? {
        val summary = store.list().firstOrNull { it.id == id } ?: return null
        val records = store.records(id)
        return buildJsonObject {
            put("id", id); put("title", summary.title); put("updated_at_ms", summary.updatedAt)
            put("total", records.size); put("offset", offset)
            putJsonArray("turns") {
                records.drop(offset).take(limit).forEachIndexed { pageIndex, (turn, files) ->
                    add(buildJsonObject {
                        put("index", offset + pageIndex); put("user_text", turn.userText)
                        put("outcome", turn.outcome); put("status", turn.status)
                        turn.note?.let { put("note", it) }
                        putJsonArray("steers") { turn.steers.forEach(::add) }
                        putJsonArray("interrupted_replies") { turn.interruptedReplies.forEach(::add) }
                        putJsonArray("finished_replies") { turn.finishedReplies.forEach(::add) }
                        putJsonArray("attachments") {
                            files.forEachIndexed { index, file -> add(buildJsonObject {
                                put("index", index); put("name", file.name); put("size", file.size)
                            }) }
                        }
                    })
                }
            }
        }
    }

    override fun attachment(id: String, turn: Int, file: Int, offset: Long, maxBytes: Int): ByteArray? {
        if (turn < 0 || file < 0 || offset < 0) return null
        if (store.list().none { it.id == id }) return null
        val record = store.records(id).getOrNull(turn) ?: return null
        val shared = record.second.getOrNull(file) ?: return null
        val uri = Uri.parse(shared.uri)
        // File cards are exports through MediaStore. Never open arbitrary paths or client-provided URIs.
        if (uri.scheme != "content" || uri.authority != "media") return null
        if (shared.size < 0 || offset > shared.size) return null
        return runCatching {
            context.contentResolver.openInputStream(uri)?.use { input ->
                var remaining = offset
                while (remaining > 0) {
                    val skipped = input.skip(remaining)
                    if (skipped <= 0) {
                        if (input.read() < 0) return@use null
                        remaining--
                    } else remaining -= skipped
                }
                val out = ByteArray(minOf(maxBytes.coerceIn(1, 128 * 1024).toLong(), shared.size - offset).toInt())
                if (out.isEmpty()) return@use out
                val count = input.read(out)
                if (count < 0) ByteArray(0) else out.copyOf(count)
            }
        }.getOrNull()
    }
}
