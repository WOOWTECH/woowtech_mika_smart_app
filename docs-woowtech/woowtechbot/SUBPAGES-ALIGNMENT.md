# Native sub-screens aligned to woowtechbot

Scope: **WOOWTECH Direct Android only** (`io.woowtech.agent`). Store brands, remote websites and the push ledger are untouched.
Decided by the owner on 2026-11-27: popovers and sheets must look and open like woowtechbot's own; options may be fewer where this
app has no such feature; dark and light both; the same component family everywhere so a later change is made once.

## Reference

| Source | Used for |
| --- | --- |
| Owner phone screenshots 2026-11-27 08:39–08:41 (real woowtechbot inside the app, plus the native screens) | what a popover, the account/plus/four-grid menus and the bot panel look like on a phone |
| Production stylesheet and bundle of woowtechbot 0.1.169 (`/assets/styles-*.css`, public static files of the HA add-on) | exact tokens, radii, spacing, keyframes |
| Design preview 06 (`design/woowtechbot-preview`, conversation 80c93a02…) | which actions each assistant screen has, and the name/icon page (`avatarPage`) |
| `design/woowtechbot-preview/research/evidence/*.png` (390 × 844 CSS px, DPR 1 captures of the real app) | pixel measurements without any density guesswork |

## What the website actually does (measured)

**Colours.** On phones only Midnight has its own set (`@media (max-width: 767.98px)`); Daylight keeps its desktop values. The settings
dialogs use a third set (`[data-settings-look]`) on every width.

| Token | Midnight (phone) | Daylight | Midnight settings look |
| --- | --- | --- | --- |
| page `--color-app` | `#141414` | `#fcfcfc` | `#121212` |
| menu / popover `--color-menu` | `#2c2c2e` | `#ffffff` | `#1f1f1f` |
| card | `#242426` | `#efefef` | `#1f1f1f` |
| control / raised | `#2c2c2e` | `#e3e3e3` | `#282828` |
| inset | `#1c1c1e` | `#e9e9e9` | `#1b1b1b` |
| hairline | `#3a3a3c` | `#1c1c1c3d` | `#383838` |
| `--radius-menu` | 22 | 12 | – |

**Popover** (`.popover-surface`): no scrim, anchored to its button (four-grid: opens upwards from its left edge; account: downwards from its
left edge; plus: downwards from its right edge; 8 dp gap), padding 6, rows 4 apart, 1 px hairline at 50 %, `--radius-menu`.
Row (`.ui-menu-row`): min 30, padding 6 × 8, gap 8, radius 6, 14/18 text, 16 icon first. Divider: 1 px, 6 in from each side.
Motion `pop-in`: 0.2 s `cubic-bezier(.22, 1, .36, 1)`, opacity 0→1, scale .96→1, 6 px rise; `pop-out` is the reverse.

**Sheet** (settings dialog on a phone): 12 below the status bar, 16 top corners, a 32 × 4 grabber 8 from the top, 44 header with a centred
16 / 600 title and a close button, cards with 12 corners. Motion `sheet-in`: 0.26 s, opacity plus a 32 px rise; scrim fades in over 0.2 s (`.glass-scrim`: `#0000008c` on Midnight, `#0000002e` on Daylight).
Settings cards carry a 0.5 px edge (`--settings-edge`: ink at 9 % Midnight / 10 % Daylight); round header buttons are 40 px circles on the card colour.
Switch: 32 × 20, knob 16 two in, 0.15 s; on = ink track with a page-coloured knob.

## Components (all in `app/src/main/java/com/wangzan101/mika/ui`)

| File | What |
| --- | --- |
| `theme/Colors.kt`, `Theme.kt` | `WoowDarkColors` / `WoowLightColors` carry the phone tokens; `WoowSheetDark/LightColors` the settings look; new fields `panel, menu, menuHover, menuActive, control, inset, raisedHover`; Material dialogs take `menu` and `menuRadius` |
| `BotUiPopovers.kt` | `BotUiPopover` (Popup, anchored, `pop-in`/`pop-out`), `BotUiPopoverItem`, `BotUiPopoverDivider` |
| `BotUiSheet.kt` | `BotUiSheet`, `BotUiCard`, `BotUiSettingsRow`, `BotUiSectionLabel`, `BotUiSwitch`, `BotUiPillButton`, `BotUiTextField`, `BotUiSearchPill` |
| `BotUiAvatar.kt` | the design's robot drawn from the preview's own SVG paths, eleven bot colours |
| `BotUiProfileEditor.kt` | chat header and the name/icon page |

## Screens

| Screen | Before | Now |
| --- | --- | --- |
| Shortcuts (four-grid) | Material dropdown over the list, 4 dp corners, 48 dp rows | popover above the button, seven real tools only (settings and About moved to the gear) |
| Gear (top left) / plus (top right) | direct actions | popovers: settings, About / new conversation, add woowtechbot service |
| Row “…” and chat “…” | Material dropdown | popovers (name and icon, pin, delete / name and icon, new, find, files) |
| Switch assistant / service | full page with a Material app bar | bottom sheet, cards, manage sheet and add dialog in the same family |
| Bot notifications | full page of buttons | bottom sheet: switch row, system settings, per-service status |
| Name and icon | app bar “✕ name ✓”, outlined field, numbered colour dots | design's page: round ✓ ✕ top right, 68 dp tile with pencil, centred name, icon card (robot / upload, three styles, eleven colours, face) |
| Chat header | full-width capsule touching both screen edges | 8 dp side margin, round buttons (40 dp circle in a 48 dp target), capsule hugs its content and sits in the middle |
| Find / files / dialogs | Material fields and text buttons | search pill, card rows, popover-surface dialogs with ink-coloured buttons (destructive stays red) |

Activities `BotServicesActivity` and `BotPushSettingsActivity` use the translucent `Theme.Mika.Sheet`, so the sheet rises over the screen that opened it.
Full-screen dialogs (name and icon, find, files, the in-service sheets) call `NoDialogDim()`: the platform dim left a darker band under the status bar.
Popover windows are created with `clippingEnabled = false`; otherwise the system slid the whole window inwards when its transparent shadow room
reached the screen edge and the menu ended up 8 dp away from its button.

## Data

`BotUiProfile.palette` (default 1) marks the generation. Profiles saved before it read as the original six colours and are mapped to the
closest of the eleven (`colorIndex()`), so no conversation changes colour; the editor saves generation 2, where `face` is automatic / white / black.

## Evidence

POCO (720 × 1600, 320 dpi, portrait), debug build, dev package `io.woowtech.agent.dev`, 2026-11-27. Screenshots are half size, in
`evidence/subpages/dark/` and `evidence/subpages/light/` with the same file names; several were taken with Craft Anything's
`adb-screenshot-take`, the rest with `adb exec-out screencap`.

| File | Shows |
| --- | --- |
| `01-history` | history list, current conversation selected, quiet “…” glyphs, 40 dp round buttons |
| `02-gear-menu` / `03-plus-menu` | popovers below-left of the gear and below-right of plus, edges aligned with their buttons |
| `04-shortcuts-menu` | four-grid popover opening upwards, the seven tools this app has |
| `05-row-menu` | row “…” popover: name and icon, pin, delete |
| `06-switch-service-sheet` / `07-add-service-dialog` / `08-bot-notifications-sheet` | bottom sheets and the add dialog |
| `09-chat-header` / `10-chat-menu` | header with side margins and a centred capsule, its menu |
| `11-name-and-icon` / `12-name-and-icon-card` | the design's name page, icon card open |
| `13-find` / `14-files` / `15-delete-confirmation` | same-family pages and dialog |

Unit tests: `BotUiProfileTest` 7, `BotUiHistoryTest` 3, all pass. CI on the pull request: all jobs pass, including the APK job.

## Not matched on purpose

- The website uses Geist; this app keeps the system font. Icons are this app's own 1.7 px stroke set, scaled to 16 dp.
- Remote pages (bot list, chat, settings inside the WebView) are the website itself and are not changed.
- Light mode on the phone website uses desktop tokens, so the native light popover is white with 12 dp corners, not a scaled-down dark one.
