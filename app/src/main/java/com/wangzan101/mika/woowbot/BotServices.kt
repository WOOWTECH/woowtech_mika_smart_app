package com.wangzan101.mika.woowbot

import android.content.Context
import androidx.webkit.ProfileStore
import androidx.webkit.WebViewFeature

object BotServices {
    /** Parent installs these on app startup. Main-thread hints; implementations must return promptly. */
    var onSessionMayHaveChanged: (BotService) -> Unit = {}
    /** Capture any needed revocation identity/cookie now, before this profile is retired. */
    var beforeSessionCleared: (BotService) -> Unit = {}
    /** Use the retired profile's captured identity, before invalidating its server session. */
    var beforeRemoteLogout: suspend (BotService) -> Boolean = { true }
    @Volatile private var registry: BotServiceRegistry? = null
    @Synchronized fun registry(context: Context): BotServiceRegistry {
        registry?.let { return it }
        // noBackupFilesDir prevents restoring metadata that points at another installation's profiles.
        val file = android.util.AtomicFile(java.io.File(context.noBackupFilesDir, "woowbot-services.json"))
        return BotServiceRegistry(object : BotServiceRegistry.Storage {
            override fun read(): String? = if (!file.baseFile.exists()) null else {
                require(file.baseFile.length() <= BotServiceRegistry.MAX_STORAGE)
                file.openRead().bufferedReader().use { it.readText() }
            }
            override fun write(value: String) {
                val stream = file.startWrite()
                try { stream.write(value.toByteArray(Charsets.UTF_8)); file.finishWrite(stream) }
                catch (error: Exception) { file.failWrite(stream); throw error }
            }
        }).also { registry = it }
    }

    fun supportsIsolation(): Boolean = runCatching {
        WebViewFeature.isFeatureSupported(WebViewFeature.MULTI_PROFILE)
    }.getOrDefault(false)

    /** Main thread, before loading profiles. Loaded profiles can only be deleted on a later process start. */
    fun cleanRetired(registry: BotServiceRegistry) {
        if (!supportsIsolation()) return
        registry.state.value.retiredProfiles.toList().forEach { name ->
            runCatching {
                val store = ProfileStore.getInstance()
                store.deleteProfile(name) || name !in store.allProfileNames
            }.onSuccess { deleted -> if (deleted) registry.acknowledgeDeleted(name) }
        }
    }
}
