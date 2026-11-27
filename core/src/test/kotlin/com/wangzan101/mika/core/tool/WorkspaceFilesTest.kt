package com.wangzan101.mika.core.tool

import com.wangzan101.mika.core.agent.AgentLoop
import com.wangzan101.mika.core.agent.FakeModel
import com.wangzan101.mika.core.agent.TaskState
import com.wangzan101.mika.core.cap.sandbox.FakeSandbox
import com.wangzan101.mika.core.cap.web.FakeWebPort
import com.wangzan101.mika.core.model.ModelReply
import com.wangzan101.mika.core.model.Part
import com.wangzan101.mika.core.model.StopReason
import com.wangzan101.mika.core.vision.ImageOps
import com.wangzan101.mika.core.vision.JvmTestImageOps
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.Base64
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream
import com.wangzan101.mika.core.assembly.toolDispatcher

private var seq = 0
private fun call(name: String, args: JsonObject) = Part.ToolCall("w${++seq}", name, args.toString())
private fun JsonObject.s(k: String) = this[k]!!.jsonPrimitive.content
private fun read(path: String) = call("read_file", buildJsonObject { put("path", path) })

/**
 * 商店版只有文件的工作区([com.wangzan101.mika.core.cap.sandbox.SandboxPort.runsCommands] 为 false):
 * 附件(照片、PDF、文字)要读得到,但不给任何执行命令、跑脚本的工具。
 */
class WorkspaceFilesTest {
    private val sb = FakeSandbox(runsCommands = false)
    private val inbox get() = File(sb.workspaceDir("conv"), "inbox").apply { mkdirs() }
    /** 商店版的样子:没有手机屏幕,只有内置浏览器和对话的工作区。 */
    private fun dispatcher(vision: Boolean = true, ops: ImageOps? = null) =
        toolDispatcher(visionEnabled = vision, web = FakeWebPort(), sandbox = sb, workspace = { "conv" }, imageOps = ops)

    @Test fun fileToolsAreOfferedWithoutCommandsOrScripts() = runTest {
        val d = dispatcher()
        val offered = d.offeredNow().map { it.name }.toSet()
        assertTrue(offered.toString(), offered.containsAll(setOf("read_file", "write_file", "search_files", "create_document", "share_file")))
        assertFalse(offered.toString(), "run_command" in offered || "run_bundled_script" in offered)
        assertFalse(d.scriptsOffered())
        assertEquals("unknown_tool", d.execute(call("run_command", buildJsonObject { put("command", "ls") })).content.s("error"))
        assertTrue(sb.runs.isEmpty())
        val prompt = d.promptSections(d.offeredNow()).joinToString("\n")
        assertTrue(prompt, "There is no command line here" in prompt)
        assertFalse(prompt, "Linux sandbox" in prompt)
        // 直接下载版的沙箱照旧:命令和文件工具都有
        val full = toolDispatcher(web = FakeWebPort(), sandbox = FakeSandbox(), workspace = { "conv" })
        assertTrue(full.definitions().any { it.name == "run_command" })
    }

    @Test fun createsAndDeliversDocumentsWithoutRunningCodeOrPreparingRuntime() = runTest {
        val d = dispatcher()
        val doc = kotlinx.serialization.json.Json.parseToJsonElement("""{"title":"上架文件","sections":[{"type":"table","columns":["項目","內容"],"rows":[["中文","<script>&"],["公式","=1+1"]]}]}""")
        for (format in listOf("html", "csv")) {
            val created = d.execute(call("create_document", buildJsonObject { put("format", format); put("document", doc) })).content
            assertEquals(created.toString(), "true", created.s("ok"))
            val path = created.s("path")
            val file = File(sb.workspaceDir("conv"), path.removePrefix("/workspace/"))
            assertTrue(file.isFile)
            if (format == "html") assertTrue(file.readText().contains("&lt;script&gt;&amp;"))
            if (format == "csv") assertTrue(file.readText().contains("'=1+1"))
            val shared = d.execute(call("share_file", buildJsonObject { put("path", path) })).content
            assertEquals(shared.toString(), "true", shared.s("ok"))
            assertEquals(file.canonicalFile, sb.shared.last().first.canonicalFile)
        }
        assertEquals(2, sb.shared.size)
        assertTrue(sb.runs.isEmpty())
        assertEquals(0, sb.waits)
        assertEquals(0, sb.prepares)
        assertFalse(d.offeredNow().any { it.name.startsWith("phone_") || it.name.startsWith("root_") })
    }

    @Test fun attachedPhotoReachesTheModelAsAnImage() = runTest {
        val photo = byteArrayOf(0xFF.toByte(), 0xD8.toByte(), 0xFF.toByte(), 0xE0.toByte(), 1, 2, 3, 4)
        File(inbox, "cat.jpg").writeBytes(photo)
        val m = FakeModel(
            ModelReply(listOf(read("/workspace/inbox/cat.jpg")), StopReason.ToolUse, null),
            com.wangzan101.mika.core.testing.answerReply("A cat on a sofa."),
        )
        val end = AgentLoop(m, dispatcher(), "BASE").run("What is in this photo?\n附件:/workspace/inbox/cat.jpg(8 B)")
        assertTrue(end.toString(), end is TaskState.Succeeded)
        assertTrue("read_file" in m.offeredTools[0])
        assertFalse("run_command" in m.offeredTools[0])
        val images = m.requests[1].flatMap { it.parts }.filterIsInstance<Part.Image>()
        assertEquals(1, images.size)
        assertEquals("image/jpeg", images[0].mime)
        assertArrayEquals(photo, Base64.getDecoder().decode(images[0].pngBase64))
    }

    @Test fun largeOrUnusualPhotosAreScaledDownFirst() = runTest {
        val big = JvmTestImageOps.encode(3000, 2000) { x, y -> (x + y) % 256 }
        File(inbox, "photo.heic").writeBytes(big)
        val r = dispatcher(ops = JvmTestImageOps).execute(read("inbox/photo.heic"))
        assertEquals("true", r.content.s("ok"))
        assertEquals("image/heic", r.content.s("type"))
        assertEquals(1280 to 853, JvmTestImageOps.size(r.image!!))
        // 看不了图的模型:只说是图片
        val blind = dispatcher(vision = false, ops = JvmTestImageOps).execute(read("inbox/photo.heic"))
        assertEquals("not_text", blind.content.s("error"))
        assertNull(blind.image)
    }

    @Test fun documentsAreReadAsTextInParts() = runTest {
        val content = "BT /F1 12 Tf 72 720 Td (Invoice 2026-11) Tj 0 -14 Td (Total NT$ 1,200) Tj ET".toByteArray(Charsets.ISO_8859_1)
        val pdf = ("%PDF-1.4\n1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n" +
            "2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n" +
            "3 0 obj\n<< /Type /Page /Parent 2 0 R /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>\nendobj\n" +
            "4 0 obj\n<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>\nendobj\n" +
            "5 0 obj\n<< /Length ${content.size} >>\nstream\n").toByteArray(Charsets.ISO_8859_1) + content +
            "\nendstream\nendobj\ntrailer\n<< /Root 1 0 R >>\n%%EOF\n".toByteArray(Charsets.ISO_8859_1)
        File(inbox, "invoice.pdf").writeBytes(pdf)
        val d = dispatcher()
        val whole = d.execute(read("/workspace/inbox/invoice.pdf")).content
        assertEquals("true", whole.s("ok"))
        assertEquals("application/pdf", whole.s("type"))
        assertEquals("1", whole.s("pages"))
        assertEquals("--- page 1 ---\nInvoice 2026-11\nTotal NT$ 1,200", whole.s("content"))
        assertEquals("true", whole.s("eof"))
        // 分段读:offset/limit 按文字的字节算
        val head = d.execute(call("read_file", buildJsonObject { put("path", "inbox/invoice.pdf"); put("limit", 15) })).content
        assertEquals("--- page 1 ---\n", head.s("content"))
        assertEquals("15", head.s("nextOffset"))
        val rest = d.execute(call("read_file", buildJsonObject { put("path", "inbox/invoice.pdf"); put("offset", 15) })).content
        assertEquals("Invoice 2026-11\nTotal NT$ 1,200", rest.s("content"))

        val docx = ByteArrayOutputStream().also { out ->
            ZipOutputStream(out).use { z ->
                z.putNextEntry(ZipEntry("word/document.xml"))
                z.write("<w:document xmlns:w=\"w\"><w:body><w:p><w:r><w:t>會議紀錄</w:t></w:r></w:p></w:body></w:document>".toByteArray())
                z.closeEntry()
            }
        }.toByteArray()
        File(inbox, "notes.docx").writeBytes(docx)
        assertEquals("會議紀錄", d.execute(read("inbox/notes.docx")).content.s("content"))

        File(inbox, "old.doc").writeBytes(ByteArray(16))
        assertEquals("document_old_format", d.execute(read("inbox/old.doc")).content.s("error"))
    }

    @Test fun directDownloadWorkspaceStillReturnsDocumentsAsBinary() = runTest {
        val full = FakeSandbox()
        File(full.workspaceDir("conv"), "a.pdf").writeBytes(byteArrayOf(0x25, 0x50, 0x44, 0x46, 0, -1, -2, 7))
        val r = toolDispatcher(web = FakeWebPort(), sandbox = full, workspace = { "conv" }).execute(read("a.pdf")).content
        assertEquals("not_text", r.s("error"))
    }
}
