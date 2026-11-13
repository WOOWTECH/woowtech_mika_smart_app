# Web tasks from chat

Owner decision 2026-11-13: a chat message can make the built-in browser do the
work, like the Play build (where every message is a task). The 104, momo and AI
news examples now open pages instead of answering from memory.

## How a task starts
- Ordinary chat offers two entry commands, like Android's folded web tools:
  `{"action":"web_read_page","url":"https://…"}` and `{"action":"web_navigate","url":"https://…"}`.
  - Memory on: `UserProfileChatFlow` accepts them when the host passes a
    `UserProfileChatWebEntry` (wording plus the host's exact validator).
  - Memory off: a system message (`ChatWebTaskPrompts.plainInstructions`) is
    added; a reply that starts with `{` or a code fence is held until complete,
    then either starts the task or is shown as the answer.
  - MCP conversations keep their own runner in this phase (no web entry).
- `ChatSession` then runs a `ChatWebTaskSession`: the `ChatWebTaskRunner`
  (AssistantBrowser) with the `ChatWebTaskTab` (App, WKWebView).

## What the model can do (read only in this phase)
`web_navigate`, `web_read_page` (whole page, `offset`/`nextOffset`, 12,000
characters by default, at most 30,000; up to 50 links, main content first),
`web_open_link`, `web_find`, `web_scroll`, `web_back`, `web_wait_for`,
`end_not_done` and `finish` with `sources` (page numbers actually read).
Page text arrives inside `<untrusted>…</untrusted>`.

## Rules
- Addresses: `ChatWebTaskPolicy` — public HTTPS with query strings, across
  sites; no credentials, private networks or local names; logout, delete,
  unsubscribe and similar paths are never opened; sign-in pages are left to the
  user. The tab applies it again to every main-frame navigation and redirect,
  allows only GET, and refuses downloads; pop-ups open in the tab; page dialogs
  close at once; camera and microphone are denied.
- Website data: the task tab shares the built-in browser's data store (owner
  decision), so sites signed in to in the app stay signed in.
- Limits like Android: no step or time limit. Guard rules stop a task after 12
  identical steps on one page or 8 failures in a row. From a site's second page
  the tab waits 4–7 s (+0.6–1 s per page, at most 12 s); 20 pages per site.
- Context: about 120,000 characters; older page text shrinks to one line, and
  the list of pages read is kept.
- Background: `.inactive` changes nothing; `.background` pauses between steps
  (a step interrupted by it is done again), and the task continues when the app
  is active again. A web content process that ends is reloaded up to twice.

## What the conversation keeps
The round is written like Android, also when stopped or not finished: the
answer plus up to six sources as Markdown links, or 「已停止。」/「沒有完成」 with
the pages read. No page text, screenshots or form contents are stored, and a
round that read web pages is not organized into memory (Android RunLearning).

## Interface
A task card in the transcript (status, time, latest steps, 檢視過程, 顯示畫面,
查看網頁, 停止) and the task tab itself, laid out at phone width and scaled to a
small view in the corner; tapping enlarges it. It stays in the window when
hidden, because WebKit pauses pages that are not. On small screens and
accessibility text sizes the small view starts hidden.

## Consent screen hook
`AppText.chatWebConsentTitle` / `.chatWebConsentBody` describe the task tab
(opened sites, addresses, titles and page text sent to the chosen model;
shared website data; no screenshots, cookies, passwords or field contents).
The AI consent screen from the multi-provider work shows them.

## Checks
- `scripts/check_chat_web_task_core.py`: policy, commands, pacing and runner with
  a scripted model and an in-memory tab (also `ChatWebTaskTests` in
  AssistantDomainTests).
- `scripts/check_chat_web_task_app.py`: real WebKit on macOS against loopback
  pages; Debug also runs the chat path end to end with the Debug fixtures.
- `ChatWebTaskUITests` (ui-browser shard) with `-UITestChatWeb`.
