package com.wangzan101.mika.woowbot

import android.app.Activity
import java.net.URI
import java.net.URLDecoder

/** Validate before any navigation/network request. The returned secret stays in process memory only. */
internal object BotPairingQr {
    fun validate(raw: String, origin: BotOrigin): String {
        require(raw.length in 1..BotOrigin.MAX_URL && raw.none { it.isWhitespace() || it.isISOControl() || it == '\\' })
        val uri = URI(raw)
        if (uri.scheme == APP_SCHEME) return fromAppLink(uri, origin)
        require(uri.scheme == "https" && origin.allows(raw))
        require(uri.rawPath == "/pair" && uri.rawQuery == null && uri.rawUserInfo == null)
        require(uri.rawFragment?.matches(Regex("code=$CODE")) == true)
        return raw
    }

    /**
     * The QR a woowtechbot server draws for phones (owner 2026-11-28: scanning it said it was not a valid link):
     * `openmausbot://pair?address=<server>&code=<code>`. Only for the service being shown; it becomes the website's own
     * pairing link, so the code is entered on that service's page and nowhere else.
     */
    private fun fromAppLink(uri: URI, origin: BotOrigin): String {
        require(uri.rawAuthority == "pair" && uri.rawPath.isNullOrEmpty() && uri.rawFragment == null && uri.rawUserInfo == null)
        val pairs = requireNotNull(uri.rawQuery).split('&').map { require('=' in it); it.substringBefore('=') to it.substringAfter('=') }
        require(pairs.map { it.first }.sorted() == listOf("address", "code"))
        val values = pairs.toMap().mapValues { URLDecoder.decode(it.value, "UTF-8") }
        val code = values.getValue("code")
        require(code.matches(Regex(CODE)))
        require(BotOrigin.parse(values.getValue("address"), allowHttpLan = origin.insecureLan).value == origin.value)
        return origin.value + "/pair#code=" + code
    }
    private const val APP_SCHEME = "openmausbot"
    private const val CODE = "[A-Za-z0-9_-]{6,256}"
}

/** Flavor implementation avoids adding the scanner to Apporo/upstream. Null means user cancellation. */
interface BotQrScanner {
    fun scan(activity: Activity, result: (String?) -> Unit, failure: () -> Unit)
    companion object {
        fun create(): BotQrScanner = Class.forName("com.wangzan101.mika.woowbot.DirectBotQrScanner")
            .getDeclaredConstructor().newInstance() as BotQrScanner
    }
}
