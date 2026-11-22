package com.wangzan101.mika.document

/** Bound generated CSV preview bytes without inventing a replacement character at the cut. */
internal object DocumentCsvPreviewText {
    const val MAX_BYTES = 64 * 1024

    fun text(bytes: ByteArray): String {
        var end = minOf(bytes.size, MAX_BYTES)
        if (end < bytes.size) {
            while (end > 0 && (bytes[end].toInt() and 0xC0) == 0x80) end--
        }
        return String(bytes, 0, end, Charsets.UTF_8).removePrefix("\uFEFF")
    }
}
