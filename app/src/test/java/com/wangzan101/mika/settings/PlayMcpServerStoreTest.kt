package com.wangzan101.mika.settings

import okhttp3.OkHttpClient
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

/** The Play package ships no Linux sandbox: local (stdio) MCP servers can't be saved, HTTPS ones still can. */
class PlayMcpServerStoreTest {
    @get:Rule val tmp = TemporaryFolder()

    private class PlainCipher : KeyCipher {
        override fun encrypt(plain: ByteArray) = plain
        override fun decrypt(data: ByteArray) = data
    }

    @Test fun playEditionRejectsLocalMcpServers() {
        assumeTrue(PlayTransportPolicy.enabled)
        assertFalse(PlayTransportPolicy.allowsStdioMcp)
        val store = McpServerStore(tmp.root, PlainCipher(), OkHttpClient())
        val local = McpServerConfig(name = "Local", url = "", transport = "stdio", command = "echo hi")
        assertEquals("stdio MCP servers are not available on this build", store.add(local).exceptionOrNull()?.message)
        assertTrue(store.servers.value.isEmpty())
        assertTrue(store.add("Remote", "https://mcp.example.com/mcp").isSuccess)
    }
}
