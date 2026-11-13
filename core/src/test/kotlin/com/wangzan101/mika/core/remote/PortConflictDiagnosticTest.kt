package com.wangzan101.mika.core.remote

import org.junit.Assert.*
import org.junit.Test
import java.net.BindException
import java.net.InetSocketAddress

/** Original shared server, real host sockets; does not identify the phone's port owner. */
class PortConflictDiagnosticTest {
    @Test fun secondInstanceFailsUntilFirstReleasesPort() {
        val first = MiniHttpServer(InetSocketAddress("127.0.0.1", 0), { HttpResponse.empty(200) })
        first.start()
        val port = first.port
        val second = MiniHttpServer(InetSocketAddress("127.0.0.1", port), { HttpResponse.empty(200) })
        try {
            val failure = runCatching { second.start() }.exceptionOrNull()
            assertTrue(failure.toString(), failure is BindException)
            first.stop()
            second.start()
            assertEquals(port, second.port)
        } finally {
            second.stop()
            first.stop()
        }
    }
}
