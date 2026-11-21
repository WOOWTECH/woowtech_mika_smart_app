package com.wangzan101.mika.document

import android.graphics.pdf.PdfRenderer
import android.net.Uri
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.wangzan101.mika.BuildConfig
import com.wangzan101.mika.cap.sandbox.AndroidSandbox
import com.wangzan101.mika.cap.sandbox.SandboxDirs
import com.wangzan101.mika.cap.web.LazyWebPort
import com.wangzan101.mika.chat.SharedFile
import com.wangzan101.mika.core.action.ActionExecutor
import com.wangzan101.mika.core.action.ActionOutcome
import com.wangzan101.mika.core.action.ActionRecorder
import com.wangzan101.mika.core.action.Origin
import com.wangzan101.mika.core.assembly.toolDispatcher
import com.wangzan101.mika.core.cap.sandbox.SandboxStatus
import com.wangzan101.mika.core.guard.OperationGuards
import com.wangzan101.mika.core.model.Part
import com.wangzan101.mika.core.record.RunSink
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.util.UUID

/** Real Play file-only port -> shared tool dispatcher -> generated files -> Android attachment URIs. */
@RunWith(AndroidJUnit4::class)
class StoreDocumentWorkflowTest {
    @Test fun allFormatsReachReadableAttachmentsWithoutExecutableRuntime() = runBlocking {
        assumeTrue(BuildConfig.PLAY_EDITION)
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val workspace = "store-document-test-${UUID.randomUUID()}"
        val cards = mutableListOf<SharedFile>()
        val port = AndroidSandbox.filesOnly(context, onShared = { cards.add(it) })
        // Play tasks retain an in-app browser surface, initialized only if a tool needs it.
        // Document generation must not initialize that browser or navigate anywhere.
        val web = LazyWebPort { error("Document generation must not initialize a browser") }
        val dispatcher = toolDispatcher(web = web, sandbox = port, workspace = { workspace })
        val executor = ActionExecutor(dispatcher, OperationGuards(), null, gate = {},
            recorder = ActionRecorder(RunSink.NONE))
        var sequence = 0
        suspend fun execute(name: String, args: JsonObject): JsonObject {
            val result = executor.run(Part.ToolCall("store-doc-${++sequence}", name, args.toString()), Origin.Model(sequence))
            assertTrue(result.toString(), result is ActionOutcome.Ran)
            return (result as ActionOutcome.Ran).exec.content
        }
        val document = Json.parseToJsonElement("""{"title":"上架文件驗收","sections":[{"type":"paragraph","text":"繁體中文 ABC 123 <>&"},{"type":"table","columns":["項目","數量","備註"],"rows":[["測試A","2","一般"],["測試B","3","含逗號,與引號"]]}]}""")
        try {
            assertFalse(port.runsCommands)
            assertTrue(port.status() is SandboxStatus.Ready)
            val offered = dispatcher.offeredNow().map { it.name }.toSet()
            assertTrue("create_document" in offered)
            assertFalse(offered.any { it in setOf("run_command", "run_bundled_script") || it.startsWith("phone_") || it.startsWith("root_") })
            val denied = execute("run_command", buildJsonObject { put("command", "echo must-not-run") })
            assertEquals("unknown_tool", denied["error"]?.jsonPrimitive?.content)
            for (format in listOf("html", "pdf", "csv")) {
                val result = execute("create_document", buildJsonObject { put("format", format); put("document", document) })
                assertEquals(result.toString(), "true", result["ok"]?.jsonPrimitive?.content)
                val path = result["path"]!!.jsonPrimitive.content
                val file = File(SandboxDirs(context).workspace(workspace), path.removePrefix("/workspace/"))
                assertTrue(file.isFile)
                val bytes = file.readBytes()
                val shared = execute("share_file", buildJsonObject { put("path", path) })
                assertEquals(shared.toString(), "true", shared["ok"]?.jsonPrimitive?.content)
                val card = cards.last()
                val uri = Uri.parse(card.uri)
                context.contentResolver.openInputStream(uri)!!.use { assertArrayEquals(bytes, it.readBytes()) }
                assertEquals(bytes.size.toLong(), card.size)
                if (format == "pdf") {
                    context.contentResolver.openFileDescriptor(uri, "r")!!.use { fd ->
                        PdfRenderer(fd).use { assertTrue(it.pageCount > 0) }
                    }
                }
            }
            assertEquals(3, cards.size)
        } finally {
            cards.forEach { context.contentResolver.delete(Uri.parse(it.uri), null, null) }
            SandboxDirs(context).workspace(workspace).deleteRecursively()
        }
    }
}
