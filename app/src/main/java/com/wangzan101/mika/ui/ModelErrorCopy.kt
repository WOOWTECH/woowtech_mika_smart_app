// WOOWTECH fork: model errors in the UI language. Not part of upstream Mika; see docs-woowtech/FORK.md.
package com.wangzan101.mika.ui

import com.wangzan101.mika.R
import com.wangzan101.mika.core.agent.TaskState
import com.wangzan101.mika.core.agent.FailKind
import com.wangzan101.mika.core.agent.ModelCallDeadlineExceeded
import com.wangzan101.mika.core.record.RunEvent
import com.wangzan101.mika.core.model.ListFailure
import com.wangzan101.mika.core.model.ModelError
import com.wangzan101.mika.core.model.ModelListResult
import com.wangzan101.mika.core.net.ProxyFailure
import com.wangzan101.mika.i18n.tr

/**
 * 模型、模型列表出错时给人看的一句短原因,按界面语言写:接在「试着让 … 调用一个工具没成功:」「连接失败:」这类话后面。
 * core 的 [ModelError.message]、[ListFailure.text] 是写死的简体中文,认不出的报错还带着整段报文;这里只引服务端的原话
 * ([ModelError.BadResponse.said]),说法和 core 的一样(简体那份逐字相同)。任务因此没做完时的整句见 [failure]。
 */
object ModelErrorCopy {
    fun reason(e: ModelError): String = when (e) {
        is ModelError.Auth -> tr(R.string.model_error_auth)
        is ModelError.QuotaExceeded -> tr(R.string.model_error_quota)
        is ModelError.RateLimited -> tr(R.string.model_error_rate_limited)
        is ModelError.ContextTooLong -> tr(R.string.model_error_context)
        is ModelError.ModelNotFound -> tr(R.string.model_reason_not_found)
        is ModelError.ModelNotAvailable ->
            if (e.detail.isEmpty()) tr(R.string.model_error_not_available) else tr(R.string.model_reason_not_available, e.detail)
        is ModelError.ToolsUnsupported -> tr(R.string.model_reason_no_tools)
        is ModelError.Network -> tr(R.string.model_error_network)
        is ModelError.Proxy -> proxy(e.failure)
        is ModelError.StreamCut -> tr(R.string.model_error_stream_cut)
        is ModelError.Server -> tr(R.string.model_reason_server, "HTTP ${e.status}")
        is ModelError.ContentRefused -> tr(R.string.model_error_refused)
        is ModelError.ChatGptLimitReached -> tr(R.string.model_error_chatgpt_limit)
        is ModelError.ChatGptNotEligible -> tr(R.string.model_error_chatgpt_not_eligible)
        is ModelError.SignInExpired -> tr(R.string.model_error_signed_out, e.account)
        is ModelError.AccountPlanNotAllowed -> tr(R.string.model_error_plan, e.account)
        is ModelError.BadResponse -> when {
            e.status != null && e.said.isNotEmpty() -> tr(R.string.model_error_server_said, "HTTP ${e.status}", e.said)
            e.status != null -> tr(R.string.model_reason_server, "HTTP ${e.status}")
            e.said.isNotEmpty() -> tr(R.string.model_error_said, e.said)
            else -> tr(R.string.model_error_unreadable)
        }
    }

    /**
     * 任务因模型出错没做完时给人看的那一句(对话里「没有完成」下面、结果通知、胶囊):[reason] 后面说去哪查;
     * 等一会儿就可能好的叫人稍后再试;原因本身已经说了怎么办的不再多说;代理的问题只说代理那句。
     * core 的 [TaskState.Failed.reason] 是写死的简体中文,见 [localized]。
     */
    fun failure(e: ModelError): String {
        if (e is ModelError.Proxy) return proxy(e.failure)
        // 404 不一定是没有这个模型(网关、中转服务也用它说别的):有原话时照原话说,和 core 一样不断定模型不存在
        val why = clause(if (e is ModelError.ModelNotFound && e.detail.isNotEmpty()) tr(R.string.model_error_said, e.detail) else reason(e))
        return when {
            e is ModelError.StreamCut || e is ModelError.Server || e is ModelError.ChatGptLimitReached -> tr(R.string.fail_model_later, why)
            // 原因里已经说了怎么办(稍后再试、检查接口地址和类型),或要到服务商那边看的
            e is ModelError.RateLimited || e is ModelError.QuotaExceeded || e is ModelError.ContentRefused ||
                (e is ModelError.BadResponse && e.status == null && e.said.isEmpty()) -> tr(R.string.fail_model_plain, why)
            else -> tr(R.string.fail_model, why)
        }
    }

    /**
     * 模型出错的结局([TaskState.Failed.modelError]):原因换成 [failure];别的结局原样返回。任务一结束就换(TaskRun.execute),
     * 对话、通知、胶囊、记下的这一轮和交给电脑的结果说的都是这一句。
     */
    fun localized(end: TaskState): TaskState {
        if (end !is TaskState.Failed) return end
        // Core currently preserves this exception as text, without a typed modelError.
        // Compare the entire generated message so ordinary receipts are never rewritten.
        if (end.kind == FailKind.Model && end.modelError == null) {
            val budget = Regex("([0-9]+)ms").find(end.reason)?.groupValues?.get(1)?.toLongOrNull()
            if (budget != null && end.reason == ModelCallDeadlineExceeded(budget).message) {
                return end.copy(reason = tr(R.string.model_call_deadline))
            }
        }
        val e = end.modelError ?: return end
        return end.copy(reason = failure(e))
    }

    /** Only recognized state codes become UI copy; never render raw diagnostic details. */
    fun retryStopped(event: RunEvent.State): String? =
        if (event.name == "model_retry_stopped" && Regex("call_deadline [0-9]+ms").matches(event.detail))
            tr(R.string.model_call_deadline)
        else null

    /** Parse only the internal retry grammar; provider text is never UI copy. */
    fun retryState(event: RunEvent.State): String? {
        if (event.name == "model_retry_stopped") return retryStopped(event)
        if (event.name != "model_retry") return null
        val match = Regex("(?:main|light) (network|stream_cut|proxy_unreachable|rate_limited|server_5[0-9]{2}) #([1-9][0-9]*) ([0-9]+)ms")
            .matchEntire(event.detail) ?: return null
        if (match.groupValues[2].toIntOrNull() == null || match.groupValues[3].toLongOrNull() == null) return null
        return tr(when (match.groupValues[1]) {
            "rate_limited" -> R.string.model_retry_wait_rate
            "network", "stream_cut", "proxy_unreachable" -> R.string.model_retry_wait_network
            else -> R.string.model_retry_wait_server
        })
    }

    /** 列模型没成功的原因;带着细节(状态码「HTTP 500」)时接在后面括起来,和 [ModelListResult.Failed.message] 一样。 */
    fun listFailure(r: ModelListResult.Failed): String {
        val reason = when (r.reason) {
            ListFailure.BadUrl -> tr(R.string.model_url_scheme)
            ListFailure.Auth -> tr(R.string.model_error_auth)
            ListFailure.Quota -> tr(R.string.model_error_quota)
            ListFailure.RateLimited -> tr(R.string.model_error_rate_limited)
            ListFailure.Network -> tr(R.string.list_error_network)
            ListFailure.ProxyUnreachable -> proxy(ProxyFailure.Unreachable)
            ListFailure.ProxyAuth -> proxy(ProxyFailure.AuthFailed)
            ListFailure.NotSupported -> tr(R.string.list_error_not_supported)
            ListFailure.Server -> tr(R.string.list_error_server)
            ListFailure.BadResponse -> tr(R.string.list_error_bad_response)
        }
        return if (r.detail.isEmpty()) reason else tr(R.string.list_error_with_detail, reason, r.detail)
    }

    private fun proxy(f: ProxyFailure): String =
        tr(if (f == ProxyFailure.AuthFailed) R.string.net_proxy_auth_failed else R.string.net_proxy_unreachable)

    /** 原因接在句中:去掉末尾一个句号(服务端原话自带的),由外面的句子补上自己的;省略号不动。和 core 引原话时一样。 */
    private fun clause(text: String): String = when {
        text.endsWith("..") -> text
        text.endsWith(".") || text.endsWith("。") -> text.dropLast(1)
        else -> text
    }
}
