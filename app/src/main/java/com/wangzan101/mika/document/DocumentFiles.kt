package com.wangzan101.mika.document

import android.content.ClipData
import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.core.content.FileProvider
import com.wangzan101.mika.chat.AttachFilesProvider
import com.wangzan101.mika.core.document.DocumentException
import com.wangzan101.mika.core.document.DocumentFormat
import com.wangzan101.mika.core.document.DocumentLimits
import com.wangzan101.mika.core.document.DocumentModel
import com.wangzan101.mika.core.document.DocumentProblem
import com.wangzan101.mika.core.document.DocumentWriters
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import java.io.File
import java.io.FilterOutputStream
import java.io.OutputStream
import java.util.UUID

internal data class GeneratedDocument(val file: File, val uri: Uri, val format: DocumentFormat)

internal object DocumentFiles {
    private const val KEEP_MS = 24 * 60 * 60 * 1000L
    private const val MAX_CACHE_BYTES = 64 * 1_048_576L
    private const val MAX_FILES = 32
    private val lock = Mutex()
    private val retentionLock = Any()

    suspend fun generate(context: Context, model: DocumentModel, format: DocumentFormat, tableIndex: Int?): GeneratedDocument =
        withContext(Dispatchers.IO) {
            lock.withLock {
                val root = File(context.cacheDir, "attach/documents").apply { mkdirs() }
                val now = System.currentTimeMillis()
                synchronized(retentionLock) {
                    root.listFiles().orEmpty().filter { now - it.lastModified() >= KEEP_MS }.forEach { it.deleteRecursively() }
                }
                val retained = root.listFiles().orEmpty()
                val bytes = retained.sumOf { dir -> dir.listFiles().orEmpty().sumOf { it.length() } }
                // Never evict a recent share to make room: recipients may still be reading it.
                if (retained.size >= MAX_FILES || bytes > MAX_CACHE_BYTES - DocumentLimits.MAX_FILE_BYTES)
                    throw DocumentException(DocumentProblem.CacheFull)
                val dir = File(root, UUID.randomUUID().toString()).apply { check(mkdir()) }
                val file = File(dir, DocumentWriters.filename(model.title, format))
                try {
                    val coroutine = currentCoroutineContext()
                    file.outputStream().use { raw ->
                        val output = LimitedOutput(raw)
                        when (format) {
                            DocumentFormat.HTML -> output.write(DocumentWriters.html(model).toByteArray(Charsets.UTF_8))
                            DocumentFormat.CSV -> output.write(DocumentWriters.csv(model, tableIndex))
                            DocumentFormat.PDF -> DocumentPdf(context, model) { coroutine.ensureActive() }.write(output)
                        }
                    }
                    coroutine.ensureActive()
                    GeneratedDocument(file, FileProvider.getUriForFile(context, AttachFilesProvider.authority(context.packageName), file), format)
                } catch (e: Throwable) {
                    dir.deleteRecursively()
                    throw e
                }
            }
        }

    /** Starts/extends retention when handed off, rather than deleting when the editor closes. */
    fun retain(document: GeneratedDocument) {
        synchronized(retentionLock) {
            check(document.file.isFile)
            document.file.parentFile?.setLastModified(System.currentTimeMillis())
        }
    }

    /** The existing viewer can also share/open a document after the editor has been dismissed. */
    fun retain(context: Context, uri: Uri) {
        if (uri.authority != AttachFilesProvider.authority(context.packageName)) return
        val parts = uri.pathSegments
        if (parts.size != 3 || parts[0] != "documents" || runCatching { UUID.fromString(parts[1]).toString() }.getOrNull() != parts[1]) return
        if (parts[2].contains('/') || parts[2] in setOf(".", "..")) return
        synchronized(retentionLock) {
            val directory = File(context.cacheDir, "attach/documents/${parts[1]}")
            if (File(directory, parts[2]).isFile) directory.setLastModified(System.currentTimeMillis())
        }
    }

    fun shareIntent(document: GeneratedDocument): Intent {
        retain(document)
        return Intent.createChooser(Intent(Intent.ACTION_SEND).apply {
            type = document.format.mime
            putExtra(Intent.EXTRA_STREAM, document.uri)
            clipData = ClipData.newRawUri(document.file.name, document.uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }, document.file.name).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    }

    suspend fun save(context: Context, document: GeneratedDocument, destination: Uri) = withContext(Dispatchers.IO) {
        retain(document)
        // "wt" also truncates a provider-selected existing destination.
        val output = context.contentResolver.openOutputStream(destination, "wt") ?: error("Cannot open destination")
        output.use { out ->
            document.file.inputStream().use { input ->
                val buffer = ByteArray(32 * 1024)
                while (true) {
                    currentCoroutineContext().ensureActive()
                    val read = input.read(buffer)
                    if (read < 0) break
                    out.write(buffer, 0, read)
                }
                out.flush()
            }
        }
    }

    private class LimitedOutput(output: OutputStream) : FilterOutputStream(output) {
        private var bytes = 0L
        private fun reserve(count: Int) {
            bytes += count
            if (bytes > DocumentLimits.MAX_FILE_BYTES) throw DocumentException(DocumentProblem.TooLarge)
        }
        override fun write(value: Int) { reserve(1); out.write(value) }
        override fun write(buffer: ByteArray, offset: Int, length: Int) { reserve(length); out.write(buffer, offset, length) }
    }
}
