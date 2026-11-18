package com.wangzan101.mika.cap.sandbox

import com.wangzan101.mika.core.cap.sandbox.SandboxStatus
import com.wangzan101.mika.core.workspace.SandboxError
import com.wangzan101.mika.core.workspace.SandboxTree
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import java.io.File
import java.nio.file.Files

/** 商店版只有文件的工作区:附件所在的同一个对话工作区照样找得到,命令和长驻进程一律不起。 */
class FilesOnlySandboxTest {
    private val tmp: File = Files.createTempDirectory("files-only").toFile()
    private fun dirs() = SandboxDirs(File(tmp, "files/sandbox"), File(tmp, "cache/proot-tmp"), File(tmp, "lib"), JVM_GATE, SandboxTree())
    private fun workspace() = AndroidSandbox(dirs(), { SandboxStatus.Ready(network = false) }, { emptyList() }, commands = false)

    @Test fun findsAttachmentsButRunsNothing() {
        val sb = workspace()
        assertFalse(sb.runsCommands)
        assertTrue(sb.status() is SandboxStatus.Ready)
        val inbox = File(dirs().workspace("conv"), "inbox").apply { mkdirs() }
        File(inbox, "photo.jpg").writeBytes(byteArrayOf(1, 2, 3))
        assertNotNull(sb.hostRoot("conv", "/workspace/inbox/photo.jpg", forWrite = false))
        assertEquals(File(inbox, "photo.jpg").canonicalFile, sb.hostPath("conv", "/workspace/inbox/photo.jpg", forWrite = false)?.canonicalFile)
        try {
            runBlocking { sb.run("conv", listOf("/bin/sh", "-lc", "ls"), null, 1_000) {} }
            fail("files-only workspace ran a command")
        } catch (e: SandboxError) {
            assertEquals(AndroidSandbox.COMMANDS_UNAVAILABLE, e.code)
        }
        try {
            runBlocking { sb.openProcess("conv", listOf("node", "server.js")) }
            fail("files-only workspace started a process")
        } catch (e: SandboxError) {
            assertEquals(AndroidSandbox.COMMANDS_UNAVAILABLE, e.code)
        }
    }

    @Test fun directDownloadSandboxStillRunsCommands() {
        assertTrue(AndroidSandbox(dirs(), { SandboxStatus.Ready(network = false) }, { emptyList() }).runsCommands)
    }
}
