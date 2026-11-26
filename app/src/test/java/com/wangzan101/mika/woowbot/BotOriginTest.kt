package com.wangzan101.mika.woowbot

import org.junit.Assert.*
import org.junit.Test

class BotOriginTest {
    @Test fun normalizesAndPinsExactOrigin() {
        val origin = BotOrigin.parse(" https://BOT.example:443/ ")
        assertEquals("https://bot.example", origin.value)
        assertTrue(origin.allows("https://bot.example/path?thread=abc#code=one-time"))
        listOf("https://bot.example.evil/", "https://evil@bot.example/", "https://bot.example:444/", "http://bot.example/", "javascript:alert(1)", "file:///etc/hosts", "https://bot.example\\@evil/").forEach {
            assertFalse(it, origin.allows(it))
        }
    }
    @Test fun rejectsStoredSecretsAndAmbiguousAddresses() {
        listOf("https://user:secret@bot.example", "https://bot.example/#code=secret", "https://bot.example?token=secret", "https://bot.example/path", "https://bot.example:0", "https://bot.example:65536", "https://bot.example./", "http://127.0.0.1", "https://169.254.169.254", "https://[::1]", "https://bot.example\n.evil", "x".repeat(2049)).forEach {
            assertThrows(it, Exception::class.java) { BotOrigin.parse(it, true) }
        }
    }
    @Test fun httpRequiresExplicitLanOptIn() {
        listOf("http://10.0.0.2:8768", "http://192.168.1.5", "http://172.16.0.5", "http://bot.local", "http://[fd00::1234]:8080").forEach {
            assertThrows(IllegalArgumentException::class.java) { BotOrigin.parse(it) }
            assertTrue(BotOrigin.parse(it, true).insecureLan)
        }
        listOf("http://bot.example", "http://8.8.8.8", "http://172.32.1.1", "http://192.168.001.1", "http://169.254.1.1", "http://[fe80::1]").forEach {
            assertThrows(it, IllegalArgumentException::class.java) { BotOrigin.parse(it, true) }
        }
    }
}
