package com.wangzan101.mika.document

import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.pdf.PdfRenderer
import android.os.ParcelFileDescriptor
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.wangzan101.mika.core.document.Document
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

@RunWith(AndroidJUnit4::class)
class DocumentPdfTest {
    @Test fun chineseMultiPageDocumentRendersAllPages() {
        val document = Document("繁體中文文件驗收", listOf(
            Document.Section("heading", "摘要與特殊符號 < > &"),
            Document.Section("paragraph", "中文測試 ABC 123，第一段。\n".repeat(300)),
            Document.Section("table", columns=listOf("名稱", "備註"), rows=listOf(
                listOf("項目一", "跨頁內容，保持完整。".repeat(200)), listOf("最後一列", "文件結束 END-OF-DOCUMENT")))
        ))
        val bytes = DocumentPdf.render(document)
        assertTrue(bytes.toString(Charsets.ISO_8859_1).startsWith("%PDF-"))
        val file = File(InstrumentationRegistry.getInstrumentation().targetContext.cacheDir, "document-acceptance.pdf")
        file.writeBytes(bytes)
        PdfRenderer(ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)).use { renderer ->
            assertTrue(renderer.pageCount > 5)
            for (i in 0 until renderer.pageCount) renderer.openPage(i).use { page ->
                val bitmap = Bitmap.createBitmap(page.width, page.height, Bitmap.Config.ARGB_8888)
                bitmap.eraseColor(Color.WHITE)
                page.render(bitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                var ink = 0
                for (y in 30 until 795 step 2) for (x in 30 until 565 step 2)
                    if (bitmap.getPixel(x,y) != Color.WHITE) ink++
                assertTrue("page $i is blank", ink > 10)
                bitmap.recycle()
            }
        }
    }

    @Test fun hugeDocumentFailsInsteadOfSilentlyTruncating() {
        val doc = Document("Too long", List(201) { Document.Section("paragraph", "line\n".repeat(60)) })
        assertThrows(IllegalArgumentException::class.java) { DocumentPdf.render(doc) }
    }
}
