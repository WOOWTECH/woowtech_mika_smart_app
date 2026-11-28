const { chromium } = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const fs = require('fs'), assert = require('node:assert/strict');
const hook = fs.readFileSync(require('path').resolve(__dirname, '../../app/src/main/assets/woowtechbot/workspace-downloads.js'), 'utf8');
const CHUNK = 512 * 1024;
(async () => {
  const browser = await chromium.launch({headless: true, executablePath: process.env.CHROME_EXECUTABLE});
  try {
    const page = await browser.newPage();
    await page.setContent('<html><body><p>downloads</p></body></html>');
    assert.equal(await page.evaluate(hook), true);
    assert.equal(await page.evaluate(hook), true, 'idempotent');
    // The website's own pattern (2026-11-27 bundle): fetch → Blob → object URL → <a download> click → revoke at once.
    const url = await page.evaluate((size) => {
      const bytes = new Uint8Array(size);
      for (let i = 0; i < size; i++) bytes[i] = (i * 31 + 7) & 255;
      const blob = new Blob([bytes], {type: 'application/pdf'});
      const href = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = href; a.download = '報告 2026.pdf'; a.style.display = 'none';
      document.body.append(a);
      try { a.click(); } finally { a.remove(); }
      setTimeout(() => URL.revokeObjectURL(href), 0);
      return href;
    }, CHUNK * 2 + 1234);
    await page.waitForTimeout(50); // revoked by now
    assert.equal(await page.evaluate(async (u) => { try { await fetch(u); return 'readable'; } catch (e) { return 'revoked'; } }, url), 'revoked');
    // The app's protocol: start, info until ready, then read/take each chunk.
    const call = (expr) => page.evaluate(expr);
    assert.equal(await call(`window.__woowDownloads.start("t1", ${JSON.stringify(url)})`), 'started');
    let info = 'pending';
    for (let i = 0; i < 50 && info === 'pending'; i++) { info = await call(`window.__woowDownloads.info("t1", ${JSON.stringify(url)})`); await page.waitForTimeout(10); }
    info = JSON.parse(info);
    assert.deepEqual(info, {size: CHUNK * 2 + 1234, type: 'application/pdf', name: '報告 2026.pdf'});
    const parts = [];
    for (let index = 0; index * CHUNK < info.size; index++) {
      assert.equal(await call(`window.__woowDownloads.read("t1", ${index}, ${CHUNK})`), 'reading');
      let data = null;
      for (let i = 0; i < 200 && data === null; i++) { data = await call(`window.__woowDownloads.take("t1", ${index})`); if (data === null) await page.waitForTimeout(5); }
      assert.notEqual(data, 'error');
      parts.push(Buffer.from(data, 'base64'));
    }
    const got = Buffer.concat(parts);
    assert.equal(got.length, info.size);
    for (let i = 0; i < got.length; i++) if (got[i] !== ((i * 31 + 7) & 255)) assert.fail('byte ' + i);
    assert.equal(await call('window.__woowDownloads.end("t1")'), true);
    assert.equal(await call(`window.__woowDownloads.info("t1", ${JSON.stringify(url)})`), 'unknown');
    // An object URL the hook never saw and that no longer exists fails; an unknown token is reported, not thrown.
    assert.equal(await call('window.__woowDownloads.start("t2", "blob:https://example.invalid/none")'), 'started');
    let state = 'pending';
    for (let i = 0; i < 50 && state === 'pending'; i++) { state = await call('window.__woowDownloads.info("t2", "blob:x")'); await page.waitForTimeout(10); }
    assert.equal(state, 'failed');
    assert.equal(await call('window.__woowDownloads.take("nope", 0)'), 'unknown');
    // Revoked Blobs are let go after 60 s, so the page's memory is not held for long.
    const released = await page.evaluate(async () => {
      const real = window.setTimeout; let delay = -1;
      window.setTimeout = (fn, ms) => { delay = ms; return real(fn, 0); };
      const href = URL.createObjectURL(new Blob(['x']));
      URL.revokeObjectURL(href);
      window.setTimeout = real;
      await new Promise((r) => real(r, 20));
      window.__woowDownloads.start('t3', href);
      await new Promise((r) => real(r, 50));
      return [delay, window.__woowDownloads.info('t3', href)];
    });
    assert.deepEqual(released, [60000, 'failed']);
    console.log('PASS: idempotent hook, website-style revoke-at-once blob kept, anchor download name, chunked read of 1 MiB+ exact bytes, end, unknown blob and token, release after 60 s');
  } finally {
    await browser.close();
  }
})().catch((error) => { console.error(error); process.exitCode = 1; });
