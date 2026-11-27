package com.wangzan101.mika.core.agent

import com.wangzan101.mika.core.model.ModelError
import com.wangzan101.mika.core.net.ProxyFailure
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** model_retry 的 detail 写法不变(运行记录照旧),界面能读回来,分得出断线和服务忙。 */
class RetryNoticeTest {
    @Test fun detailKeepsTheRecordedFormatAndReadsBack() {
        val n = RetryNotice(ModelCaller.ROLE_MAIN, RetryPolicy.label(ModelError.Server(502)), 1, 1000)
        assertEquals("main server_502 #1 1000ms", n.detail)
        assertEquals(n, RetryNotice.parse(n.detail))
        assertNull(RetryNotice.parse("main server_502 1000ms"))
    }

    @Test fun tellsANetworkProblemFromABusyService() {
        fun notice(e: Throwable) = RetryNotice("main", RetryPolicy.label(e), 1, 0)
        assertTrue(notice(ModelError.StreamCut()).network)
        assertTrue(notice(ModelError.Proxy(ProxyFailure.Unreachable)).network)
        assertFalse(notice(ModelError.RateLimited(1500)).network)
        assertFalse(notice(ModelError.Server(503)).network)
        assertTrue(RetryNotice.parse("light network #3 8000ms")!!.network)
    }
}
