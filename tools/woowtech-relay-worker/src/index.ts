import { DurableObject } from "cloudflare:workers";
import { AccountAuth, authCall, authRoute, currentAccount, SITE, redirect } from './auth';
import cliSource from '../downloads/woow-relay-cli.py';
import cliLicense from '../downloads/LICENSE.txt';
import appIntegration from '../docs/app-integration.md';
import { ReportInbox } from './reports';
import { privacyPlayHtml, privacyPlayCss } from './privacy-play';
export { AccountAuth };
export { ReportInbox };

export interface Env {
  RELAY: DurableObjectNamespace<RelayDurableObject>;
  OWNER_KEY: string;
  REPORT_ADMIN_KEY?: string;
  AUTH: DurableObjectNamespace<AccountAuth>;
  REPORTS: DurableObjectNamespace<ReportInbox>;
}

type RelayFrame = {
  type: "request" | "response" | "cancel";
  id: string;
  method?: string;
  path?: string;
  query?: string;
  headers?: Record<string, string>;
  body?: string;
  status?: number;
  client?: string;
  transportError?: boolean;
};

const ORIGIN = "https://assistant-relay.woowtech.io";
const PROTOCOL = "mika-relay.v2";
const MAX_BODY = 1 << 20;
const REQUEST_HEADERS = new Set(["authorization", "origin", "x-mika-client", "content-type", "accept", "mcp-protocol-version", "mcp-method", "mcp-name", "mcp-session-id", "last-event-id"]);
const RESPONSE_HEADERS = new Set(["content-type", "cache-control", "allow", "retry-after", "www-authenticate", "mcp-protocol-version"]);
const encoder = new TextEncoder();

function json(data: unknown, status = 200, headers: HeadersInit = {}): Response {
  return new Response(JSON.stringify(data) + "\n", { status, headers: { "content-type": "application/json; charset=utf-8", ...headers } });
}

function failure(status: number, code: string, api = false): Response {
  return json(api ? { error: { code, message: code } } : { error: code }, status);
}

function security(response: Response): Response {
  const h = new Headers(response.headers);
  h.set("cache-control", "no-store");
  h.set("x-content-type-options", "nosniff");
  h.set("referrer-policy", "same-origin");
  h.set("strict-transport-security", "max-age=31536000");
  h.set("content-security-policy", "default-src 'none'; style-src 'self'; script-src 'self'; form-action 'self'; frame-ancestors 'none'; base-uri 'none'");
  return new Response(response.body, { status: response.status, statusText: response.statusText, headers: h, webSocket: response.webSocket });
}

function randomSecret(bytes = 32): string {
  const data = crypto.getRandomValues(new Uint8Array(bytes));
  return btoa(String.fromCharCode(...data)).replaceAll("+", "-").replaceAll("/", "_").replaceAll("=", "");
}

async function digest(value: string): Promise<string> {
  const hash = await crypto.subtle.digest("SHA-256", encoder.encode(value));
  return [...new Uint8Array(hash)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

async function matches(value: string, hash: string | undefined): Promise<boolean> {
  if (!value || !hash) return false;
  const candidate = await digest(value);
  let difference = candidate.length ^ hash.length;
  for (let i = 0; i < Math.min(candidate.length, hash.length); i++) difference |= candidate.charCodeAt(i) ^ hash.charCodeAt(i);
  return difference === 0;
}

function bearer(request: Request): string {
  const value = request.headers.get("authorization") || "";
  return /^Bearer /i.test(value) ? value.slice(7).trim() : "";
}

function client(request: Request): string {
  const value = request.headers.get("cf-connecting-ip") || "";
  if (value.includes(":")) return value.split(":").slice(0, 4).join(":") + "::/64";
  return value;
}

function safeHeaders(headers: Record<string, string>): boolean {
  if (!headers || typeof headers !== "object" || Array.isArray(headers)) return false;
  const entries = Object.entries(headers);
  return entries.every(([k, v]) => typeof v === "string" && /^[!#$%&'*+.^_`|~0-9A-Za-z-]+$/.test(k) && !/[\r\n]/.test(v)) && entries.length <= 16 && entries.reduce((n, [k, v]) => n + encoder.encode(k + v).length, 0) <= 8192;
}

async function boundedBody(request: Request, limit: number): Promise<ArrayBuffer> {
  const reader = request.body?.getReader();
  if (!reader) return new ArrayBuffer(0);
  const chunks: Uint8Array[] = []; let size = 0;
  try {
    while (true) {
      const { value, done } = await reader.read();
      if (done) break;
      size += value.byteLength;
      if (size > limit) { await reader.cancel(); throw new Error("body_too_large"); }
      chunks.push(value);
    }
  } finally { reader.releaseLock(); }
  const result = new Uint8Array(size); let offset = 0;
  for (const chunk of chunks) { result.set(chunk, offset); offset += chunk.length; }
  return result.buffer;
}

function bodyToBase64(body: ArrayBuffer): string {
  const bytes = new Uint8Array(body);
  let binary = "";
  for (let i = 0; i < bytes.length; i += 0x8000) binary += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
  return btoa(binary);
}

function base64ToBody(body = ""): Uint8Array {
  const binary = atob(body);
  return Uint8Array.from(binary, (c) => c.charCodeAt(0));
}

function html(message = "", code = "", bad = false): string {
  const notice = message ? `<section class="notice ${bad ? "bad" : "ok"}" role="${bad ? "alert" : "status"}">${message}</section>` : "";
  const pairing = code ? `<section class="card"><h2>配對碼</h2><output>${code}</output><p>五分鐘內有效，只能使用一次。</p></section>` : "";
  return `<!doctype html><html lang="zh-Hant"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="theme-color" content="#6183FC"><title>渥屋助理遠端中繼</title><link rel="stylesheet" href="/style.css"><script src="/app.js" defer></script></head><body><header><div><span class="brand">woowtech</span><span>遠端中繼</span></div></header><main><section class="hero"><p class="eyebrow">The Smart Space Solution</p><h1>連接你的渥屋助理</h1><p>沿用 Mika 的遠端流程，透過 WoowTech 自有中繼安全地連接手機。</p></section>${notice}${pairing}<section class="card endpoint"><h2>手機要填的閘道位址</h2><code>${ORIGIN}</code><p>渥屋助理 → 設定 → 連接電腦 → 遠端。配對後仍須另外開啟遠端存取。</p></section><section class="card"><h2>管理手機配對</h2><form id="admin" action="/admin" method="post"><label for="owner">管理金鑰</label><input id="owner" name="owner_key" type="password" required autocomplete="current-password"><p>管理金鑰只用來產生配對碼與撤銷裝置，不是手機存取權杖。</p><div class="actions"><button name="action" value="status">查詢手機狀態</button><button name="action" value="pair">產生配對碼</button><button class="secondary" id="revoke" name="action" value="revoke">解除手機配對</button><input id="confirm" type="hidden" name="confirm" value=""></div></form></section><section class="grid"><article class="card"><h2>電腦端</h2><p>MCP 端點是 <code>${ORIGIN}/mcp</code>。Authorization 使用手機提供的存取權杖，不能填配對碼或管理金鑰。</p></article><article class="card"><h2>斷線處理</h2><p>網路中斷會重連；手機關閉遠端存取則停止重連。收到 delivery_unknown 時先查任務，避免重複執行修改操作。</p></article></section><section class="card privacy"><h2>資料與隱私</h2><p>HTTPS/WSS 在這個中繼終止，中繼技術上可讀取轉送的標頭、任務與結果；它不是電腦到手機的端對端加密。離線請求不排隊，重新連線不自動重送。</p></section><footer>單一管理者 · 單一手機 · WoowTech 自有中繼</footer></main></body></html>`;
}

function accountPage(message='',code='',tenant=''):string {
 const page=html(message,code);
 const login='<section class="card"><h2>你的手機，你的專屬連線</h2><p>使用既有 WoowTech 帳號登入，建立自己的手機配對與電腦連線。</p><a class="button" href="/auth/start">使用 WoowTech 帳號登入</a></section>';
 const controls=`<section class="card"><h2>我的手機</h2><form action="/account" method="post"><div class="actions"><button name="action" value="status">更新狀態</button><button name="action" value="pair">產生配對碼</button><button class="secondary" name="action" value="revoke">解除配對</button></div></form><p>每個帳號一支手機；每分鐘最多 240 個轉送請求，同時最多 8 個請求。配對與管理操作每分鐘最多 8 次。</p></section><section class="card"><h2>你的電腦連線位址</h2><p>MCP</p><code>${SITE}/r/${tenant}/mcp</code><p>CLI：使用下列網址作為 --url，搭配手機提供的存取權杖。</p><code>${SITE}/r/${tenant}</code><p>手機仍填上方共用閘道位址。電腦需使用這裡的專屬位址及手機權杖；位址本身不授予操作權限。</p></section><form action="/auth/logout" method="post"><button class="secondary">登出網站</button></form>`;
 const cliHelp=`<section class="card"><h2>使用命令列</h2><p>原版 Mika CLI 不接受帳號專屬路徑，請使用本站相容版本（Python 3.10 以上）。</p><a href="/downloads/woow-relay-cli.py">下載渥屋中繼 CLI</a><code>python3 woow-relay-cli.py --url ${SITE}/r/${tenant} --token-file /你的私人權杖檔 doctor</code><p>衍生自 Apache-2.0 授權的 Mika CLI。</p></section>`;
 return page.replace(/<section class="card"><h2>管理手機配對<\/h2>.*?<\/section>/s,tenant?controls+cliHelp:login)
  .replace(/<section class="grid">.*?<\/section>/s,'')
  .replace('單一管理者 · 單一手機 · WoowTech 自有中繼','個人帳號 · 獨立手機配對 · WoowTech 自有中繼');
}

const STYLE = `:root{--ww-blue:#6183FC;--ww-blue-700:#3F63E8;--ww-blue-050:#EEF2FF;--ww-white:#fff;--ww-gray:#EFF1F5;--ww-deep-gray:#646262;--ww-black:#212121;--space-2:8px;--space-4:16px;--space-6:24px;--space-8:32px;--radius-sm:12px;--radius:20px;--radius-lg:28px;--radius-pill:999px;--shadow:0 10px 28px rgba(33,33,33,.08);--font-title:Poppins,"Noto Sans TC",sans-serif;--font-body:Outfit,"Noto Sans TC",sans-serif}*{box-sizing:border-box}body{margin:0;background:var(--ww-gray);color:var(--ww-black);font:400 16px/1.6 var(--font-body)}header{background:rgba(255,255,255,.92);border-bottom:1px solid rgba(33,33,33,.07)}header>div,main{width:min(100% - 32px,880px);margin:auto}header>div{min-height:64px;display:flex;align-items:center;gap:16px;font:600 17px var(--font-title)}.brand{color:var(--ww-blue)}main{padding:48px 0}.hero{margin-bottom:32px}.eyebrow{color:var(--ww-blue);font-weight:600}.hero h1{font:600 clamp(32px,7vw,52px)/1.08 var(--font-title);letter-spacing:-.02em;margin:8px 0 16px}.hero p,.card p{color:var(--ww-deep-gray)}.card{background:var(--ww-white);border-radius:var(--radius);box-shadow:var(--shadow);padding:24px;margin:16px 0}.card h2{font:600 20px/1.2 var(--font-title);letter-spacing:-.02em;margin:0 0 12px}.endpoint{border-left:4px solid var(--ww-blue)}code,output{display:block;overflow-wrap:anywhere;background:var(--ww-blue-050);border-radius:var(--radius-sm);padding:12px;color:#304fc1;font:600 14px/1.5 ui-monospace,monospace}output{font-size:24px;letter-spacing:.05em}label{display:block;font-weight:600;margin-bottom:8px}input{width:100%;min-height:48px;border:1px solid #cfd3dc;border-radius:var(--radius-pill);padding:10px 16px;font:inherit}.actions{display:flex;flex-wrap:wrap;gap:12px;margin-top:20px}button{min-height:48px;border:0;border-radius:var(--radius-pill);padding:10px 20px;background:var(--ww-blue);color:white;font:600 15px var(--font-body);cursor:pointer;transition:220ms cubic-bezier(.4,0,.2,1)}button:hover{background:var(--ww-blue-700)}button:active{transform:scale(.97)}button.secondary{background:var(--ww-blue-050);color:#304fc1}:focus-visible{outline:3px solid #212121;outline-offset:3px}.notice{border-radius:var(--radius);padding:16px 20px;font-weight:600}.notice.ok{background:#e9f8ef;color:#176d3a}.notice.bad{background:#fff0ee;color:#a72b23}.grid{display:grid;grid-template-columns:1fr 1fr;gap:16px}.grid .card{margin:0}.privacy{border-top:4px solid #7BDBE0}footer{text-align:center;color:var(--ww-deep-gray);padding:32px 0}@media(max-width:600px){main{padding:32px 0}.grid{grid-template-columns:1fr}.actions button{width:100%}}`;
const LINK_STYLE = `.button{display:inline-flex;align-items:center;justify-content:center;min-height:48px;padding:10px 20px;background:var(--ww-blue-050);color:#304fc1;border-radius:var(--radius-pill);text-decoration:none;font-weight:600}.button:hover{background:#e1e8ff}.button:active{transform:scale(.97)}`;
const SCRIPT = `"use strict";const f=document.querySelector("#admin"),r=document.querySelector("#revoke"),c=document.querySelector("#confirm");f?.addEventListener("submit",e=>{if(e.submitter===r&&c.value!=="yes"&&!confirm("解除這台手機的配對？遠端連線會中斷。")){e.preventDefault()}else if(e.submitter===r){c.value="yes"}});`;

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    if (url.host !== new URL(ORIGIN).host) return security(failure(400, "invalid_host"));
    if (!env.OWNER_KEY || env.OWNER_KEY.length < 32) return security(failure(503, "not_configured"));
    if (url.pathname === '/privacy/play' && request.method === 'GET')
      return security(new Response(privacyPlayHtml, { headers: { 'content-type': 'text/html; charset=utf-8' } }));
    if (url.pathname === '/privacy/play.css' && request.method === 'GET')
      return security(new Response(privacyPlayCss, { headers: { 'content-type': 'text/css; charset=utf-8' } }));
    if (url.pathname === '/api/v1/ai-reports' || /^\/api\/v1\/ai-reports\/[0-9a-f-]+$/i.test(url.pathname) || url.pathname === '/admin/ai-reports' || /^\/admin\/ai-reports\/[0-9a-f-]+$/i.test(url.pathname)) {
      if (request.headers.has('origin')) return security(failure(403, 'browser_not_allowed', true));
      const admin = url.pathname.startsWith('/admin/');
      const deleting = request.method === 'DELETE';
      if (admin ? !(request.method === 'GET' || deleting) : !(request.method === 'POST' && url.pathname === '/api/v1/ai-reports' || deleting))
        return security(failure(405, 'method_not_allowed', true));
      if (admin) {
        const key = bearer(request);
        const owner = await matches(key, await digest(env.OWNER_KEY));
        const reportAdmin = env.REPORT_ADMIN_KEY && env.REPORT_ADMIN_KEY.length >= 32 &&
          await matches(key, await digest(env.REPORT_ADMIN_KEY));
        if (!owner && !reportAdmin) return security(failure(403, 'access_denied', true));
      }
      let body: ArrayBuffer | undefined;
      if (request.method === 'POST') {
        if (request.headers.get('content-type')?.split(';')[0].trim().toLowerCase() !== 'application/json') return security(failure(415, 'unsupported_media_type', true));
        try { body = await boundedBody(request, 16 * 1024); } catch { return security(failure(413, 'body_too_large', true)); }
      }
      const path = deleting ? '/delete/' + url.pathname.split('/').at(-1) : admin ? '/review' + url.search : '/intake';
      const headers = new Headers({ 'content-type': 'application/json' });
      if (admin) headers.set('x-report-owner', 'yes');
      else if (deleting) headers.set('x-report-receipt', bearer(request));
      else headers.set('x-report-ip', client(request));
      const inbox = env.REPORTS.getByName('ai-reports-v1');
      return security(await inbox.fetch('https://internal' + path, { method: request.method, headers, body }));
    }
    if(url.pathname==='/docs/app-integration.md'&&request.method==='GET')return security(new Response(appIntegration,{headers:{'content-type':'text/plain; charset=utf-8'}}));
    if(url.pathname==='/downloads/LICENSE.txt'&&request.method==='GET')return security(new Response(cliLicense,{headers:{'content-type':'text/plain; charset=utf-8'}}));
    if(url.pathname==='/downloads/woow-relay-cli.py'&&request.method==='GET')return security(new Response(cliSource,{headers:{'content-type':'text/x-python; charset=utf-8','content-disposition':'attachment; filename="woow-relay-cli.py"'}}));
    if(url.pathname.startsWith('/auth/'))return security(await authRoute(request,env));
    if(url.pathname==='/' && request.method==='GET')return security(new Response(accountPage(),{headers:{'content-type':'text/html; charset=utf-8'}}));
    if(url.pathname==='/account') {
      const account=await currentAccount(request,env);
      if(!account)return security(redirect('/auth/start'));
      if(request.method!=='GET'&&request.method!=='POST')return security(failure(405,'method_not_allowed'));
      let action='status'; let confirm='';
      if(request.method==='POST') {
        if(request.headers.get('origin')!==SITE)return security(failure(403,'invalid_origin'));
        let form: URLSearchParams;
        try{form=new URLSearchParams(new TextDecoder().decode(await boundedBody(request,4096)));}catch{return security(failure(413,'body_too_large'));}
        action=form.get('action')||'';confirm=form.get('confirm')||'';
        if(!['status','pair','revoke'].includes(action))return security(failure(400,'invalid_request'));
        if(action==='revoke'&&confirm!=='yes')return security(new Response(accountPage('解除配對會斷開這支手機。', '',account.tenant).replace('<h2>我的手機</h2>','<h2>確認解除配對？</h2><form action="/account" method="post"><input type="hidden" name="action" value="revoke"><button name="confirm" value="yes">確認解除配對</button></form>'),{headers:{'content-type':'text/html; charset=utf-8'}}));
      }
      const result=await env.RELAY.getByName('account:'+account.tenant).fetch(SITE+'/admin',{method:'POST',headers:{'content-type':'application/x-www-form-urlencoded','x-relay-owner-hash':await digest(env.OWNER_KEY),'x-relay-tenant':account.tenant,'cf-connecting-ip':account.tenant},body:new URLSearchParams({owner_key:env.OWNER_KEY,action,confirm})});
      const rendered=await result.text();
      const message=rendered.match(/role="(?:status|alert)">([^<]*)<\/section>/)?.[1]||'';
      const code=rendered.match(/<output>([-_A-Za-z0-9]+)<\/output>/)?.[1]||'';
      return security(new Response(accountPage(message,code,account.tenant),{status:result.status,headers:{'content-type':'text/html; charset=utf-8'}}));
    }
    let tenant=''; let targetPath=url.pathname; let pairBody: ArrayBuffer|undefined;
    const route=url.pathname.match(/^\/r\/([-_A-Za-z0-9]{22})(\/mcp|\/admin|\/api\/v1(?:\/.*)?)$/);
    if(route){tenant=route[1];targetPath=route[2];}
    else if(url.pathname==='/pair'&&request.method==='POST') {
      try{pairBody=await boundedBody(request,16384);const input=JSON.parse(new TextDecoder().decode(pairBody));if(typeof input.code==='string'&&/^[-_A-Za-z0-9]{22}_[-_A-Za-z0-9]{16}$/.test(input.code))tenant=input.code.slice(0,22);}catch{return security(failure(400,'invalid_request'));}
    } else if(url.pathname==='/device'||url.pathname==='/device/info') {
      const token=bearer(request);if(/^[-_A-Za-z0-9]{22}_[-_A-Za-z0-9]{20}$/.test(token))tenant=token.slice(0,22);
    }
    if(tenant) {
      const known=await (await authCall(env,'/exists',{tenant})).json<{exists:boolean}>();
      if(!known.exists){if(url.pathname==='/device'||url.pathname==='/device/info')tenant='';else return security(failure(404,'not_found'));}
    }
    const stub = env.RELAY.getByName(tenant?'account:'+tenant:"primary");
    const rewritten=new URL(request.url);rewritten.pathname=targetPath;
    if(pairBody)request=new Request(request.url,{method:'POST',headers:request.headers,body:pairBody});
    const forwarded = new Request(rewritten,request);
    forwarded.headers.delete('x-relay-tenant');
    if(tenant)forwarded.headers.set('x-relay-tenant',tenant);
    forwarded.headers.set("x-relay-owner-hash", await digest(env.OWNER_KEY));
    const response = url.pathname === "/style.css" ? new Response(STYLE+LINK_STYLE, { headers: { "content-type": "text/css; charset=utf-8" } }) : url.pathname === "/app.js" ? new Response(SCRIPT, { headers: { "content-type": "text/javascript; charset=utf-8" } }) : await stub.fetch(forwarded);
    return security(response);
  }
} satisfies ExportedHandler<Env>;

export class RelayDurableObject extends DurableObject<Env> {
  private pending = new Map<string, { socket: WebSocket; resolve: (f: RelayFrame) => void; timer: ReturnType<typeof setTimeout> }>();
  private controlTail: Promise<unknown> = Promise.resolve();

  private control(operation: () => Promise<Response>): Promise<Response> {
    const result = this.controlTail.then(operation);
    this.controlTail = result.catch(() => {});
    return result;
  }

  private disconnect(ws: WebSocket, code = 1000): void {
    for (const pending of this.pending.values()) if (pending.socket === ws) pending.resolve({ type: "response", id: "", status: 502, transportError: true });
    try { ws.close(code, "connection closed"); } catch {}
  }
  private limits = new Map<string, { count: number; until: number }>();

  private async limited(request: Request, category: string, max: number): Promise<boolean> {
    const now = Date.now();
    if(request.headers.has('x-relay-tenant')) {
      const key='quota:'+category;
      return this.ctx.storage.transaction(async tx=>{let value=await tx.get<{count:number;until:number}>(key);if(!value||value.until<=now)value={count:0,until:now+60000};value.count++;await tx.put(key,value);return value.count>max;});
    }
    for (const [k, v] of this.limits) if (v.until <= now) this.limits.delete(k);
    const key = `${category}:${client(request)}`;
    const value = this.limits.get(key) || { count: 0, until: now + 60_000 };
    value.count++;
    this.limits.set(key, value);
    return this.limits.size > 1024 || value.count > max;
  }

  private async owner(request: Request): Promise<boolean> {
    const hash = request.headers.get("x-relay-owner-hash") || "";
    const form = new URLSearchParams(new TextDecoder().decode(await boundedBody(request.clone(), 4096)));
    return matches(String(form.get("owner_key") || ""), hash);
  }

  async fetch(request: Request): Promise<Response> {
    const url = new URL(request.url);
    if (url.pathname === "/healthz") return request.method === "GET" ? json({ status: "ok" }) : failure(405, "method_not_allowed");
    if (url.pathname === "/" && request.method === "GET") return new Response(html(), { headers: { "content-type": "text/html; charset=utf-8" } });
    if (["/admin", "/pair", "/device", "/device/info"].includes(url.pathname)) {
      let body: ArrayBuffer;
      try { body = await boundedBody(request, url.pathname === "/admin" ? 4096 : 16384); }
      catch { return failure(413, "body_too_large"); }
      const prepared = new Request(request.url, { method: request.method, headers: request.headers, body: ["GET", "HEAD"].includes(request.method) ? undefined : body });
      return this.control(() => url.pathname === "/admin" ? this.admin(prepared) : url.pathname === "/pair" ? this.pair(prepared) : url.pathname === '/device/info' ? this.deviceInfo(prepared) : this.device(prepared));
    }
    if (url.pathname === "/mcp" || url.pathname === "/api/v1" || url.pathname.startsWith("/api/v1/")) return this.proxy(request);
    return failure(404, "not_found");
  }

  private async admin(request: Request): Promise<Response> {
    if (request.method !== "POST") return failure(405, "method_not_allowed");
    if (request.headers.get("origin") && request.headers.get("origin") !== ORIGIN) return new Response(html("請直接從中繼網站操作。", "", true), { status: 403, headers: { "content-type": "text/html; charset=utf-8" } });
    if (await this.limited(request, "owner", 8)) return new Response(html("嘗試次數過多，請一分鐘後重試。", "", true), { status: 429, headers: { "content-type": "text/html; charset=utf-8" } });
    if (!(await this.owner(request))) return new Response(html("管理金鑰不正確。", "", true), { status: 403, headers: { "content-type": "text/html; charset=utf-8" } });
    const form = new URLSearchParams(await request.text());
    const action = String(form.get("action") || "");
    const sockets = this.ctx.getWebSockets().filter(ws => ws.readyState === WebSocket.OPEN);
    if(action==='diagnostics')return json({paired:!!await this.ctx.storage.get('deviceHash'),sockets:this.ctx.getWebSockets().map(ws=>({state:ws.readyState,tags:this.ctx.getTags(ws)})),pending:this.pending.size});
    if (action === "status") {
      const deviceHash = await this.ctx.storage.get<string>("deviceHash");
      const message = !deviceHash ? "尚未配對手機。" : sockets.length ? "手機通道已連線。電腦仍需要有效的手機存取權杖。" : "手機已配對，但目前離線。請確認遠端存取及手機網路。";
      return new Response(html(message), { headers: { "content-type": "text/html; charset=utf-8" } });
    }
    if (action === "pair") {
      if (await this.ctx.storage.get("deviceHash")) return new Response(html("已有手機配對，請先解除原配對。", "", true), { status: 409, headers: { "content-type": "text/html; charset=utf-8" } });
      const tenant=request.headers.get('x-relay-tenant');
      const code = (tenant?tenant+'_':'')+randomSecret().slice(0, 16);
      await this.ctx.storage.put({ pairHash: await digest(code), pairUntil: Date.now() + 300_000 });
      return new Response(html("請在渥屋助理輸入此配對碼。", code), { headers: { "content-type": "text/html; charset=utf-8" } });
    }
    if (action === "revoke" && form.get("confirm") === "yes") {
      await this.ctx.storage.delete(["deviceHash", "pairHash", "pairUntil"]);
      for (const ws of sockets) this.disconnect(ws);
      return new Response(html("手機配對已解除，遠端轉發已關閉。"), { headers: { "content-type": "text/html; charset=utf-8" } });
    }
    return new Response(html("請確認解除配對。", "", true), { status: 400, headers: { "content-type": "text/html; charset=utf-8" } });
  }

  private async pair(request: Request): Promise<Response> {
    if (request.method !== "POST") return failure(405, "method_not_allowed");
    if (request.headers.get("origin") || await this.limited(request, "pair", 5)) return failure(403, "access_denied");
    const input: { code?: string } = await request.json<{ code?: string }>().catch(() => ({}));
    if (!input || typeof input.code !== "string") return failure(400, "invalid_request");
    const pairHash = await this.ctx.storage.get<string>("pairHash");
    const pairUntil = await this.ctx.storage.get<number>("pairUntil");
    if (!pairUntil || Date.now() >= pairUntil || !(await matches(input.code || "", pairHash))) return failure(403, "invalid_pairing_code");
    if (await this.ctx.storage.get("deviceHash")) return failure(409, "pairing_unavailable");
    const tenant=request.headers.get('x-relay-tenant');
    const deviceToken = tenant?tenant+'_'+randomSecret().slice(0,20):randomSecret();
    await this.ctx.storage.put("deviceHash", await digest(deviceToken));
    await this.ctx.storage.delete(["pairHash", "pairUntil"]);
    return json({ deviceToken, mcpUrl: `${ORIGIN}/mcp` });
  }

  private async deviceInfo(request: Request): Promise<Response> {
    if(request.method!=='GET')return failure(405,'method_not_allowed');
    if(request.headers.has('origin'))return failure(403,'access_denied');
    if(await this.limited(request,'device-info',60))return failure(429,'rate_limited');
    if(!(await matches(bearer(request),await this.ctx.storage.get<string>('deviceHash'))))return failure(401,'invalid_device_token');
    const tenant=request.headers.get('x-relay-tenant');
    const base=ORIGIN+(tenant?'/r/'+tenant:'');
    return json({schemaVersion:1,gatewayUrl:ORIGIN+'/',mcpUrl:base+'/mcp',apiBaseUrl:base+'/api/v1',relayProtocol:PROTOCOL});
  }

  private async device(request: Request): Promise<Response> {
    const hash = await this.ctx.storage.get<string>("deviceHash");
    if (request.headers.get("origin") || !(await matches(bearer(request), hash))) return failure(401, "invalid_device_token");
    if (request.method === "DELETE") {
      await this.ctx.storage.delete(["deviceHash", "pairHash", "pairUntil"]);
      for (const ws of this.ctx.getWebSockets()) this.disconnect(ws);
      return new Response(null, { status: 204 });
    }
    if (request.method !== "GET") return failure(405, "method_not_allowed");
    const protocols = (request.headers.get("sec-websocket-protocol") || "").split(",").map((s) => s.trim());
    if (request.headers.get("upgrade")?.toLowerCase() !== "websocket" || !protocols.includes(PROTOCOL)) return failure(426, "update_phone_and_gateway");
    const pair = new WebSocketPair();
    for (const old of this.ctx.getWebSockets()) this.disconnect(old, 1012);
    this.ctx.acceptWebSocket(pair[1], ["device"]);
    return new Response(null, { status: 101, webSocket: pair[0], headers: { "sec-websocket-protocol": PROTOCOL } });
  }

  async webSocketMessage(_ws: WebSocket, message: string | ArrayBuffer): Promise<void> {
    if (typeof message !== "string" || message.length > 2 * MAX_BODY) return _ws.close(1008, "invalid frame");
    let frame: RelayFrame;
    try { frame = JSON.parse(message) as RelayFrame; } catch { return _ws.close(1008, "invalid frame"); }
    if (!frame || frame.type !== "response" || typeof frame.id !== "string" || !Number.isInteger(frame.status) || !frame.status || frame.status < 200 || frame.status > 599 || !safeHeaders(frame.headers || {}) || (frame.body != null && typeof frame.body !== "string")) return this.disconnect(_ws, 1008);
    try { if (base64ToBody(frame.body).byteLength > MAX_BODY) return this.disconnect(_ws, 1008); } catch { return this.disconnect(_ws, 1008); }
    delete frame.transportError;
    const pending = this.pending.get(frame.id);
    if (pending?.socket === _ws) pending.resolve(frame);
  }

  async webSocketClose(_ws: WebSocket, code: number, reason: string): Promise<void> {
    this.disconnect(_ws, [1004, 1005, 1006, 1015].includes(code) ? 1000 : code);
  }

  async webSocketError(ws: WebSocket): Promise<void> { this.disconnect(ws, 1011); }

  private async proxy(request: Request): Promise<Response> {
    const url = new URL(request.url);
    const api = url.pathname !== "/mcp";
    if (await this.limited(request, "relay", 240)) return failure(429, "rate_limited", api);
    if (!new Set(["GET", "POST", "DELETE"]).has(request.method)) return failure(405, "method_not_allowed", api);
    if (url.search.length > 8193) return failure(414, "query_too_large", api);
    let bytes: ArrayBuffer;
    try { bytes = await boundedBody(request, MAX_BODY); } catch { return failure(413, "body_too_large", api); }
    const sockets = this.ctx.getWebSockets("device").filter(ws => ws.readyState === WebSocket.OPEN);
    if (sockets.length !== 1) return failure(503, "device_offline", api);
    if (this.pending.size >= 8) return failure(429, "device_busy", api);
    const headers: Record<string, string> = {};
    for (const [k, v] of request.headers) if (REQUEST_HEADERS.has(k.toLowerCase())) headers[k.toLowerCase()] = v;
    if (!safeHeaders(headers)) return failure(400, "invalid_headers", api);
    const id = randomSecret();
    const frame: RelayFrame = { type: "request", id, method: request.method, path: url.pathname, query: url.search.slice(1), headers, body: bodyToBase64(bytes), client: client(request) };
    const result = new Promise<RelayFrame>((resolve) => {
      const timer = setTimeout(() => resolve({ type: "response", id, status: 504, transportError: true }), 65_000);
      this.pending.set(id, { socket: sockets[0], resolve: (value) => { clearTimeout(timer); resolve(value); }, timer });
    });
    try { sockets[0].send(JSON.stringify(frame)); } catch { this.disconnect(sockets[0], 1011); }
    const reply = await result;
    this.pending.delete(id);
    if (reply.transportError) {
      try { sockets[0].send(JSON.stringify({ type: "cancel", id })); } catch {}
      return failure(reply.status || 502, "delivery_unknown", api);
    }
    const out = new Headers();
    for (const [k, v] of Object.entries(reply.headers || {})) if (RESPONSE_HEADERS.has(k.toLowerCase())) out.set(k, v);
    return new Response([204, 205, 304].includes(reply.status!) ? null : base64ToBody(reply.body).buffer as ArrayBuffer, { status: reply.status || 502, headers: out });
  }
}
