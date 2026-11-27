const { chromium } = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const fs = require('fs'), assert = require('node:assert/strict');
const source = fs.readFileSync(require('path').resolve(__dirname, '../../app/src/main/assets/woowtechbot/workspace-list.js'), 'utf8');
const script = open => source.replace('__WOOW_OPEN__', String(open));
// The website's phone layout (2026-11-27 bundle): the app root, the list button first in the content area, the sidebar with
// bot rows kept mounted. The button opens the list like the site's own drawer hook does.
const workspace = `<div data-look="app"><div role="status"><button aria-expanded="false" id="banner">Details</button></div>
  <div class="relative flex"><button type="button" aria-label="Open bot list" aria-expanded="false" id="list" class="md:hidden">&lt;</button>
  <div class="contents"><div class="contents"><aside data-look="sidebar"><div data-sidebar-top-slot></div><div id="rows"></div></aside>
  <main><textarea id="draft">keep</textarea><button aria-expanded="false" id="menu">More</button></main></div></div></div></div>
  <script>document.querySelector('#list').addEventListener('click', e => e.currentTarget.setAttribute('aria-expanded', 'true'));</script>`;
(async () => {
  const browser = await chromium.launch({headless: true, executablePath: process.env.CHROME_EXECUTABLE});
  try {
    const page = await browser.newPage({viewport: {width: 390, height: 844}});
    // Sign-in and pairing pages, and other sites.
    await page.setContent('<form><input id="code" placeholder="XXXX-XXXX-XXXX"><input type="hidden" name="t"></form>');
    assert.equal(await page.evaluate(script(true)), 'form');
    await page.setContent('<main><h1>Example</h1><input type="hidden"></main>');
    assert.equal(await page.evaluate(script(true)), 'none');
    // Starting: the website's root stays empty until the session is checked and its app code has loaded.
    await page.setContent('<div id="root"></div>');
    assert.equal(await page.evaluate(script(true)), 'boot');
    await page.setContent('<div id="root"><p>Another app</p></div>');
    assert.equal(await page.evaluate(script(true)), 'none');
    // Connecting: the website's loading screen; nothing is clicked.
    await page.setContent(workspace.replace('<main>', '<main data-app-loading="app.loading.connecting">'));
    assert.equal(await page.evaluate(script(true)), 'connecting');
    assert.equal(await page.locator('#list').getAttribute('aria-expanded'), 'false');
    // Connected without any bot: the list (inbox, new bot) still opens.
    await page.setContent(workspace.replace('<main>', '<main data-app-loading="app.loading.noBots">'));
    assert.equal(await page.evaluate(script(true)), 'opening');
    assert.equal(await page.evaluate(script(true)), 'open');
    // Loaded app, bots not in the list yet: nothing is clicked.
    await page.setContent(workspace);
    assert.equal(await page.evaluate(script(true)), 'app');
    assert.equal(await page.locator('#list').getAttribute('aria-expanded'), 'false');
    await page.evaluate(() => { document.querySelector('#rows').innerHTML = '<a data-sidebar-bot-row>Bot</a>'; });
    // Only asked: report. Asked to open: one click on the list button, never on another expandable button.
    assert.equal(await page.evaluate(script(false)), 'closed');
    assert.equal(await page.evaluate(script(true)), 'opening');
    assert.equal(await page.locator('#list').getAttribute('aria-expanded'), 'true');
    assert.equal(await page.locator('#menu').getAttribute('aria-expanded'), 'false');
    assert.equal(await page.locator('#banner').getAttribute('aria-expanded'), 'false');
    assert.equal(await page.evaluate(script(true)), 'open');
    assert.equal(await page.locator('#draft').inputValue(), 'keep');
    // Wide screens hide the button (md:hidden) because the list is beside the chat.
    await page.evaluate(() => { document.querySelector('#list').style.display = 'none'; });
    assert.equal(await page.evaluate(script(true)), 'wide');
    // A changed website without the button is not clicked around: it is reported as having no phone list.
    await page.evaluate(() => document.querySelector('#list').remove());
    assert.equal(await page.evaluate(script(true)), 'wide');
    assert.equal(await page.locator('#menu').getAttribute('aria-expanded'), 'false');
    assert.equal(await page.locator('#banner').getAttribute('aria-expanded'), 'false');
    console.log('PASS: sign-in page, other site, starting site, connecting workspace, workspace without bots, bots not loaded, closed list report, one click on the list button only (not a banner or chat button), open list, wide layout and missing button');
  } finally {
    await browser.close();
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
