package com.wangzan101.mika.woowbot

import com.wangzan101.mika.R
import org.junit.Assert.*
import org.junit.Test

class BotDownloadNamesTest {
    private fun resolve(explicit: String? = null, disposition: String? = null, url: String? = null, type: String? = null) =
        BotDownloadNames.resolve(explicit, disposition, url, type)

    @Test fun contentDispositionPrefersTheExtendedName() {
        assertEquals("報告 2026.pdf", BotDownloadNames.fromDisposition(
            "attachment; filename=\"report.pdf\"; filename*=UTF-8''%E5%A0%B1%E5%91%8A%202026.pdf"))
        assertEquals("a \"quoted\"; name.txt", BotDownloadNames.fromDisposition("attachment; filename=\"a \\\"quoted\\\"; name.txt\""))
        assertEquals("plain.csv", BotDownloadNames.fromDisposition("attachment;filename=plain.csv"))
        assertEquals("caf\u00e9.txt", BotDownloadNames.fromDisposition("attachment; filename*=iso-8859-1'en'caf%E9.txt"))
        assertEquals("a+b.txt", BotDownloadNames.fromDisposition("attachment; filename*=UTF-8''a+b.txt"))
        assertNull(BotDownloadNames.fromDisposition("inline"))
        assertNull(BotDownloadNames.fromDisposition(null))
    }

    @Test fun theNameOrderIsAnchorThenHeaderThenUrl() {
        assertEquals("from-anchor.pdf", resolve("from-anchor.pdf", "attachment; filename=header.pdf", "https://bot.example.com/f/url.pdf").first)
        assertEquals("header.pdf", resolve(null, "attachment; filename=header.pdf", "https://bot.example.com/f/url.pdf").first)
        assertEquals("影片 1.mp4", resolve(url = "https://bot.example.com/f/%E5%BD%B1%E7%89%87%201.mp4?x=1").first)
        assertEquals("download", resolve(url = "blob:https://bot.example.com/3f2a").first)
    }

    @Test fun aKnownExtensionDecidesTheType() {
        listOf(
            "a.png" to "image/png", "a.JPG" to "image/jpeg", "a.webp" to "image/webp", "a.heic" to "image/heic",
            "a.mp4" to "video/mp4", "a.mov" to "video/quicktime", "a.mp3" to "audio/mpeg", "a.m4a" to "audio/mp4", "a.wav" to "audio/wav",
            "a.pdf" to "application/pdf", "a.docx" to "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
            "a.xlsx" to "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", "a.doc" to "application/msword",
            "a.xls" to "application/vnd.ms-excel", "a.pptx" to "application/vnd.openxmlformats-officedocument.presentationml.presentation",
            "a.html" to "text/html", "a.zip" to "application/zip", "a.csv" to "text/csv", "a.json" to "application/json",
        ).forEach { (name, type) -> assertEquals(name, type, resolve(explicit = name, type = "application/octet-stream").second) }
        // The page's own type does not rename a file whose extension is known (the website saves HTML as octet-stream).
        assertEquals("page.html" to "text/html", resolve(explicit = "page.html", type = "application/octet-stream"))
        assertEquals("table.csv" to "text/csv", resolve(explicit = "table.csv", type = "text/plain;charset=utf-8"))
    }

    @Test fun aNameWithoutExtensionGetsTheTypesOne() {
        assertEquals("report.pdf" to "application/pdf", resolve(explicit = "report", type = "application/pdf"))
        assertEquals("photo.jpg" to "image/jpeg", resolve(explicit = "photo", type = "image/jpeg"))
        assertEquals("download" to "application/octet-stream", resolve(type = "application/octet-stream"))
        assertEquals("notes.weird" to "text/x-weird", resolve(explicit = "notes.weird", type = "text/x-weird"))
        // System lookups fill in what the table does not know.
        assertEquals("a.blend" to "application/x-blender",
            BotDownloadNames.resolve("a.blend", null, null, null, systemType = { if (it == "blend") "application/x-blender" else null }))
    }

    @Test fun namesCannotEscapeOrHideTheirExtension() {
        assertEquals("passwd", BotDownloadNames.sanitize("../../etc/passwd"))
        assertEquals("evil.exe", BotDownloadNames.sanitize("C:\\temp\\evil.exe"))
        assertEquals("abcfdp.exe", BotDownloadNames.sanitize("abc\u202Efdp.exe"))
        assertEquals("a_b", BotDownloadNames.sanitize("a\u0000_b"))
        assertEquals("download", BotDownloadNames.sanitize(" .. "))
        val long = BotDownloadNames.sanitize("n".repeat(300) + ".xlsx")
        assertEquals(BotDownloadNames.MAX_NAME, long.length)
        assertTrue(long.endsWith(".xlsx"))
    }

    @Test fun dataUrlsDecodeWithinTheLimit() {
        val png = BotDataUrl.decode("data:image/png;base64,iVBORw0KGgo=")
        assertEquals("image/png", png.type)
        assertArrayEquals(byteArrayOf(-119, 80, 78, 71, 13, 10, 26, 10), png.bytes)
        val text = BotDataUrl.decode("data:text/csv;charset=utf-8,a%2Cb%0A%E4%B8%AD,2")
        assertEquals("text/csv", text.type)
        assertEquals("a,b\n中,2", String(text.bytes, Charsets.UTF_8))
        assertEquals("text/plain", BotDataUrl.decode("data:,hi").type)
        val tooLarge = runCatching { BotDataUrl.decode("data:text/plain;base64," + "A".repeat(4000), limit = 1000) }.exceptionOrNull()
        assertEquals(R.string.bot_services_download_too_large, (tooLarge as BotDownloadException).reason)
        assertTrue(runCatching { BotDataUrl.decode("javascript:alert(1)") }.isFailure)
        assertTrue(runCatching { BotDataUrl.decode("data:text/plain;base64,A") }.isFailure)
    }

    @Test fun onlyTheServicesOwnObjectUrlsAreRead() {
        val service = BotService(id = "11111111-1111-4111-8111-111111111111", name = "QA", origin = "https://bot.example.com",
            profileId = "p", enabled = true)
        assertTrue(blobOfService("blob:https://bot.example.com/9b1d-44", service))
        assertFalse(blobOfService("blob:https://evil.example/9b1d-44", service))
        assertFalse(blobOfService("blob:null/9b1d-44", service))
        assertFalse(blobOfService("https://bot.example.com/file.pdf", service))
    }

    @Test fun evaluateJavascriptAnswersAreUnquoted() {
        assertNull(BotBlobReader.text("null"))
        assertEquals("started", BotBlobReader.text("\"started\""))
        assertEquals("{\"size\":3}", BotBlobReader.text("\"{\\\"size\\\":3}\""))
        assertEquals("true", BotBlobReader.text("true"))
    }
}
