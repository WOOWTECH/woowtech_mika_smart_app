package com.wangzan101.mika.settings

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test

class PlayTransportPolicyTest {
    @Test fun playEditionRequiresHttpsOutsideThePhone() {
        assumeTrue(PlayTransportPolicy.enabled)
        assertTrue(PlayTransportPolicy.permits("https://example.com/v1"))
        assertTrue(PlayTransportPolicy.permits("http://127.0.0.1:11434/v1"))
        assertTrue(PlayTransportPolicy.permits("http://localhost:11434/v1"))
        assertFalse(PlayTransportPolicy.permits("http://192.168.1.10:11434/v1"))
        assertFalse(PlayTransportPolicy.permits("http://example.com/v1"))
        assertFalse(PlayTransportPolicy.permits("not-a-url"))
    }
}
