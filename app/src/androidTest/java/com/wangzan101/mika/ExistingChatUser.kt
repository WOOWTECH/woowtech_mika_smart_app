package com.wangzan101.mika

import android.content.Context
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.rules.TestRule
import org.junit.runner.Description
import org.junit.runners.model.Statement

/** Prepare an existing user before MainActivity launches; restore onboarding preferences afterwards. */
class ExistingChatUser : TestRule {
    override fun apply(base: Statement, description: Description): Statement = object : Statement() {
        override fun evaluate() {
            val ctx = InstrumentationRegistry.getInstrumentation().targetContext
            val keys = listOf("onboarding" to "model_setup_done", "phone_setup" to "guide_seen")
            val saved = keys.map { (file, key) ->
                val prefs = ctx.getSharedPreferences(file, Context.MODE_PRIVATE)
                Triple(prefs, key, if (prefs.contains(key)) prefs.getBoolean(key, false) else null)
            }
            try {
                saved.forEach { (prefs, key, _) -> prefs.edit().putBoolean(key, true).commit() }
                base.evaluate()
            } finally {
                saved.forEach { (prefs, key, value) ->
                    prefs.edit().also { if (value == null) it.remove(key) else it.putBoolean(key, value) }.commit()
                }
            }
        }
    }
}
