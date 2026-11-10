// Explicit opt-in: creates a temporary portal-only user in prod, then archives it.
// No passwords, cookies, codes or tokens are printed or written to disk.
import fs from 'node:fs';
import crypto from 'node:crypto';
import assert from 'node:assert/strict';
import WebSocket from 'ws';
import {chromium} from 'playwright';
import {Client} from '@modelcontextprotocol/sdk/client/index.js';
import {StreamableHTTPClientTransport} from '@modelcontextprotocol/sdk/client/streamableHttp.js';
import {mcpUrl} from '../tools/mcp-config.mjs';
assert.ok(process.argv.includes('--prod'), 'Pass --prod for live acceptance');
const endpoint=mcpUrl();
const client=new Client({name:'relay-live-acceptance',version:'1'});
const site='https://assistant-relay.woowtech.io',identity='https://aiot.woowtech.io';
const login='relay-acceptance-'+crypto.randomUUID(),password=crypto.randomBytes(32).toString('base64url');
let userId,oauthClientId,stage='connect',paired=false,socket,browser;const jar=new Map();
async function mcp(name,args){const r=await client.callTool({name,arguments:{...args,instance:'default'}});const d=r.structuredContent||JSON.parse(r.content.find(c=>c.type==='text').text);if(r.isError||d.success===false)throw new Error('mcp_failure');return d;}
async function req(url,opts={}){const u=new URL(url);assert.ok([site,identity].includes(u.origin));const r=await fetch(u,{...opts,redirect:'manual',headers:{cookie:jar.get(u.origin)||'',...opts.headers},signal:AbortSignal.timeout(20000)});const cookies=new Map((jar.get(u.origin)||'').split('; ').filter(Boolean).map(s=>{const i=s.indexOf('=');return [s.slice(0,i),s.slice(i+1)];}));for(const c of r.headers.getSetCookie()){const s=c.split(';')[0],i=s.indexOf('=');cookies.set(s.slice(0,i),s.slice(i+1));}jar.set(u.origin,[...cookies].map(([k,v])=>k+'='+v).join('; '));return r;}
function fields(html){const p=new URLSearchParams();for(const tag of html.matchAll(/<input\b[^>]*>/g)){const attr={};for(const m of tag[0].matchAll(/([\w-]+)=["']([^"']*)["']/g))attr[m[1]]=m[2].replaceAll('&amp;','&').replaceAll('&#34;','"');if(attr.name&&attr.type==='hidden')p.set(attr.name,attr.value||'');}return p;}
async function post(url,body){return req(url,{method:'POST',headers:{'content-type':'application/x-www-form-urlencoded',origin:new URL(url).origin},body});}
async function follow(url){for(let i=0;i<8;i++){const r=await req(url);if(![301,302,303,307,308].includes(r.status))return r;url=new URL(r.headers.get('location'),url);}throw new Error('redirect_loop');}
try{
 await client.connect(new StreamableHTTPClientTransport(endpoint));
 const clients=await mcp('search_records',{model:'woow_paas_platform.oauth_client',domain:[['client_id','=','woowtech-assistant-relay']],fields:['id'],limit:2});assert.equal(clients.result.length,1);oauthClientId=clients.result[0].id;
 const groups=await mcp('search_records',{model:'ir.model.data',domain:[['module','=','base'],['name','=','group_portal']],fields:['res_id'],limit:1});assert.equal(groups.result.length,1);const portalGroupId=groups.result[0].res_id;
 stage='create test portal user';
 await mcp('execute_method',{model:'res.users',method:'create',args:[{name:'Relay acceptance temporary',login,password,email:false,groups_id:[[6,0,[portalGroupId]]]}],kwargs:{context:{no_reset_password:true,mail_create_nolog:true,mail_create_nosubscribe:true,tracking_disable:true}}});
 const found=await mcp('search_records',{model:'res.users',domain:[['login','=',login]],fields:['id','share','groups_id'],limit:1});userId=found.result[0].id;assert.equal(found.result[0].share,true);console.log('PASS: temporary portal-only user created',userId);
 stage='start';const start=await req(site+'/auth/start');assert.equal(start.status,303);const authorize=start.headers.get('location');
 stage='login page';const anon=await req(authorize);assert.equal(anon.status,303);const loginUrl=new URL(anon.headers.get('location'),identity);const page=await follow(loginUrl);const form=fields(await page.text());assert.ok(form.get('csrf_token'));form.set('login',login);form.set('password',password);form.set('redirect',new URL(authorize).pathname+new URL(authorize).search);
 stage='password login';const signed=await post(identity+'/web/login',form);assert.ok([302,303].includes(signed.status),'password login redirect');console.log('PASS: actual Odoo password login');
 stage='consent page';const consent=await follow(authorize);const html=await consent.text();assert.equal(consent.status,200);const approval=fields(html);assert.equal(approval.get('client_id'),'woowtech-assistant-relay');approval.set('approve','1');
 stage='consent';const approved=await post(identity+'/oauth2/authorize',approval);assert.ok([302,303].includes(approved.status));const callback=new URL(approved.headers.get('location'));assert.equal(callback.origin,site);assert.ok(callback.searchParams.get('code'));assert.ok(callback.searchParams.get('state'));console.log('PASS: actual consent returns code and state');
 stage='relay callback';const result=await req(callback);const body=await result.text();console.log('Callback result',{status:result.status,message:result.status===303?'redirect':body.slice(0,250)});assert.equal(result.status,303,'live callback must succeed');assert.equal(result.headers.get('location'),'/account');
 stage='account';const account=await req(site+'/account');assert.equal(account.status,200);assert.match(await account.text(),/我的手機/);console.log('PASS: live OAuth callback and personal account');
 stage='pairing';const pairPage=await post(site+'/account',new URLSearchParams({action:'pair'}));assert.equal(pairPage.status,200);const pairCode=(await pairPage.text()).match(/<output>([-_A-Za-z0-9]+)<\/output>/)?.[1];assert.ok(pairCode);assert.equal(pairCode.length,39);
 const pair=()=>req(site+'/pair',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({code:pairCode})});
 const pairResult=await pair();assert.equal(pairResult.status,200);const device=await pairResult.json();paired=true;assert.equal(device.deviceToken.length,43);assert.notEqual((await pair()).status,200);
 const phoneToken=crypto.randomBytes(32).toString('base64url'),tenant=pairCode.slice(0,22);
 stage='device discovery';const discovery=await req(site+'/device/info',{headers:{authorization:'Bearer '+device.deviceToken}});assert.equal(discovery.status,200);assert.deepEqual(await discovery.json(),{schemaVersion:1,gatewayUrl:site+'/',mcpUrl:site+'/r/'+tenant+'/mcp',apiBaseUrl:site+'/r/'+tenant+'/api/v1',relayProtocol:'mika-relay.v2'});console.log('PASS: authenticated live device discovery');
 stage='phone protocol connection';socket=new WebSocket(site.replace('https:','wss:')+'/device',['mika-relay.v2'],{headers:{authorization:'Bearer '+device.deviceToken},handshakeTimeout:15000});
 await new Promise((resolve,reject)=>{socket.once('open',resolve);socket.once('error',reject);});
 socket.on('message',raw=>{const f=JSON.parse(raw);if(f.type!=='request')return;socket.send(JSON.stringify({type:'response',id:f.id,status:f.headers.authorization==='Bearer '+phoneToken?200:401,body:Buffer.from('acceptance-ok').toString('base64')}));});
 stage='MCP forwarding';const forwarded=await req(site+'/r/'+tenant+'/mcp',{headers:{authorization:'Bearer '+phoneToken}});assert.equal(forwarded.status,200);assert.equal(await forwarded.text(),'acceptance-ok');assert.equal((await req(site+'/r/'+tenant+'/mcp',{headers:{authorization:'Bearer invalid'}})).status,401);
 stage='revoke confirmation';const confirm=await post(site+'/account',new URLSearchParams({action:'revoke'}));assert.match(await confirm.text(),/確認解除配對/);assert.equal((await req(site+'/r/'+tenant+'/mcp',{headers:{authorization:'Bearer '+phoneToken}})).status,200);
 stage='revoke device';assert.equal((await post(site+'/account',new URLSearchParams({action:'revoke',confirm:'yes'}))).status,200);paired=false;assert.equal((await req(site+'/device',{headers:{authorization:'Bearer '+device.deviceToken}})).status,401);
 assert.equal((await req(site+'/device/info',{headers:{authorization:'Bearer '+device.deviceToken}})).status,401);
 console.log('PASS: live single-use pairing, WSS v2 forwarding, phone token rejection, revoke confirmation and device revocation (synthetic phone)');
 stage='logout';assert.equal((await post(site+'/auth/logout',new URLSearchParams())).status,303);assert.equal((await req(site+'/account')).status,303);console.log('PASS: logout removes account access');
 if(process.argv.includes('--browser')) {
  stage='browser launch';browser=await chromium.launch({headless:true});const context=await browser.newContext({viewport:{width:360,height:800},isMobile:true,hasTouch:true});const page=await context.newPage();page.setDefaultTimeout(20000);
  stage='browser login';await page.goto(site);await page.getByRole('link',{name:'使用 WoowTech 帳號登入'}).click();await page.locator('input[name="login"]').fill(login);await page.locator('input[name="password"]').fill(password);await page.locator('form.oe_login_form button[type="submit"]').click();
  stage='browser deny';await page.locator('button[name="deny"]').click();await page.waitForURL(u=>u.origin===site);assert.match(await page.locator('code').innerText(),/access_denied/);
  stage='browser retry approve';await page.getByRole('link',{name:'重新登入',exact:true}).click();await page.locator('button[name="approve"]').click();await page.waitForURL(site+'/account');assert.ok(await page.getByRole('heading',{name:'我的手機'}).isVisible());assert.ok((await page.locator('body').innerText()).includes('/r/'+tenant+'/mcp'),'repeat login restores same tenant');
  const session=(await context.cookies(site)).find(c=>c.name==='__Host-relay_session');assert.ok(session?.httpOnly&&session?.secure&&session.sameSite==='Lax');
  stage='browser logout';await page.getByRole('button',{name:'登出網站'}).click();await page.waitForURL(site+'/');assert.ok(!(await context.cookies(site)).some(c=>c.name==='__Host-relay_session'));
  console.log('PASS: Chromium mobile login, denial, retry, consent, real Cookie binding, stable account and logout');
  const artifacts=fs.mkdtempSync('/tmp/relay-browser-');
  for(const width of [320,360,1280])for(const [label,path] of [['landing','/'],['error','/auth/callback']]){
   stage='browser layout '+label+' '+width;await page.setViewportSize({width,height:800});await page.goto(site+path);
   const layout=await page.evaluate(()=>({overflow:document.documentElement.scrollWidth>innerWidth,font:parseFloat(getComputedStyle(document.body).fontSize),background:getComputedStyle(document.body).backgroundColor,buttons:[...document.querySelectorAll('button,a.button')].map(b=>b.getBoundingClientRect().height)}));assert.equal(layout.overflow,false);assert.ok(layout.font>=16);assert.ok(layout.buttons.every(h=>h>=44));assert.equal(layout.background,'rgb(239, 241, 245)');
   await page.screenshot({path:artifacts+'/'+label+'-'+width+'.png',fullPage:true});
  }
  console.log('PASS: 320/360/1280px landing/error layouts, shared CSS, readable type and touch controls; screenshots:',artifacts);
 }
}catch(e){console.error('FAIL at',stage,e.name);if(browser){const p=browser.contexts()[0]?.pages()[0];if(p){const u=new URL(p.url());console.error('Browser diagnostic',{origin:u.origin,path:u.pathname,title:await p.title(),buttons:await p.locator('button').allTextContents(),errorCode:await p.locator('section[role="alert"] code').allTextContents()});}}process.exitCode=1;}
finally{
 await browser?.close();
 socket?.terminate();
 if(paired){try{const r=await post(site+'/account',new URLSearchParams({action:'revoke',confirm:'yes'}));assert.equal(r.status,200);console.log('CLEANUP: test phone revoked');}catch{console.error('CLEANUP FAILED: revoke test phone for test user',userId);process.exitCode=1;}}
 try{if(userId){const tokens=await mcp('search_records',{model:'woow_paas_platform.oauth_token',domain:[['client_id','=',oauthClientId],['user_id','=',userId]],fields:['id'],limit:100});if(tokens.result.length)await mcp('execute_method',{model:'woow_paas_platform.oauth_token',method:'write',args:[tokens.result.map(t=>t.id),{is_revoked:true}]});await mcp('execute_method',{model:'res.users',method:'write',args:[[userId],{active:false,password:crypto.randomBytes(32).toString('base64url')}]});console.log('CLEANUP: test tokens revoked and test user archived',userId);}}
 catch{console.error('CLEANUP FAILED: inspect temporary test user',userId);process.exitCode=1;}
 await client.close();
}
