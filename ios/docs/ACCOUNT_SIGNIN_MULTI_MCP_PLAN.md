# iOS: alignment with the Android direct-download edition

Owner decision, 2026-11-18: iOS follows the Android direct-download edition for models, chat, memory, skills, browser, MCP and everything else except phone control, in phases. This is the hand-off for the session that builds the work on the MacBook with Xcode.

Branch: `ios/1.1-account-signin-multi-mcp`, started from `ios/parity-1.0` at `35bbb4bb6`.

## Phase 1

1. **Full-height drawer.** The drawer reaches the bottom of the screen with no part of the chat composer showing, and its title sits below the status bar.
2. **Defects from the device test** (below).
3. **ChatGPT sign-in** with a Plus or Pro plan.
4. **xAI / Grok sign-in** with SuperGrok or X Premium+.
5. **Several MCP servers.** iOS keeps one endpoint today; Android keeps a list.
6. **Remove the per-conversation MCP switch** 本次對話使用 MCP 工具 (`chat.useMCP`). A saved MCP server is available in every chat.

## Phase 2

Start with a fresh item-by-item comparison against Android `main`, then close every gap except phone control. Known gaps:

- OpenRouter sign-in
- Anthropic, Gemini, OpenAI, Ollama and LM Studio presets, and choosing Chat Completions or Responses
- Vision and light model roles, reasoning and context settings
- Token usage page and run timeline
- Scheduled tasks and the plans page
- Steering a running task, step limit, keep screen on and network proxy
- The browser Ask bar
- Autonomous mode. **Owner decision: payments always ask first, even in autonomous mode.**

Claude and Google account sign-in are not offered on Android either (`docs/dev/account-signin.md` on `main` explains why).

## Android reference (read only)

Direct-download edition: `main`. The latest public release is `v0.1.37-woow.10` at `b3a5fe0d`. Match its behavior unless iOS needs a platform difference, and record any difference.

| Area | Files |
|---|---|
| ChatGPT sign-in | `core/src/main/kotlin/com/wangzan101/mika/core/chatgpt/ChatGptAuth.kt`, `ChatGptSession.kt` |
| xAI sign-in | `core/src/main/kotlin/com/wangzan101/mika/core/oauth/XaiAuth.kt`, `DeviceCode.kt`, `AccountSession.kt` |
| Shared sign-in parts | `core/src/main/kotlin/com/wangzan101/mika/core/oauth/LoopbackCallback.kt`, `Pkce.kt` |
| Responses protocol | `core/src/main/kotlin/com/wangzan101/mika/core/model/ResponsesModel.kt` |
| Sign-in screens | `app/src/main/java/com/wangzan101/mika/ui/AccountSignIn.kt`, `ModelsScreen.kt`, `ModelSetupViewModel.kt` |
| MCP servers | `app/src/main/java/com/wangzan101/mika/ui/McpServersScreen.kt`, `core/src/main/kotlin/com/wangzan101/mika/core/cap/mcp/` |
| Drawer | `app/src/main/java/com/wangzan101/mika/ui/ChatDrawer.kt` |

## Defects from the device test

Build 4 on iPhone 15 Pro, iOS 26.5, main model `chatgpt/gpt-6-sol`, 2026-11-18. The causes are not confirmed yet.

| Severity | Defect | Expected |
|---|---|---|
| High | The home screen example 在內建瀏覽器找一篇最近的 AI 新聞，摘要三個重點 answers that it cannot operate the built-in browser. | The web task runs. |
| High | Going to the home screen for about 10 seconds during a streaming reply loses the reply and shows 呼叫模型失敗：網路連線失敗. | The reply continues, or is kept and can resume. |
| High | After attaching a photo, the model answers that it cannot view the image. Check whether the image is sent for a custom provider whose vision support is unknown. | The model describes the photo. |
| Medium | Markdown tables show raw `\|` characters and code blocks have no block style. | Formatted table and code block. |
| Medium | The 任務已完成 banner appears while the app is open on that chat. | No banner on the chat in front. |
| Low | In English, the greeting on a new chat is cut off under the MCP switch row. | The greeting is fully visible. |
| Low | 回到最新訊息 stays over the text after a long reply ends. | The button goes away at the end of the reply. |
| Low | In dark mode, the note 已開啟保存的對話 overlaps messages when an old chat opens. | The note does not cover messages. |

A 2,633-character reply finished in about 87 seconds on build 4. That is just under the 90-second limit fixed by PR #40, so it does not prove long replies work on this build.

## Existing iOS prototype

Branch `ios/play-parity-chatgpt-signin` at `bdefd429` adds `ChatGPTSignIn.swift`, `LoopbackCallbackServer.swift`, `ChatGPTResponses.swift` and their checks. It was never merged and is not connected to a screen or a model client. Its 153 checks ran against fake servers only.

Still unproven on a real device:

- anything at OpenAI
- the loopback listener while `ASWebAuthenticationSession` is open
- whether iOS shows a local-network prompt
- Safari loading the `http://127.0.0.1` callback
- reopening the listener after the app is suspended

Prove these first. If the loopback callback cannot work on iOS, stop and report before building the screens on top of it.

## Phase 1 details

### Drawer layout (`ContentView.swift`)

- Measured on iPhone 15 Pro (852 pt tall, safe areas 59 and 34, build 4): the drawer runs from y = -46.5 to y = 805.5. It stops 46.5 pt above the bottom edge, which shows the composer, and its header sits 46.5 pt too high, which puts the title under the clock.
- Cause: the drawer is taller than its container, so `ZStack(alignment: .leading)` and `.frame(width:height:alignment: .leading)` centre it vertically before `.offset(y: -geometry.safeAreaInsets.top)` moves it again.
- Fix: use `.topLeading` for both alignments, then confirm the drawer runs from y = 0 to the bottom of the screen.
- Android's `ChatDrawer.kt` fills the height behind the system bars and pads its content by the status and navigation bar insets.
- Check iPhone with Dynamic Island, iPhone SE, iPad and landscape.

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

- Add the group 用帳號登入 · 不用填 Key.
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

### Per-conversation MCP switch (`ContentView.swift`, `ChatSession.swift`)

- The switch is more than a screen control. `ChatSession.usesMCP` decides whether a turn goes through the MCP runner (`attemptSend(mcp:)`), and `docs/BACKLOG.md` lists MCP together with web tasks and skill tools in one chat as the work that lets the switch go.
- Make one chat turn able to use MCP tools, web tasks and skill tools together first. Removing only the switch would either cut MCP off or take web tasks and skill tools away from chats that have a saved server.
- Then remove the toggle, `usesMCP` and the `chatUseMCP` string, and rewrite the `mcpExplanation` text, which tells people to turn the switch on.
- Update the UI tests that use `chat.useMCP`: `MCPConversationUITests`, `LiveMCPConversationUITests` and `MCPLearningUITests`.

## Phase 1 order of work

1. Full-height drawer.
2. High-severity defects, then the other device-test defects.
3. Real-device proof of the sign-in callback.
4. Responses client with tests.
5. ChatGPT sign-in, end to end.
6. xAI / Grok sign-in, end to end.
7. Several MCP servers, including migration.
8. MCP, web tasks and skill tools in one chat, then remove the per-conversation switch.

## Done means

- Module checks, App harnesses and UI tests cover each item, and CI is green or every failure is explained.
- With the drawer open, no part of the composer is visible on any tested device, and the title does not touch the status bar.
- Every device-test defect is retested on a real iPhone.
- Tested on a real iPhone and iPad: sign-in, model list, streaming chat, a long reply over 90 seconds, token refresh, cancel, sign-out, and backgrounding during sign-in.
- MCP tested with at least two real servers, including migration from one server and one server being down.
- With a saved MCP server and no switch on screen, one chat can call an MCP tool, run a web task and use a skill.

## Boundaries

- The owner completes every real sign-in and enters every password, code and key personally.
- Tokens and keys never go into logs, diagnostics, files, commits or messages.
- Do not merge into `main`, upload to TestFlight or App Store Connect, or reply to App Review without the owner's approval.
- Follow the build, simulator and device coordination rules on that Mac.
