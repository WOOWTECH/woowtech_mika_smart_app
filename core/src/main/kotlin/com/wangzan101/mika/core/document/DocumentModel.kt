package com.wangzan101.mika.core.document

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/** Phase-one interchange model. Source Markdown is kept separately and never rewritten in chat. */
@Serializable
data class DocumentModel(
    val title: String,
    val language: String,
    val sections: List<DocumentSection>,
    val schemaVersion: Int = 1,
)

@Serializable
sealed interface DocumentSection {
    @Serializable @SerialName("heading")
    data class Heading(val level: Int, val text: String) : DocumentSection
    @Serializable @SerialName("paragraph")
    data class Paragraph(val text: String) : DocumentSection
    @Serializable @SerialName("list")
    data class ListSection(val items: List<String>, val ordered: Boolean) : DocumentSection
    @Serializable @SerialName("table")
    data class Table(val columns: List<String>, val rows: List<List<String>>) : DocumentSection
}

enum class DocumentFormat(val extension: String, val mime: String) {
    HTML("html", "text/html"), PDF("pdf", "application/pdf"), CSV("csv", "text/csv"),
}

enum class DocumentProblem { Empty, TooLarge, RaggedTable, EmptyTable, MissingTable, SelectTable, InvalidSchema, InvalidTitle, InvalidLanguage, InvalidContent, CacheFull }
class DocumentException(val problem: DocumentProblem) : IllegalArgumentException(problem.name)

object DocumentLimits {
    const val MAX_SOURCE_BYTES = 1_048_576
    const val MAX_COLUMNS = 64
    const val MAX_ROWS = 5_000
    const val MAX_CELLS = 50_000
    const val MAX_TABLES = 64
    const val MAX_TITLE_BYTES = 1024
    const val MAX_SECTIONS = 10_000
    const val MAX_LIST_ITEMS = 50_000
    const val MAX_FILE_BYTES = 16 * 1_048_576
    const val MAX_PDF_PAGES = 256

    fun source(source: String) {
        if (source.isBlank()) throw DocumentException(DocumentProblem.Empty)
        if (source.length > MAX_SOURCE_BYTES || source.toByteArray(Charsets.UTF_8).size > MAX_SOURCE_BYTES)
            throw DocumentException(DocumentProblem.TooLarge)
        text(source)
    }

    fun validate(document: DocumentModel) {
        if (document.schemaVersion != 1) throw DocumentException(DocumentProblem.InvalidSchema)
        if (document.title.isBlank() || document.title.toByteArray(Charsets.UTF_8).size > MAX_TITLE_BYTES || document.title.any(Char::isISOControl))
            throw DocumentException(DocumentProblem.InvalidTitle)
        if (document.language.length > 63 || !Regex("[A-Za-z]{1,8}(?:-[A-Za-z0-9]{1,8})*").matches(document.language))
            throw DocumentException(DocumentProblem.InvalidLanguage)
        if (document.sections.isEmpty()) throw DocumentException(DocumentProblem.Empty)
        if (document.sections.size > MAX_SECTIONS) throw DocumentException(DocumentProblem.TooLarge)
        var cells = 0L
        var tables = 0
        var items = 0L
        var bytes = 0L
        fun count(value: String) { text(value); bytes += value.toByteArray(Charsets.UTF_8).size }
        count(document.title)
        count(document.language)
        for (section in document.sections) when (section) {
            is DocumentSection.Heading -> {
                if (section.level !in 1..6 || section.text.isBlank()) throw DocumentException(DocumentProblem.InvalidSchema)
                count(section.text)
            }
            is DocumentSection.Paragraph -> {
                if (section.text.isBlank()) throw DocumentException(DocumentProblem.Empty)
                count(section.text)
            }
            is DocumentSection.ListSection -> {
                if (section.items.isEmpty() || section.items.any(String::isBlank)) throw DocumentException(DocumentProblem.InvalidContent)
                items += section.items.size
                section.items.forEach(::count)
            }
            is DocumentSection.Table -> {
                if (++tables > MAX_TABLES) throw DocumentException(DocumentProblem.TooLarge)
                if (section.columns.isEmpty() || section.columns.any(String::isBlank) || section.rows.isEmpty())
                    throw DocumentException(DocumentProblem.EmptyTable)
                if (section.columns.size > MAX_COLUMNS || section.rows.size > MAX_ROWS)
                    throw DocumentException(DocumentProblem.TooLarge)
                if (section.rows.any { it.size != section.columns.size }) throw DocumentException(DocumentProblem.RaggedTable)
                cells += section.columns.size.toLong() * (section.rows.size + 1)
                section.columns.forEach(::count)
                section.rows.forEach { it.forEach(::count) }
            }
        }
        if (cells > MAX_CELLS || bytes > MAX_SOURCE_BYTES || items > MAX_LIST_ITEMS) throw DocumentException(DocumentProblem.TooLarge)
    }

    private fun text(value: String) {
        if (value.any { (it.code < 32 && it !in "\t\r\n") || it.code == 127 })
            throw DocumentException(DocumentProblem.InvalidContent)
    }
}
