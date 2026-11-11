# Model connection check

Android's model setup can list models and probe a tool call, and records models
saved without a test. This iOS candidate tests only the existing configured
OpenAI-compatible text-completion path; a pass does not establish tool calling,
streaming, vision, provider-wide compatibility or future availability.

The settings button is enabled only when saved settings and key exist and the
editable URL, model and key fields have no unsaved changes. A deliberate tap
reads the saved key through the existing read-only model access and sends one
fixed short test message; it does not send the conversation, change settings,
write a key, create a conversation or archive the response. The interface
discloses the request and potential cost. Editing, saving, removing, leaving the
page, scene inactivity or starting chat invalidates and cancels an in-flight test.
Results are transient, so reopening the page starts at untested.

The injected client receives a 32-token output limit and a 20-second local
deadline. Cancellation is propagated to the normal HTTP client; the generation
guard also discards late results from clients that do not cooperate. Errors are
mapped to fixed categories and never expose server bodies, keys or URLs.
The timeout cannot forcibly stop a third-party injected client that ignores
cancellation. A service may reject the chosen test or output limit even when
other API requests work.

Run `python3 scripts/check_model_connection.py` in `ios/`. It exercises the
actual core with synthetic clients and a URLProtocol session that intercepts
all requests. The native UI fixture is in `WoowAssistantUITests`. Neither is a
real-service test; Xcode/iOS builds and native UI execution remain separate.
