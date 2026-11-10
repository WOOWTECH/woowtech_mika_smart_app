import fs from 'node:fs';

// Provision privately; never commit MCP URLs containing credentials.
export function mcpUrl() {
 const value=process.env.WOOWTECH_ODOO_MCP_URL || (process.env.WOOWTECH_ODOO_MCP_URL_FILE ? fs.readFileSync(process.env.WOOWTECH_ODOO_MCP_URL_FILE,'utf8').trim() : '');
 if(!value)throw new Error('Set WOOWTECH_ODOO_MCP_URL_FILE to a private file containing the authorized prod Odoo MCP URL.');
 try {const url=new URL(value);if(url.protocol!=='https:')throw new Error();return url;}
 catch {throw new Error('Odoo MCP URL must be valid HTTPS (value withheld).');}
}
