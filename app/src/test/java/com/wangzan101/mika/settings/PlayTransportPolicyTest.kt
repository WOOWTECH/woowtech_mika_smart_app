package com.wangzan101.mika.settings

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test

class PlayTransportPolicyTest {
    @Test fun playEditionRequiresHttpsOutsideThePhone() {
        assumeTrue(PlayTransportPolicy.enabled)
        assertTrue(PlayTransportPolicy.allows("https://example.com/v1"))
        assertTrue(PlayTransportPolicy.allows("http://127.0.0.1:11434/v1"))
        assertTrue(PlayTransportPolicy.allows("http://localhost:11434/v1"))
        assertFalse(PlayTransportPolicy.allows("http://192.168.1.10:11434/v1"))
        assertFalse(PlayTransportPolicy.allows("http://example.com/v1"))
        assertFalse(PlayTransportPolicy.allows("not-a-url"))
    }
}
