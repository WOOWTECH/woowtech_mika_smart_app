import { DurableObject } from "cloudflare:workers";
import { AccountAuth, authCall, authRoute, currentAccount, SITE, redirect } from './auth';
import { accountPage, html, STYLE, SCRIPT } from './page';
import cliSource from '../downloads/apporo-relay-cli.py';
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

const ORIGIN = "https://assistant-relay.apporo.ai";
const PROTOCOL = "mika-relay.v2";
const MAX_BODY = 1 << 20;
const REQUEST_HEADERS = new Set(["authorization", "origin", "x-mika-client", "content-type", "accept", "mcp-protocol-version", "mcp-method", "mcp-name", "mcp-session-id", "last-event-id"]);
const RESPONSE_HEADERS = new Set(["content-type", "allow", "retry-after", "www-authenticate", "mcp-protocol-version"]);
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

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    if (url.host !== new URL(ORIGIN).host) return security(failure(400, "invalid_host"));
    if (!env.OWNER_KEY || env.OWNER_KEY.length < 32) return security(failure(503, "not_configured"));
    // HEAD too: link checkers probe the Play listing's privacy URL without downloading it.
    if (url.pathname === '/privacy/play' && (request.method === 'GET' || request.method === 'HEAD'))
      return security(new Response(request.method === 'HEAD' ? null : privacyPlayHtml, { headers: { 'content-type': 'text/html; charset=utf-8' } }));
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
    if(url.pathname==='/downloads/apporo-relay-cli.py'&&request.method==='GET')return security(new Response(cliSource,{headers:{'content-type':'text/x-python; charset=utf-8','content-disposition':'attachment; filename="apporo-relay-cli.py"'}}));
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
        if(action==='revoke'&&confirm!=='yes')return security(new Response(accountPage('Disconnecting will close remote access for this phone.', '', account.tenant, true),{headers:{'content-type':'text/html; charset=utf-8'}}));
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
    const response = url.pathname === "/style.css" ? new Response(STYLE, { headers: { "content-type": "text/css; charset=utf-8" } }) : url.pathname === "/app.js" ? new Response(SCRIPT, { headers: { "content-type": "text/javascript; charset=utf-8" } }) : await stub.fetch(forwarded);
    return security(response);
  }
} satisfies ExportedHandler<Env>;

export class RelayDurableObject extends DurableObject<Env> {
  private pending = new Map<string, { socket: WebSocket; resolve: (f: RelayFrame) => void; timer: ReturnType<typeof setTimeout> }>();
  private controlTail: Promise<unknown> = Promise.resolve();

  // getWebSockets() may still include an older connection after the phone reconnects.
  // Persist the current connection ID so hibernation and delayed close handshakes
  // cannot make a newly connected phone appear offline.
  private async activeDevice(): Promise<WebSocket | null> {
    const id = await this.ctx.storage.get<string>('activeDevice');
    if (!id) return null;
    const sockets = this.ctx.getWebSockets('device').filter(ws =>
      ws.readyState === WebSocket.OPEN && ws.deserializeAttachment() === id);
    return sockets.length === 1 ? sockets[0] : null;
  }

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
    if (request.headers.get("origin") && request.headers.get("origin") !== ORIGIN) return new Response(html("Open the relay website directly.", "", true), { status: 403, headers: { "content-type": "text/html; charset=utf-8" } });
    if (await this.limited(request, "owner", 8)) return new Response(html("Too many attempts. Try again in one minute.", "", true), { status: 429, headers: { "content-type": "text/html; charset=utf-8" } });
    if (!(await this.owner(request))) return new Response(html("Incorrect management key.", "", true), { status: 403, headers: { "content-type": "text/html; charset=utf-8" } });
    const form = new URLSearchParams(await request.text());
    const action = String(form.get("action") || "");
    const sockets = this.ctx.getWebSockets().filter(ws => ws.readyState === WebSocket.OPEN);
    if(action==='diagnostics')return json({paired:!!await this.ctx.storage.get('deviceHash'),sockets:this.ctx.getWebSockets().map(ws=>({state:ws.readyState,tags:this.ctx.getTags(ws)})),pending:this.pending.size});
    if (action === "status") {
      const deviceHash = await this.ctx.storage.get<string>("deviceHash");
      const message = !deviceHash ? "No phone is paired." : await this.activeDevice() ? "Phone connected. Your computer still needs the phone access token." : "Phone paired but offline. Check remote access and the phone network.";
      return new Response(html(message), { headers: { "content-type": "text/html; charset=utf-8" } });
    }
    if (action === "pair") {
      if (await this.ctx.storage.get("deviceHash")) return new Response(html("A phone is already paired. Disconnect it before pairing another.", "", true), { status: 409, headers: { "content-type": "text/html; charset=utf-8" } });
      const tenant=request.headers.get('x-relay-tenant');
      const code = (tenant?tenant+'_':'')+randomSecret().slice(0, 16);
      await this.ctx.storage.put({ pairHash: await digest(code), pairUntil: Date.now() + 300_000 });
      return new Response(html("Enter this pairing code in Apporo Assistant.", code), { headers: { "content-type": "text/html; charset=utf-8" } });
    }
    if (action === "revoke" && form.get("confirm") === "yes") {
      await this.ctx.storage.delete(["deviceHash", "pairHash", "pairUntil", "activeDevice"]);
      for (const ws of sockets) this.disconnect(ws);
      return new Response(html("Phone pairing revoked. Remote forwarding is off."), { headers: { "content-type": "text/html; charset=utf-8" } });
    }
    return new Response(html("Confirm the disconnection first.", "", true), { status: 400, headers: { "content-type": "text/html; charset=utf-8" } });
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
      await this.ctx.storage.delete(["deviceHash", "pairHash", "pairUntil", "activeDevice"]);
      for (const ws of this.ctx.getWebSockets()) this.disconnect(ws);
      return new Response(null, { status: 204 });
    }
    if (request.method !== "GET") return failure(405, "method_not_allowed");
    const protocols = (request.headers.get("sec-websocket-protocol") || "").split(",").map((s) => s.trim());
    if (request.headers.get("upgrade")?.toLowerCase() !== "websocket" || !protocols.includes(PROTOCOL)) return failure(426, "update_phone_and_gateway");
    const pair = new WebSocketPair();
    for (const old of this.ctx.getWebSockets()) this.disconnect(old, 1012);
    this.ctx.acceptWebSocket(pair[1], ["device"]);
    const id = randomSecret();
    pair[1].serializeAttachment(id);
    await this.ctx.storage.put('activeDevice', id);
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
    const socket = await this.activeDevice();
    if (!socket) return failure(503, "device_offline", api);
    if (this.pending.size >= 8) return failure(429, "device_busy", api);
    const headers: Record<string, string> = {};
    for (const [k, v] of request.headers) if (REQUEST_HEADERS.has(k.toLowerCase())) headers[k.toLowerCase()] = v;
    if (!safeHeaders(headers)) return failure(400, "invalid_headers", api);
    const id = randomSecret();
    const frame: RelayFrame = { type: "request", id, method: request.method, path: url.pathname, query: url.search.slice(1), headers, body: bodyToBase64(bytes), client: client(request) };
    const result = new Promise<RelayFrame>((resolve) => {
      const timer = setTimeout(() => resolve({ type: "response", id, status: 504, transportError: true }), 65_000);
      this.pending.set(id, { socket, resolve: (value) => { clearTimeout(timer); resolve(value); }, timer });
    });
    try { socket.send(JSON.stringify(frame)); } catch { this.disconnect(socket, 1011); }
    const reply = await result;
    this.pending.delete(id);
    if (reply.transportError) {
      try { socket.send(JSON.stringify({ type: "cancel", id })); } catch {}
      return failure(reply.status || 502, "delivery_unknown", api);
    }
    const out = new Headers();
    for (const [k, v] of Object.entries(reply.headers || {})) if (RESPONSE_HEADERS.has(k.toLowerCase())) out.set(k, v);
    return new Response([204, 205, 304].includes(reply.status!) ? null : base64ToBody(reply.body).buffer as ArrayBuffer, { status: reply.status || 502, headers: out });
  }
}
