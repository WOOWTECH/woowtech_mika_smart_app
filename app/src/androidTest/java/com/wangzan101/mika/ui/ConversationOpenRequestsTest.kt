package com.wangzan101.mika.ui

import android.content.Intent
import android.os.Bundle
import android.os.Parcel
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

/** Android Intent/Bundle semantics without starting tasks, models, or the phone helper. */
@RunWith(AndroidJUnit4::class)
class ConversationOpenRequestsTest {
    private fun intent(id: String) = Intent().putExtra(MainActivity.EXTRA_OPEN_CONVERSATION, id)

    private fun saved(requests: ConversationOpenRequests): Bundle {
        val parcel = Parcel.obtain()
        return try {
            val state = Bundle().also(requests::save)
            parcel.writeBundle(state)
            parcel.setDataPosition(0)
            parcel.readBundle(javaClass.classLoader)!!
        } finally { parcel.recycle() }
    }

    @Test fun consumedLaunchIsNotReplayedFromAnOriginalIntentAfterRestoration() {
        val original = intent("b").putExtra("unrelated", "keep")
        val frameworkCopy = Intent(original)
        val requests = ConversationOpenRequests()
        requests.restore(original, null)
        requests.consumed(requests.pending!!)
        assertFalse(original.hasExtra(MainActivity.EXTRA_OPEN_CONVERSATION))
        assertEquals("keep", original.getStringExtra("unrelated"))

        val restored = ConversationOpenRequests()
        restored.restore(frameworkCopy, saved(requests))
        assertNull(restored.pending)
        assertFalse(frameworkCopy.hasExtra(MainActivity.EXTRA_OPEN_CONVERSATION))
    }

    @Test fun unhandledRequestSurvivesRestorationAndLauncherDelivery() {
        val requests = ConversationOpenRequests()
        val source = intent("b")
        requests.receive(source)
        requests.receive(Intent(Intent.ACTION_MAIN))
        assertTrue(source.hasExtra(MainActivity.EXTRA_OPEN_CONVERSATION))
        val restored = ConversationOpenRequests()
        restored.restore(Intent(Intent.ACTION_MAIN), saved(requests))
        assertEquals("b", restored.pending!!.conversationId)
        restored.consumed(restored.pending!!)
        assertNull(restored.pending)
    }

    @Test fun oldCompletionCannotConsumeANewerSameOrDifferentTarget() {
        for (nextId in listOf("b", "c")) {
            val requests = ConversationOpenRequests()
            requests.receive(intent("b"))
            val old = requests.pending!!
            val nextIntent = intent(nextId)
            requests.receive(nextIntent)
            val next = requests.pending!!
            assertNotSame(old, next)
            requests.consumed(old)
            assertSame(next, requests.pending)
            assertEquals(nextId, nextIntent.getStringExtra(MainActivity.EXTRA_OPEN_CONVERSATION))
            requests.consumed(next)
            assertNull(requests.pending)
            assertFalse(nextIntent.hasExtra(MainActivity.EXTRA_OPEN_CONVERSATION))
        }
    }

    @Test fun aNewDeliveryAfterConsumedRestorationIsNotSuppressed() {
        val requests = ConversationOpenRequests()
        requests.receive(intent("b"))
        requests.consumed(requests.pending!!)
        val restored = ConversationOpenRequests()
        restored.restore(intent("b"), saved(requests))
        restored.receive(intent("b"))
        assertEquals("b", restored.pending!!.conversationId)
    }
}
