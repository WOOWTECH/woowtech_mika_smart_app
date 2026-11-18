# iOS: account sign-in and several MCP servers

Owner request, 2026-11-18. This is the hand-off for the session that builds the work on the MacBook with Xcode.

Branch: `ios/1.1-account-signin-multi-mcp`, started from `ios/parity-1.0` at `35bbb4bb6`.

## Scope

1. **ChatGPT sign-in** with a Plus or Pro plan.
2. **xAI / Grok sign-in** with SuperGrok or X Premium+.
3. **Several MCP servers.** iOS keeps one endpoint today; Android keeps a list.
4. **Drawer title fix.** On iPhone 15 Pro (iOS 26.5, build 4) the drawer title 渥屋助理 sits inside the status bar and overlaps the clock.

Out of scope: OpenRouter sign-in, and Claude or Google account sign-in (`docs/dev/account-signin.md` on `main` explains why those two are not offered).

## Android reference (read only)

Branch `playstore/woowtech-compliant-20261111` at `964d7bec`. Match its behavior unless iOS needs a platform difference, and record any difference.

| Area | Files |
|---|---|
| ChatGPT sign-in | `core/src/main/kotlin/com/wangzan101/mika/core/chatgpt/ChatGptAuth.kt`, `ChatGptSession.kt` |
| xAI sign-in | `core/src/main/kotlin/com/wangzan101/mika/core/oauth/XaiAuth.kt`, `DeviceCode.kt`, `AccountSession.kt` |
| Shared sign-in parts | `core/src/main/kotlin/com/wangzan101/mika/core/oauth/LoopbackCallback.kt`, `Pkce.kt` |
| Responses protocol | `core/src/main/kotlin/com/wangzan101/mika/core/model/ResponsesModel.kt` |
| Sign-in screens | `app/src/main/java/com/wangzan101/mika/ui/AccountSignIn.kt`, `ModelsScreen.kt`, `ModelSetupViewModel.kt` |
| MCP servers | `app/src/main/java/com/wangzan101/mika/ui/McpServersScreen.kt`, `core/src/main/kotlin/com/wangzan101/mika/core/cap/mcp/` |

## Existing iOS prototype

Branch `ios/play-parity-chatgpt-signin` at `bdefd429` adds `ChatGPTSignIn.swift`, `LoopbackCallbackServer.swift`, `ChatGPTResponses.swift` and their checks. It was never merged and is not connected to a screen or a model client. Its 153 checks ran against fake servers only.

Still unproven on a real device:

- anything at OpenAI
- the loopback listener while `ASWebAuthenticationSession` is open
- whether iOS shows a local-network prompt
- Safari loading the `http://127.0.0.1` callback
- reopening the listener after the app is suspended

Prove these first. If the loopback callback cannot work on iOS, stop and report before building the screens on top of it.

## Gaps to close

### Model layer

- `ModelProviderKind` has only `.openAICompatible`, and `HTTPChatModelClient` speaks only chat/completions.
- Add a Responses client shared by ChatGPT (`https://api.openai.com/v1/responses`) and xAI (`https://api.x.ai/v1/responses`). It must support what chat already uses: streaming, images, cancellation, the long-reply behavior from PR #40, and the tool and structured-output paths.
- The prototype sends no tools. Close that gap before calling chat, web tasks or MCP done on these providers.

### Accounts

- Keep sessions in the Keychain, with one refresh at a time and refresh before expiry or after a 401.
- Signing out clears this device only and keeps the provider and its model choices, as on Android.
- Add the xAI device-code flow, with the host checks from `XaiAuth.kt`.
- An xAI HTTP 403 means the plan cannot use this interface: do not retry, and suggest an xAI API key.

### Screens (`ModelProviderSettingsView.swift`, `ModelProviderForm.swift`, `ModelSettings.swift`)

- Add the group 用帳號登入 · 不用填 Key with ChatGPT and xAI / Grok.
- Open an explanation sheet first. Sign-in starts only after the person continues.
- Show the xAI risk note before sign-in. The flow uses the public client id of xAI's official command-line tool, which xAI did not register for this app.
- Add the device-code view, progress, cancel, failure reasons, and a provider page with account, status, models and sign-out.
- Add every string to `Localization/AppText.json` in English and Traditional Chinese.

### Several MCP servers (`MCPSettings.swift`, `MCPSession.swift`, `MCPToolsView.swift`, `Sources/AssistantMCP/`)

- Add a named server list with add, edit, delete, test and status per server.
- Keep endpoints and tokens in the Keychain per server, and the tool selection per server.
- Migrate the current single server without losing its endpoint, token or tool selection.
- One chat can use tools from every connected server. Handle two servers that offer the same tool name.
- A server that is down must not block the others.
- Deleting a server clears only that server's Keychain items.

## Order of work

1. Drawer title fix.
2. Real-device proof of the sign-in callback.
3. Responses client with tests.
4. ChatGPT sign-in, end to end.
5. xAI / Grok sign-in, end to end.
6. Several MCP servers, including migration.

## Done means

- Module checks, App harnesses and UI tests cover each item, and CI is green or every failure is explained.
- Tested on a real iPhone and iPad: sign-in, model list, streaming chat, a long reply, token refresh, cancel, sign-out, and backgrounding during sign-in.
- MCP tested with at least two real servers, including migration from one server and one server being down.

## Boundaries

- The owner completes every real sign-in and enters every password, code and key personally.
- Tokens and keys never go into logs, diagnostics, files, commits or messages.
- Do not merge into `main`, upload to TestFlight or App Store Connect, or reply to App Review without the owner's approval.
- Follow the build, simulator and device coordination rules on that Mac.
