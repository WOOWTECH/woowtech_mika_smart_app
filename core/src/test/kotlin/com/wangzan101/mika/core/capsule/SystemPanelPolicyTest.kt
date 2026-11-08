package com.wangzan101.mika.core.capsule

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.assertEquals
import org.junit.Test
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest

@OptIn(ExperimentalCoroutinesApi::class)
class SystemPanelPolicyTest {
    @Test fun focusedOverlayOwnershipRemainsUnknownUntilConfirmedOrAnAppReturns() {
        val own = "com.apporo.assistant"
        assertEquals(null, SystemPanelPolicy.ownOverlayFocus(false, listOf(null), own))
        assertEquals(true, SystemPanelPolicy.ownOverlayFocus(false, listOf(own), own))
        assertEquals(null, SystemPanelPolicy.ownOverlayFocus(false, listOf(null), own))
        assertEquals(false, SystemPanelPolicy.ownOverlayFocus(false, listOf("other.overlay"), own))
        assertEquals(false, SystemPanelPolicy.ownOverlayFocus(true, listOf(null), own))
        assertEquals(false, SystemPanelPolicy.ownOverlayFocus(false, emptyList(), own))
    }
    @Test fun composerKeepingFocusOverAnOccludingShadeStillHidesTheCapsule() {
        assertTrue(SystemPanelPolicy.panelHasFocus(false, true, false))
        assertTrue(SystemPanelPolicy.panelHasFocus(true, false, false))
        // Dismissal exposes the underlying app, even while the composer keeps focus.
        assertFalse(SystemPanelPolicy.panelHasFocus(false, true, true))
    }

    @Test fun anOrdinaryKeyboardOrAnotherOverlayCannotSubstituteForPanelFocus() {
        assertFalse(SystemPanelPolicy.panelHasFocus(false, false, false))
        assertFalse(SystemPanelPolicy.panelHasFocus(false, false, true))
        assertTrue(SystemPanelPolicy.panelHasFocus(true, false, true))
    }
    @Test fun knownNonSystemUiOwnerAndEmptySnapshotDoNotStartRetries() = runTest {
        for (snapshot in listOf(listOf(SystemPanelPolicy.Candidate(7, "com.example.other")), emptyList())) {
            var reads = 0
            val results = mutableListOf<Boolean>()
            val job = backgroundScope.launch {
                SystemPanelPolicy.observe(MutableSharedFlow<Unit>()) {
                    reads++
                    snapshot
                }.collect { results += it }
            }
            runCurrent()
            advanceTimeBy(1_000); runCurrent()
            assertEquals(1, reads)
            assertEquals(listOf(false), results)
            job.cancel()
        }
    }

    @Test fun failedSnapshotIsRetriedAndCanRecoverWithoutAnotherEvent() = runTest {
        val reads = mutableListOf<Long>()
        val results = mutableListOf<Boolean>()
        backgroundScope.launch {
            SystemPanelPolicy.observe(MutableSharedFlow<Unit>()) {
                reads += testScheduler.currentTime
                if (reads.size == 1) null else listOf(SystemPanelPolicy.Candidate(7, "com.android.systemui"))
            }.collect { results += it }
        }
        runCurrent()
        advanceTimeBy(10_000); runCurrent()
        assertEquals(listOf(50L, 200L), reads)
        assertEquals(listOf(false, true), results)
    }

    @Test fun permanentlyFailedSnapshotHasOnlyTwoRetries() = runTest {
        val reads = mutableListOf<Long>()
        val results = mutableListOf<Boolean>()
        backgroundScope.launch {
            SystemPanelPolicy.observe(MutableSharedFlow<Unit>()) {
                reads += testScheduler.currentTime
                null
            }.collect { results += it }
        }
        runCurrent()
        advanceTimeBy(10_000); runCurrent()
        assertEquals(listOf(50L, 200L, 550L), reads)
        assertEquals(listOf(false), results)
    }

    @Test fun unknownOwnerIsRetriedWithoutAnotherEventAndThenStops() = runTest {
        val events = MutableSharedFlow<Unit>()
        val reads = mutableListOf<Long>()
        val results = mutableListOf<Boolean>()
        backgroundScope.launch {
            SystemPanelPolicy.observe(events) {
                reads += testScheduler.currentTime
                listOf(SystemPanelPolicy.Candidate(7, if (reads.size == 1) null else "com.android.systemui"))
            }.collect { results += it }
        }
        runCurrent()
        advanceTimeBy(1_000); runCurrent()
        assertEquals(listOf(50L, 200L), reads)
        assertEquals(listOf(false, true), results)
        advanceTimeBy(10_000); runCurrent()
        assertEquals(2, reads.size)
    }

    @Test fun permanentlyUnknownOwnerHasOnlyTwoRetries() = runTest {
        val reads = mutableListOf<Long>()
        val results = mutableListOf<Boolean>()
        backgroundScope.launch {
            SystemPanelPolicy.observe(MutableSharedFlow<Unit>()) {
                reads += testScheduler.currentTime
                listOf(SystemPanelPolicy.Candidate(7, null))
            }.collect { results += it }
        }
        runCurrent()
        advanceTimeBy(10_000); runCurrent()
        assertEquals(listOf(50L, 200L, 550L), reads)
        assertEquals(listOf(false), results)
    }

    @Test fun dismissalDuringRetryUsesFreshSnapshotAndStops() = runTest {
        var reads = 0
        val results = mutableListOf<Boolean>()
        backgroundScope.launch {
            SystemPanelPolicy.observe(MutableSharedFlow<Unit>()) {
                reads++
                if (reads == 1) listOf(SystemPanelPolicy.Candidate(7, null)) else emptyList()
            }.collect { results += it }
        }
        runCurrent()
        advanceTimeBy(10_000); runCurrent()
        assertEquals(2, reads)
        assertEquals(listOf(false), results)
    }

    @Test fun contentSignalCanRecoverAfterRetryBudgetIsExhausted() = runTest {
        val events = MutableSharedFlow<Unit>()
        var owner: String? = null
        var reads = 0
        val results = mutableListOf<Boolean>()
        backgroundScope.launch {
            SystemPanelPolicy.observe(events) {
                reads++
                listOf(SystemPanelPolicy.Candidate(7, owner))
            }.collect { results += it }
        }
        runCurrent()
        advanceTimeBy(1_000); runCurrent()
        assertEquals(3, reads)
        owner = "com.android.systemui"
        events.emit(Unit)
        advanceTimeBy(51); runCurrent()
        assertEquals(4, reads)
        assertEquals(listOf(false, true), results)
    }

    @Test fun burstDuringInitialReadIsConflatedButNotLost() = runTest {
        val events = MutableSharedFlow<Unit>()
        val reads = mutableListOf<Long>()
        backgroundScope.launch {
            SystemPanelPolicy.observe(events) {
                reads += testScheduler.currentTime
                emptyList()
            }.collect {}
        }
        runCurrent()
        // The upstream must already be subscribed while the initial 50ms delay is pending.
        repeat(100) { events.emit(Unit) }
        advanceTimeBy(1_000); runCurrent()
        assertEquals(listOf(50L, 100L), reads)
    }

    @Test fun cancellationStopsInitialDelayAndPendingRetries() {
        for (cancelAt in listOf(25L, 100L, 250L)) runTest {
            var reads = 0
            val job = backgroundScope.launch {
                SystemPanelPolicy.observe(MutableSharedFlow<Unit>()) {
                    reads++
                    listOf(SystemPanelPolicy.Candidate(7, null))
                }.collect {}
            }
            runCurrent()
            advanceTimeBy(cancelAt); runCurrent()
            val beforeCancel = reads
            job.cancel()
            advanceTimeBy(10_000); runCurrent()
            assertEquals(beforeCancel, reads)
        }
    }

    @Test fun newServiceCollectionDoesNotInheritConfirmedOwner() = runTest {
        var owner: String? = "com.android.systemui"
        val observer = SystemPanelPolicy.observe(MutableSharedFlow<Unit>()) {
            listOf(SystemPanelPolicy.Candidate(7, owner))
        }
        val oldResults = mutableListOf<Boolean>()
        val old = backgroundScope.launch { observer.collect { oldResults += it } }
        runCurrent()
        advanceTimeBy(51); runCurrent()
        assertEquals(listOf(true), oldResults)
        old.cancel()
        owner = null
        val newResults = mutableListOf<Boolean>()
        backgroundScope.launch { observer.collect { newResults += it } }
        runCurrent()
        advanceTimeBy(1_000); runCurrent()
        assertEquals(listOf(false), newResults)
    }

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
