package com.wangzan101.mika.woowbot

import android.os.Bundle
import android.os.Parcel
import android.webkit.WebView

/** Process-memory only: history may contain private URLs, so it must never enter savedInstanceState/disk. */
internal object BotWebSessions {
    private const val MAX_BYTES_PER_PROFILE = 256 * 1024
    private val histories = LinkedHashMap<String, Bundle>()

    fun save(service: BotService, view: WebView) {
        val history = view.copyBackForwardList()
        if ((0 until history.size).any { !service.policy.allows(history.getItemAtIndex(it).url) }) return
        val state = Bundle()
        if (view.saveState(state) == null) return
        val parcel = Parcel.obtain()
        val size = try { parcel.writeBundle(state); parcel.dataSize() } finally { parcel.recycle() }
        if (size > MAX_BYTES_PER_PROFILE) { clear(service.profileName); return }
        histories.remove(service.profileName)
        histories[service.profileName] = state
        while (histories.size > BotServiceRegistry.MAX_SERVICES) histories.remove(histories.keys.first())
    }

    fun restore(service: BotService, view: WebView): Boolean = histories[service.profileName]?.let {
        runCatching { view.restoreState(Bundle(it)) != null }.getOrDefault(false)
    } ?: false

    fun clear(profileName: String) { histories.remove(profileName) }
}
