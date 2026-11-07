package com.wangzan101.mika.core.model

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ModelAccessErrorsTest {
    private fun notAvailable(status: Int, body: String) = ModelAccessErrors.of(status, body, "m") as ModelError.ModelNotAvailable

    /** 各家「这个账号用不了这个模型」的说法:认成 ModelNotAvailable,带上服务端的原话。 */
    @Test fun accountCannotUseTheModel() {
        val notActivated = """{"code":"InvalidParameter","message":"The product is not activated, please confirm that you have activated products and try again after activation.","request_id":"x"}"""
        val e = notAvailable(400, notActivated)
        assertEquals("m", e.model)
        assertTrue(e.detail, e.detail.startsWith("The product is not activated"))
        assertEquals("Model access denied.", notAvailable(403, """{"error":{"code":"Model.AccessDenied","message":"Model access denied."}}""").detail)
        notAvailable(403, """{"error":{"message":"You are not authorized to access this model","type":"permission_error"}}""")
        notAvailable(403, """{"error":{"message":"Project does not have access to model gpt-x","code":"model_not_found"}}""")
        notAvailable(400, """{"error":{"code":"1220","message":"您当前使用该 API 的权限未开通"}}""")
        notAvailable(403, """{"error":{"message":"无权限访问该模型"}}""")
        // 404 也可能这样说
        notAvailable(404, """{"error":{"message":"Model not activated for this account"}}""")
        assertEquals("plain text not activated", notAvailable(400, "plain text not activated").detail)
    }

    @Test fun modelDoesNotSupportTools() {
        assertTrue(ModelAccessErrors.of(400, """{"error":{"message":"registry.ollama.ai/library/gemma:2b does not support tools"}}""", "gemma") is ModelError.ToolsUnsupported)
        assertTrue(ModelAccessErrors.of(400, """{"error":{"message":"Function calling is not supported for this model"}}""", "x") is ModelError.ToolsUnsupported)
    }

    /** 400 / 403 里说没有这个模型的:认成找不到模型,带上原话;404 没说别的由调用方照旧处理。 */
    @Test fun modelNotFoundInsideOtherStatuses() {
        val nf = ModelAccessErrors.of(400, """{"error":{"message":"Model Not Exist","type":"invalid_request_error"}}""", "m") as ModelError.ModelNotFound
        assertEquals("m", nf.model)
        assertEquals("Model Not Exist", nf.detail)
        assertTrue(ModelAccessErrors.of(400, """{"error":{"code":"model_not_found"}}""", "m") is ModelError.ModelNotFound)
        assertNull(ModelAccessErrors.of(404, """{"error":{"code":"model_not_found","message":"The model `x` does not exist or you do not have access to it."}}""", "m"))
    }

    /** 找不到模型时只要 JSON 里的原话:地址不对时反向代理回的 HTML 页、空内容不当原话。 */
    @Test fun jsonDetailTakesOnlyWhatJsonSays() {
        assertEquals("none of group/rpa's models is ready", ModelAccessErrors.jsonDetail("""{"error":{"type":"not_found_error","message":"none of group/rpa's models is ready"}}"""))
        assertEquals("no route", ModelAccessErrors.jsonDetail("""{"error":"no route"}"""))
        assertEquals("Not Found", ModelAccessErrors.jsonDetail("""{"detail":"Not Found"}"""))
        assertEquals("models/x not found", ModelAccessErrors.jsonDetail("""[{"error":{"code":404,"message":"models/x not found"}}]"""))
        assertEquals("", ModelAccessErrors.jsonDetail("<html><head><title>404 Not Found</title></head></html>"))
        assertEquals("", ModelAccessErrors.jsonDetail(""))
        assertEquals("<html><head><title>404 Not Found</title></head></html>", ModelAccessErrors.detail("<html><head><title>404 Not Found</title></head></html>"))
    }

    /** WOOWTECH fork: 网关(如 LiteLLM)把上游的 JSON 报错包在原话里转述时,取里面那句,不把 JSON 原样给人看。 */
    @Test fun nestedJsonErrorIsUnwrapped() {
        val litellm = """{"error":{"message":"litellm.BadRequestError: AnthropicException - {\"type\":\"error\",\"error\":{\"type\":\"invalid_request_error\",\"message\":\"Your credit balance is too low to access the Anthropic API.\"},\"request_id\":\"req_1\"}","type":null,"param":null,"code":"400"}}"""
        assertEquals("Your credit balance is too low to access the Anthropic API.", ModelAccessErrors.detail(litellm))
        assertEquals("Your credit balance is too low to access the Anthropic API.", ModelAccessErrors.jsonDetail(litellm))
        // 花括号里不是 JSON 的照原样
        assertEquals("Invalid value {name} for tools", ModelAccessErrors.detail("""{"error":{"message":"Invalid value {name} for tools"}}"""))
    }

    /** WOOWTECH fork: 认不出是哪一类的报错给人看的原话:先要原话,没有原话只有错误代码时给代码;HTML 错误页不算原话。 */
    @Test fun shownDetailPrefersWordsThenCodes() {
        assertEquals("Bad things", ModelAccessErrors.shownDetail("""{"error":{"code":"x","message":"Bad things"}}"""))
        assertEquals("MissingSessionID", ModelAccessErrors.shownDetail("""{"error":{"type":"MissingSessionID"}}"""))
        // 是 JSON 却没有原话、也没有代码:什么也不引
        assertEquals("", ModelAccessErrors.shownDetail("""{"id":"x","object":"error"}"""))
        assertEquals("upstream timeout", ModelAccessErrors.shownDetail("upstream timeout"))
        assertEquals("", ModelAccessErrors.shownDetail("<html><head><title>400 Bad Request</title></head></html>"))
        assertEquals("", ModelAccessErrors.shownDetail(""))
    }

    /** WOOWTECH fork: 认不出的 HTTP 报错带着状态码和原话,界面据此说原因;message 照旧(给开发看)。 */
    @Test fun unrecognizedHttpErrorKeepsStatusAndWords() {
        val e = ModelHttp.openAiError(400, null, """{"error":{"message":"Your credit balance is too low"}}""", "m") as ModelError.BadResponse
        assertEquals(400, e.status)
        assertEquals("Your credit balance is too low", e.said)
        assertTrue(e.message!!, e.message!!.startsWith("模型返回了无法解析的内容: HTTP 400 {\"error\""))
        val unreadable = ModelError.BadResponse("缺少 choices")
        assertNull(unreadable.status)
        assertEquals("", unreadable.said)
    }

    /** 原话去掉首尾空白;太长的截短,末尾加「…」。 */
    @Test fun longDetailIsClippedWithAnEllipsis() {
        assertEquals("short", ModelAccessErrors.jsonDetail("""{"error":{"message":"  short \n"}}"""))
        val long = "models/x is not found. " + "y".repeat(200)
        val clipped = ModelAccessErrors.jsonDetail("""{"error":{"message":"$long"}}""")
        assertEquals(161, clipped.length)
        assertTrue(clipped, clipped.startsWith("models/x is not found. yyy") && clipped.endsWith("y…"))
        assertEquals(clipped, ModelAccessErrors.detail("""{"error":{"message":"$long"}}"""))
    }

    /** 429 里说这个账号在这个模型上额度为零:换模型才行,认成用不了;其余 429(真限流、额度用完)交给调用方。 */
    @Test fun quotaZeroForThisModelIsNotAvailable() {
        val freeTierZero = """{"error":{"code":429,"message":"You exceeded your current quota, please check your plan and billing details. """ +
            """* Quota exceeded for metric: generativelanguage.googleapis.com/generate_content_free_tier_requests, limit: 0, model: gemini-x-pro",""" +
            """"status":"RESOURCE_EXHAUSTED","details":[{"@type":"type.googleapis.com/google.rpc.QuotaFailure","violations":[{"quotaMetric":"generate_content_free_tier_requests"}]}]}}"""
        val e = notAvailable(429, freeTierZero)
        assertTrue(e.detail, e.detail.startsWith("You exceeded your current quota"))
        notAvailable(429, """{"error":{"code":429,"message":"Quota exceeded","status":"RESOURCE_EXHAUSTED","details":[{"violations":[{"quotaValue":"0"}]}]}}""")
        notAvailable(429, """{"error":{"code":429,"message":"This model doesn't have a free quota tier. Please enable billing.","status":"RESOURCE_EXHAUSTED"}}""")
        // OpenAI 兼容的入口回的是数组
        val inArray = notAvailable(429, """[{"error":{"code":429,"message":"Quota exceeded for metric: free_tier_input_token_count, limit: 0","status":"RESOURCE_EXHAUSTED"}}]""")
        assertEquals("Quota exceeded for metric: free_tier_input_token_count, limit: 0", inArray.detail)
        assertNull(ModelAccessErrors.of(429, """{"error":{"code":429,"message":"Quota exceeded for metric: requests_per_minute, limit: 10. Please retry in 7s.","status":"RESOURCE_EXHAUSTED"}}""", "m"))
        assertNull(ModelAccessErrors.of(429, """{"error":{"code":429,"message":"Resource has been exhausted (e.g. check quota).","status":"RESOURCE_EXHAUSTED"}}""", "m"))
        assertNull(ModelAccessErrors.of(429, """{"error":{"code":429,"message":"limit: 0.5 rps","status":"RESOURCE_EXHAUSTED"}}""", "m"))
        assertNull(ModelAccessErrors.of(429, "", "m"))
    }

    /** 模型下线了:404 / 400 里说 no longer available、retired、model … deprecated 的认成用不了,带原话;Gemini 的 not found for API version 认成找不到。 */
    @Test fun retiredModels() {
        assertEquals(
            "Gemini 1.5 Flash is no longer available. Please switch to a newer model.",
            notAvailable(404, """{"error":{"code":404,"message":"Gemini 1.5 Flash is no longer available. Please switch to a newer model.","status":"NOT_FOUND"}}""").detail,
        )
        notAvailable(400, """{"error":{"message":"The model gemini-1.0-pro has been retired."}}""")
        notAvailable(400, """{"error":{"message":"models/gemini-1.5-pro-001 is deprecated and no longer served"}}""")
        notAvailable(400, """{"error":{"message":"This model is deprecated."}}""")
        notAvailable(400, """{"error":{"message":"该模型已下线"}}""")
        assertTrue(
            ModelAccessErrors.of(400, """{"error":{"code":400,"message":"models/gemini-x is not found for API version v1beta, or is not supported for generateContent.","status":"INVALID_ARGUMENT"}}""", "m")
                is ModelError.ModelNotFound,
        )
        // 只说某个参数弃用了的不认
        assertNull(ModelAccessErrors.of(400, """{"error":{"message":"The parameter `max_tokens` is deprecated, use `max_completion_tokens`."}}""", "m"))
    }

    /** 400 里说这个模型不能走当前这个接口(服务商要求另一套形状):算这个模型用不了、接着试下一个,带上服务端的原话。 */
    @Test fun modelCannotGoThroughThisEndpoint() {
        val shape = """{"error":{"message":"Model claude-sonnet-5-5 must be called via /provider/v1/messages (Anthropic Messages shape).","type":"invalid_request_error","param":"model","code":"unsupported_model"}}"""
        val e = notAvailable(400, shape)
        assertEquals("m", e.model)
        assertTrue(e.detail, e.detail.startsWith("Model claude-sonnet-5-5 must be called via /provider/v1/messages"))
        // 只说错误代码的
        notAvailable(400, """{"error":{"type":"invalid_request_error","param":"model","code":"unsupported_model"}}""")
        notAvailable(400, """{"error":{"message":"This model is only supported in v1/responses and not in v1/chat/completions.","param":"model"}}""")
        assertTrue(ModelAccessErrors.of(400, """{"error":{"message":"gpt-4o is not supported for this endpoint"}}""", "gpt-4o") is ModelError.ModelNotAvailable)
        // 请求本身不对的不认,交给调用方按状态码说
        assertNull(ModelAccessErrors.of(400, """{"error":{"message":"Invalid value for 'temperature': 3"}}""", "m"))
        // 说的是 Key 不能用这个接口、不是模型:不认,403 照旧由调用方当 Key 的问题
        assertNull(ModelAccessErrors.of(403, """{"error":{"message":"Your API key is not supported for this endpoint"}}""", "gpt-x"))
        assertTrue(ModelHttp.openAiError(403, null, """{"error":{"message":"Your API key is not supported for this endpoint"}}""", "gpt-x") is ModelError.Auth)
    }

    /** Key、额度、请求本身不对的不认;401 一律不看。 */
    @Test fun otherErrorsAreLeftToTheAdapter() {
        assertNull(ModelAccessErrors.of(401, """{"error":{"message":"not activated"}}""", "m"))
        assertNull(ModelAccessErrors.of(400, """{"error":{"message":"Invalid parameter: messages"}}""", "m"))
        assertNull(ModelAccessErrors.of(403, """{"error":{"message":"Incorrect API key provided"}}""", "m"))
        assertNull(ModelAccessErrors.of(500, """{"error":{"message":"not activated"}}""", "m"))
        assertNull(ModelAccessErrors.of(400, "context_length_exceeded", "m"))
    }
}
