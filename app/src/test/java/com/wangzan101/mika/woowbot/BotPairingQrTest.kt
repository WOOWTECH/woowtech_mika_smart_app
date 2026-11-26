package com.wangzan101.mika.woowbot

import org.junit.Assert.*
import org.junit.Test

class BotPairingQrTest {
    private val origin = BotOrigin.parse("https://bot.example.com")
    @Test fun acceptsOnlySameServicePairingFragment() {
        val url = "https://bot.example.com/pair#code=ABCDEF-123456"
        assertEquals(url, BotPairingQr.validate(url, origin))
    }
    @Test fun rejectsCrossOriginCommandsCredentialsAndAmbiguousParameters() {
        listOf(
            "https://evil.example/pair#code=ABCDEF",
            "https://bot.example.com.evil.example/pair#code=ABCDEF",
            "https://user@bot.example.com/pair#code=ABCDEF",
            "http://bot.example.com/pair#code=ABCDEF",
            "javascript:alert(1)", "file:///pair#code=ABCDEF",
            "https://bot.example.com/pair?code=ABCDEF",
            "https://bot.example.com/pair?redirect=evil#code=ABCDEF",
            "https://bot.example.com/other#code=ABCDEF",
            "https://bot.example.com/pair#code=ABCDEF&code=GHIJKL",
            "https://bot.example.com/pair#code=ABCDEF&redirect=evil",
            "https://bot.example.com/pair#code=%41BCDEF",
            "https://bot.example.com/pair#code=abc",
            "https://bot.example.com/pair#code=" + "a".repeat(257),
            "https://bot.example.com/pair#code=ABCDEF\n",
        ).forEach { value -> assertTrue("Unsafe QR accepted", runCatching { BotPairingQr.validate(value, origin) }.isFailure) }
    }
}
