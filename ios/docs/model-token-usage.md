# Model token usage: parsing and metering

Phase 1 of matching the Android store build's token usage
(`playstore/woowtech-compliant-20261111` @ `465a17c9`). It parses and meters;
nothing is shown, archived or stored yet. A turn's count, the conversation
total and the Token usage page come later.

## Reading usage

`HTTPChatModelClient` reads the OpenAI Chat Completions `usage` object from a
complete reply, from a JSON reply to a stream request, and from SSE events,
where the last usable report wins. Each field is decoded on its own: a missing,
negative or malformed field is unknown (nil), never zero, and no usage value
can fail a reply. Like Android's `OpenAiCompatModel.parseUsage`:

- input is `prompt_tokens`, else cache hit plus miss (without overflow);
- a reply counts as reported only with an input count, so `total_tokens`
  alone is unreported; a missing output counts as 0;
- cached input is the larger of `prompt_tokens_details.cached_tokens` and
  `prompt_cache_hit_tokens`. Unlike Android, cached above input and reasoning
  above output are unknown instead of being capped. Input includes cache hits
  and output includes reasoning.

Providers are not estimated: no report means no number.

## Asking for usage while streaming

Stream requests ask with `stream_options: {"include_usage": true}`; complete
requests never do, and their bodies are unchanged. Some compatible endpoints
stream but refuse that option. A 400, 415 or 422 whose short body names
`stream_options` (as Android checks) becomes
`HTTPStreamFallbackError.usageOptionUnsupported`, and the client stops asking
that endpoint and model for the rest of the process. The client never resends.
`ChatSession` resends a plain request once, only before any text arrived;
`UserProfileChatFlow` falls back to one complete request, as it does for an
endpoint that refuses streaming. MCP runs use complete only.

## Metering

The transport records each request exactly once, so wrappers and runners never
count it again:

- `ModelUsageScope.tally` (task-local) receives fully validated replies only.
  Failed, cut, timed-out and cancelled requests never count toward a run; the
  record happens before the stream ends, so a consumer that sees the end sees it.
- An optional `ModelUsageSink` receives every request, failures included with
  nil usage, with endpoint, model, `ModelUsageScope.purpose` and whether the
  request reached URLSession. It never gets text, keys, headers or bodies.
- `ModelUsageScope.metered` is false for the connection test, which Android
  does not meter either.

Task-local values follow child tasks and `Task {}`, not `Task.detached`: a
model call moved into a detached task would silently miss the run's tally.

Run `python3 scripts/check_model_token_usage.py` (also run by
`scripts/test_model_token_usage.py`); its URLProtocol fixture intercepts every
request. The ChatSession resend is covered by the `usageOptionFallback` group
of `scripts/check_chat_streaming_app.py`. Neither is a live provider test.
