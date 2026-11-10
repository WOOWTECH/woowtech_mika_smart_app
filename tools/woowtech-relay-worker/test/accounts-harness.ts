import worker, { RelayDurableObject } from '../src/index';
import { AccountAuth as RealAccountAuth, hash, CLIENT } from '../src/auth';
export { RelayDurableObject };
// This entrypoint is used ONLY by wrangler.test.toml, never deployed.
export class AccountAuth extends RealAccountAuth {
 protected override async provider(path:string, form:Record<string,string>):Promise<any> {
  if(path==='/oauth2/token' && form.code==='transport-probe')return super.provider(path,form);
  if(path==='/oauth2/token') {
   const [subject,challenge]=form.code.split(':');
   if(!['101','202'].includes(subject)||challenge!==await hash(form.code_verifier))throw new Error('bad_pkce');
   return {access_token:'fake-'+subject};
  }
  if(path==='/oauth2/introspect')return {active:true,sub:form.token.slice(5),client_id:CLIENT,scope:'relay:identity',exp:Math.floor(Date.now()/1000)+3600};
  return {};
 }
}
export default worker;
