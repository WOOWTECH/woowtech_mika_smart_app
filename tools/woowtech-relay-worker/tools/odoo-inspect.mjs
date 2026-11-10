import {mcpUrl} from './mcp-config.mjs';
import {Client} from '@modelcontextprotocol/sdk/client/index.js';
import {StreamableHTTPClientTransport} from '@modelcontextprotocol/sdk/client/streamableHttp.js';
const client=new Client({name:'assistant-relay-identity-inspection',version:'1.0.0'});
try {
 await client.connect(new StreamableHTTPClientTransport(mcpUrl()));
 const {tools}=await client.listTools();
 if(process.argv.includes('--register')) {
  const model='woow_paas_platform.oauth_client';
  const found=await client.callTool({name:'search_records',arguments:{model,domain:[['client_id','=','woowtech-assistant-relay']],fields:['id','client_id','scopes','redirect_uris','require_pkce','client_type','is_active'],limit:1,instance:'default'}});
  const data=found.structuredContent || JSON.parse(found.content.find(c=>c.type==='text').text);
  if(!data.success) throw new Error('Lookup failed');
  if(data.count) {console.log(JSON.stringify(data));}
  else {
   const result=await client.callTool({name:'execute_method',arguments:{model,method:'create',args:[{name:'渥屋助理中繼網站',client_id:'woowtech-assistant-relay',client_type:'public',require_pkce:true,redirect_uris:'https://assistant-relay.woowtech.io/auth/callback',redirect_uri_match_mode:'exact',scopes:'relay:identity',grant_types:'authorization_code',is_active:true}],instance:'default'}});
   console.log(JSON.stringify(result));
  }
  await client.close();process.exit(0);
 }
 console.log(JSON.stringify(tools.filter(t=>t.name==='execute_method').map(t=>t.inputSchema)));
 for(const [name,args] of [['get_model_fields',{model:'woow_paas_platform.oauth_client',field_names:['name','client_id','client_type','require_pkce','redirect_uris','redirect_uri_match_mode','client_category','scopes','grant_types','is_active'],instance:'default'}],['search_records',{model:'woow_paas_platform.oauth_client',domain:[['client_id','=','woowtech-assistant-relay']],fields:['id','name','client_id','scopes','redirect_uris'],limit:1,instance:'default'}]]) {
  const r=await client.callTool({name,arguments:args}); console.log(JSON.stringify(r));
 }
} catch(e){console.error('Odoo MCP inspection failed:',e.constructor.name);process.exitCode=1;}
finally {await client.close();}
