package com.wangzan101.mika.cap.phone.a11y

import android.graphics.Bitmap
import com.wangzan101.mika.core.uistate.VisibleTextLine

/** The Play edition has no cross-app screen recognition. Keep callers fail-closed if reached. */
internal object PhoneOcr {
    suspend fun read(bitmap: Bitmap): List<VisibleTextLine> {
        bitmap.recycle()
        throw UnsupportedOperationException("Screen recognition is unavailable in this edition")
    }
}
