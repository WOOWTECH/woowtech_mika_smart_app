import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {mkdtempSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import WebSocket from 'ws';
const dir=mkdtempSync(tmpdir()+'/relay-accounts-');
const child=spawn('node',['node_modules/wrangler/bin/wrangler.js','dev','--config','wrangler.test.toml','--ip','127.0.0.1','--port','18792','--persist-to',dir,'--var','OWNER_KEY:test-key-with-at-least-thirty-two-characters'],{stdio:['ignore','pipe','pipe']});
let logs='';child.stdout.on('data',b=>logs+=b);child.stderr.on('data',b=>logs+=b);
const site='https://assistant-relay.apporo.ai',base='http://127.0.0.1:18792';
const sockets=[];
async function call(path,options={}) {return fetch(base+path,{...options,redirect:'manual',headers:{host:'assistant-relay.apporo.ai',...options.headers},signal:AbortSignal.timeout(12000)});}
function cookie(r,name) {return r.headers.getSetCookie().find(c=>c.startsWith(name+'='))?.split(';')[0];}
async function login(subject) {
 const start=await call('/auth/start');assert.equal(start.status,303);
 const url=new URL(start.headers.get('location'));assert.equal(url.origin,'https://www.apporo.ai');
 const path='/auth/callback?'+new URLSearchParams({state:url.searchParams.get('state'),code:subject+':'+url.searchParams.get('code_challenge')});
 assert.equal((await call(path)).status,400,'requires initiating browser');
 const r=await call(path,{headers:{cookie:cookie(start,'__Host-relay_login')}});assert.equal(r.status,303);
 assert.equal((await call(path,{headers:{cookie:cookie(start,'__Host-relay_login')}})).status,400,'code/state is one use');
 const session=cookie(r,'__Host-relay_session');assert.ok(session);
 assert.match(r.headers.get('set-cookie'),/HttpOnly/);
 return session;
}
async function account(session,action,extra={}) {return call('/account',{method:'POST',headers:{cookie:session,origin:site,'content-type':'application/x-www-form-urlencoded'},body:new URLSearchParams({action,...extra})});}
async function pair(session) {
 const response=await account(session,'pair');assert.equal(response.status,200);
 const page=await response.text(),code=page.match(/<output>([-_A-Za-z0-9]+)<\/output>/)[1];assert.equal(code.length,39);
 const r=await call('/pair',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({code})});assert.equal(r.status,200);
 const data=await r.json();assert.equal(data.deviceToken.length,43);assert.equal(data.mcpUrl,site+'/mcp');
 return {tenant:code.slice(0,22),token:data.deviceToken};
}
async function connect(device,phoneToken) {
 const ws=new WebSocket(base.replace('http','ws')+'/device',['mika-relay.v2'],{headers:{host:'assistant-relay.apporo.ai',authorization:'Bearer '+device.token}});sockets.push(ws);
 await new Promise((resolve,reject)=>{ws.once('open',resolve);ws.once('error',reject);});
 ws.on('message',raw=>{const f=JSON.parse(raw);if(f.type!=='request')return;ws.send(JSON.stringify({type:'response',id:f.id,status:f.headers.authorization==='Bearer '+phoneToken?200:401,body:Buffer.from(device.tenant).toString('base64')}));});return ws;
}
try {
 let ready=false;for(let i=0;i<120;i++){try{if((await call('/healthz')).ok){ready=true;break;}}catch{}await new Promise(r=>setTimeout(r,100));}assert.ok(ready,logs);
 assert.equal((await call('/account')).status,303);
 for(const [path,code] of [['/auth/callback','invalid_login'],['/auth/callback?error=access_denied','access_denied'],['/auth/callback?error=%3Cscript%3E','invalid_login'],['/auth/callback?state=x&code=y','missing_browser']]) {
  const r=await call(path);assert.equal(r.status,400);assert.match(r.headers.get('content-type'),/text\/html/);const page=await r.text();assert.ok(page.includes('<code>'+code+'</code>'));assert.match(page,/name="viewport"/);assert.match(page,/Sign in again/);assert.ok(!page.includes('<script>'));
 }
 if(process.argv.includes('--provider')) {
  // Exercise the real provider implementation inside workerd, not the OAuth mock.
  // Invalid synthetic code must reach Odoo and be rejected with HTTP 400.
  const start=await call('/auth/start'),url=new URL(start.headers.get('location'));
  const r=await call('/auth/callback?'+new URLSearchParams({state:url.searchParams.get('state'),code:'transport-probe'}),{headers:{cookie:cookie(start,'__Host-relay_login')}});
  assert.equal(r.status,502);assert.match(await r.text(),/token_http_400/,'provider request must reach Odoo without runtime TypeError');
  console.log('PASS: real workerd provider transport reaches Odoo');
 }
 const a=await login('101'),b=await login('202');
 assert.equal((await call('/account',{method:'POST',headers:{cookie:a,origin:'https://evil.example'},body:'action=pair'})).status,403);
 const da=await pair(a),db=await pair(b);assert.notEqual(da.tenant,db.tenant);
 const info=(token,extra={})=>call('/device/info',{headers:{authorization:'Bearer '+token,...extra}});
 assert.equal((await call('/device/info')).status,401);
 assert.equal((await info(da.token.slice(0,-1)+(da.token.endsWith('A')?'B':'A'))).status,401);
 assert.equal((await info(da.token,{origin:site})).status,403);
 assert.equal((await call('/device/info',{method:'POST',headers:{authorization:'Bearer '+da.token}})).status,405);
 for(const d of [da,db]) {
  const r=await info(d.token,{'x-relay-tenant':d===da?db.tenant:da.tenant});assert.equal(r.status,200);assert.equal(r.headers.get('cache-control'),'no-store');
  assert.deepEqual(await r.json(),{schemaVersion:1,gatewayUrl:site+'/',mcpUrl:site+'/r/'+d.tenant+'/mcp',apiBaseUrl:site+'/r/'+d.tenant+'/api/v1',relayProtocol:'mika-relay.v2'});
 }
 const diagnosticPath='/r/'+da.tenant+'/admin';
 const diagnostic=key=>call(diagnosticPath,{method:'POST',body:new URLSearchParams({owner_key:key,action:'diagnostics'})});
 assert.equal((await diagnostic('wrong')).status,403,'diagnostics requires owner secret, not browser session');
 const state=await diagnostic('test-key-with-at-least-thirty-two-characters');assert.equal(state.status,200);assert.deepEqual(await state.json(),{paired:true,sockets:[],pending:0});
 await connect(da,'phone-a');await connect(db,'phone-b');
 for(const [device,token] of [[da,'phone-a'],[db,'phone-b']]) {
  const r=await call('/r/'+device.tenant+'/mcp',{headers:{authorization:'Bearer '+token}});assert.equal(r.status,200);assert.equal(await r.text(),device.tenant);
 }
 assert.equal((await call('/r/'+db.tenant+'/mcp',{headers:{authorization:'Bearer phone-a'}})).status,401);
 // Injecting another tenant into the form cannot change the session's ownership.
 assert.equal((await account(a,'revoke',{tenant:db.tenant,confirm:'yes'})).status,200);
 assert.equal((await call('/device',{headers:{authorization:'Bearer '+da.token}})).status,401);
 assert.equal((await info(da.token)).status,401);
 assert.equal((await info(db.token)).status,200);
 assert.equal((await call('/r/'+db.tenant+'/mcp',{headers:{authorization:'Bearer phone-b'}})).status,200);
 // Account A's management quota is independent of B.
 let limited=false;for(let i=0;i<9;i++){if((await account(a,'status')).status===429){limited=true;break;}}assert.ok(limited);
 assert.equal((await account(b,'status')).status,200);
 await call('/auth/logout',{method:'POST',headers:{cookie:b,origin:site}});
 assert.equal((await call('/account',{headers:{cookie:b}})).status,303);
 // Forged trusted-routing headers cannot select an account on the root relay.
 assert.equal((await call('/mcp',{headers:{'x-relay-tenant':db.tenant,authorization:'Bearer phone-b'}})).status,503);
 console.log('PASS: two-account PKCE login, browser/state binding, callback replay, 43-char Android credential contract, isolated pairing/forwarding/revoke/quotas, CSRF rejection, logout invalidation, header forgery rejection');
}finally{for(const s of sockets)s.terminate();child.kill('SIGTERM');await Promise.race([new Promise(r=>child.once('exit',r)),new Promise(r=>setTimeout(r,3000))]);rmSync(dir,{recursive:true,force:true});}
