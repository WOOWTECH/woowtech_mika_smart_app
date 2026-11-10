import { spawn } from "node:child_process";
import assert from "node:assert/strict";
import WebSocket from "ws";
import { readFileSync, mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";

const live = process.env.RELAY_LIVE === "1";
const origin = live ? "https://assistant-relay.woowtech.io" : "http://127.0.0.1:18793";
const dataDir = live ? null : mkdtempSync(tmpdir()+'/relay-smoke-');
const owner = live ? readFileSync(process.env.RELAY_OWNER_FILE, "utf8").trim() : "local-test-owner-key-at-least-thirty-two-characters";
const child = live ? null : spawn("node", ["node_modules/wrangler/bin/wrangler.js", "dev", "--local", "--ip", "127.0.0.1", "--port", "18793", "--persist-to", dataDir, "--var", `OWNER_KEY:${owner}`], { stdio: ["ignore", "pipe", "pipe"] });
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
  assert.doesNotMatch(page, /OWNER_KEY|local-test-owner/);
  assert.match(response.headers.get("content-security-policy"), /default-src 'none'/);

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
  console.log("PASS: page security, owner auth, concurrent single-use pairing, offline/online state, mika-relay.v2 forwarding, transparent 502/504/204, cross-origin rejection, body limit, device revoke");
} finally {
  child?.kill("SIGTERM");
  if (child) await Promise.race([new Promise((resolve) => child.once("exit", resolve)), new Promise((resolve) => setTimeout(resolve, 3000))]);
  if(dataDir)rmSync(dataDir,{recursive:true,force:true});
}
