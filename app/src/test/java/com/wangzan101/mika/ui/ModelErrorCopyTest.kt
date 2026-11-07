// WOOWTECH fork: tests for ModelErrorCopy. Not part of upstream Mika; see docs-woowtech/FORK.md.
package com.wangzan101.mika.ui

import com.wangzan101.mika.core.model.ListFailure
import com.wangzan101.mika.core.model.ModelError
import com.wangzan101.mika.core.model.ModelHttp
import com.wangzan101.mika.core.model.ModelListResult
import com.wangzan101.mika.core.net.ProxyFailure
import com.wangzan101.mika.i18n.EnglishTexts
import com.wangzan101.mika.i18n.ResFileTexts
import com.wangzan101.mika.i18n.UiText
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

class ModelErrorCopyTest {
    @get:Rule val texts = EnglishTexts()

    private val cjk = Regex("[\\u4e00-\\u9fff]")

    /** 认不出的 HTTP 报错:说状态码和服务端的原话,不贴整段报文;网关(LiteLLM)包着的上游报错取里面那句。 */
    @Test fun unrecognizedHttpErrorShowsTheStatusAndTheServersWords() {
        val litellm = """{"error":{"message":"litellm.BadRequestError: AnthropicException - {\"type\":\"error\",\"error\":{\"type\":\"invalid_request_error\",\"message\":\"Your credit balance is too low to access the Anthropic API.\"}}","type":null,"param":null,"code":"400"}}"""
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
        }
        for (f in ListFailure.entries) {
            val r = ModelErrorCopy.listFailure(ModelListResult.Failed(f))
            assertTrue("$f: $r", r.isNotBlank() && !cjk.containsMatchIn(r))
        }
        assertEquals("the server returned an error (HTTP 502)", ModelErrorCopy.reason(ModelError.Server(502)))
        assertEquals("the server returned an error (HTTP 500)", ModelErrorCopy.listFailure(ModelListResult.Failed(ListFailure.Server, "HTTP 500")))
    }

    /** 简体中文那份和 core 的说法逐字相同:上游的中文界面不变。 */
    @Test fun simplifiedChineseKeepsCoresWording() {
        UiText.source = ResFileTexts.chinese
        for (e in listOf(
            ModelError.Auth(), ModelError.QuotaExceeded(), ModelError.RateLimited(null), ModelError.ContextTooLong(), ModelError.Network(),
            ModelError.StreamCut(), ModelError.ContentRefused(), ModelError.ChatGptLimitReached(), ModelError.ChatGptNotEligible(),
        )) assertEquals(e.message, ModelErrorCopy.reason(e))
        for (f in listOf(ListFailure.Auth, ListFailure.RateLimited, ListFailure.Network, ListFailure.NotSupported, ListFailure.Server)) {
            assertEquals(f.text, ModelErrorCopy.listFailure(ModelListResult.Failed(f)))
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
}
