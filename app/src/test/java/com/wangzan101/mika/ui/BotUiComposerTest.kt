package com.wangzan101.mika.ui

import com.wangzan101.mika.chat.ConversationStore
import com.wangzan101.mika.core.agent.TaskState
import com.wangzan101.mika.takeover.Takeover
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.test.*
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

@OptIn(ExperimentalCoroutinesApi::class)
class BotUiComposerTest {
    @get:Rule val tmp = TemporaryFolder()
    private val actions = object : TaskActions {
        override fun start(goal: String, conversationId: String) {}
        override fun cancel() {}
        override fun resume() {}
        override fun takeOver() {}
        override fun handBack() {}
        override fun finishedMyself() {}
        override fun skip() {}
        override fun answer(text: String) {}
        override fun approve(key: Int) {}
        override fun decline(key: Int) {}
    }
    private fun TestScope.vm(describe: suspend (List<String>) -> List<PendingAttachment> = { emptyList() }) = ChatViewModel(
        backgroundScope, MutableStateFlow(TaskState.Idle), MutableStateFlow(Takeover.Stage.None), actions,
        ConversationStore(tmp.newFolder()), sandboxReady = MutableStateFlow(true), describeAttachments = describe,
    ).also { runCurrent() }

    @Test fun stableFreshIdentityAndAttachmentsStayWithTheirConversation() = runTest {
        val vm = vm()
        val a = vm.botUiConversationId()
        assertEquals(a, vm.botUiConversationId())
        val attachment = PendingAttachment("content://test/a", "a.txt", 42)
        vm.toggleAttachment(attachment)
        vm.newConversation()
        val b = vm.botUiConversationId()
        assertNotEquals(a, b)
        assertTrue(vm.ui.value.attachments.isEmpty())
        vm.openConversation(a)
        assertEquals(listOf(attachment), vm.ui.value.attachments)
        vm.removeAttachment(attachment.uri)
        vm.openConversation(b)
        vm.openConversation(a)
        assertTrue(vm.ui.value.attachments.isEmpty())
    }

    @Test fun lateAttachmentDescriptionIsNotDeliveredToNewConversation() = runTest {
        val ready = CompletableDeferred<List<PendingAttachment>>()
        val vm = vm { ready.await() }
        val a = vm.botUiConversationId()
        vm.attach(listOf("content://test/a"))
        runCurrent()
        vm.newConversation()
        vm.botUiConversationId()
        val attachment = PendingAttachment("content://test/a", "a.txt", 42)
        ready.complete(listOf(attachment))
        runCurrent()
        assertTrue(vm.ui.value.attachments.isEmpty())
        vm.openConversation(a)
        assertEquals(listOf(attachment), vm.ui.value.attachments)
    }

    @Test fun originalUnscopedBehaviorIsUnchangedUntilBotUiIsEnabled() = runTest {
        val vm = vm()
        vm.toggleAttachment(PendingAttachment("content://test/a", "a.txt", 42))
        vm.newConversation()
        assertNull(vm.ui.value.conversationId)
        assertTrue(vm.ui.value.attachments.isEmpty())
    }
}
