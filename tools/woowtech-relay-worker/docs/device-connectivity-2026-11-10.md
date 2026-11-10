# Physical phone connectivity acceptance

User-provided personal MCP endpoint, user-reported Pixel, existing phone access token. Only MCP initialize, initialized notification and tools/list were sent. No tools/call, tasks, wake, unlock or device-unpair request was made. Credentials were not saved in source or repeated in result output.

Earlier initialization returned 503 device_offline. Read-only owner status later reported an online phone for the personal tenant; legacy primary was unpaired. Actual personal-endpoint initialization subsequently succeeded, identifying `mika`, title `woowtech agent`, version `0.1.37-woow.4`. SDK initialization and tools/list succeeded (ten tools). Three additional SDK sessions, each after a 22-second idle interval, independently passed initialization and tools/list.

No evidence establishes the original transient-offline root cause. Do not attribute recovery to the diagnostic-only change or claim a proven functional bug fix. The new diagnostics action was recognized by primary but not yet by the user's already-active Durable Object during these checks. Cloudflare documents eventual Worker/DO code propagation; this is not proof that version skew caused the offline response.

Deployment `e7553ee8-1499-4737-b63a-fbdebf38d776` adds owner-authenticated per-tenant `/admin` routing and a `diagnostics` action returning pairing presence, WebSocket states/tags and pending count, not credentials. Existing owner authentication and limits remain in place. Added tests reject invalid owner keys and verify the diagnostic response. TypeScript, legacy smoke and two-account suites passed.

The Android app has NOT been updated by this work. Its copied root `/mcp` remains incompatible with personal tenant routing; use the personal `/r/<tenant>/mcp` URL. A successful tool list proves MCP reachability, not phone task execution. Long-term reliability, network switching and background operation remain outside this acceptance.
