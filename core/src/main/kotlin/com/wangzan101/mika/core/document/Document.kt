package com.wangzan101.mika.core.document

import kotlinx.serialization.json.*

/** Portable, text-only document. No markup, executable content or network resources. */
data class Document(val title: String, val sections: List<Section>) {
    data class Section(val type: String, val text: String = "", val level: Int = 1,
        val items: List<String> = emptyList(), val columns: List<String> = emptyList(),
        val rows: List<List<String>> = emptyList())

    companion object {
        fun parse(o: JsonObject): Document {
            require(o.toString().length <= 250_000) { "Document exceeds 250000 characters" }
            fun text(e: JsonElement?): String = (e as? JsonPrimitive)?.takeIf { it.isString }?.content
                ?: throw IllegalArgumentException("Expected text")
            fun list(e: JsonElement?): List<String> = (e as? JsonArray)?.map { text(it) }
                ?: throw IllegalArgumentException("Expected array of text")
            require(o.keys.all { it in setOf("title", "sections") }) { "Unknown document field" }
            val title = text(o["title"])
            require(title.isNotBlank() && title.length <= 200) { "Title must contain 1-200 characters" }
            val sections = (o["sections"] as? JsonArray)?.map { value ->
                val s = value as? JsonObject ?: throw IllegalArgumentException("Expected section object")
                val type = text(s["type"])
                val allowed = when(type) {
                    "heading" -> setOf("type", "text", "level")
                    "paragraph" -> setOf("type", "text")
                    "bulletList", "orderedList" -> setOf("type", "items")
                    "table" -> setOf("type", "columns", "rows")
                    else -> emptySet()
                }
                require(s.keys.all { it in allowed }) { "Unknown or misplaced section field" }
                if ("level" in s) require((s["level"] as? JsonPrimitive)?.takeIf { !it.isString }?.intOrNull in 1..6) { "Invalid heading level" }
                when (type) {
                    "heading", "paragraph" -> Section(type, text(s["text"]),
                        if (type == "heading") (s["level"] as? JsonPrimitive)?.intOrNull?.also {
                            require(it in 1..6) { "Heading level must be 1-6" }
                        } ?: 1 else 1)
                    "bulletList", "orderedList" -> Section(type, items = list(s["items"]).also { require(it.size in 1..1000) })
                    "table" -> {
                        val columns = list(s["columns"])
                        require(columns.size in 1..12) { "Table requires 1-12 columns" }
                        val rows = (s["rows"] as? JsonArray)?.map { list(it) } ?: throw IllegalArgumentException("Expected rows")
                        require(rows.size <= 1000 && rows.all { it.size == columns.size }) { "Invalid table dimensions" }
                        Section(type, columns = columns, rows = rows)
                    }
                    else -> throw IllegalArgumentException("Unsupported section: $type")
                }
            } ?: throw IllegalArgumentException("Expected sections")
            require(sections.size in 1..200 && sections.any { it.text.isNotBlank() || it.items.isNotEmpty() || it.columns.isNotEmpty() }) { "Document is empty or too long" }
            return Document(title, sections)
        }
    }

    fun fileName(format: String): String = title.replace(Regex("[\\p{C}\\\\/:*?\"<>|]"), "_")
        .trim(' ', '.').take(80).trimEnd { Character.isHighSurrogate(it) }.ifBlank { "document" } + ".$format"

    fun html(): String {
        fun esc(s: String) = s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace("\"", "&quot;")
        return buildString {
            append("<!doctype html><html><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width\"><meta http-equiv=\"Content-Security-Policy\" content=\"default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'\"><title>${esc(title)}</title><style>body{font-family:sans-serif;margin:24px;line-height:1.6;overflow-wrap:anywhere}p,li,td,th{white-space:pre-wrap}table{border-collapse:collapse;width:100%;table-layout:fixed}td,th{border:1px solid #999;padding:6px;text-align:left}thead{display:table-header-group}</style></head><body><h1>${esc(title)}</h1>")
            sections.forEach { s -> when(s.type) {
                "heading" -> append("<h${s.level}>${esc(s.text)}</h${s.level}>")
                "paragraph" -> append("<p>${esc(s.text)}</p>")
                "bulletList", "orderedList" -> { val tag = if(s.type == "bulletList") "ul" else "ol"; append("<$tag>"); s.items.forEach { append("<li>${esc(it)}</li>") }; append("</$tag>") }
                "table" -> { append("<table><thead><tr>"); s.columns.forEach { append("<th>${esc(it)}</th>") }; append("</tr></thead><tbody>"); s.rows.forEach { row -> append("<tr>"); row.forEach { append("<td>${esc(it)}</td>") }; append("</tr>") }; append("</tbody></table>") }
            } }
            append("</body></html>")
        }
    }

    /** CSV uses UTF-8 BOM/CRLF, quoting every field. Formula-like fields gain a visible apostrophe. */
    fun csv(tableIndex: Int?): String {
        val tables = sections.filter { it.type == "table" }
        require(tables.isNotEmpty()) { "No table available" }
        require(tableIndex != null || tables.size == 1) { "Multiple tables: select a zero-based tableIndex" }
        val table = tables.getOrNull(tableIndex ?: 0) ?: throw IllegalArgumentException("Invalid tableIndex")
        fun cell(raw: String): String {
            val risky = raw.trimStart().firstOrNull() in listOf('=', '+', '-', '@') || raw.firstOrNull() in listOf('\t', '\r', '\n')
            val safe = if (risky) "'$raw" else raw
            return "\"${safe.replace("\"", "\"\"")}\""
        }
        return "\uFEFF" + (listOf(table.columns) + table.rows).joinToString("\r\n", postfix = "\r\n") { row -> row.joinToString(",") { cell(it) } }
    }
}
