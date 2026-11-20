package com.wangzan101.mika.core.document

import java.util.Locale
import java.text.Normalizer

object DocumentWriters {
    fun html(document: DocumentModel): String {
        DocumentLimits.validate(document)
        return buildString {
            append("<!doctype html><html lang=\"").append(escape(document.language)).append("\"><head><meta charset=\"utf-8\">")
            append("<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">")
            append("<meta http-equiv=\"Content-Security-Policy\" content=\"default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'\">")
            append("<title>").append(escape(document.title)).append("</title>")
            append("<style>body{font:16px/1.65 sans-serif;color:#17212b;background:#fff;max-width:960px;margin:auto;padding:24px;overflow-wrap:anywhere}h1,h2,h3,h4,h5,h6{line-height:1.3}p,li,td,th{white-space:pre-wrap}table{border-collapse:collapse;width:100%;margin:20px 0}td,th{border:1px solid #8995a1;padding:8px;text-align:start;vertical-align:top}th{background:#eef2f6}caption{text-align:start}@media print{thead{display:table-header-group}body{padding:0}}</style></head><body><h1>")
            append(escape(document.title)).append("</h1>")
            for (section in document.sections) when (section) {
                is DocumentSection.Heading -> append("<h${section.level}>").append(escape(section.text)).append("</h${section.level}>")
                is DocumentSection.Paragraph -> append("<p>").append(escape(section.text)).append("</p>")
                is DocumentSection.ListSection -> {
                    val tag = if (section.ordered) "ol" else "ul"
                    append("<$tag>")
                    section.items.forEach { append("<li>").append(escape(it)).append("</li>") }
                    append("</$tag>")
                }
                is DocumentSection.Table -> {
                    append("<table><thead><tr>")
                    section.columns.forEach { append("<th scope=\"col\">").append(escape(it)).append("</th>") }
                    append("</tr></thead><tbody>")
                    section.rows.forEach { row ->
                        append("<tr>"); row.forEach { append("<td>").append(escape(it)).append("</td>") }; append("</tr>")
                    }
                    append("</tbody></table>")
                }
            }
            append("</body></html>")
        }
    }

    /** One explicit table only. BOM + CRLF + RFC4180 quoting, including trailing newline. */
    fun csv(document: DocumentModel, tableIndex: Int?): ByteArray {
        DocumentLimits.validate(document)
        val tables = document.sections.filterIsInstance<DocumentSection.Table>()
        if (tables.isEmpty()) throw DocumentException(DocumentProblem.MissingTable)
        val index = tableIndex ?: if (tables.size == 1) 0 else throw DocumentException(DocumentProblem.SelectTable)
        val table = tables.getOrNull(index) ?: throw DocumentException(DocumentProblem.SelectTable)
        return buildString {
            append('\uFEFF')
            (listOf(table.columns) + table.rows).forEach { row ->
                append(row.joinToString(",") {
                    val normalized = it.replace("\r\n", "\n").replace("\r", "\n").replace("\n", "\r\n")
                    "\"${safeCell(normalized).replace("\"", "\"\"")}\""
                })
                append("\r\n")
            }
        }.toByteArray(Charsets.UTF_8)
    }

    /** Prefix is intentional data mutation: negatives and formula-looking text become text. */
    fun safeCell(value: String): String {
        val leading = value.takeWhile { it.isWhitespace() || it == '\uFEFF' }
        val remainder = value.drop(leading.length)
        val unsafe = leading.any { it in "\t\r\n" } || remainder.firstOrNull() in listOf('=', '+', '-', '@')
        return if (unsafe) "'$value" else value
    }

    fun filename(title: String, format: DocumentFormat): String {
        val base = StringBuilder()
        var count = 0
        var bytes = 0
        Normalizer.normalize(title, Normalizer.Form.NFC).codePoints().forEachOrdered { cp ->
            val unsafe = Character.isISOControl(cp) || Character.getType(cp) == Character.FORMAT.toInt() || cp in "\\/:*?\"<>|".map(Char::code)
            if (!unsafe && count < 80) {
                val part = String(Character.toChars(cp))
                val size = part.toByteArray(Charsets.UTF_8).size
                // Also fit filesystems whose single-component limit is 255 bytes.
                if (bytes + size <= 240) { base.append(part); count++; bytes += size }
            }
        }
        var clean = base.toString().trim().trim('.').trim().ifBlank { "document" }
        if (clean.substringBefore('.').uppercase(Locale.ROOT) in reserved) {
            clean = "_$clean"
            while (clean.codePointCount(0, clean.length) > 80 || clean.toByteArray(Charsets.UTF_8).size > 240)
                clean = clean.substring(0, clean.offsetByCodePoints(clean.length, -1))
        }
        return "$clean.${format.extension}"
    }

    private val reserved = setOf("CON", "PRN", "AUX", "NUL") + (1..9).flatMap { listOf("COM$it", "LPT$it") }
    private fun escape(text: String) = buildString {
        text.forEach { append(when (it) { '&' -> "&amp;"; '<' -> "&lt;"; '>' -> "&gt;"; '"' -> "&quot;"; '\'' -> "&#39;"; else -> it.toString() }) }
    }
}
