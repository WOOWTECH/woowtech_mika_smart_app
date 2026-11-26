package com.wangzan101.mika.woowbot

import android.app.Activity
import java.net.URI

/** Validate before any navigation/network request. The returned secret stays in process memory only. */
internal object BotPairingQr {
    fun validate(raw: String, origin: BotOrigin): String {
        require(raw.length in 1..BotOrigin.MAX_URL && raw.none { it.isWhitespace() || it.isISOControl() || it == '\\' })
        val uri = URI(raw)
        require(uri.scheme == "https" && origin.allows(raw))
        require(uri.rawPath == "/pair" && uri.rawQuery == null && uri.rawUserInfo == null)
        require(uri.rawFragment?.matches(Regex("code=[A-Za-z0-9_-]{6,256}")) == true)
        return raw
    }
}

/** Flavor implementation avoids adding the scanner to Apporo/upstream. Null means user cancellation. */
interface BotQrScanner {
    fun scan(activity: Activity, result: (String?) -> Unit, failure: () -> Unit)
    companion object {
        fun create(): BotQrScanner = Class.forName("com.wangzan101.mika.woowbot.DirectBotQrScanner")
            .getDeclaredConstructor().newInstance() as BotQrScanner
    }
}
