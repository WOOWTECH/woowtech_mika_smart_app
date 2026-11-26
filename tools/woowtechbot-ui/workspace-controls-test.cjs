const { chromium } = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const fs = require('fs'), assert = require('node:assert/strict');
const source = fs.readFileSync(require('path').resolve(__dirname, '../../app/src/main/assets/woowtechbot/workspace-controls.js'), 'utf8');
const script = skin => source.replace('__WOOW_CONFIGURATION__', JSON.stringify({skin, services: 'Services', notifications: 'Notifications'}));
(async () => {
  const browser = await chromium.launch({headless: true, executablePath: process.env.CHROME_EXECUTABLE});
  try {
    const page = await browser.newPage({viewport: {width: 390, height: 844}});
    await page.setContent('<html><head></head><body><div data-look="app"><aside id="sidebar"><header data-sidebar-top-slot><button id="original">New conversation</button></header></aside><textarea id="draft">preserve draft</textarea></div></body></html>');
    assert.equal(await page.evaluate(script('midnight')), true);
    assert.equal(await page.evaluate(script('midnight')), true);
    assert.equal(await page.locator('.woow-workspace-controls').count(), 1);
    assert.equal(await page.locator('.woow-workspace-controls a').count(), 2);
    assert.equal(await page.locator('head style').count(), 1);
    assert.equal(await page.locator('#original').count(), 1);
    assert.equal(await page.locator('#draft').inputValue(), 'preserve draft');
    for (const [skin, colorScheme] of [['daylight', 'light'], ['midnight', 'dark']]) {
      assert.equal(await page.evaluate(script(skin)), true);
      assert.equal(await page.locator('html').getAttribute('data-skin'), skin);
      assert.equal(await page.evaluate(() => document.documentElement.style.colorScheme), colorScheme);
      assert.equal(await page.locator('#draft').inputValue(), 'preserve draft');
    }
    // Normal mobile chat: the list is mounted but closed, not unsupported.
    await page.evaluate(() => { document.querySelector('#sidebar').style.display = 'none'; });
    assert.equal(await page.locator('.woow-workspace-controls').isVisible(), false);
    assert.equal(await page.evaluate(script('midnight')), true);
    await page.evaluate(() => { document.querySelector('#sidebar').style.display = ''; });
    assert.equal(await page.locator('.woow-workspace-controls').isVisible(), true);
    assert.equal(await page.locator('#draft').inputValue(), 'preserve draft');
    // React replacement is repaired by the observer, without a native reinjection.
    await page.evaluate(() => {
      const replacement = document.createElement('header'); replacement.dataset.sidebarTopSlot = '';
      replacement.innerHTML = '<button id="original">New conversation</button>';
      document.querySelector('[data-sidebar-top-slot]').replaceWith(replacement);
    });
    await page.waitForFunction(() => document.querySelectorAll('.woow-workspace-controls a').length === 2);
    assert.equal(await page.locator('#original').count(), 1);
    assert.equal(await page.locator('.woow-workspace-controls a').first().getAttribute('href'), 'woowtech-ui://services');
    // Reinjection must repair incomplete controls synchronously, not trust a marker.
    assert.equal(await page.evaluate(code => {
      document.querySelector('a[href="woowtech-ui://notifications"]').remove();
      return (0, eval)(code);
    }, script('daylight')), true);
    assert.equal(await page.locator('.woow-workspace-controls').count(), 1);
    assert.equal(await page.locator('.woow-workspace-controls a').count(), 2);
    await page.evaluate(() => document.querySelector('[data-sidebar-top-slot]').remove());
    assert.equal(await page.evaluate(script('midnight')), false);
    // A marker alone, or an unrelated slot outside the app, cannot suppress fallback.
    const unsupported = await browser.newPage();
    await unsupported.setContent('<div data-look="app"><textarea>draft</textarea></div><header data-sidebar-top-slot></header>');
    assert.equal(await unsupported.evaluate(script('midnight')), false);
    assert.equal(await unsupported.evaluate(script('daylight')), false);
    assert.equal(await unsupported.locator('.woow-workspace-controls').count(), 0);
    await unsupported.evaluate(() => {
      const slot = document.createElement('header'); slot.dataset.sidebarTopSlot = '';
      document.querySelector('[data-look="app"]').append(slot);
    });
    await unsupported.waitForFunction(() => document.querySelectorAll('.woow-workspace-controls a').length === 2);
    assert.equal(await unsupported.evaluate(script('midnight')), true);
    await unsupported.evaluate(() => document.querySelector('[data-look="app"]').remove());
    assert.equal(await unsupported.evaluate(script('midnight')), false);
    console.log('PASS: repeat injection, original controls, draft retention, both themes, hidden chat sidebar, React slot replacement, incomplete controls repair, missing slot/app fallback and late slot recovery');
  } finally {
    await browser.close();
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
