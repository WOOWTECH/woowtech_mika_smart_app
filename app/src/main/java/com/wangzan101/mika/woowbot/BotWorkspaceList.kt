package com.wangzan101.mika.woowbot

import android.content.Context

/**
 * Tells the transition page what the shown woowtechbot page is (sign-in, workspace loading, list open or closed) and opens the
 * phone bot list once when asked. The script is fixed and reads structure only; its one action is the site's own list button.
 */
internal object BotWorkspaceList {
    private var source: String? = null
    fun script(context: Context, open: Boolean): String {
        val text = source ?: context.assets.open("woowtechbot/workspace-list.js").bufferedReader().use { it.readText() }.also { source = it }
        return text.replace("__WOOW_OPEN__", open.toString())
    }
}
