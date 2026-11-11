// Execute the shipped page script with a minimal DOM: no network or browser account.
const {readFileSync} = require('node:fs');
const {resolve} = require('node:path');
const {runInNewContext} = require('node:vm');
const {test} = require('node:test');
const assert = require('node:assert/strict');
const html = readFileSync(resolve(__dirname, '../web/open-apporo-assistant.html'), 'utf8');
const script = html.match(/<script>([\s\S]*?)<\/script>/)[1];
function page(href='https://apporo.example/open?redirect=https://bad.example#payload', ua='Android Chrome') {
  const listeners = {}, timers = new Map(); let id = 0;
  const nodes = {open:{addEventListener:(name, fn)=>{listeners[name]=fn;}},status:{hidden:true}};
  const document = {hidden:false, getElementById:k=>nodes[k], addEventListener:(name,fn)=>{listeners[name]=fn;}};
  const location = new URL(href);
  runInNewContext(script, {URL, URLSearchParams, document, location, navigator:{userAgent:ua},
    setTimeout:fn=>{timers.set(++id,fn);return id;}, clearTimeout:key=>timers.delete(key)});
  return {nodes, timers, listeners, document, location};
}
test('Apporo identity and compatible download use the current public release',()=>{
  assert.match(html, /<html lang="en">/);
  assert.match(html, /https:\/\/github\.com\/WOOWTECH\/apporo-assistant-releases\/releases\/latest/);
  assert.doesNotMatch(html, /io\.woowtech\.agent|渥屋|apporo\.7-qa/);
});
test('only Apporo is targeted; fallback stays on the deployed page without payload',()=>{
  const p=page();
  assert.match(p.nodes.open.href, /scheme=com\.apporo\.assistant;package=com\.apporo\.assistant;/);
  const fallback=decodeURIComponent(p.nodes.open.href.split('S.browser_fallback_url=')[1].split(';')[0]);
  assert.equal(fallback, 'https://apporo.example/open?v=fb');
  assert.equal(p.timers.size, 0); // No automatic opening or polling.
  assert.equal(p.location.href, 'https://apporo.example/open?redirect=https://bad.example#payload');
});
test('fallback explains recovery without redirecting again',()=>{
  const p=page('https://apporo.example/open?v=fb');
  assert.equal(p.nodes.status.hidden,false);
  assert.match(p.nodes.status.textContent,/could not open/);
  assert.equal(p.timers.size,0);
});
test('non-Android users get guidance instead of an unusable launch button',()=>{
  const p=page('https://apporo.example/open','iPhone');
  assert.equal(p.nodes.open.hidden,true);
  assert.match(p.nodes.status.textContent,/Android phone/);
});
test('a click that stays visible shows recovery guidance, not success',()=>{
  const p=page();p.listeners.click();
  assert.equal(p.timers.size,1); [...p.timers.values()][0]();
  assert.match(p.nodes.status.textContent,/If the app did not open/);
});
test('leaving the page cancels guidance without claiming successful app launch',()=>{
  const p=page();p.listeners.click();p.document.hidden=true;p.listeners.visibilitychange();
  assert.equal(p.timers.size,0);assert.equal(p.nodes.status.hidden,true);
});
test('repeat taps replace the timer instead of accumulating retries',()=>{
  const p=page();p.listeners.click();p.listeners.click();assert.equal(p.timers.size,1);
});
