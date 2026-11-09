package com.wangzan101.mika.core.general

import com.wangzan101.mika.core.observation.ObsKind
import com.wangzan101.mika.core.observation.Observation
import com.wangzan101.mika.core.memory.MemoryIndex
import com.wangzan101.mika.core.memory.MemoryKind
import com.wangzan101.mika.core.memory.MemoryRejected
import com.wangzan101.mika.core.memory.MemorySource
import com.wangzan101.mika.core.memory.MemoryStore
import com.wangzan101.mika.core.prompt.Feedback
import com.wangzan101.mika.core.prompt.Prompts
import com.wangzan101.mika.core.tool.AgentTool
import com.wangzan101.mika.core.tool.ArgError
import com.wangzan101.mika.core.tool.Args
import com.wangzan101.mika.core.tool.Concurrency
import com.wangzan101.mika.core.tool.EvidenceLog
import com.wangzan101.mika.core.tool.Risk
import com.wangzan101.mika.core.tool.ToolContext
import com.wangzan101.mika.core.tool.ToolDef
import com.wangzan101.mika.core.tool.ToolExecution
import com.wangzan101.mika.core.tool.Verb
import com.wangzan101.mika.core.tool.argStr
import com.wangzan101.mika.core.tool.fail
import com.wangzan101.mika.core.tool.ok
import com.wangzan101.mika.core.tool.str
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.put

private const val MEMORY_SEARCH_LIMIT = 8

/** 记忆和用户本次说过的话都给了才提供。 */
private fun memoryOn(ctx: ToolContext) = ctx.config.memory != null && ctx.config.utterances != null

/** Delete exactly the reviewed record, never a bulk UI operation or another app's data. */
internal object MemoryForget : AgentTool {
    override val verb = Verb.MemoryForget
    override val label = "删除一条记忆"
    override val risk = Risk.Write
    override val offScreen = true
    override val def = ToolDef("memory_forget", Prompts.tool("memory_forget"), mapOf(
        "id" to str("The exact id returned by memory_search."),
        "content" to str("The exact current content returned by memory_search; changed records are not deleted."),
        "quote" to str("The user's exact words asking to forget this memory, from the current task."),
    ), listOf("id", "content", "quote"))

    override fun available(ctx: ToolContext) = memoryOn(ctx)

    override suspend fun execute(a: Args, ctx: ToolContext): ToolExecution {
        val id = a.str("id", max = 200)!!
        val content = a.str("content", max = MemoryStore.MAX_CONTENT)!!
        val quote = a.str("quote", max = 1000)!!
        if (!ctx.config.utterances!!.contains(quote))
            return fail("quote_not_from_user", Feedback["memory.quote_not_from_user"], recoverable = false)
        return ctx.config.memory!!.forget(id, expectedContent = content).fold(
            onSuccess = { change ->
                ctx.noteSaved(change)
                ok { put("id", id); put("deleted", true) }
            },
            onFailure = { e ->
                when ((e as? MemoryRejected)?.code) {
                    "not_found" -> fail("not_found", "This memory no longer exists. Search again; nothing was deleted.", recoverable = false)
                    "content_changed" -> fail("content_changed", "The memory changed since it was read. Search again before deciding whether it still matches the user's deletion request.", recoverable = true)
                    "unavailable" -> fail("memory_unavailable", Feedback["memory.unavailable"], recoverable = false)
                    else -> throw e
                }
            },
        )
    }
}

internal object MemorySearch : AgentTool {
    override val verb = Verb.MemorySearch
    override val label = "查找记忆" // WOOWTECH fork: 上游没有说法,界面上露出工具名
    override val risk = Risk.Read
    override val concurrency = Concurrency.ParallelSafe
    override val def = ToolDef("memory_search",
        Prompts.tool("memory_search"),
        mapOf("query" to str("Words to look for, 1-100 characters.")), listOf("query"))

    override fun available(ctx: ToolContext) = memoryOn(ctx)

    override suspend fun execute(a: Args, ctx: ToolContext): ToolExecution {
        val q = a.str("query", max = 100)!!
        val found = MemoryIndex(ctx.config.memory!!.items.value).search(q, MEMORY_SEARCH_LIMIT)
        return ok {
            put("memories", JsonArray(found.map { (m, _) ->
                buildJsonObject { put("id", m.id); put("kind", m.kind.name); put("content", m.content) }
            }))
        }
    }

    /** 记忆里的是用户以前说的:作为用户给的事实交给核查。 */
    override fun observations(o: JsonObject, r: ToolExecution, log: EvidenceLog): List<Observation> {
        if (r.content["ok"] != JsonPrimitive(true)) return emptyList()
        return listOfNotNull((r.content["memories"] as? JsonArray)?.takeIf { it.isNotEmpty() }?.let { list ->
            Observation(ObsKind.UserSaid, list.joinToString("\n", "记忆检索「${o.argStr("query")}」:\n") { m -> ((m as? JsonObject)?.get("content") as? JsonPrimitive)?.contentOrNull.orEmpty() },
                source = "memory")
        })
    }
}

/** 只改 Mika 自己的记忆,不动屏幕和外部世界。 */
internal object MemorySave : AgentTool {
    override val verb = Verb.MemorySave
    override val label = "记住一件事" // WOOWTECH fork: 上游没有说法,界面上露出工具名
    override val risk = Risk.Read
    override val def = ToolDef("memory_save",
        Prompts.tool("memory_save"),
        mapOf(
            "kind" to str("fact = about the user, preference = what the user likes, procedure = how the user wants a kind of task done.", listOf("fact", "preference", "procedure")),
            "content" to str("One sentence in the third person, at most 200 characters, e.g. 用户点外卖不要香菜."),
            "quote" to str("The user's exact words this is based on."),
            "keywords" to buildJsonObject {
                put("type", "array"); put("description", "Optional, up to 8 search words incl. synonyms.")
                put("items", buildJsonObject { put("type", "string") })
            },
        ), listOf("kind", "content", "quote"))

    override fun available(ctx: ToolContext) = memoryOn(ctx)

    override suspend fun execute(a: Args, ctx: ToolContext): ToolExecution {
        val kind = a.str("kind")!!.let { k -> MemoryKind.entries.find { it.name == k } ?: throw ArgError("kind", "must be fact, preference or procedure") }
        val content = a.str("content", max = MemoryStore.MAX_CONTENT)!!
        val quote = a.str("quote", max = 1000)!!
        val keywords = a.strList("keywords", 0, MemoryStore.MAX_KEYWORDS, itemMax = 30) ?: emptyList()
        val utterances = ctx.config.utterances!!
        // 引文要出自用户本次说的话;屏幕和网页上的字不能当成用户说的
        if (!utterances.contains(quote)) return fail("quote_not_from_user",
            Feedback["memory.quote_not_from_user"], recoverable = false)
        // 引文对上了,内容里的具体值(地址、号码、名字)也得是用户说过的,不能从屏幕上补
        if ((listOf(content) + keywords).any { utterances.unsupportedSpecifics(it, quote).isNotEmpty() }) return fail("content_not_from_user",
            Feedback["memory.content_not_from_user"], recoverable = false)
        val store = ctx.config.memory!!
        val added = store.add(kind, content, keywords, MemorySource("user_said", quote.trim(), ctx.config.conversationId, store.clock(),
            ctx.config.runSpec?.provenance?.origin?.name))
        added.getOrNull()?.let(ctx::noteSaved)
        return added.fold(
            onSuccess = { c -> ok { put("id", c.item.id); put("kind", c.item.kind.name); put("status", c.item.status.name) } },
            onFailure = { e ->
                when ((e as? MemoryRejected)?.code) {
                    "sensitive" -> fail("sensitive", Feedback["memory.sensitive"], recoverable = false)
                    "memory_full" -> fail("memory_full", Feedback["memory.full"], recoverable = false)
                    "unavailable" -> fail("memory_unavailable", Feedback["memory.unavailable"], recoverable = false)
                    "too_long" -> throw ArgError("content", "must be 1-${MemoryStore.MAX_CONTENT} characters")
                    else -> throw e
                }
            },
        )
    }
}
