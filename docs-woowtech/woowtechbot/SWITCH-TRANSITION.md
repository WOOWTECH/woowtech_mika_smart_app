# Opening a woowtechbot service: transition page and bot list

Owner request, 2026-11-27, Direct edition (`io.woowtech.agent`): when jumping to a woowtechbot service, do not show the
intermediate screen (the Material bar "服務 <name> 更多", the address line and the website's own "正在連線到你的機器人…"); if a
screen is needed, use a designed transition page. After the jump, land on the bot list, not on a conversation.

## Why it landed on a conversation

- The phone website keeps its bot list in a drawer that is closed on every load (`use-bot-list-drawer`: `useState(false)`, and
  closed again whenever the selected bot, the view, plugins or settings change). It always starts on the selected bot's chat.
  Its URL stays `/` (state-based; push links `?thread=&bot=` are consumed with `replaceState`), so loading `/` or skipping the
  app's session restore does not change where it lands.
- The injected services and notifications controls attach while that list is mounted but hidden, so "integrated" was already
  true on the chat and during "connecting".
- The website's app code (about 2.5 MB) loads after `onPageFinished`; the appearance checks at 0.25, 1 and 3 s could all run
  before it mounted, which left the native bar and address line up over the website.

## What the app does now

- A transition page (app background, robot tile, service name, "正在打開機器人列表…", small spinner) covers the page from the
  first frame until the list is open, then fades out in 220 ms. It says "正在打開對話…" for a push target and "正在重新載入…"
  for a reload. It covers at once: a fade-in showed the new page's first frame and HyperOS then painted the status bar white.
- `assets/woowtechbot/workspace-list.js` is asked every 0.2 s what the page shows. It is fixed and reads markup structure and
  the website's loading-state key only; its one action is a click on the website's own list button. States: `form` (sign-in
  or pairing page), `none` (not a workspace), `boot` (empty `#root`), `connecting`, `app` (no bots in the list yet), `closed`,
  `opening` (clicked), `open`, `wide` (no phone list button).
- The transition page goes when the list is open on two polls, or at a sign-in page, 4 s after a page that is not a workspace
  has loaded, 5 s into `app`, or at 20 s. After a sign-in page, or a site still starting or connecting at 20 s, the list is
  still opened once when the workspace appears. For 2.5 s after the reveal the list is opened again if the website closes it
  by itself, until the first touch, so it never fights the user.
- Opening from the services sheet, switching services in the service screen, and reconnecting a disconnected service land on
  the list. A push target, a reload and a recreated activity keep the website's own page. Switching back to a kept page loads
  its root behind the transition page.
- Pages that are not the workspace (sign-in, other sites) get an app-style bar: services button, name and address, more button.
  It replaces the Material top bar and the separate address line.
- New web views start with the page colour instead of white, and appearance answers only count for the page they were asked on.

## Website structure this relies on (bundle of 2026-11-27)

- The app root `[data-look="app"]`; in its content area the first child is the phone-only `button[aria-expanded]`
  (`app.openBotList`, hidden from `md` up), and the list is `aside[data-look="sidebar"]` in the same area. Bot rows carry
  `data-sidebar-bot-row`. The loading screen is `main[data-app-loading]` with `app.loading.connecting`, `app.loading.updating`
  or `app.loading.noBots` (connected, no bots).
- The boot script renders into an empty `#root` after the session check and the app code have loaded; the pairing page (also
  "session ended") has inputs and no app root.
- If the website changes, a missing button is treated as `wide` and missing rows fall back to the 5 s and 20 s limits. The worst
  case is the old landing on the chat, never a click on anything else.

## Verification

- `tools/woowtechbot-ui/workspace-list-test.cjs` (Playwright, isolated pages): every state, one click on the list button only
  (not a banner or chat button), the no-bots workspace, a wide layout and a missing button. `workspace-controls-test.cjs` passes.
- POCO (720 × 1600), dev build, 2026-11-27, with `tools/woowtechbot-ui/list-fixture.html` served on the local network (the
  website's structure and timeline: app at 0.8 s, connecting, bots at 2.5 s, the list closed by the site at 2.8 s and 4.6 s) and
  with the real openmausbot.woowtech.io, not signed in:
  - Opening: `boot` → `connecting` → `opening` → `open`; the transition page for about 3.5 s, then the bot list; no white frame.
  - From a chat, switching to the other service and back: back on the bot list, not on the chat.
  - The site closing the list after the reveal: reopened. A tap on a bot right after the reveal: its chat stays.
  - Reload: "正在重新載入…", then the website's own page.
  - Not signed in: the pairing page after about 1.5 s, with the app-style bar.
  - `main` for comparison: switching to a new service showed the Material bar over a white page for 1.3 s.
- Not verified on a signed-in woowtechbot service: pairing needs a code from the server. The structure above comes from the
  website's published bundle, which the fixture mirrors.
- Seen once: when a switch creates a new web view, HyperOS painted the system bars white for one frame (about 30 ms).

Screenshots (half size) are in `evidence/switch-transition/`: `main` before (01), the transition page (02), the bot list (03),
the sign-in page with the app-style bar (04), the switcher's new hint (05), back on the list after switching (06), and the
reload transition (07).
