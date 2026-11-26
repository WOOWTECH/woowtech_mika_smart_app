import { PATHS, validate, buildMessage, hash } from './contract.mjs';
import { classifyFirebaseError } from './errors.mjs';
const fail = (status, error) => ({ status, body: { error } });
/** verifyInstallation(bearer) -> trusted { installationId }; authorize(principal, context) -> boolean.
 * Both hooks are mandatory. The bearer is never a Firebase credential or an Android app secret.
 */
export function createAdapter({ verifyInstallation, authorize, state, sender }) {
  if (typeof verifyInstallation !== 'function' || typeof authorize !== 'function' || !state) throw new TypeError('Authentication, authorization and state are required');
  return async function handle({ method, path, headers = {}, body }) {
    if (method !== 'POST') return fail(405, 'method_not_allowed');
    const operation = Object.keys(PATHS).find(k => PATHS[k] === path);
    if (!operation) return fail(404, 'not_found');
    const auth = headers.authorization;
    if (typeof auth !== 'string' || !/^Bearer [A-Za-z0-9_.-]{20,512}$/.test(auth)) return fail(401, 'unauthorized');
    try {
      const principal = await verifyInstallation(auth.slice(7));
      if (!principal || typeof principal.installationId !== 'string' || !principal.installationId) return fail(401, 'unauthorized');
      if (!validate(operation, body)) return fail(400, 'invalid_request');
      // Own snapshot prevents an in-process caller changing fields while authorization awaits.
      body = structuredClone(body);
      const serviceId = operation === 'send' ? body.target.serviceId : body.serviceId;
      if (await authorize(principal, { operation, serviceId, ...(operation === 'send' ? { target: { ...body.target } } : {}) }) !== true) return fail(403, 'forbidden');
      const registrationKey = hash(principal.installationId, serviceId, body.token);
      if (operation === 'register') { await state.register(registrationKey); return { status: 200, body: { ok: true } }; }
      if (operation === 'unregister') { await state.unregister(registrationKey); return { status: 200, body: { ok: true } }; }
      if (!await state.has(registrationKey)) return fail(404, 'push_device_unknown');
      if (typeof sender !== 'function') return fail(503, 'push_unavailable');
      const eventKey = hash(registrationKey, body.target.botId, body.target.threadId, body.target.eventId);
      return await state.run(eventKey, async () => {
        // Recheck revocation after acquiring a distributed dedup claim.
        if (!await state.has(registrationKey)) return fail(404, 'push_device_unknown');
        try { await sender(buildMessage(body)); }
        catch (error) {
          const { action, ...answer } = classifyFirebaseError(error);
          if (action === 'revoke') await state.unregister(registrationKey);
          return answer;
        }
        return { status: 201, body: { ok: true } };
      });
    } catch { return fail(503, 'upstream_unavailable'); }
  };
}
// Fastify-compatible mounting without importing Fastify or Firebase. Use a dedicated server/profile.
export function mountRoutes(server, handle) {
  for (const path of Object.values(PATHS)) server.post(path, { bodyLimit: 4096 }, async (request, reply) => {
    const result = await handle({ method: 'POST', path, headers: request.headers, body: request.body });
    if (result.headers) reply.headers(result.headers);
    return reply.code(result.status).send(result.body);
  });
}
