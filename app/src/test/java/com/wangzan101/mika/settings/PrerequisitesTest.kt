package com.wangzan101.mika.settings

import com.wangzan101.mika.core.shell.BuiltinShellStatus
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class PrerequisitesTest {
    // SystemStatus still carries phone fields; the Play prerequisite check must ignore them.
    private val ready = SystemStatus(
        sdkInt = 34,
        builtinShell = BuiltinShellStatus.Running,
        accessibility = AccessibilityState.On,
        notificationsAllowed = true,
    )

    @Test
    fun modelConfiguredHasNoProblems() {
        val check = Prerequisites.check(ready, hasMainModel = true)
        assertTrue(check.canStartTask)
        assertTrue(check.blockers.isEmpty())
        assertTrue(check.problems.isEmpty())
    }

    @Test
    fun phoneStateAndSdkDoNotAddPlayProblems() {
        for (sdk in listOf(30, 31, 33, 34)) {
            val check = Prerequisites.check(
                ready.copy(sdkInt = sdk, builtinShell = BuiltinShellStatus.NotPaired, accessibility = AccessibilityState.Off),
                hasMainModel = true,
            )
            assertTrue(check.canStartTask)
            assertTrue(check.problems.isEmpty())
        }
    }

    @Test
    fun noMainModelBlocksStart() {
        val check = Prerequisites.check(ready, hasMainModel = false)
        assertFalse(check.canStartTask)
        assertEquals(listOf<Problem>(Problem.NoModel), check.blockers)
        assertEquals(listOf<Problem>(Problem.NoModel), check.problems)
    }

    @Test
    fun notificationsOffOnlyWarns() {
        val check = Prerequisites.check(ready.copy(notificationsAllowed = false), hasMainModel = true)
        assertTrue(check.canStartTask)
        assertTrue(check.blockers.isEmpty())
        assertEquals(listOf<Problem>(Problem.NotificationsOff), check.problems)
    }

    @Test
    fun loweredChannelCombinationsOnlyWarn() {
        fun problems(attention: Boolean, result: Boolean) =
            Prerequisites.check(ready.copy(attentionLowered = attention, resultLowered = result), hasMainModel = true).problems

        assertEquals(emptyList<Problem>(), problems(false, false))
        assertEquals(listOf<Problem>(Problem.AttentionLowered(true, false)), problems(true, false))
        assertEquals(listOf<Problem>(Problem.AttentionLowered(false, true)), problems(false, true))
        assertEquals(listOf<Problem>(Problem.AttentionLowered(true, true)), problems(true, true))

        val check = Prerequisites.check(ready.copy(attentionLowered = true, resultLowered = true), hasMainModel = true)
        assertTrue(check.canStartTask)
        assertTrue(check.blockers.isEmpty())
    }

    @Test
    fun notificationsOffSuppressesChannelWarnings() {
        val check = Prerequisites.check(
            ready.copy(notificationsAllowed = false, attentionLowered = true, resultLowered = true),
            hasMainModel = true,
        )
        assertEquals(listOf<Problem>(Problem.NotificationsOff), check.problems)
        assertTrue(check.canStartTask)
    }

    @Test
    fun modelBlockerPrecedesNotificationWarning() {
        val check = Prerequisites.check(
            ready.copy(notificationsAllowed = false, builtinShell = BuiltinShellStatus.NotPaired, accessibility = AccessibilityState.Off),
            hasMainModel = false,
        )
        assertEquals(listOf<Problem>(Problem.NoModel, Problem.NotificationsOff), check.problems)
        assertEquals(listOf<Problem>(Problem.NoModel), check.blockers)
        assertFalse(check.canStartTask)
    }
}
