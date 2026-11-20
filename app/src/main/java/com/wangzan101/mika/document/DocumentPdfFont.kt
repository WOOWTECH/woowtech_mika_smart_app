package com.wangzan101.mika.document

import android.content.Context
import android.graphics.Typeface
import android.graphics.fonts.Font
import android.graphics.fonts.FontFamily

/** Distinct Unicode aliases need distinct glyph IDs for Android PdfDocument's ToUnicode map.
 * Only the affected characters use this small OFL font; other text retains system fallback.
 * No text normalization or replacement is applied to the source or the generated PDF.
 */
internal object DocumentPdfFont {
    @Volatile private var cached: Typeface? = null

    fun get(context: Context): Typeface = cached ?: synchronized(this) {
        cached ?: run {
            val font = Font.Builder(context.assets, "fonts/apporo_document_aliases.ttf").build()
            Typeface.CustomFallbackBuilder(FontFamily.Builder(font).build())
                .setSystemFallback("sans-serif").build().also { cached = it }
        }
    }
}
