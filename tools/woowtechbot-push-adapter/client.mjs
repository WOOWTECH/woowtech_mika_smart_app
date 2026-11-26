import { PATHS, validate } from './contract.mjs';
export function createRelayClient({ origin, credential, fetchImpl = fetch }) {
  const url = new URL(origin);
  if (url.protocol !== 'https:' || url.username || url.password || url.search || url.hash || url.pathname !== '/') throw new TypeError('HTTPS origin required');
  if (typeof credential !== 'function') throw new TypeError('Credential provider required');
  return async (operation, body) => {
    if (!validate(operation, body)) throw new TypeError('invalid_request');
    try {
      const bearer = await credential();
      if (typeof bearer !== 'string' || !/^[A-Za-z0-9_.-]{20,512}$/.test(bearer)) return { status: 401, code: 'unauthorized' };
      const response = await fetchImpl(`${url.origin}${PATHS[operation]}`, {
        method: 'POST', headers: { authorization: `Bearer ${bearer}`, 'content-type': 'application/json' },
        body: JSON.stringify(body), redirect: 'error', signal: AbortSignal.timeout(10000),
      });
      const payload = await response.json().catch(() => null);
      const retry = Number(response.headers.get('retry-after'));
      return { status: response.status,
        ...(typeof payload?.error === 'string' && /^[a-z_]{1,64}$/.test(payload.error) ? { code: payload.error } : {}),
        ...(Number.isFinite(retry) && retry > 0 ? { retryAfterMs: Math.min(retry * 1000, 21600000) } : {}) };
    } catch { return { status: 503, code: 'upstream_unavailable' }; }
  };
}
