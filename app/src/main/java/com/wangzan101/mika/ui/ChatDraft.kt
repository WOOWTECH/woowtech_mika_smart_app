package com.wangzan101.mika.ui

import android.content.Context
import android.content.SharedPreferences
import androidx.compose.runtime.Composable
import androidx.compose.runtime.MutableState
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalContext

/**
 * The chat composer has one draft (as before), including typed text and completed voice input.
 * Save edits when they happen, not just in Activity saved state: revoking a permission can kill
 * the foreground process without saving that state. Android preferences serialize disk writes
 * asynchronously and flush pending writes across normal Activity lifecycle transitions.
 *
 * Sending or explicitly clearing the field removes the saved text. This is app-private storage;
 * backup is disabled in the manifest. It does not contain partial/cancelled recordings or audio.
 */
internal class ChatDraftState(private val prefs: SharedPreferences, private val textKey: String = "text") : MutableState<String> {
    private val state = mutableStateOf(prefs.getString(textKey, "").orEmpty())

    override var value: String
        get() = state.value
        set(text) {
            if (text == state.value) return
            state.value = text
            prefs.edit().also { editor ->
                if (text.isEmpty()) editor.remove(textKey) else editor.putString(textKey, text)
            }.apply()
        }

    override fun component1(): String = value
    override fun component2(): (String) -> Unit = { value = it }

}

@Composable
internal fun rememberChatDraft(
    prefs: SharedPreferences = LocalContext.current.applicationContext
        .getSharedPreferences("chat_draft", Context.MODE_PRIVATE),
): MutableState<String> = remember(prefs) { ChatDraftState(prefs) }

/** One-time copy of the legacy draft; its original value is retained for rollback to the old UI. */
internal fun botUiDraft(prefs: SharedPreferences, id: String): ChatDraftState {
    val key = "bot_ui_text_$id"
    if (!prefs.contains("bot_ui_seen_$id")) prefs.edit().putLong("bot_ui_seen_$id", System.currentTimeMillis()).apply()
    if (!prefs.contains("bot_ui_migrated")) {
        val edit = prefs.edit().putBoolean("bot_ui_migrated", true)
        if (!prefs.contains(key)) edit.putString(key, prefs.getString("text", "").orEmpty())
        edit.apply()
    }
    return ChatDraftState(prefs, key)
}

@Composable
internal fun rememberBotUiDraft(id: String, prefs: SharedPreferences = LocalContext.current.applicationContext
    .getSharedPreferences("chat_draft", Context.MODE_PRIVATE)): MutableState<String> {
    return remember(prefs, id) { botUiDraft(prefs, id) }
}

internal fun botUiForgetDraft(prefs: SharedPreferences, id: String) {
    prefs.edit().remove("bot_ui_seen_$id").remove("bot_ui_text_$id").apply()
}
