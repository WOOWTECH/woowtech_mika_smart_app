package com.wangzan101.mika.core.document

/** Deliberately small, loss-preserving Markdown subset; unsupported inline markup stays literal.
 * Unlike GFM renderers, this parser never silently pads or discards ragged table cells. */
object DocumentMarkdown {
    private val heading = Regex("^ {0,3}(#{1,6})[ \\t]+(.*)$")
    private val list = Regex("^([-+*]|[1-9]\\d{0,8}\\.)[ \\t]+(\\S.*)$")
    private val divider = Regex(":?-{3,}:?")

    fun parse(title: String, language: String, source: String): DocumentModel {
        DocumentLimits.source(source)
        val lines = source.replace("\r\n", "\n").replace('\r', '\n').lines()
        val sections = mutableListOf<DocumentSection>()
        var i = 0
        var tables = 0
        var totalItems = 0
        fun tableAt(index: Int): Boolean = index + 1 < lines.size &&
            lines[index].contains('|') && lines[index + 1].contains('|') &&
            cells(lines[index + 1]).all { divider.matches(it.trim()) }
        while (i < lines.size) {
            val line = lines[i]
            if (line.isBlank()) { i++; continue }
            if (sections.size >= DocumentLimits.MAX_SECTIONS) throw DocumentException(DocumentProblem.TooLarge)
            if (line.startsWith("    ") || line.startsWith('\t')) {
                val literal = mutableListOf(lines[i++])
                while (i < lines.size && (lines[i].startsWith("    ") || lines[i].startsWith('\t'))) literal += lines[i++]
                sections += DocumentSection.Paragraph(literal.joinToString("\n"))
                continue
            }
            // Keep fenced code literally, including its fences; do not mistake examples for tables.
            val fence = Regex("^ {0,3}(`{3,}|~{3,}).*$").matchEntire(line)?.groupValues?.get(1)
            if (fence != null) {
                val block = mutableListOf(lines[i++])
                while (i < lines.size) {
                    val next = lines[i++]
                    block += next
                    if (next.trim().length >= fence.length && next.trim().all { it == fence[0] }) break
                }
                sections += DocumentSection.Paragraph(block.joinToString("\n"))
                continue
            }
            if (tableAt(i)) {
                if (++tables > DocumentLimits.MAX_TABLES) throw DocumentException(DocumentProblem.TooLarge)
                val columns = cells(line)
                if (cells(lines[i + 1]).size != columns.size) throw DocumentException(DocumentProblem.RaggedTable)
                i += 2
                val rows = mutableListOf<List<String>>()
                while (i < lines.size && lines[i].isNotBlank() && lines[i].contains('|')) {
                    val row = cells(lines[i++])
                    if (row.size != columns.size) throw DocumentException(DocumentProblem.RaggedTable)
                    rows += row
                    if (rows.size > DocumentLimits.MAX_ROWS) throw DocumentException(DocumentProblem.TooLarge)
                }
                sections += DocumentSection.Table(columns, rows)
                continue
            }
            val h = heading.matchEntire(line)
            if (h != null && h.groupValues[2].isNotBlank()) {
                sections += DocumentSection.Heading(h.groupValues[1].length, h.groupValues[2])
                i++; continue
            }
            val item = list.matchEntire(line)
            if (item != null) {
                val ordered = item.groupValues[1][0].isDigit()
                val items = mutableListOf<String>()
                val original = mutableListOf<String>()
                var supported = true
                while (i < lines.size) {
                    val m = list.matchEntire(lines[i]) ?: break
                    if (m.groupValues[1][0].isDigit() != ordered) break
                    if (ordered && m.groupValues[1].dropLast(1).toIntOrNull() != items.size + 1) supported = false
                    items += m.groupValues[2]
                    if (++totalItems > DocumentLimits.MAX_LIST_ITEMS) throw DocumentException(DocumentProblem.TooLarge)
                    original += lines[i]
                    i++
                }
                while (i < lines.size && lines[i].isNotBlank() && (lines[i].startsWith(' ') || lines[i].startsWith('\t'))) {
                    supported = false
                    original += lines[i++]
                }
                sections += if (supported) DocumentSection.ListSection(items, ordered) else DocumentSection.Paragraph(original.joinToString("\n"))
                continue
            }
            val paragraph = mutableListOf(lines[i++])
            while (i < lines.size && lines[i].isNotBlank() && !tableAt(i) &&
                heading.matchEntire(lines[i]) == null && list.matchEntire(lines[i]) == null &&
                !lines[i].trimStart().startsWith("```") && !lines[i].trimStart().startsWith("~~~")) paragraph += lines[i++]
            sections += DocumentSection.Paragraph(paragraph.joinToString("\n"))
        }
        return DocumentModel(title.trim(), language, sections).also(DocumentLimits::validate)
    }

    /** Split only unescaped pipes outside code spans, removing optional outside delimiters. */
    internal fun cells(line: String): List<String> {
        val result = mutableListOf<String>()
        val cell = StringBuilder()
        val text = line.trim(' ')
        var i = 0
        var ticks = 0
        while (i < text.length) {
            val c = text[i]
            if (c == '\\' && i + 1 < text.length && text[i + 1] in "|\\") {
                cell.append(text[i + 1]); i += 2; continue
            }
            if (c == '`') {
                var end = i + 1
                while (end < text.length && text[end] == '`') end++
                val run = end - i
                if (ticks == 0) ticks = run else if (ticks == run) ticks = 0
                cell.append(text, i, end); i = end; continue
            }
            if (c == '|' && ticks == 0) { result += cell.toString().trim(' '); cell.clear() }
            else cell.append(c)
            i++
        }
        result += cell.toString().trim(' ')
        if (text.startsWith('|')) result.removeAt(0)
        if (result.size > 1 && text.endsWith('|') && result.last().isEmpty()) result.removeAt(result.lastIndex)
        return result
    }
}
