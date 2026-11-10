package com.wangzan101.mika

import androidx.compose.ui.test.junit4.AndroidComposeTestRule
import androidx.compose.ui.test.junit4.ComposeContentTestRule
import androidx.test.ext.junit.rules.ActivityScenarioRule
import org.junit.rules.TestRule
import org.junit.runner.Description
import org.junit.runners.model.Statement

/**
 * Compose 1.7 drains its test scheduler on the instrumentation thread during cleanup.
 * Close the Activity first so pending test frames cannot race Android's real layout pass.
 * Keep this rule inside the Compose rule (order = Int.MAX_VALUE); assertions and @After
 * callbacks still execute with the Activity alive.
 */
class CloseComposeActivity(private val compose: ComposeContentTestRule) : TestRule {
    override fun apply(base: Statement, description: Description): Statement = object : Statement() {
        override fun evaluate() {
            try {
                base.evaluate()
            } finally {
                val rule = compose as AndroidComposeTestRule<*, *>
                (rule.activityRule as ActivityScenarioRule<*>).scenario.close()
            }
        }
    }
}
