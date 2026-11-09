// WOOWTECH fork: tests for ModelErrorCopy. Not part of upstream Mika; see docs-woowtech/FORK.md.
package com.wangzan101.mika.ui

import com.wangzan101.mika.core.agent.FailKind
import com.wangzan101.mika.core.agent.TaskState
import com.wangzan101.mika.core.agent.ModelCallDeadlineExceeded
import com.wangzan101.mika.core.record.RunEvent
import com.wangzan101.mika.core.model.ListFailure
import com.wangzan101.mika.core.model.ModelError
import com.wangzan101.mika.core.model.ModelHttp
import com.wangzan101.mika.core.model.ModelListResult
import com.wangzan101.mika.core.net.ProxyFailure
import com.wangzan101.mika.i18n.EnglishTexts
import com.wangzan101.mika.i18n.ResFileTexts
import com.wangzan101.mika.i18n.UiText
import org.junit.Assert.assertEquals
import org.junit.Assert.assertSame
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

class ModelErrorCopyTest {
    @get:Rule val texts = EnglishTexts()

    private val cjk = Regex("[\\u4e00-\\u9fff]")

    /** LiteLLM 网关转述上游(Anthropic)的报错:原话包在一段 JSON 里。 */
    private val litellm = """{"error":{"message":"litellm.BadRequestError: AnthropicException - {\"type\":\"error\",\"error\":{\"type\":\"invalid_request_error\",\"message\":\"Your credit balance is too low to access the Anthropic API.\"}}","type":null,"param":null,"code":"400"}}"""

    /** 认不出的 HTTP 报错:说状态码和服务端的原话,不贴整段报文;网关(LiteLLM)包着的上游报错取里面那句。 */
    @Test fun unrecognizedHttpErrorShowsTheStatusAndTheServersWords() {
        assertEquals(
            "the server returned an error (HTTP 400): Your credit balance is too low to access the Anthropic API.",
            ModelErrorCopy.reason(ModelHttp.openAiError(400, null, litellm, "m")),
        )
        assertEquals("the server returned an error (HTTP 400): MissingSessionID",
            ModelErrorCopy.reason(ModelHttp.openAiError(400, null, """{"error":{"type":"MissingSessionID"}}""", "m")))
        // 反向代理的 HTML 错误页不当原话
        assertEquals("the server returned an error (HTTP 418)", ModelErrorCopy.reason(ModelHttp.openAiError(418, null, "<html>teapot</html>", "m")))
        // 流里报的错:没有状态码,有原话
        assertEquals("the model service reported an error: Overloaded", ModelErrorCopy.reason(ModelError.BadResponse("{}", said = "Overloaded")))
        // 内容看不懂:不把 core 给开发看的细节(简体中文)带出来
        assertEquals("its reply couldn’t be read; check that the base URL and API type match", ModelErrorCopy.reason(ModelError.BadResponse("缺少 choices")))
    }

    /** 英文界面里每一种原因都是英文,不留中文。 */
    @Test fun everyReasonIsEnglishInTheEnglishUi() {
        val all = listOf(
            ModelError.Auth(), ModelError.QuotaExceeded(), ModelError.RateLimited(null), ModelError.ContextTooLong(),
            ModelError.ModelNotFound("m"), ModelError.ModelNotAvailable("m"), ModelError.ModelNotAvailable("m", "not activated"),
            ModelError.ToolsUnsupported("m"), ModelError.Network(), ModelError.Proxy(ProxyFailure.Unreachable), ModelError.Proxy(ProxyFailure.AuthFailed),
            ModelError.StreamCut(), ModelError.Server(502), ModelError.ContentRefused(), ModelError.ChatGptLimitReached(),
            ModelError.ChatGptNotEligible("plan"), ModelError.SignInExpired("xAI"), ModelError.AccountPlanNotAllowed("xAI", "tier"),
            ModelError.BadResponse(), ModelError.BadResponse.http(400, "{}"),
        )
        for (e in all) {
            val r = ModelErrorCopy.reason(e)
            assertTrue("${e::class.simpleName}: $r", r.isNotBlank() && !cjk.containsMatchIn(r))
            val f = ModelErrorCopy.failure(e)
            assertTrue("${e::class.simpleName}: $f", f.isNotBlank() && !cjk.containsMatchIn(f))
        }
        for (f in ListFailure.entries) {
            val r = ModelErrorCopy.listFailure(ModelListResult.Failed(f))
            assertTrue("$f: $r", r.isNotBlank() && !cjk.containsMatchIn(r))
        }
        assertEquals("the server returned an error (HTTP 502)", ModelErrorCopy.reason(ModelError.Server(502)))
        assertEquals("the service had a temporary error; try again later (HTTP 500)",
            ModelErrorCopy.listFailure(ModelListResult.Failed(ListFailure.Server, "HTTP 500")))
    }

    /** 简体中文那份和 core 的说法逐字相同:上游的中文界面不变。 */
    @Test fun simplifiedChineseKeepsCoresWording() {
        UiText.source = ResFileTexts.chinese
        for (e in listOf(
            ModelError.Auth(), ModelError.QuotaExceeded(), ModelError.RateLimited(null), ModelError.ContextTooLong(), ModelError.Network(),
            ModelError.StreamCut(), ModelError.ContentRefused(), ModelError.ChatGptLimitReached(), ModelError.ChatGptNotEligible(),
        )) assertEquals(e.message, ModelErrorCopy.reason(e))
        for (f in listOf(ListFailure.Auth, ListFailure.RateLimited, ListFailure.Network, ListFailure.NotSupported, ListFailure.Server, ListFailure.BadResponse)) {
            assertEquals(f.text, ModelErrorCopy.listFailure(ModelListResult.Failed(f)))
            assertEquals(ModelListResult.Failed(f, "HTTP 500").message, ModelErrorCopy.listFailure(ModelListResult.Failed(f, "HTTP 500")))
        }
    }

    /** 繁中界面:台湾的说法、全形标点。 */
    @Test fun traditionalChinese() {
        UiText.source = ResFileTexts.traditional
        assertEquals("API Key 無效或沒有權限", ModelErrorCopy.reason(ModelError.Auth()))
        assertEquals("伺服器端出錯（HTTP 400）：MissingSessionID",
            ModelErrorCopy.reason(ModelHttp.openAiError(400, null, """{"error":{"type":"MissingSessionID"}}""", "m")))
        assertEquals("連不上這個位址，請檢查網路和介面網址", ModelErrorCopy.listFailure(ModelListResult.Failed(ListFailure.Network)))
    }

    /** 任务因模型出错没做完时那一句:按界面语言说原因,再说去哪查或稍后再试;不贴报文,原话句末的点不重复。 */
    @Test fun taskFailureSaysWhatToDo() {
        val credit = ModelHttp.openAiError(400, null, litellm, "m")
        assertEquals(
            "The model call failed: the server returned an error (HTTP 400): Your credit balance is too low to access the Anthropic API. Check Settings › Models.",
            ModelErrorCopy.failure(credit),
        )
        assertEquals("The model call failed: the API key is invalid or has no access. Check Settings › Models.", ModelErrorCopy.failure(ModelError.Auth()))
        // 等一会儿就可能好的叫人稍后再试;原因里已经说了怎么办的不再多说
        assertEquals("The model call failed: the server returned an error (HTTP 502). Try again later.", ModelErrorCopy.failure(ModelError.Server(502)))
        assertEquals("The model call failed: too many requests; try again later.", ModelErrorCopy.failure(ModelError.RateLimited(null)))
        assertEquals("The model call failed: its reply couldn’t be read; check that the base URL and API type match.",
            ModelErrorCopy.failure(ModelError.BadResponse("缺少 choices")))
        // 404 不一定是没有这个模型:有原话时照原话说
        assertEquals(
            "The model call failed: the model service reported an error: none of group/rpa’s models is ready. Check Settings › Models.",
            ModelErrorCopy.failure(ModelError.ModelNotFound("group/rpa", "none of group/rpa’s models is ready")),
        )
        assertEquals("The model call failed: the provider has no such model. Check Settings › Models.", ModelErrorCopy.failure(ModelError.ModelNotFound("m")))
        // 代理的问题只说代理那句
        val proxy = ModelError.Proxy(ProxyFailure.Unreachable)
        assertEquals(ModelErrorCopy.reason(proxy), ModelErrorCopy.failure(proxy))
        UiText.source = ResFileTexts.traditional
        assertEquals("呼叫模型失敗：伺服器端出錯（HTTP 400）：Your credit balance is too low to access the Anthropic API。請到設定 › 模型檢查。", ModelErrorCopy.failure(credit))
        assertEquals("呼叫模型失敗：回覆還沒傳完，連線就中斷了。請稍後再試。", ModelErrorCopy.failure(ModelError.StreamCut()))
        UiText.source = ResFileTexts.chinese
        assertEquals("调用模型失败：API Key 无效或没有权限。请到设置 › 模型检查。", ModelErrorCopy.failure(ModelError.Auth()))
    }

    /** 任务一结束,模型出错的原因就换成按界面语言写的那句,种类不变;别的结局原样。 */
    @Test fun modelFailureIsLocalizedWhenTheTaskEnds() {
        val failed = TaskState.Failed("模型服务出错(HTTP 502),请稍后再试。", FailKind.Model, ModelError.Server(502))
        assertEquals(
            TaskState.Failed("The model call failed: the server returned an error (HTTP 502). Try again later.", FailKind.Model),
            ModelErrorCopy.localized(failed),
        )
        val noAnswer = TaskState.Failed("模型停止了操作,没有给出回答。", FailKind.Model)
        assertSame(noAnswer, ModelErrorCopy.localized(noAnswer))
        assertSame(TaskState.Cancelled, ModelErrorCopy.localized(TaskState.Cancelled))
    }

    @Test fun deadlineFailureAndStoppedEventUseLocalizedCopyWithoutDiagnostics() {
        val reason = ModelCallDeadlineExceeded(12345).message.orEmpty()
        val failed = TaskState.Failed(reason, FailKind.Model)
        val event = RunEvent.State(0, "model_retry_stopped", "call_deadline 12345ms")
        val expected = "The model took too long to respond, including time spent retrying. Retries have stopped; the task is not complete."
        assertEquals(TaskState.Failed(expected, FailKind.Model), ModelErrorCopy.localized(failed))
        assertEquals(expected, ModelErrorCopy.retryStopped(event))
        UiText.source = ResFileTexts.traditional
        val traditional = "等待模型回覆的時間已達上限（包含重試等待）。已停止重試，任務尚未完成。"
        assertEquals(TaskState.Failed(traditional, FailKind.Model), ModelErrorCopy.localized(failed))
        assertEquals(traditional, ModelErrorCopy.retryStopped(event))
    }

    @Test fun deadlineMappingDoesNotRewriteReceiptsOrExposeUnknownStateDetails() {
        val reason = ModelCallDeadlineExceeded(12345).message.orEmpty()
        val receipt = TaskState.Failed("Partial result: [page](https://example.com). $reason", FailKind.GaveUp)
        assertSame(receipt, ModelErrorCopy.localized(receipt))
        val quoted = TaskState.Failed("Quoted error: $reason", FailKind.Model)
        assertSame(quoted, ModelErrorCopy.localized(quoted))
        val otherKind = TaskState.Failed(reason, FailKind.Environment)
        assertSame(otherKind, ModelErrorCopy.localized(otherKind))
        assertNull(ModelErrorCopy.retryStopped(RunEvent.State(0, "model_retry_stopped", "internal result: secret")))
        assertNull(ModelErrorCopy.retryStopped(RunEvent.State(0, "other", "call_deadline 12345ms")))
    }
}
