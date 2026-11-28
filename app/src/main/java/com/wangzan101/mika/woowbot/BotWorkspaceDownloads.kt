package com.wangzan101.mika.woowbot

import android.content.Context

/**
 * Keeps the Blobs a woowtechbot page turns into download links readable after the page revokes them, and hands one to the
 * app in chunks when asked (see BotBlobReader). Fixed script, idempotent, installed at document start where supported.
 */
internal object BotWorkspaceDownloads {
    private var source: String? = null
    fun script(context: Context): String =
        source ?: context.assets.open("woowtechbot/workspace-downloads.js").bufferedReader().use { it.readText() }.also { source = it }
}
