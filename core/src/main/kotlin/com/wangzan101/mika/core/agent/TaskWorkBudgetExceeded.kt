package com.wangzan101.mika.core.agent

/** Exploration must stop before another model request; AgentLoop owns budget settlement. */
internal class TaskWorkBudgetExceeded : Exception("Task exploration budget exhausted")
