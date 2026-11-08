package com.wangzan101.mika.core.capsule

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class SystemPanelPolicyTest {
    @Test fun missingRootOnConfirmedWindowDoesNotFlashTheCapsule() {
        val tracker = SystemPanelPolicy.Tracker()
        assertTrue(tracker.update(listOf(SystemPanelPolicy.Candidate(7, "com.android.systemui"))))
        repeat(20) { assertTrue(tracker.update(listOf(SystemPanelPolicy.Candidate(7, null)))) }
        assertTrue(tracker.update(null)) // transient failure to read all windows
        // Removal, loss of input focus or loss of panel bounds all exclude the candidate.
        assertFalse(tracker.update(emptyList()))
        assertFalse(tracker.update(listOf(SystemPanelPolicy.Candidate(7, null))))
    }

    @Test fun unknownWindowsDoNotInheritAnotherWindowsIdentity() {
        val tracker = SystemPanelPolicy.Tracker()
        assertFalse(tracker.update(null))
        assertFalse(tracker.update(listOf(SystemPanelPolicy.Candidate(7, null))))
        assertTrue(tracker.update(listOf(SystemPanelPolicy.Candidate(7, "com.android.systemui"))))
        assertFalse(tracker.update(listOf(SystemPanelPolicy.Candidate(8, null))))
        assertTrue(tracker.update(listOf(SystemPanelPolicy.Candidate(8, "com.android.systemui"))))
        assertFalse(tracker.update(listOf(SystemPanelPolicy.Candidate(8, "com.example.other"))))
    }

    @Test fun duplicateOverlayEventsDoNotChangeTheDecisionAndReconnectStartsFresh() {
        val tracker = SystemPanelPolicy.Tracker()
        val shade = listOf(SystemPanelPolicy.Candidate(7, "com.android.systemui"))
        repeat(20) { assertTrue(tracker.update(shade)) }
        repeat(20) { assertFalse(tracker.update(emptyList())) }
        assertFalse(SystemPanelPolicy.Tracker().update(listOf(SystemPanelPolicy.Candidate(7, null))))
    }

    private fun covers(
        system: Boolean = true, focused: Boolean = true, owner: String? = "com.android.systemui",
        left: Int = 0, top: Int = 0, right: Int = 1080, bottom: Int = 2400,
        width: Int = 1080, height: Int = 2400,
    ): Boolean {
        val candidates = if (SystemPanelPolicy.isPanelWindow(system, focused, left, top, right, bottom, width, height))
            listOf(SystemPanelPolicy.Candidate(7, owner)) else emptyList()
        return SystemPanelPolicy.Tracker().update(candidates)
    }

    @Test fun notificationShadeAndQuickSettingsAtDifferentDisplaySizes() {
        // Pixel-only ratios do not depend on font scale, density, or translated tile text.
        for ((width, height) in listOf(1080 to 2400, 922 to 2048, 2400 to 1080, 720 to 1600)) {
            assertTrue(covers(right = width, bottom = height, width = width, height = height))
            assertTrue(covers(right = width, bottom = height / 2, width = width, height = height))
        }
    }

    @Test fun ordinaryBarsAndHeadsUpDoNotSuppressEvenWhenFocused() {
        for (bottom in listOf(24, 96, 200, 600)) assertFalse(covers(bottom = bottom))
        assertFalse(covers(top = 2304)) // navigation bar
        assertFalse(covers(top = 96, bottom = 800)) // floating notification
    }

    @Test fun focusIsRequiredEvenForFullScreenSystemUiBounds() {
        assertFalse(covers(focused = false))
        assertTrue(covers(focused = true))
        assertFalse(covers(focused = false)) // dismissal may retain a non-focused full-size window
    }

    @Test fun applicationKeyboardAndOurOwnOverlayCannotSuppress() {
        assertFalse(covers(system = false))
        assertFalse(covers(owner = "com.wangzan101.mika"))
        assertFalse(covers(owner = "com.example.app"))
        assertFalse(covers(owner = null))
        assertFalse(covers(owner = ""))
    }

    @Test fun sidePanelsAndFloatingSystemDialogsDoNotSuppress() {
        assertFalse(covers(left = 700))
        assertFalse(covers(right = 500))
        assertFalse(covers(top = 400, bottom = 2000))
    }

    @Test fun coverageThresholdsHaveExplicitBoundaries() {
        assertTrue(covers(right = 864, bottom = 1200))
        assertFalse(covers(right = 863, bottom = 1200))
        assertFalse(covers(right = 864, bottom = 1199))
        assertFalse(covers(top = 1))
    }

    @Test fun invalidAndOffScreenBoundsDoNotCountAsCoverage() {
        assertFalse(covers(width = 0))
        assertFalse(covers(height = -1))
        assertFalse(covers(right = 0))
        assertFalse(covers(bottom = 0))
        assertFalse(covers(left = 2000, right = 4000))
        assertFalse(covers(top = -2400, bottom = -1))
        assertFalse(covers(left = -2000, right = 100))
        assertTrue(covers(left = -1, top = -1, right = 1081, bottom = 2401))
    }
}
