import { DurableObject } from 'cloudflare:workers';

export const SITE = 'https://assistant-relay.woowtech.io';
export const IDENTITY = 'https://aiot.woowtech.io';
export const CLIENT = 'woowtech-assistant-relay';
export interface Account { tenant: string; subject: string; }
type Intent = { verifier: string; browserHash: string; expires: number };
type Session = { account: Account; token: string; expires: number };
interface IdentityResult { active: boolean; sub: string; client_id: string; scope: string; exp: number; }
export interface AuthEnv { AUTH: DurableObjectNamespace<AccountAuth>; }
export class AuthFailure extends Error { constructor(public code:string){super(code);} }
export function secret(size=32): string { return b64(crypto.getRandomValues(new Uint8Array(size))); }
function b64(bytes: Uint8Array): string {return btoa(String.fromCharCode(...bytes)).replaceAll('+','-').replaceAll('/','_').replaceAll('=','');}
export async function hash(s: string): Promise<string> {return b64(new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(s))));}
export function cookie(req: Request,name: string): string {return req.headers.get('cookie')?.split(';').map(v=>v.trim()).find(v=>v.startsWith(name+'='))?.slice(name.length+1)||'';}
export function setCookie(name:string,value:string,seconds:number): string {return `${name}=${value}; Path=/; HttpOnly; Secure; SameSite=Lax; Max-Age=${seconds}`;}
export function reply(value: unknown,status=200): Response {return Response.json(value,{status});}
export function redirect(url: string,cookies: string[]=[]): Response {const h=new Headers({location:url});for(const c of cookies)h.append('set-cookie',c);return new Response(null,{status:303,headers:h});}

// Only Worker-internal requests reach this class. Tokens never enter browser responses.
export class AccountAuth extends DurableObject {
 protected async provider(path:string,form:Record<string,string>):Promise<any> {
  const stage=path==='/oauth2/token'?'token':'identity';
  let r:Response;
  // Workers does not implement redirect:"error". Manual mode rejects 3xx below
  // without forwarding credentials to a redirected destination.
  try {r=await fetch(IDENTITY+path,{method:'POST',redirect:'manual',headers:{'content-type':'application/x-www-form-urlencoded'},body:new URLSearchParams(form),signal:AbortSignal.timeout(15000)});}
  catch(e){throw new AuthFailure(stage+(e instanceof TypeError?'_fetch_typeerror':'_network_error'));}
  if(!r.ok)throw new AuthFailure(stage+'_http_'+r.status);
  try{return await r.json();}catch{throw new AuthFailure(stage+'_invalid_json');}
 }
 private async identity(token:string):Promise<IdentityResult> {
  const data=await this.provider('/oauth2/introspect',{client_id:CLIENT,token}) as IdentityResult;
  if(data.active!==true || data.client_id!==CLIENT || typeof data.sub!=='string' || !/^\d+$/.test(data.sub) || !data.scope?.split(' ').includes('relay:identity') || !(data.exp>Date.now()/1000))throw new AuthFailure('identity_rejected');
  return data;
 }
 private async cleanupLater() {if(!await this.ctx.storage.getAlarm())await this.ctx.storage.setAlarm(Date.now()+600000);}
 async alarm() {
  for(const prefix of ['intent:','session:','limit:']) {
   const entries=await this.ctx.storage.list<{expires:number}>({prefix});
   for(const [key,value] of entries)if(value.expires<=Date.now())await this.ctx.storage.delete(key);
  }
  await this.ctx.storage.setAlarm(Date.now()+600000);
 }
 private async limit(ip:string):Promise<boolean> {
  const key='limit:'+await hash(ip); const now=Date.now();
  return this.ctx.storage.transaction(async tx=>{let v=await tx.get<{count:number;expires:number}>(key);if(!v||v.expires<now)v={count:0,expires:now+60000};v.count++;await tx.put(key,v);return v.count<=10;});
 }
 async fetch(request: Request):Promise<Response> {
  const path=new URL(request.url).pathname;
  const data=await request.json<any>();
  try {
   if(path==='/start') {
    if(!await this.limit(data.ip||''))return reply({error:'rate_limited'},429);
    const state=secret(),browser=secret(),verifier=secret();
    await this.ctx.storage.put('intent:'+await hash(state),{verifier,browserHash:await hash(browser),expires:Date.now()+600000} satisfies Intent);
    await this.cleanupLater();
    const params=new URLSearchParams({response_type:'code',client_id:CLIENT,redirect_uri:SITE+'/auth/callback',scope:'relay:identity',state,code_challenge:await hash(verifier),code_challenge_method:'S256'});
    return reply({url:IDENTITY+'/oauth2/authorize?'+params,browser});
   }
   if(path==='/callback') {
    if(typeof data.state!=='string'||typeof data.browser!=='string'||typeof data.code!=='string'||data.code.length>2048)return reply({error:'invalid_login'},400);
    if(!data.browser)return reply({error:'missing_browser'},400);
    const key='intent:'+await hash(data.state),browserHash=await hash(data.browser);
    const intent=await this.ctx.storage.transaction(async tx=>{
     const v=await tx.get<Intent>(key);if(!v||v.expires<=Date.now()||v.browserHash!==browserHash)return null;
     await tx.delete(key);return v;
    });
    if(!intent)return reply({error:'expired_login'},400);
    const tokens=await this.provider('/oauth2/token',{grant_type:'authorization_code',client_id:CLIENT,code:data.code,code_verifier:intent.verifier,redirect_uri:SITE+'/auth/callback'});
    if(typeof tokens.access_token!=='string')throw new AuthFailure('invalid_token');
    const identity=await this.identity(tokens.access_token);
    const accountKey='account:'+identity.sub;
    const account=await this.ctx.storage.transaction(async tx=>{
     let a=await tx.get<Account>(accountKey);
     if(!a){a={subject:identity.sub,tenant:secret(16)};await tx.put(accountKey,a);await tx.put('tenant:'+a.tenant,true);}
     return a;
    });
    const session=secret(); const expires=Math.min(identity.exp*1000,Date.now()+3600000);
    await this.ctx.storage.put('session:'+await hash(session),{account,token:tokens.access_token,expires} satisfies Session);
    await this.cleanupLater();
    return reply({session,seconds:Math.max(1,Math.floor((expires-Date.now())/1000))});
   }
   if(path==='/exists')return reply({exists:typeof data.tenant==='string' && !!await this.ctx.storage.get('tenant:'+data.tenant)});
   if(path==='/session'||path==='/logout') {
    if(typeof data.session!=='string'||!/^[-_A-Za-z0-9]{43}$/.test(data.session))return reply({error:'login_required'},401);
    const key='session:'+await hash(data.session),session=await this.ctx.storage.get<Session>(key);
    if(path==='/logout') {
     await this.ctx.storage.delete(key);
     if(session) {try{await this.provider('/oauth2/revoke',{client_id:CLIENT,token:session.token});}catch{}}
     return reply({ok:true});
    }
    if(!session||session.expires<=Date.now()) {await this.ctx.storage.delete(key);return reply({error:'login_required'},401);}
    try {
     const identity=await this.identity(session.token);
     if(identity.sub!==session.account.subject)throw new Error('identity_changed');
    }catch{return reply({error:'login_required'},401);}
    if(!await this.ctx.storage.get(key))return reply({error:'login_required'},401);
    return reply({account:session.account});
   }
   return reply({error:'not_found'},404);
  }catch(e){return reply({error:e instanceof AuthFailure?e.code:'identity_unavailable'},502);}
 }
}

export async function authCall(env:AuthEnv,path:string,data:unknown):Promise<Response> {
 return env.AUTH.getByName('accounts-v1').fetch('https://internal'+path,{method:'POST',body:JSON.stringify(data)});
}
export async function currentAccount(request:Request,env:AuthEnv):Promise<Account|null> {
 const r=await authCall(env,'/session',{session:cookie(request,'__Host-relay_session')});
 if(!r.ok)return null;
 return (await r.json<{account:Account}>()).account;
}
function loginFailure(rawCode:string,status:number):Response {
 const code=/^[a-z0-9_]{1,64}$/.test(rawCode)?rawCode:'identity_unavailable';
 const explanations:Record<string,string>={
  missing_browser:'瀏覽器沒有帶回登入識別。請在同一個瀏覽器分頁重新登入，並允許本站使用 Cookie。',
  expired_login:'這次登入已過期、已使用，或已被另一次登入取代。請重新開始登入，不要重新整理舊的授權回傳頁。',
  invalid_login:'登入回傳資料不完整。請從本站重新開始登入。',
  access_denied:'你尚未同意 WoowTech 登入授權，因此本站沒有建立登入狀態。',
  rate_limited:'登入嘗試太頻繁。請稍候一分鐘，再重新登入。',
  identity_rejected:'WoowTech 未確認這次登入身分，本站沒有建立登入狀態。請重新登入；若持續發生，請提供下方錯誤代碼。',
 };
 const message=explanations[code]||'中繼站未能完成與 WoowTech 的登入驗證。這不一定是密碼錯誤或操作逾時；請稍後重試，若持續發生，請提供下方錯誤代碼。';
 return new Response(`<!doctype html><html lang="zh-Hant"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="theme-color" content="#6183FC"><title>登入未完成 · 渥屋助理</title><link rel="stylesheet" href="/style.css"></head><body><header><div>渥屋助理遠端中繼</div></header><main><section class="card" role="alert"><h1>登入未完成</h1><p>${message}</p><p>錯誤代碼</p><code>${code}</code><div class="actions"><a class="button" href="/auth/start">重新登入</a><a class="button" href="/">回首頁</a></div><p>不需要提供密碼、配對碼或網址中的授權參數。</p></section></main></body></html>`,{status,headers:{'content-type':'text/html; charset=utf-8'}});
}
export async function authRoute(request:Request,env:AuthEnv):Promise<Response> {
 const url=new URL(request.url);
 if(url.pathname==='/auth/start'&&request.method==='GET') {
  const r=await authCall(env,'/start',{ip:request.headers.get('cf-connecting-ip')||''});if(!r.ok)return loginFailure((await r.json<{error:string}>()).error,r.status);
  const d=await r.json<{url:string;browser:string}>();return redirect(d.url,[setCookie('__Host-relay_login',d.browser,600)]);
 }
 if(url.pathname==='/auth/callback'&&request.method==='GET') {
  if(url.searchParams.has('error'))return loginFailure(url.searchParams.get('error')==='access_denied'?'access_denied':'invalid_login',400);
  const r=await authCall(env,'/callback',{state:url.searchParams.get('state'),code:url.searchParams.get('code'),browser:cookie(request,'__Host-relay_login')});
  if(!r.ok)return loginFailure((await r.json<{error:string}>()).error,r.status);
  const d=await r.json<{session:string;seconds:number}>();
  return redirect('/account',[setCookie('__Host-relay_session',d.session,d.seconds),setCookie('__Host-relay_login','',0)]);
 }
 if(url.pathname==='/auth/logout'&&request.method==='POST'&&request.headers.get('origin')===SITE) {
  await authCall(env,'/logout',{session:cookie(request,'__Host-relay_session')});
  return redirect('/',[setCookie('__Host-relay_session','',0)]);
 }
 return reply({error:'invalid_request'},400);
}
