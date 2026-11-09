package com.wangzan101.mika.core.cap.sandbox

import com.wangzan101.mika.core.guard.GuardVerdict
import com.wangzan101.mika.core.guard.Severity
import com.wangzan101.mika.core.guard.actionSignature
import java.security.MessageDigest
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.longOrNull
import kotlinx.serialization.json.put

/** Evidence of repeated reads, not repeated commands. No output or argument text is retained.
 *
 * OffScreenGuard receives neither ToolInfo nor ToolExecution.changed. Commands/scripts are declared
 * Risk.Write, so only a deliberately small shell grammar qualifies. Unknown operations break the
 * streak: they may write, poll, or otherwise make progress. This is not a shell effect analyser.
 */
internal class SandboxReadProgress {
    private val fingerprints = linkedMapOf<String, String>()
    private var duplicates = 0

    fun result(tool: String, args: JsonObject, content: JsonObject): GuardVerdict? {
        val payload = payload(tool, args, content)
        if (payload == null) {
            reset()
            return null
        }
        // Execution timing is not evidence; file offsets, size, eof and actual output are.
        val key = digest(actionSignature(tool, JsonObject(args - "timeoutSec")))
        val value = digest(actionSignature("read", payload))
        val previous = fingerprints[key]
        if (previous != null && previous != value) reset()
        duplicates = if (previous == value) (duplicates + 1).coerceAtMost(STOP_DUPLICATES) else 0
        fingerprints.remove(key)
        fingerprints[key] = value
        if (fingerprints.size > MAX_FINGERPRINTS) fingerprints.remove(fingerprints.keys.first())
        if (duplicates < WARN_DUPLICATES) return null
        val severity = if (duplicates >= STOP_DUPLICATES) Severity.Stop else Severity.Warn
        return GuardVerdict("sandbox_no_progress", severity, buildJsonObject {
            put("tool", tool)
            put("duplicateReadCount", duplicates)
            put("reason", "Successful reads keep returning previously seen, identical content without new evidence.")
            put("hint", HINT)
        }, nudge = HINT.takeIf { severity == Severity.Warn })
    }

    private fun reset() {
        fingerprints.clear()
        duplicates = 0
    }

    private fun payload(tool: String, args: JsonObject, content: JsonObject): JsonObject? {
        if (content["ok"] != JsonPrimitive(true)) return null
        if (listOf("outputTruncated", "truncated", "timedOut", "killedBySystem").any {
                (content[it] as? JsonPrimitive)?.booleanOrNull == true
            } || ((content["droppedBytes"] as? JsonPrimitive)?.longOrNull ?: 0) > 0) return null
        when (tool) {
            RunCommand.name -> {
                if (transientPath(args.text("cwd").orEmpty())) return null
                if (!simpleRead(args.text("command") ?: return null)) return null
                if (content.text("output") == null) return null
            }
            ReadFile.name -> {
                if (transientPath(args.text("path") ?: return null)) return null
                // Images have only metadata here: identical metadata does not prove identical pixels.
                if (content.text("content") == null) return null
            }
            SearchFiles.name -> {
                if (transientPath(args.text("path").orEmpty())) return null
                if (content["matches"] !is kotlinx.serialization.json.JsonArray) return null
            }
            else -> return null
        }
        // Keep all semantic fields, including ls timestamps. Stripping timestamps could hide a
        // genuine external write. Per-execution duration and advisory notes are nondeterministic.
        // The dispatcher adds moreTools only when a folded group first opens; it is not read data.
        return JsonObject(content - setOf("durationMs", "hint", "networkNote", "moreTools"))
    }

    private fun simpleRead(command: String): Boolean {
        // Only these two separators are accepted, and every segment must qualify independently.
        // Empty segments reject malformed chains; all other shell syntax fails SIMPLE_WORD.
        // Do not trim newlines: they are shell syntax, not whitespace in this limited grammar.
        return command.split(Regex(";|&&")).all(::simpleReadSegment)
    }

    private fun simpleReadSegment(command: String): Boolean {
        val words = command.trim(' ', '\t').split(Regex("[ \\t]+"))
        if (words.any { !SIMPLE_WORD.matches(it) || transientPath(it) }) return false
        return when (words.firstOrNull()) {
            "pwd" -> words.size == 1
            "ls", "cat", "head", "wc" -> true
            else -> false
        }
    }

    private fun transientPath(path: String): Boolean =
        listOf("/proc", "/sys", "/dev").any { path == it || path.startsWith("$it/") } ||
            POLLING_PATH.containsMatchIn(path)

    private fun JsonObject.text(key: String): String? =
        (this[key] as? JsonPrimitive)?.takeIf { it.isString }?.content

    private fun digest(value: String): String = MessageDigest.getInstance("SHA-256")
        .digest(value.toByteArray(Charsets.UTF_8)).joinToString("") { "%02x".format(it) }

    companion object {
        private const val MAX_FINGERPRINTS = 16
        private const val WARN_DUPLICATES = 3
        private const val STOP_DUPLICATES = 6
        private val SIMPLE_WORD = Regex("[A-Za-z0-9_./:@%+=,*?-]+")
        private val POLLING_PATH = Regex("(^|[/_.-])(status|progress|health|heartbeat|logs?|pid|lock)([/_.-]|$)", RegexOption.IGNORE_CASE)
        private const val HINT = "Reuse the evidence already read and produce the requested result, or inspect a different source/range. " +
            "If waiting for an external change, use a bounded wait/poll operation. If blocked, explain the blocker and end_not_done."
    }
}
