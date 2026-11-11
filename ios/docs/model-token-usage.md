# Model response usage foundation

The Android reference at `de5be35` reads provider-reported counters from each
adapter's response, records per-call usage and separately counts missing usage.
Its chat UI uses completed run metrics for per-turn counts and a conversation
total, marking incomplete totals as at least the known amount. It does not
estimate missing token usage. Android supports provider-specific Chat, Responses,
Anthropic and Gemini mappings; its Chat stream asks for `include_usage` and can
retry after a rejected option.

iOS currently has an OpenAI Chat Completions transport only. This change adds an
optional usage-reporting capability alongside the existing text-only protocols.
`completeWithUsage` returns text and optional counters for the same successful
response. `streamWithUsage` yields text deltas and exactly one terminal event on
success; usage received before an error, cancellation, truncation or timeout is
never published as a completed result. A missing or invalid counter is nil, not
zero. Explicitly reported zero remains zero. The usage belongs to the specific
request, not the client instance; clients retain no last-usage cache.

By default the streaming request body remains unchanged. Explicit
`requestOpenAICompatible` opts into `stream_options.include_usage`; endpoints
may reject that extension. No automatic retry or second request is performed.
The JSON response fallback uses the same request and preserves its usage.
This adapter does not claim Responses, Anthropic or Gemini compatibility.
Cache-hit plus cache-miss is accepted as an input count when both are present;
cached input and reasoning output are subsets and must not be added again.
Counters are provider reports, not evidence of billing, cost or exactness.

The host must associate the terminal result with the same active request and
conversation and drop it after a generation/context change. Cancellation after
a terminal event cannot retract a value already handed to a consumer. Existing
callers keep using their text-only interfaces; this change does not wire UI,
persist usage, aggregate multi-call runs, or claim Android's statistics screen
is implemented. A future display must distinguish no report from an actual zero
and label partial totals rather than guessing. No model text, key, URL or usage
is logged by this capability.

Run `python3 scripts/check_model_token_usage.py` and
`python3 scripts/check_model_attachments.py`; their URLProtocol fixtures
intercept all requests. They are local checks, not live provider or native UI
validation. A real service may omit usage or reject the optional stream field.
