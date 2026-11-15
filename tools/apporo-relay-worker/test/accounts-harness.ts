import worker, { RelayDurableObject, ReportInbox } from '../src/index';
import { AccountAuth as RealAccountAuth, hash, CLIENT } from '../src/auth';
export { RelayDurableObject, ReportInbox };
// This entrypoint is used ONLY by wrangler.test.toml, never deployed.
// The fake provider answers only the literal relay-owned paths served by
// apporo_relay_oauth, so a wrong path in src/auth.ts fails the account test.
const TOKEN='/apporo-relay/oauth2/token',INTROSPECT='/apporo-relay/oauth2/introspect',REVOKE='/apporo-relay/oauth2/revoke';
export class AccountAuth extends RealAccountAuth {
 protected override async provider(path:string, form:Record<string,string>):Promise<any> {
  await this.ctx.storage.put('test-provider:'+path,true);
  if(path===TOKEN && form.code==='transport-probe')return super.provider(path,form);
  if(path===TOKEN) {
   const [subject,challenge]=form.code.split(':');
   if(!['101','202'].includes(subject)||challenge!==await hash(form.code_verifier))throw new Error('bad_pkce');
   return {access_token:'fake-'+subject};
  }
  if(path===INTROSPECT)return {active:true,sub:form.token.slice(5),client_id:CLIENT,scope:'relay:identity',exp:Math.floor(Date.now()/1000)+3600};
  if(path===REVOKE)return {};
  throw new Error('unexpected_provider_path');
 }
 override async fetch(request:Request):Promise<Response> {
  if(new URL(request.url).pathname==='/test/provider-paths')return Response.json([...(await this.ctx.storage.list({prefix:'test-provider:'})).keys()].map(k=>k.slice('test-provider:'.length)).sort());
  return super.fetch(request);
 }
}
export default {
 async fetch(request:Request, env:any, ctx:ExecutionContext):Promise<Response> {
  // Lets accounts.mjs check every identity-provider path the Worker called, including revoke on logout.
  if(new URL(request.url).pathname==='/__test/provider-paths')return env.AUTH.getByName('accounts-v1').fetch('https://internal/test/provider-paths');
  return worker.fetch(request, env, ctx);
 }
};
