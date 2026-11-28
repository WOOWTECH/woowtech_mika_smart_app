package com.wangzan101.mika.woowbot

import org.junit.Assert.*
import org.junit.Test

class BotPairingQrTest {
    private val origin = BotOrigin.parse("https://bot.example.com")
    @Test fun acceptsOnlySameServicePairingFragment() {
        val url = "https://bot.example.com/pair#code=ABCDEF-123456"
        assertEquals(url, BotPairingQr.validate(url, origin))
    }
    @Test fun acceptsTheServersPhoneQrForThisServiceAsItsOwnPairingLink() {
        assertEquals("https://bot.example.com/pair#code=ABCD-EFGH-IJKL",
            BotPairingQr.validate("openmausbot://pair?address=https%3A%2F%2Fbot.example.com&code=ABCD-EFGH-IJKL", origin))
        assertEquals("https://bot.example.com/pair#code=ABCD-EFGH-IJKL",
            BotPairingQr.validate("openmausbot://pair?code=ABCD-EFGH-IJKL&address=https%3A%2F%2Fbot.example.com%2F", origin))
    }
    @Test fun rejectsAPhoneQrForAnotherServerOrWithAmbiguousParts() {
        listOf(
            "openmausbot://pair?address=https%3A%2F%2Fevil.example&code=ABCD-EFGH-IJKL",
            "openmausbot://pair?address=http%3A%2F%2Fbot.example.com&code=ABCD-EFGH-IJKL",
            "openmausbot://pair?address=https%3A%2F%2Fbot.example.com%2Fx&code=ABCD-EFGH-IJKL",
            "openmausbot://pair?address=https%3A%2F%2Fbot.example.com",
            "openmausbot://pair?code=ABCD-EFGH-IJKL",
            "openmausbot://pair?address=https%3A%2F%2Fbot.example.com&code=ABCD-EFGH-IJKL&redirect=x",
            "openmausbot://pair?address=https%3A%2F%2Fbot.example.com&code=ABCD&code=EFGH-IJKL",
            "openmausbot://pair?address=https%3A%2F%2Fbot.example.com&code=AB%3CCD%3EEFGH",
            "openmausbot://pair?address=https%3A%2F%2Fbot.example.com&code=abc",
            "openmausbot://pair?address=https%3A%2F%2Fbot.example.com&code=ABCD-EFGH-IJKL#x",
            "openmausbot://thread/abc?address=https%3A%2F%2Fbot.example.com&code=ABCD-EFGH-IJKL",
            "openmausbot://pair/x?address=https%3A%2F%2Fbot.example.com&code=ABCD-EFGH-IJKL",
            "openmausbot://user@pair?address=https%3A%2F%2Fbot.example.com&code=ABCD-EFGH-IJKL",
        ).forEach { value -> assertTrue(value, runCatching { BotPairingQr.validate(value, origin) }.isFailure) }
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
