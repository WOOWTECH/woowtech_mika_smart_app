package com.wangzan101.mika.core.agent

/** Logical model call exhausted its total budget. Not parent cancellation or a retryable network failure. */
class ModelCallDeadlineExceeded(val budgetMs: Long) : Exception(
    "模型调用超过总时间上限（${budgetMs}ms，包含请求、流式回复和重试等待）。",
)
