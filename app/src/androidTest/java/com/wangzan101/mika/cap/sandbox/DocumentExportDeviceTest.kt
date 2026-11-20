package com.wangzan101.mika.cap.sandbox

import com.wangzan101.mika.document.DocumentPdf

import android.net.Uri
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.wangzan101.mika.core.document.Document
import com.wangzan101.mika.ui.viewer.FileViewer
import com.wangzan101.mika.ui.viewer.ViewerKind
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

@RunWith(AndroidJUnit4::class)
class DocumentExportDeviceTest {
    @Test fun generatedFormatsExportReadableAttachments() = runBlocking {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val dir = File(context.cacheDir, "document-export-test").apply { mkdirs() }
        val doc = Document("文件驗收", listOf(Document.Section("table", columns=listOf("中文", "數值"),
            rows=listOf(listOf("逗號,雙引號\"換\n行", "00123"), listOf("公式", "=1+1")))))
        val exports = listOf("html" to doc.html().toByteArray(), "csv" to doc.csv(null).toByteArray(), "pdf" to DocumentPdf.render(doc))
        try {
            for ((extension, bytes) in exports) {
                if (extension != "pdf") File(context.cacheDir, "document-acceptance.$extension").writeBytes(bytes)
                val file = File(dir, "驗收.$extension").apply { writeBytes(bytes) }
                val card = AndroidFdSys.gate.openRead(dir, file.name).use { ShareExporter(context).export(it, file.name) }
                val uri = Uri.parse(card.uri)
                try {
                    assertEquals(bytes.size.toLong(), card.size)
                    context.contentResolver.openInputStream(uri)!!.use { assertArrayEquals(bytes, it.readBytes()) }
                    val kind = FileViewer.kindOf(context, uri, card.name)
                    assertNotNull("Missing viewer for $extension", kind)
                    if (extension == "pdf") assertEquals(ViewerKind.Pdf, kind)
                    if (extension == "html") assertEquals(ViewerKind.Html, kind)
                } finally { context.contentResolver.delete(uri, null, null) }
            }
        } finally { dir.deleteRecursively() }
    }
}
