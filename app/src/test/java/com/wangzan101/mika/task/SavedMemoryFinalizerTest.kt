package com.wangzan101.mika.task

import com.wangzan101.mika.chat.ConversationStore
import com.wangzan101.mika.core.agent.Turn
import com.wangzan101.mika.core.memory.MemoryExtractor
import com.wangzan101.mika.core.memory.MemoryKind
import com.wangzan101.mika.core.memory.MemorySource
import com.wangzan101.mika.core.memory.NoteKind
import com.wangzan101.mika.memory.RunNotes
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

@OptIn(ExperimentalCoroutinesApi::class)
class SavedMemoryFinalizerTest {
    @get:Rule val tmp = TemporaryFolder()

    private inner class Fixture {
        val directory = tmp.newFolder()
        val conversations = ConversationStore(directory)
        val memory = memoryStore()
        val forgotten = memory.add(MemoryKind.preference, "I prefer jasmine tea", emptyList(),
            MemorySource("user_said", "I prefer jasmine tea", atMs = 1)).getOrThrow()
        val kept = memory.add(MemoryKind.preference, "I prefer window seats", emptyList(),
            MemorySource("user_said", "I prefer window seats", atMs = 1)).getOrThrow()
        val deletion = memory.forget(forgotten.item.id).getOrThrow()
        val published = mutableListOf<RunNotes>()

        init {
            for (conversation in listOf("earlier", "remote")) {
                conversations.append(conversation, Turn("remember", "saved", "succeeded", runId = "old-$conversation",
                    memoryNotes = MemoryExtractor.notes(listOf(forgotten, kept)),
                    usedMemory = listOf(forgotten.item.id, kept.item.id)))
            }
            conversations.append("remote", Turn("Forget my tea preference", "forgotten", "succeeded", runId = "remote-run"))
        }

        suspend fun finish(runId: String? = "remote-run") = SavedMemoryFinalizer.finish("remote", runId, listOf(deletion),
            strip = { conversations.stripMemory(it) },
            publish = { notes ->
                published += notes
                conversations.updateTurn(notes.conversationId, notes.runId) {
                    it.copy(memoryNotes = notes.memoryNotes, usedMemory = notes.usedMemory, skillNotes = notes.skillNotes)
                }
            },
        )

        fun assertCleaned() {
            // Reopen to check disk, including a different conversation's references.
            val reopened = ConversationStore(directory)
            for (conversation in listOf("earlier", "remote")) {
                val old = reopened.turns(conversation).first()
                assertEquals(listOf(kept.item.id), old.memoryNotes.map { it.memoryId })
                assertEquals(listOf(kept.item.id), old.usedMemory)
            }
            assertEquals(listOf(kept.item), memory.items.value)
        }

        fun assertUndoPublished() {
            val notes = published.single()
            assertEquals("remote", notes.conversationId)
            assertEquals("remote-run", notes.runId)
            assertTrue(notes.usedMemory.isEmpty())
            assertTrue(notes.skillNotes.isEmpty())
            val note = notes.memoryNotes.single()
            assertEquals(NoteKind.forgot, note.kind)
            assertEquals(forgotten.item.id, note.memoryId)
            assertEquals(deletion.undoToken, note.undoToken)
            assertEquals(notes.memoryNotes, ConversationStore(directory).turns("remote").last().memoryNotes)
            val token = requireNotNull(note.undoToken)
            assertTrue(memory.undo(token))
            assertTrue(forgotten.item in memory.items.value)
            assertFalse(memory.undo(token))
        }
    }

    @Test fun forgetRemovesOnlyDeletedReferencesAndPublishesWorkingUndo() = runTest {
        val fixture = Fixture()
        fixture.finish()
        fixture.assertCleaned()
        fixture.assertUndoPublished()
    }

    @Test fun missingRunIdStillStripsDeletedReferences() = runTest {
        val fixture = Fixture()
        fixture.finish(runId = null)
        fixture.assertCleaned()
        assertTrue(fixture.published.isEmpty())
    }

    @Test fun noSavedChangesDoesNotStripOrPublish() = runTest {
        SavedMemoryFinalizer.finish("remote", "run", emptyList(),
            strip = { error("No deletion was requested") },
            publish = { error("No memory change was requested") },
        )
    }

    @Test fun notificationFailureStillFinalizesSavedChanges() = runTest {
        val fixture = Fixture()
        val failure = IllegalStateException("notification failed")
        val caught = runCatching {
            RunLearning.launchAfter(this, notify = { throw failure }, finalizeSaved = { fixture.finish() }) {
                error("Judging must not run after failed notification")
            }
        }.exceptionOrNull()
        assertSame(failure, caught)
        runCurrent()
        fixture.assertCleaned()
        fixture.assertUndoPublished()
    }

    @Test fun notificationCancellationStillFinalizesSavedChanges() = runTest {
        val fixture = Fixture()
        val cancelled = CancellationException("service stopped during delivery")
        val caught = runCatching {
            RunLearning.launchAfter(this, notify = { throw cancelled }, finalizeSaved = { fixture.finish() }) {
                error("Judging must not run after cancelled notification")
            }
        }.exceptionOrNull()
        assertSame(cancelled, caught)
        runCurrent()
        fixture.assertCleaned()
        fixture.assertUndoPublished()
    }

    @Test fun savedChangesFinalizeBeforeBlockedOrFailingJudgment() = runTest {
        val fixture = Fixture()
        val finishJudging = CompletableDeferred<Unit>()
        val judgmentStarted = CompletableDeferred<Unit>()
        val failure = IllegalStateException("judging failed")
        var caught: Throwable? = null
        val job = RunLearning.launchAfter(this, notify = {}, finalizeSaved = { fixture.finish() }) {
            judgmentStarted.complete(Unit)
            caught = runCatching { finishJudging.await(); throw failure }.exceptionOrNull()
        }
        runCurrent()
        assertTrue(judgmentStarted.isCompleted)
        assertFalse(job.isCompleted)
        fixture.assertCleaned()
        fixture.assertUndoPublished()
        finishJudging.complete(Unit)
        job.join()
        assertSame(failure, caught)
        // A later judge failure must not republish the already-consumed undo token.
        assertEquals(1, fixture.published.size)
        assertTrue(fixture.forgotten.item in fixture.memory.items.value)
    }
}
