package com.wangzan101.mika.document

import android.content.Intent
import android.annotation.TargetApi
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Typeface
import android.graphics.pdf.PdfDocument
import android.graphics.pdf.PdfRenderer
import android.os.ParcelFileDescriptor
import android.os.Build
import android.webkit.WebView
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.filters.SdkSuppress
import com.wangzan101.mika.R
import com.wangzan101.mika.core.document.DocumentFormat
import com.wangzan101.mika.core.document.DocumentModel
import com.wangzan101.mika.core.document.DocumentSection
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import java.io.File
import java.util.UUID

/** Device/emulator checks only; not evidence of physical-device acceptance. */
class DocumentDeviceTest {
    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val context get() = instrumentation.targetContext

    @Test
    @SdkSuppress(minSdkVersion = 35)
    @TargetApi(35)
    fun documentFontKeepsCJKAndRadicalCodePointsDistinct() {
        val typeface = DocumentPdfFont.get(context)
        val expected = "CJK_中文_RADICAL_⽂_END"
        val file = File(context.cacheDir, "font-control-${UUID.randomUUID()}.pdf")
        val pdf = PdfDocument()
        try {
            for (style in listOf(Typeface.NORMAL, Typeface.BOLD)) {
                val page = pdf.startPage(PdfDocument.PageInfo.Builder(595, 842, style + 1).create())
                val paint = Paint().apply { textSize = 16f; this.typeface = Typeface.create(typeface, style) }
                page.canvas.drawText(expected, 36f, 60f, paint)
                pdf.finishPage(page)
            }
            file.outputStream().use(pdf::writeTo)
            PdfRenderer(ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)).use { renderer ->
                for (index in 0 until renderer.pageCount) renderer.openPage(index).use { page ->
                    assertEquals(expected, page.textContents.joinToString("") { it.text }.trim())
                }
            }
        } finally {
            val evidence = File(context.filesDir, "document-test-evidence").apply { mkdirs() }
            if (file.exists()) file.copyTo(File(evidence, "unicode-font.pdf"), overwrite = true)
            pdf.close(); file.delete()
        }
    }

    @Test fun longChineseTableProducesMultiplePagesWithVisibleContentOnLastPage() {
        val file = File(context.cacheDir, "pdf-test-${UUID.randomUUID()}.pdf")
        val tail = "最後一行中文"
        val model = DocumentModel("中文報告", "zh-Hant", listOf(
            DocumentSection.Table(listOf("項目", "內容"), listOf(listOf("測試", (1..500).joinToString("\n") { "第 $it 行，完整保存。" } + "\n" + tail))),
            DocumentSection.Paragraph(tail.repeat(40)),
        ))
        try {
            file.outputStream().use { DocumentPdf(context, model).write(it) }
            PdfRenderer(ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)).use { renderer ->
                assertTrue(renderer.pageCount > 8)
                renderer.openPage(renderer.pageCount - 1).use { page ->
                    val bitmap = Bitmap.createBitmap(page.width, page.height, Bitmap.Config.ARGB_8888)
                    try {
                        bitmap.eraseColor(Color.WHITE)
                        page.render(bitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                        var ink = 0
                        // Exclude footer: the final page must contain document content, not only a page number.
                        for (y in 36 until 802) for (x in 36 until 559) if (bitmap.getPixel(x, y) != Color.WHITE) ink++
                        assertTrue("Final content page must not be blank", ink > 100)
                    } finally { bitmap.recycle() }
                }
            }
        } finally { file.delete() }
    }

    /** Text extraction was added in API 35; older devices record a skipped test, never a pass.
     * https://developer.android.com/reference/android/graphics/pdf/PdfRenderer.Page#getTextContents()
     */
    @Test
    @SdkSuppress(minSdkVersion = 35)
    @TargetApi(35)
    fun api35ExtractedTextPreservesTallHeadersCellTailsAndCrossPanelRowIdentity() {
        assumeTrue("PDF text extraction requires API 35+", Build.VERSION.SDK_INT >= 35)
        val file = File(context.cacheDir, "pdf-text-test-${UUID.randomUUID()}.pdf")
        val evidence = File(context.filesDir, "document-test-evidence")
        // Keep other cases' evidence, regardless of JUnit execution order.
        File(evidence, "pagination.pdf").delete()
        File(evidence, "extracted.txt").delete()
        val extractedPages = mutableListOf<String>()
        val headerLines = (1..180).map { "欄位說明${it.toString().padStart(3, '0')}" }
        val cellLines = (1..240).map { "CELL_LINE_${it.toString().padStart(3, '0')}" }
        val headerTail = "HEADER_LAST_9Q"
        val cellTail = "CELL_LAST_7Z中文"
        val table = DocumentSection.Table(
            listOf("名稱", (headerLines + headerTail).joinToString("\n"), "第三欄", "第四欄", "第五欄", "第六欄"),
            listOf(
                listOf("ROW_ONE", (cellLines + cellTail).joinToString("\n"), "ONE_C3", "ONE_C4", "ONE_C5", "ONE_C6"),
                listOf("ROW_TWO", "TWO_C2", "TWO_C3", "TWO_C4", "TWO_C5", "TWO_C6"),
            ),
        )
        try {
            file.outputStream().use { DocumentPdf(context, DocumentModel("文字完整性", "zh-Hant", listOf(table))).write(it) }
            val pages = PdfRenderer(ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)).use { renderer ->
                assertTrue("Fixture must exercise pagination", renderer.pageCount > 5)
                (0 until renderer.pageCount).map { index ->
                    renderer.openPage(index).use { page ->
                        val text = page.textContents.joinToString("\n") { it.text }
                        extractedPages += "PAGE ${index + 1}\n$text"
                        text.filterNot(Char::isWhitespace)
                    }
                }
            }
            val allText = pages.joinToString("")
            for (expected in headerLines + cellLines + listOf(headerTail, cellTail, "ROW_ONE", "ROW_TWO",
                "ONE_C3", "ONE_C4", "ONE_C5", "ONE_C6", "TWO_C2", "TWO_C3", "TWO_C4", "TWO_C5", "TWO_C6")) {
                assertTrue("Missing exported text: $expected", allText.contains(expected))
            }
            val continuedPages = pages.filter { it.contains("CELL_LINE_") }
            assertTrue("Long cell must continue across pages", continuedPages.size > 2)
            continuedPages.forEach { text ->
                assertTrue("Continuation must identify its column panel", text.contains("欄1–4"))
                assertTrue("Continuation must repeat the short header ID", text.contains("[2]"))
                assertTrue("Continuation must repeat its row number", text.contains("#1"))
            }
            val lastPanel = pages.single { it.contains("ONE_C5") }
            assertTrue(lastPanel.contains("欄5–6"))
            assertTrue(lastPanel.contains("#1"))
            assertTrue(lastPanel.contains("#2"))
        } finally {
            evidence.mkdirs()
            if (file.exists()) file.copyTo(File(evidence, "pagination.pdf"), overwrite = true)
            File(evidence, "extracted.txt").writeText(extractedPages.joinToString("\n\n"))
            file.delete()
        }
    }

    @Test fun staticPreviewHasNoScriptFileContentOrNetworkAccess() {
        instrumentation.runOnMainSync {
            val view = WebView(context)
            try {
                StaticDocumentPreview.restrict(view)
                assertFalse(view.settings.javaScriptEnabled)
                assertFalse(view.settings.allowFileAccess)
                assertFalse(view.settings.allowContentAccess)
                assertFalse(view.settings.domStorageEnabled)
                assertTrue(view.settings.blockNetworkLoads)
                assertTrue(view.webViewClient.shouldOverrideUrlLoading(view, "https://example.com"))
                val response = view.webViewClient.shouldInterceptRequest(view, "file:///etc/passwd")
                assertEquals(-1, response!!.data.read())
            } finally { view.destroy() }
        }
    }

    @Test fun providerShareAndCancelledSavePreserveTheFileWithoutClaimingDelivery() = runBlocking {
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
        val model = DocumentModel("分享測試", "zh-Hant", listOf(DocumentSection.Paragraph("內容")))
        val document = DocumentFiles.generate(context, model, DocumentFormat.HTML, null)
        try {
            context.contentResolver.openInputStream(document.uri)!!.use { assertTrue(it.read() >= 0) }
            try {
                context.contentResolver.openFileDescriptor(document.uri, "w")?.close()
                fail("Generated content URI must be read-only")
            } catch (_: SecurityException) { }
            val chooser = DocumentFiles.shareIntent(document)
            @Suppress("DEPRECATION") val send = chooser.getParcelableExtra<Intent>(Intent.EXTRA_INTENT)!!
            assertEquals("text/html", send.type)
            assertEquals(document.uri, send.clipData!!.getItemAt(0).uri)
            assertEquals(Intent.FLAG_GRANT_READ_URI_PERMISSION, send.flags and Intent.FLAG_GRANT_READ_URI_PERMISSION)
            withContext(Dispatchers.Main) {
                val session = DocumentExportSession(scope, "內容", "分享測試", "zh-Hant", DocumentFormat.HTML)
                session.generateWith { _, _, _ -> document }
                // Parsing runs on Default; wait below without blocking the main thread.
                while (session.busy) kotlinx.coroutines.delay(10)
                session.beginSave()
                session.saveResult(context, null)
                assertEquals(R.string.document_save_cancelled, session.status)
                assertTrue(document.file.exists())
                session.shareOpened()
                assertEquals(R.string.document_share_opened, session.status)
                assertTrue(document.file.exists())
            }
        } finally { scope.cancel(); document.file.parentFile?.deleteRecursively() }
    }
}
