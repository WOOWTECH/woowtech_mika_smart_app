package com.wangzan101.mika.core.cap.mcp

import okhttp3.RequestBody
import okio.BufferedSink

/** A tools/call may already have changed data when its HTTP response fails. */
internal fun RequestBody.forMcpToolCall(): RequestBody {
    val original = this
    return object : RequestBody() {
        override fun contentType() = original.contentType()
        override fun contentLength() = original.contentLength()
        override fun writeTo(sink: BufferedSink) = original.writeTo(sink)
        // Disabling connection retry alone does not stop OkHttp's HTTP 503 follow-up.
        override fun isOneShot() = true
    }
}
