# Workspace presentation checks

Run with Node 20+ and Playwright available. Set `PLAYWRIGHT_MODULE` to an installed module path if needed; set `CHROME_EXECUTABLE` to a local Chrome executable if Playwright has no downloaded browser.

```sh
node tools/woowtechbot-ui/workspace-controls-test.cjs
```

The isolated fixture checks repeat injection, original website controls, draft preservation during appearance changes, both skins, React slot replacement and missing-app fallback. It makes no request to live services and uses no account cookies. Android gesture/origin action validation is covered by `BotWorkspaceAppearanceTest`.
