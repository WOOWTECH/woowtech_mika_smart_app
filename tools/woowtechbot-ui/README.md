# Workspace presentation checks

Run with Node 20+ and Playwright available. Set `PLAYWRIGHT_MODULE` to an installed module path if needed; set `CHROME_EXECUTABLE` to a local Chrome executable if Playwright has no downloaded browser.

```sh
node tools/woowtechbot-ui/workspace-controls-test.cjs
```

The isolated fixture checks repeat injection, original website controls, draft preservation during appearance changes, both skins, React slot replacement and missing-app fallback. It makes no request to live services and uses no account cookies. Android gesture/origin action validation is covered by `BotWorkspaceAppearanceTest`.

## Bot list landing

```sh
node tools/woowtechbot-ui/workspace-list-test.cjs
```

Checks `app/src/main/assets/woowtechbot/workspace-list.js` on isolated pages: sign-in page, other site, a site still starting,
connecting, no bots, bots not loaded, list closed and open, the click landing only on the list button, a wide layout and a
missing button.

For a device check, serve `list-fixture.html` on the local network (for example `python3 -m http.server 8765 --bind <LAN IP>`
in a folder holding it as `index.html`) and add `http://<LAN IP>:8765` as a woowtechbot service with the trusted-LAN option.
It mirrors the phone website's structure and timeline, including the list closing by itself after the bots load. Build with
`-PbotViewportDiagnostics=true` to see each state as `BotRouteQA: transition shown=…` in logcat.
