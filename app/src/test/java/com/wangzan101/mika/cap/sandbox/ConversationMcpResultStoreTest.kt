package com.wangzan101.mika.cap.sandbox

import com.wangzan101.mika.core.workspace.SandboxPaths
import com.wangzan101.mika.core.workspace.SandboxTree
import com.wangzan101.mika.mcp.ConversationMcpResultStore
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.nio.file.Files

class ConversationMcpResultStoreTest {
    @Test fun longResultIsReadableInChunksOnlyFromItsConversationAndDeletedWithIt() = runBlocking {
        val root = Files.createTempDirectory("mcp-result").toFile()
        try {
            val dirs = SandboxDirs(File(root, "sandbox"), File(root, "tmp"), File(root, "lib"), JVM_GATE, SandboxTree())
            val body = "前段" + "甲".repeat(4100) + "😀後段"
            val ref = ConversationMcpResultStore(dirs, "chat-a").save("server", "search", body)
            assertTrue(ref.startsWith("${SandboxPaths.WORKSPACE}/mcp-results/"))
            val rel = ref.removePrefix("${SandboxPaths.WORKSPACE}/")
            val bytes = body.toByteArray(Charsets.UTF_8)
            val split = "前段".toByteArray(Charsets.UTF_8).size + "甲".repeat(4100).toByteArray(Charsets.UTF_8).size
            dirs.gate.openRead(dirs.workspace("chat-a"), rel).use { file ->
                assertEquals(bytes.size.toLong(), file.size)
                assertEquals("😀後段", file.read(split.toLong(), bytes.size - split).toString(Charsets.UTF_8))
            }
            assertFalse(File(dirs.workspace("chat-b"), rel).exists())
            dirs.deleteWorkspace("chat-a")
            assertFalse(File(dirs.workspace("chat-a"), rel).exists())
        } finally { root.deleteRecursively() }
    }
}
