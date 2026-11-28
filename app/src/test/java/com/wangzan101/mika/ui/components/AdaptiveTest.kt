package com.wangzan101.mika.ui.components

import androidx.compose.ui.unit.dp
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** WOOWTECH fork: the large-screen rules shared with the iPad app (owner 2026-11-28). */
class AdaptiveTest {
    @Test fun contentIsAtMost720AndCentred() {
        // A phone keeps its 16 dp margins; a tablet centres a 720 dp column.
        assertEquals(16.dp, Adaptive.side(411.dp, 16.dp))
        assertEquals(16.dp, Adaptive.side(740.dp, 16.dp))
        assertEquals(40.dp, Adaptive.side(800.dp, 16.dp))
        assertEquals(280.dp, Adaptive.side(1280.dp, 16.dp))
        // Beside a docked inbox (1280 − 360 − 1 dp of hairline).
        assertEquals(99.5.dp, Adaptive.side(919.dp, 16.dp))
    }

    @Test fun inboxDocksFrom1100() {
        // Every iPad and Android tablet in landscape docks; the largest iPad Pro in portrait (1032 pt) does not.
        assertTrue(Adaptive.docked(1100.dp))
        assertTrue(Adaptive.docked(1280.dp))
        assertFalse(Adaptive.docked(1032.dp))
        assertFalse(Adaptive.docked(800.dp))
    }

    @Test fun sheetsBecomeWindowsFrom600() {
        assertTrue(Adaptive.sheetWindow(600.dp))
        assertTrue(Adaptive.sheetWindow(640.dp))
        assertFalse(Adaptive.sheetWindow(411.dp))
    }
}
