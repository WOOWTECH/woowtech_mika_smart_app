package com.wangzan101.mika.task

import com.wangzan101.mika.core.memory.Change
import com.wangzan101.mika.core.memory.MemoryExtractor
import com.wangzan101.mika.memory.RunNotes

/** Finalize changes already made by memory tools, without extraction or skill learning. */
internal object SavedMemoryFinalizer {
    suspend fun finish(
        conversationId: String,
        runId: String?,
        saved: List<Change>,
        strip: suspend (Set<String>) -> Unit,
        publish: suspend (RunNotes) -> Unit,
    ) {
        val forgotten = saved.filterIsInstance<Change.Forgot>().map { it.before.id }.toSet()
        // Cleanup is required even when no run record exists to carry an undo note.
        if (forgotten.isNotEmpty()) strip(forgotten)
        if (runId == null || saved.isEmpty()) return
        publish(RunNotes(conversationId, runId, memoryNotes = MemoryExtractor.notes(saved)))
    }
}
