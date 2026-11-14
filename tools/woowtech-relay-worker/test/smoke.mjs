import { spawn } from "node:child_process";
import assert from "node:assert/strict";
import WebSocket from "ws";
import { readFileSync, mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";

const live = process.env.RELAY_LIVE === "1";
const origin = live ? "https://assistant-relay.woowtech.io" : "http://127.0.0.1:18793";
const dataDir = live ? null : mkdtempSync(tmpdir()+'/relay-smoke-');
const owner = live ? readFileSync(process.env.RELAY_OWNER_FILE, "utf8").trim() : "local-test-owner-key-at-least-thirty-two-characters";
const reportAdmin = "local-test-report-admin-key-at-least-thirty-two-characters";
const child = live ? null : spawn("node", ["node_modules/wrangler/bin/wrangler.js", "dev", "--local", "--ip", "127.0.0.1", "--port", "18793", "--persist-to", dataDir, "--var", `OWNER_KEY:${owner}`, "--var", `REPORT_ADMIN_KEY:${reportAdmin}`], { stdio: ["ignore", "pipe", "pipe"] });
let output = "";
child?.stdout.on("data", (b) => output += b);
child?.stderr.on("data", (b) => output += b);

async function waitReady() {
  for (let i = 0; i < 100; i++) {
    try { if ((await fetch(origin + "/healthz", { headers: { host: "assistant-relay.woowtech.io" } })).ok) return; } catch {}
    await new Promise((r) => setTimeout(r, 100));
  }
  throw new Error("wrangler dev did not become ready\n" + output);
}

async function form(action, key = owner, extra = {}) {
  return fetch(origin + "/admin", {
    method: "POST",
    headers: { host: "assistant-relay.woowtech.io", "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ owner_key: key, action, ...extra })
  });
}

try {
  await waitReady();
  let response = await fetch(origin + "/", { headers: { host: "assistant-relay.woowtech.io" } });
  assert.equal(response.status, 200);
  let page = await response.text();
  assert.match(page, /渥屋助理遠端中繼/);
  assert.match(page, /<main><section class="play-note">.*io\.woowtech\.assistant.*href="\/privacy\/play"/s, 'homepage says what the Play app uses');
  assert.doesNotMatch(page, /OWNER_KEY|local-test-owner/);
  assert.match(response.headers.get("content-security-policy"), /default-src 'none'/);
  response = await fetch(origin + '/privacy/play', { headers: { host: 'assistant-relay.woowtech.io' } });
  assert.equal(response.status, 200, 'privacy policy works without sign-in');
  assert.match(response.headers.get('content-type'), /text\/html/);
  const privacy = await response.text();
  assert.match(privacy, /io\.woowtech\.assistant/);
  assert.match(privacy, /woowtech@designsmart\.com\.tw/);
  assert.match(privacy, /30 days/);
  assert.doesNotMatch(privacy, /OWNER_KEY|REPORT_ADMIN_KEY/);
  for (const text of ['渥屋助理（woowtech agent）隱私權政策', 'woowtech agent (渥屋助理) Privacy Policy', 'WOOW TECH CO., LTD.',
    '自動記住我說過的事', 'Remember what I say', '使用 ChatGPT 繼續', 'Continue with ChatGPT', '<h2>刪除資料</h2>', '<h2>Deleting your data</h2>'])
    assert.ok(privacy.includes(text), 'privacy policy covers: ' + text);
  assert.doesNotMatch(privacy, /Play edition|商店版|Google Play 版|WoowTech Assistant/, 'one app name, no edition wording');
  response = await fetch(origin + '/privacy/play', { method: 'HEAD', headers: { host: 'assistant-relay.woowtech.io' } });
  assert.equal(response.status, 200, 'privacy policy answers HEAD for link checkers');
  assert.match(response.headers.get('content-type'), /text\/html/);
  assert.equal(await response.text(), '');

  response = await fetch(origin + '/privacy/ios', { headers: { host: 'assistant-relay.woowtech.io' } });
  assert.equal(response.status, 200, 'iOS privacy policy works without sign-in');
  assert.match(response.headers.get('content-type'), /text\/html/);
  assert.match(response.headers.get('content-security-policy'), /style-src 'self'/);
  const iosPrivacy = await response.text();
  for (const text of ['渥屋助理（woowtech agent）iOS 隱私權政策', 'woowtech agent (渥屋助理) iOS Privacy Policy', 'WOOW TECH CO., LTD.',
    'woowtech@designsmart.com.tw', '從做過的事裡學（技能和操作路線）', 'Learn from past tasks (skills and routes)',
    '<h2>刪除資料</h2>', '<h2>Deleting your data</h2>', '<link rel="stylesheet" href="/privacy/ios.css">'])
    assert.ok(iosPrivacy.includes(text), 'iOS privacy policy covers: ' + text);
  assert.doesNotMatch(iosPrivacy, /<style|<script|<!--|OWNER_KEY|REPORT_ADMIN_KEY|ChatGPT|Baidu|百度/,
    'no inline style or script, no draft notes, no feature the iOS 1.0 app lacks');
  response = await fetch(origin + '/privacy/ios', { method: 'HEAD', headers: { host: 'assistant-relay.woowtech.io' } });
  assert.equal(response.status, 200, 'iOS privacy policy answers HEAD for link checkers');
  assert.equal(await response.text(), '');
  response = await fetch(origin + '/privacy/ios.css', { headers: { host: 'assistant-relay.woowtech.io' } });
  assert.equal(response.status, 200);
  assert.match(response.headers.get('content-type'), /text\/css/);
  assert.match(await response.text(), /^body\{.*ul\{margin:\.6em 0;padding-left:1\.4em\}li\{margin:\.25em 0\}$/s);

  const reportId = '123e4567-e89b-42d3-a456-426614174000';
  const reportBody = { id: reportId, reason: 'incorrect', note: 'test note', response: 'test response', created_at_ms: Date.now() };
  const reportHeaders = { host: 'assistant-relay.woowtech.io', 'cf-connecting-ip': '192.0.2.42', 'content-type': 'application/json' };
  response = await fetch(origin + '/api/v1/ai-reports', { method: 'POST', headers: reportHeaders, body: JSON.stringify(reportBody) });
  assert.equal(response.status, 201, 'unpaired report intake');
  const acceptedReport = await response.json();
  assert.deepEqual({ id: acceptedReport.id, accepted: acceptedReport.accepted }, { id: reportId, accepted: true });
  assert.match(acceptedReport.deletion_receipt, /^[A-Za-z0-9_-]{43}$/);
  response = await fetch(origin + '/api/v1/ai-reports', { method: 'POST', headers: reportHeaders, body: JSON.stringify(reportBody) });
  assert.equal(response.status, 201);
  assert.deepEqual(await response.json(), { id: reportId, accepted: true });
  response = await fetch(origin + '/admin/ai-reports', { headers: { host: 'assistant-relay.woowtech.io', authorization: 'Bearer wrong' } });
  assert.equal(response.status, 403);
  response = await fetch(origin + '/admin/ai-reports', { headers: { host: 'assistant-relay.woowtech.io', 'x-report-owner': 'yes' } });
  assert.equal(response.status, 403, 'forged internal owner header');
  response = await fetch(origin + '/admin/ai-reports', { headers: { host: 'assistant-relay.woowtech.io', authorization: 'Bearer ' + owner } });
  assert.equal(response.status, 200);
  assert.equal((await response.json()).reports[0].response, reportBody.response);
  if (!live) {
    response = await fetch(origin + '/admin/ai-reports', { headers: { host: 'assistant-relay.woowtech.io', authorization: 'Bearer ' + reportAdmin } });
    assert.equal(response.status, 200, 'dedicated report reviewer key');
    assert.equal((await response.json()).reports[0].id, reportId);
  }
  response = await fetch(origin + '/api/v1/ai-reports/' + reportId, { method: 'DELETE', headers: { host: 'assistant-relay.woowtech.io', authorization: 'Bearer ' + acceptedReport.deletion_receipt } });
  assert.equal(response.status, 200);
  response = await fetch(origin + '/admin/ai-reports', { headers: { host: 'assistant-relay.woowtech.io', authorization: 'Bearer ' + owner } });
  assert.equal((await response.json()).reports.length, 0);
  if (!live) {
    // Reviewers can share one exit IP: 60 reports per source IP per hour are accepted, the 61st is not.
    const burst = { ...reportHeaders, 'cf-connecting-ip': '192.0.2.43' };
    for (let i = 0; i <= 60; i++) {
      const id = '223e4567-e89b-42d3-a456-' + String(426614174000 + i);
      response = await fetch(origin + '/api/v1/ai-reports', { method: 'POST', headers: burst, body: JSON.stringify({ ...reportBody, id }) });
      await response.arrayBuffer();
      assert.equal(response.status, i < 60 ? 201 : 429, `report ${i + 1} from one source IP`);
    }
  }

  response = await form("status", "wrong");
  assert.equal(response.status, 403);
  assert.doesNotMatch(await response.text(), /local-test-owner/);

  response = await form("pair");
  assert.equal(response.status, 200);
  page = await response.text();
  const code = page.match(/<output>([A-Za-z0-9_-]{16})<\/output>/)?.[1];
  assert.equal(code?.length, 16);

  const simultaneous = await Promise.all([0, 1].map(() => fetch(origin + "/pair", { method: "POST", headers: { host: "assistant-relay.woowtech.io", "content-type": "application/json" }, body: JSON.stringify({ code }) })));
  assert.equal(simultaneous.filter(r => r.status === 200).length, 1, "only one concurrent pairing may succeed");
  response = simultaneous.find(r => r.status === 200);
  const paired = await response.json();
  assert.equal(paired.mcpUrl, "https://assistant-relay.woowtech.io/mcp");
  assert.ok(paired.deviceToken.length >= 40);
  assert.deepEqual(Object.keys(paired).sort(),['deviceToken','mcpUrl']);
  const info=await fetch(origin+'/device/info',{headers:{host:'assistant-relay.woowtech.io',authorization:'Bearer '+paired.deviceToken}});
  assert.equal(info.status,200);
  assert.equal((await info.json()).mcpUrl,'https://assistant-relay.woowtech.io/mcp');

  response = await fetch(origin + "/pair", { method: "POST", headers: { host: "assistant-relay.woowtech.io", "content-type": "application/json" }, body: JSON.stringify({ code }) });
  assert.equal(response.status, 403);

  response = await form("status");
  assert.match(await response.text(), /目前離線/);

  const ws = new WebSocket(origin.replace("http", "ws") + "/device", ["mika-relay.v2"], { headers: { host: "assistant-relay.woowtech.io", authorization: `Bearer ${paired.deviceToken}` } });
  await new Promise((resolve, reject) => { ws.addEventListener("open", resolve, { once: true }); ws.addEventListener("error", reject, { once: true }); });
  response = await form("status");
  assert.match(await response.text(), /手機通道已連線/);

  const requestFrame = new Promise((resolve) => ws.addEventListener("message", (event) => resolve(JSON.parse(event.data)), { once: true }));
  const proxied = fetch(origin + "/api/v1/tasks?limit=1", { headers: { host: "assistant-relay.woowtech.io", authorization: "Bearer phone-access", "x-mika-client": "smoke" } });
  const frame = await requestFrame;
  assert.equal(frame.type, "request");
  assert.equal(frame.path, "/api/v1/tasks");
  assert.equal(frame.query, "limit=1");
  assert.equal(frame.headers.authorization, "Bearer phone-access");
  ws.send(JSON.stringify({ type: "response", id: frame.id, status: 200, headers: { "content-type": "application/json" }, body: btoa('{"ok":true}') }));
  response = await proxied;
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { ok: true });

  for (const status of [502, 504, 204]) {
    const next = new Promise(resolve => ws.addEventListener("message", e => resolve(JSON.parse(e.data)), { once: true }));
    const call = fetch(origin + "/mcp", { method: "POST", headers: { host: "assistant-relay.woowtech.io" }, body: "{}" });
    const f = await next;
    ws.send(JSON.stringify({ type: "response", id: f.id, status, body: status === 204 ? "" : btoa("phone response") }));
    const result = await call;
    assert.equal(result.status, status);
    assert.equal(await result.text(), status === 204 ? "" : "phone response");
  }

  response = await fetch(origin + "/admin", { method: "POST", headers: { host: "assistant-relay.woowtech.io", origin: "https://untrusted.example", "content-type": "application/x-www-form-urlencoded" }, body: new URLSearchParams({ owner_key: owner, action: "revoke", confirm: "yes" }) });
  assert.equal(response.status, 403);
  response = await fetch(origin + "/mcp", { method: "POST", headers: { host: "assistant-relay.woowtech.io" }, body: "x".repeat(1048577) });
  assert.equal(response.status, 413);

  response = await fetch(origin + "/device", { method: "DELETE", headers: { host: "assistant-relay.woowtech.io", authorization: `Bearer ${paired.deviceToken}` } });
  assert.equal(response.status, 204);
  response = await fetch(origin + "/device", { headers: { host: "assistant-relay.woowtech.io", authorization: `Bearer ${paired.deviceToken}` } });
  assert.equal(response.status, 401);
  console.log("PASS: page security, Play privacy policy (GET/HEAD), iOS privacy policy (GET/HEAD/CSS), report intake/deletion/per-IP limit, owner auth, concurrent single-use pairing, offline/online state, mika-relay.v2 forwarding, transparent 502/504/204, cross-origin rejection, body limit, device revoke");
} finally {
  child?.kill("SIGTERM");
  if (child) await Promise.race([new Promise((resolve) => child.once("exit", resolve)), new Promise((resolve) => setTimeout(resolve, 3000))]);
  if(dataDir)rmSync(dataDir,{recursive:true,force:true});
}
