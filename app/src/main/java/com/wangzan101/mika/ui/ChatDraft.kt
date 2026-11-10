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
internal class ChatDraftState(private val prefs: SharedPreferences) : MutableState<String> {
    private val state = mutableStateOf(prefs.getString(TEXT, "").orEmpty())

    override var value: String
        get() = state.value
        set(text) {
            if (text == state.value) return
            state.value = text
            prefs.edit().also { editor ->
                if (text.isEmpty()) editor.remove(TEXT) else editor.putString(TEXT, text)
            }.apply()
        }

    override fun component1(): String = value
    override fun component2(): (String) -> Unit = { value = it }

    private companion object { const val TEXT = "text" }
}

@Composable
internal fun rememberChatDraft(
    prefs: SharedPreferences = LocalContext.current.applicationContext
        .getSharedPreferences("chat_draft", Context.MODE_PRIVATE),
): MutableState<String> = remember(prefs) { ChatDraftState(prefs) }
