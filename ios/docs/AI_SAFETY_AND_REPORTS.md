# AI safety rules and AI reply reports

Both follow the Google Play build at `964d7bec` (`PlayAiSafetyPrompt.kt`, `AiResponseReports.kt`,
`AiResponseReportDelivery.kt`, `AiResponseReportDialog.kt`, `MessageMenu.kt`, `ChatScreen.kt`). The Play
text, limits and menu order this app is checked against are copied in
`docs/evidence/play-964d7bec-ai-safety-reports.json`.

## Safety rules

`AISafetyRules` (AssistantModels) holds Play's rules word for word, except "Google Play edition" reads
"App Store edition", and the first line of Play's identity prompt with this app's names:
`You are woowtech agent (渥屋助理 in Traditional Chinese), the user's personal assistant on their iPhone or
iPad.` Together they are `AISafetyRules.prompt`, like Play's `PlayAiSafetyPrompt.identity`. The model sees
them in English whatever the interface language.

- Play sends its identity prompt and the rules on every agent run and child run. Each request here sends
  them after its own instructions, in one system message: ordinary chat (after the skill tools offer when
  there is one, alone when there is none), the skill tools step, the memory and profile chat flow, MCP
  chat, website research, route replay answers, browser action proposals, every step of a web task
  started from chat, memory extraction, skill drafts and model-written skills.
- The skill learning outcome judge does not get them: it answers an internal yes/no, never shown. Neither does Play's outcome judge for chat skill steps (`ChatOutcomeJudge`, 2026-11-14), which Play also sends without them. Nor does
  the fixed connection test in model settings, whose reply only tells whether the service answered.
- Play sends no rules with its memory extractor and skill drafter; here both get them because their text
  is shown to the user.

`scripts/check_ai_safety_and_reports.py` compares the text with the evidence and fails when a model
request site is added, or a listed one stops sending requests, without the list being updated.

## 檢舉 AI 回覆

Long-press a saved AI reply: 複製, 引用, 選取文字, **檢舉 AI 回覆**, 從這裡分支 (Play's order). The sheet has
Play's states: the delivery notice, the reply's reference, the first 300 characters of the reply, three
reasons (冒犯性內容 first), an optional note of up to 1,000 characters, then pending / received /
not confirmed / outside seven days, 重新傳送, 新建檢舉, 查看本機新建的檢舉 and 刪除檢舉, with the same
fail-closed handling of unreadable or damaged saved reports.

What leaves the device: `POST https://assistant-relay.woowtech.io/api/v1/ai-reports` with exactly
`id` (a new lowercase UUID), `reason` (`offensive`, `unsafe` or `other`), `note`, `response` (the reply's
plain text, at most 4,000 UTF-16 units) and `created_at_ms`. No account, device ID, conversation, model
setting or other message is sent, and no header beyond `Content-Type` (plus URLSession's defaults). The
session keeps no cookies or cache and follows no redirects. Deleting a received report sends
`DELETE …/ai-reports/<id>` with the relay's deletion receipt as a bearer token.

On the device: one JSON file per report in `Application Support/AIResponseReports/personal/`
(protected until first unlock; the folder and each file are excluded from iCloud and computer backups):
the reply's conversation and message IDs, the sent fields, the delivery state and the deletion receipt. Files stay until the user deletes the report or the app; the relay keeps
a report for up to 30 days (`tools/woowtech-relay-worker/docs/ai-reports.md`).

Delivery: when the user submits, and every 30 seconds while the chat is on screen, pending reports are
sent, at most three times automatically (again after 30 seconds, then 2 minutes). UI tests use their own
namespace and a fixture relay; they never reach the real one.

Differences from Play: replies here keep a stable ID in the archive, so a reference is the conversation ID
plus the reply's ID, and Android's no-stable-ID state (and its run IDs and answer indexes) does not
apply. The dialog is a sheet; reasons are a checkmark list instead of chips.
