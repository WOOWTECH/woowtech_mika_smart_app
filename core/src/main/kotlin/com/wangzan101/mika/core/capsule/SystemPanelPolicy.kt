package com.wangzan101.mika.core.capsule

/** Conservative window-based proxy for an expanded notification / quick-settings panel.
 * No titles, text, accessibility focus, or active-window state: those can change on overlay events.
 * OEMs that do not expose a focused System UI window with these bounds are not detected.
 */
object SystemPanelPolicy {
    /** Only windows already passing type, input-focus and geometry checks enter this tracker. */
    data class Candidate(val id: Int, val ownerPackage: String?)

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
