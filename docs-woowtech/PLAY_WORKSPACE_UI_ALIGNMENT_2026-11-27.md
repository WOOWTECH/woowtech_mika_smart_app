# Play editions: workspace UI aligned with the direct-download edition

Owner decision, 2026-11-27: both Play editions (`io.woowtech.assistant` and `com.apporo.assistant.play`) get the same look and
interactions as the direct-download WOOWTECH edition (`io.woowtech.agent`, PR #52 on `main`): full-page history, the gear / plus /
four-grid / row popovers, the name-and-icon page, the conversation header and its menu, find and files pages, dialogs, dark and
light. Apporo keeps its own accent colour. The direct-download edition's woowtechbot parts are not part of this line: no service
switcher, no bot notifications, no QR pairing, no "add woowtechbot service".

Base: `feature/store-document-acceptance-20261121` (PR #46, `0.1.37-play.4` and `-play.2` as submitted to Google on 2026-11-21).

## How it was ported

The direct-download line's changes since the common ancestor `05bce637` were merged file by file (three-way, `git merge-file`)
into the Play line for `ChatScreen`, `ChatViewModel`, `ChatDrawer`, `ChatDraft`, `ConversationStore`, `Colors`, `Theme`, `Dialog`
and `Icons`; all merged without conflict and the Play-only code (AI response reports, steer ids, the Play transport) is untouched.
`MainActivity` keeps the Play version: the direct line's changes there are woowtechbot push and phone control. The new files
`BotUiProfile`, `BotUiAvatar`, `BotUiChat`, `BotUiHistory`, `BotUiPopovers`, `BotUiProfileEditor` and `BotUiSheet`, their strings
(`bot_ui_strings.xml`, English and Traditional Chinese, no brand names) and unit tests come from PR #52.

## Differences from the direct-download edition

| | Direct download | Play editions |
| --- | --- | --- |
| Switch on | `WOOWTECHBOT_ENABLED` and the `io.woowtech.agent(.dev)` package | `BuildConfig.PLAY_EDITION` (both Play flavors) |
| History header | gear, services, notifications, plus | gear and plus |
| Plus menu | new conversation, add woowtechbot service | new conversation |
| Gear menu | settings, About (with an update dot) | settings, About (no self-update on this line) |
| Accent | woowtechbot blue (#0B69CC / #7FC0FF) | WOOWTECH: the same; Apporo: its brand gold (#8B6B24 / #C49E53) |

Upstream and the non-Play Apporo flavor keep the drawer and their palettes.
