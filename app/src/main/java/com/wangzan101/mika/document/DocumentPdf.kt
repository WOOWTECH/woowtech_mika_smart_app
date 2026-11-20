package com.wangzan101.mika.document

import android.graphics.Color
import android.graphics.Paint
import android.graphics.Typeface
import android.graphics.pdf.PdfDocument
import android.text.Layout
import android.text.StaticLayout
import android.text.TextPaint
import com.wangzan101.mika.core.document.Document
import java.io.ByteArrayOutputStream

/** A4 text layout using Android's installed fonts (including CJK fallback). */
internal object DocumentPdf {
    fun render(document: Document): ByteArray {
        val pdf = PdfDocument()
        var page: PdfDocument.Page? = null
        var y = 40f
        var count = 0
        val paint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.BLACK }
        fun finish() {
            page?.let {
                val footer = Paint(Paint.ANTI_ALIAS_FLAG).apply { textSize = 9f; color = Color.DKGRAY }
                it.canvas.drawText(count.toString(), 290f, 820f, footer)
                pdf.finishPage(it)
            }
            page = null
        }
        fun nextPage() {
            finish()
            require(count < 200) { "PDF exceeds 200 pages; split the document" }
            page = pdf.startPage(PdfDocument.PageInfo.Builder(595, 842, ++count).create())
            y = 40f
        }
        fun block(text: String, size: Float = 12f, bold: Boolean = false) {
            paint.textSize = size
            paint.typeface = if (bold) Typeface.DEFAULT_BOLD else Typeface.DEFAULT
            val layout = StaticLayout.Builder.obtain(text, 0, text.length, paint, 515)
                .setAlignment(Layout.Alignment.ALIGN_NORMAL).setIncludePad(true)
                .setLineSpacing(3f, 1f).build()
            var line = 0
            while (line < layout.lineCount) {
                if (page == null || y + layout.getLineBottom(line) - layout.getLineTop(line) > 795f) nextPage()
                val start = line
                val top = layout.getLineTop(start)
                while (line < layout.lineCount && y + layout.getLineBottom(line) - top <= 795f) line++
                require(line > start) { "PDF line is too tall" }
                val height = layout.getLineBottom(line - 1) - top
                page!!.canvas.apply {
                    save()
                    clipRect(40f, y, 555f, y + height)
                    translate(40f, y - top)
                    layout.draw(this)
                    restore()
                }
                y += height
            }
            y += 8f
        }
        fun table(section: Document.Section) {
            val width = 515f / section.columns.size
            val cellPaint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.BLACK; textSize = 10f }
            val border = Paint().apply { color = Color.GRAY; style = Paint.Style.STROKE; strokeWidth = 0.5f }
            fun layouts(cells: List<String>, bold: Boolean = false): List<StaticLayout> {
                cellPaint.typeface = if (bold) Typeface.DEFAULT_BOLD else Typeface.DEFAULT
                return cells.map { text -> StaticLayout.Builder.obtain(text, 0, text.length, TextPaint(cellPaint), width.toInt() - 12)
                    .setIncludePad(true).setLineSpacing(2f, 1f).build() }
            }
            val header = layouts(section.columns, true)
            val headerHeight = header.maxOf { it.height }.toFloat() + 12f
            // Extremely long column labels need a readable fallback rather than an endless repeating header.
            if (headerHeight > 200f) {
                section.rows.forEachIndexed { i, row -> block("${i + 1}. " + section.columns.zip(row).joinToString("\n") { (key, value) -> "$key: $value" }) }
                if (section.rows.isEmpty()) block(section.columns.joinToString(" / "))
                return
            }
            fun draw(cells: List<StaticLayout>, starts: IntArray, ends: IntArray, height: Float) {
                cells.forEachIndexed { index, layout ->
                    val x = 40f + index * width
                    page!!.canvas.apply {
                        drawRect(x, y, x + width, y + height, border)
                        if (ends[index] > starts[index]) {
                            save()
                            clipRect(x + 6f, y + 6f, x + width - 6f, y + height - 6f)
                            translate(x + 6f, y + 6f - layout.getLineTop(starts[index]))
                            layout.draw(this)
                            restore()
                        }
                    }
                }
                y += height
            }
            fun drawHeader() = draw(header, IntArray(header.size), IntArray(header.size) { header[it].lineCount }, headerHeight)
            if (page == null || y + headerHeight + 28f > 795f) nextPage()
            drawHeader()
            section.rows.forEach { row ->
                val cells = layouts(row)
                val starts = IntArray(cells.size)
                while (cells.indices.any { starts[it] < cells[it].lineCount }) {
                    if (y + 28f > 795f) { nextPage(); drawHeader() }
                    val ends = starts.copyOf()
                    var height = 0f
                    cells.forEachIndexed { index, layout ->
                        if (starts[index] < layout.lineCount) {
                            val top = layout.getLineTop(starts[index])
                            while (ends[index] < layout.lineCount && layout.getLineBottom(ends[index]) - top + 12f <= 795f - y) ends[index]++
                            if (ends[index] > starts[index]) height = maxOf(height, layout.getLineBottom(ends[index] - 1) - top + 12f)
                        }
                    }
                    if (height == 0f) { nextPage(); drawHeader(); continue }
                    draw(cells, starts, ends, height)
                    ends.copyInto(starts)
                }
            }
            y += 8f
        }
        try {
            block(document.title, 22f, true)
            document.sections.forEach { s -> when (s.type) {
                "heading" -> { if (y > 735f) nextPage(); block(s.text, (21 - s.level).toFloat(), true) }
                "paragraph" -> block(s.text)
                "bulletList", "orderedList" -> s.items.forEachIndexed { i, text -> block("${if (s.type == "bulletList") "•" else "${i + 1}."} $text") }
                "table" -> table(s)
            } }
            finish()
            return ByteArrayOutputStream().use { out -> pdf.writeTo(out); out.toByteArray() }
        } finally {
            finish()
            pdf.close()
        }
    }
}
