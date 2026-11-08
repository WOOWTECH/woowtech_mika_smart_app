package com.wangzan101.mika.core.capsule

import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.conflate
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.onStart

/** Conservative window-based proxy for an expanded notification / quick-settings panel.
 * No titles, text, accessibility focus, or active-window state: those can change on overlay events.
 * An input-focused overlay can retain focus over the shade. In that case the system panel
 * must also occlude all application windows; a normal keyboard over an app is not enough.
 */
object SystemPanelPolicy {
    /** null preserves uncertainty so the observer can retry without trusting another overlay. */
    fun ownOverlayFocus(applicationVisible: Boolean, focusedOverlayOwners: List<String?>, ownPackage: String): Boolean? = when {
        applicationVisible -> false
        ownPackage in focusedOverlayOwners -> true
        focusedOverlayOwners.any { it == null } -> null
        else -> false
    }

    fun panelHasFocus(systemFocused: Boolean, ownOverlayFocused: Boolean, applicationVisible: Boolean): Boolean =
        systemFocused || (ownOverlayFocused && !applicationVisible)

    /** Only windows passing the panel or heads-up geometry policy enter this owner tracker. */
    data class Candidate(val id: Int, val ownerPackage: String?)

    /** One reader, one conflated pending event, and at most two retries per event batch.
     * Unknown owners and failed snapshots are retried. A retry reads fresh windows: it must
     * never reuse a candidate after focus loss/dismissal.
     * Collection belongs to the connected service; cancellation also cancels pending delays.
     */
    fun observe(events: Flow<Unit>, read: () -> List<Candidate>?): Flow<Boolean> = flow {
        val tracker = Tracker()
        events.onStart { emit(Unit) }.conflate().collect {
            delay(50L)
            currentCoroutineContext().ensureActive()
            var candidates = read()
            emit(tracker.update(candidates))
            for (waitMs in listOf(150L, 350L)) {
                if (candidates != null && candidates.none { it.ownerPackage == null }) break
                delay(waitMs)
                currentCoroutineContext().ensureActive()
                candidates = read()
                emit(tracker.update(candidates))
            }
        }
    }.distinctUntilChanged()

    class Tracker {
        private var confirmedIds = emptySet<Int>()

        /** null means the snapshot failed, empty means the panel is gone. Scoped to one service. */
        fun update(candidates: List<Candidate>?): Boolean {
            if (candidates != null) {
                confirmedIds = candidates.filter {
                    it.ownerPackage == "com.android.systemui" ||
                        (it.ownerPackage == null && it.id in confirmedIds)
                }.map { it.id }.toSet()
            }
            return confirmedIds.isNotEmpty()
        }
    }

    /** Conservative heads-up geometry from the default-display accessibility touchable region.
     * Heads-up notifications need not take focus from the application underneath.
     * Ownership must still be verified by Tracker; full-screen shade uses isPanelWindow.
     */
    fun isHeadsUpWindow(
        systemWindow: Boolean,
        left: Int, top: Int, right: Int, bottom: Int,
        displayWidth: Int, displayHeight: Int,
    ): Boolean {
        if (!systemWindow || displayWidth <= 0 || displayHeight <= 0 || top > 0) return false
        val width = (minOf(right, displayWidth).toLong() - maxOf(left, 0)).coerceAtLeast(0)
        val height = (minOf(bottom, displayHeight).toLong() - maxOf(top, 0)).coerceAtLeast(0)
        return width * 5 >= displayWidth.toLong() * 4 &&
            height * 10 >= displayHeight && height * 2 < displayHeight
    }

    fun isPanelWindow(
        systemWindow: Boolean,
        focused: Boolean,
        left: Int, top: Int, right: Int, bottom: Int,
        displayWidth: Int, displayHeight: Int,
    ): Boolean {
        if (!systemWindow || !focused) return false
        if (displayWidth <= 0 || displayHeight <= 0 || top > 0) return false
        val width = (minOf(right, displayWidth).toLong() - maxOf(left, 0)).coerceAtLeast(0)
        val height = (minOf(bottom, displayHeight).toLong() - maxOf(top, 0)).coerceAtLeast(0)
        return width * 5 >= displayWidth.toLong() * 4 && height * 2 >= displayHeight
    }
}
