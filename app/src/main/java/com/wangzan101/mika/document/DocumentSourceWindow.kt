package com.wangzan101.mika.document

/** Bounded source editing: replacements affect only the displayed range, never the unseen tail. */
internal data class DocumentSourceWindow(val start: Int, val end: Int, val text: String) {
    fun replace(source: String, edited: String): String = source.substring(0, start) + edited + source.substring(end)

    companion object {
        const val SIZE = 1500
        fun at(source: String, requestedStart: Int): DocumentSourceWindow {
            var start = requestedStart.coerceIn(0, source.length)
            if (start > 0 && start < source.length && source[start].isLowSurrogate() && source[start - 1].isHighSurrogate()) start--
            var end = minOf(start + SIZE, source.length)
            if (end < source.length && end > start && source[end - 1].isHighSurrogate() && source[end].isLowSurrogate()) end--
            return DocumentSourceWindow(start, end, source.substring(start, end))
        }
    }
}
