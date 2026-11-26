import { createHash } from 'node:crypto';
export const PATHS = Object.freeze(Object.fromEntries(['register', 'unregister', 'send'].map(x => [x, `/v1/installations/self/push/${x}`])));
export const CHANNELS = Object.freeze({ finished: 'woowtechbot_results', permission: 'woowtechbot_attention', attention: 'woowtechbot_attention' });
export const ID = /^[A-Za-z0-9][A-Za-z0-9_.:-]{0,127}$/;
const tokenOK = x => typeof x === 'string' && x.length >= 20 && x.length <= 512 && /^[A-Za-z0-9_:-]+$/.test(x) && x.includes(':');
const idOK = x => typeof x === 'string' && ID.test(x);
const exact = (x, keys) => x !== null && typeof x === 'object' && !Array.isArray(x) && Object.keys(x).length === keys.length && keys.every(k => Object.hasOwn(x, k));
export function validate(operation, b) {
  if (operation === 'send') return exact(b, ['v', 'token', 'locale', 'reason', 'target']) && b.v === 1 && tokenOK(b.token) && ['en', 'zh-TW'].includes(b.locale) && Object.hasOwn(CHANNELS, b.reason) && exact(b.target, ['serviceId', 'botId', 'threadId', 'eventId']) && Object.values(b.target).every(idOK);
  return ['register', 'unregister'].includes(operation) && exact(b, ['v', 'platform', 'token', 'serviceId']) && b.v === 1 && b.platform === 'fcm' && tokenOK(b.token) && idOK(b.serviceId);
}
export const hash = (...values) => createHash('sha256').update(JSON.stringify(values)).digest('hex');
export function buildMessage(body) {
  if (!validate('send', body)) throw new TypeError('invalid_request');
  const { token, reason, target } = body;
  // Data-only: Android must validate/deduplicate/check account binding before any display.
  // Never add root or Android notification fields: background OS rendering bypasses that gate.
  return { token, data: { v: '1', ...target, reason },
    android: { priority: 'high', ttl: 600000 } };
}
// Call only after the bot's existing audience, live-stream, feature and kind checks.
export function fromBotFrame({ notification, seq }, { token, serviceId, locale, eventId }) {
  const reason = { done: 'finished', approval: 'permission', question: 'attention', 'sign-in': 'attention' }[notification?.kind];
  // eventId must be stable across retries and unique across server restarts; seq alone is insufficient.
  const body = { v: 1, token, locale, reason, target: { serviceId, botId: notification?.botId, threadId: notification?.threadId, eventId } };
  if (!Number.isSafeInteger(seq) || seq < 0 || !validate('send', body)) throw new TypeError('invalid_request');
  return body;
}
