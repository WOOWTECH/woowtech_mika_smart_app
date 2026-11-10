package com.wangzan101.mika

import android.app.LocaleManager
import android.os.Build
import android.os.LocaleList
import android.os.SystemClock
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.assertEquals
import org.junit.rules.TestRule
import org.junit.runner.Description
import org.junit.runners.model.Statement

/** Shared functional tests use Apporo English; upstream keeps its original Chinese assertions. */
class BrandTestUi : TestRule {
    override fun apply(base: Statement, description: Description): Statement {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        if (context.packageName != "com.apporo.assistant") return ChineseUi().apply(base, description)
        return object : Statement() {
            override fun evaluate() {
                check(Build.VERSION.SDK_INT >= 33) { "Apporo functional acceptance requires per-app locales" }
                val manager = context.getSystemService(LocaleManager::class.java)
                val before = manager.applicationLocales
                try {
                    manager.applicationLocales = LocaleList.forLanguageTags("en-US")
                    val deadline = SystemClock.uptimeMillis() + 5_000
                    while (context.resources.configuration.locales[0].language != "en" && SystemClock.uptimeMillis() < deadline) {
                        SystemClock.sleep(50)
                    }
                    assertEquals("en", context.resources.configuration.locales[0].language)
                    base.evaluate()
                } finally { manager.applicationLocales = before }
            }
        }
    }
}
