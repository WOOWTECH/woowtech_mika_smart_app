package com.wangzan101.mika.document

import android.graphics.Color
import android.graphics.Paint
import android.graphics.Typeface
import android.graphics.pdf.PdfDocument
import android.text.Layout
import android.text.StaticLayout
import android.text.TextPaint
import com.wangzan101.mika.core.document.DocumentException
import com.wangzan101.mika.core.document.DocumentLimits
import com.wangzan101.mika.core.document.DocumentModel
import com.wangzan101.mika.core.document.DocumentProblem
import com.wangzan101.mika.core.document.DocumentSection
import java.io.OutputStream
import java.util.Locale

/** Native, searchable text with Android font fallback (including Chinese). No WebView/print service. */
internal class DocumentPdf(private val model: DocumentModel, private val checkActive: () -> Unit = {}) {
    private val pdf = PdfDocument()
    private var page: PdfDocument.Page? = null
    private var pageCount = 0
    private var y = TOP
    private val border = Paint().apply { color = Color.LTGRAY; style = Paint.Style.STROKE; strokeWidth = 0.5f }
    private val footer = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.DKGRAY; textSize = 9f }

    fun write(output: OutputStream) {
        try {
            DocumentLimits.validate(model)
            newPage()
            text(model.title, 22f, true)
            for (section in model.sections) {
                checkActive()
                when (section) {
                    is DocumentSection.Heading -> text(section.text, (20 - section.level).toFloat(), true)
                    is DocumentSection.Paragraph -> text(section.text)
                    is DocumentSection.ListSection -> section.items.forEachIndexed { i, item ->
                        text((if (section.ordered) "${i + 1}. " else "• ") + item)
                    }
                    is DocumentSection.Table -> table(section)
                }
            }
            finishPage()
            pdf.writeTo(output)
        } finally {
            finishPage()
            pdf.close()
        }
    }

    private fun layout(value: String, width: Int, size: Float, bold: Boolean = false): StaticLayout {
        val paint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.BLACK
            textSize = size
            typeface = if (bold) Typeface.create("sans-serif", Typeface.BOLD) else Typeface.create("sans-serif", Typeface.NORMAL)
            textLocale = Locale.forLanguageTag(model.language)
        }
        return StaticLayout.Builder.obtain(value, 0, value.length, paint, width)
            .setAlignment(Layout.Alignment.ALIGN_NORMAL).setIncludePad(true)
            .setLineSpacing(2f, 1f).setBreakStrategy(Layout.BREAK_STRATEGY_HIGH_QUALITY).build()
    }

    private fun text(value: String, size: Float = 11f, bold: Boolean = false) {
        row(listOf(layout(value, WIDTH.toInt(), size, bold)), grid = false)
        y += 8f
    }

    /** Wide tables use consecutive column bands so no column is squeezed away or dropped. */
    private fun table(table: DocumentSection.Table) {
        for (start in table.columns.indices step 4) {
            val end = minOf(start + 4, table.columns.size)
            val wide = table.columns.size > 4
            val width = WIDTH / (end - start + if (wide) 1 else 0)
            val textWidth = (width - 12).toInt()
            val columnRange = (if (model.language.startsWith("zh")) "欄" else "Columns") + " ${start + 1}–$end"
            fun headers(values: List<String>) =
                (if (wide) listOf("#") + values else values).map { layout(it, textWidth, 10f, true) }
            var header = headers(table.columns.subList(start, end))
            if (header.maxOf { it.height } > 160) {
                // Preserve every header character in a numbered legend. The short column IDs below
                // can then repeat on every data page without crowding out the rows.
                if (wide) text(columnRange, 11f, true)
                for (column in start until end) text("[${column + 1}] ${table.columns[column]}", 10f, true)
                header = headers((start until end).map { "[${it + 1}]" })
            }
            fun repeatHeader() {
                val labelHeight = if (wide) layout(columnRange, WIDTH.toInt(), 11f, true).height + 8f else 0f
                if (BOTTOM - y < labelHeight + header.maxOf { it.height } + 12f + 28f) newPage()
                if (wide) text(columnRange, 11f, true)
                row(header, grid = true)
            }
            repeatHeader()
            for ((rowIndex, values) in table.rows.withIndex()) {
                checkActive()
                val data = values.subList(start, end)
                val cells = (if (wide) listOf("#${rowIndex + 1}") + data else data).map { layout(it, textWidth, 10f) }
                row(cells, grid = true, onPage = ::repeatHeader, repeatFirstCell = wide)
            }
            y += 12f
        }
    }

    /** Split each cell at actual laid-out line boundaries. Even a cell taller than a page is complete. */
    private fun row(layouts: List<StaticLayout>, grid: Boolean, onPage: (() -> Unit)? = null, repeatFirstCell: Boolean = false) {
        val starts = IntArray(layouts.size)
        val pad = if (grid) 6f else 0f
        val width = WIDTH / layouts.size
        fun unfinished() = layouts.indices.any { (!repeatFirstCell || it > 0) && starts[it] < layouts[it].lineCount }
        fun continuePage() {
            newPage()
            onPage?.invoke()
            // Reprint the row number on every fragment, including after its original cell is spent.
            if (repeatFirstCell) starts[0] = 0
        }
        while (unfinished()) {
            checkActive()
            val available = BOTTOM - y - pad * 2
            val ends = IntArray(layouts.size) { index ->
                val layout = layouts[index]
                val start = starts[index]
                var end = start
                if (start < layout.lineCount) {
                    val top = layout.getLineTop(start)
                    while (end < layout.lineCount && layout.getLineBottom(end) - top <= available) end++
                }
                end
            }
            if (ends.indices.none { (!repeatFirstCell || it > 0) && ends[it] > starts[it] }) { continuePage(); continue }
            val height = layouts.indices.maxOf { index ->
                if (ends[index] == starts[index]) 0 else layouts[index].getLineBottom(ends[index] - 1) - layouts[index].getLineTop(starts[index])
            }.toFloat() + pad * 2
            val canvas = checkNotNull(page).canvas
            layouts.forEachIndexed { index, layout ->
                val x = LEFT + index * width
                if (grid) canvas.drawRect(x, y, x + width, y + height, border)
                if (ends[index] > starts[index]) {
                    canvas.save()
                    canvas.clipRect(x + pad, y + pad, x + width - pad, y + height - pad)
                    canvas.translate(x + pad, y + pad - layout.getLineTop(starts[index]))
                    layout.draw(canvas)
                    canvas.restore()
                }
                starts[index] = ends[index]
            }
            y += height
            if (unfinished()) continuePage()
        }
    }

    private fun newPage() {
        checkActive()
        finishPage()
        if (pageCount >= DocumentLimits.MAX_PDF_PAGES) throw DocumentException(DocumentProblem.TooLarge)
        page = pdf.startPage(PdfDocument.PageInfo.Builder(595, 842, ++pageCount).create())
        y = TOP
    }

    private fun finishPage() {
        page?.let {
            it.canvas.drawText(pageCount.toString(), LEFT, 822f, footer)
            pdf.finishPage(it)
            page = null
        }
    }

    private companion object { const val LEFT = 36f; const val TOP = 36f; const val BOTTOM = 802f; const val WIDTH = 523f }
}
