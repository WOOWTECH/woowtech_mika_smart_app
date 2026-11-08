package com.wangzan101.mika.core.brand

import java.io.File
import java.util.Properties
import org.junit.Assert.*
import org.junit.Test

class ApporoBrandTest {
    private fun apporo() = BrandValues(Properties().apply {
        File("../app/src/apporo/resources/brand.properties").reader(Charsets.UTF_8).use(::load)
    })

    @Test fun independentIdentityAndUpdateChannel() {
        val brand = apporo()
        assertEquals("Apporo Assistant", brand.name)
        assertEquals("Apporo Assistant", brand.nameZh)
        assertEquals("en", brand.defaultLanguage)
        assertTrue(brand.latestReleaseApi.contains("/apporo-assistant-releases/"))
        assertEquals("Open Apporo Assistant", brand.text("Open Mika"))
        assertEquals("mika_run_task", brand.text("mika_run_task"))
        assertNull(BrandValues(Properties()).defaultLanguage)
    }

    @Test fun apporoIdentityRetainsCoreInstructions() {
        val original = "You are Mika, the user's assistant. Never bypass confirmation."
        val result = apporo().prompt(BrandValues.IDENTITY, original)
        assertTrue(result.startsWith("You are Apporo Assistant, the user's assistant. Never bypass confirmation."))
        assertTrue(result.contains("Never invent a server address"))
        assertEquals("untouched tool instructions", apporo().prompt("tools/phone_tap.md", "untouched tool instructions"))
    }
}
