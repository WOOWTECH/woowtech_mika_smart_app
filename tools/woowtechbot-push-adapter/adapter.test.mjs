import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createAdapter, mountRoutes } from './adapter.mjs';
import { createMemoryState } from './memory-state.mjs';
import { PATHS, buildMessage, validate, fromBotFrame } from './contract.mjs';
import { classifyFirebaseError } from './errors.mjs';
import { createRelayClient } from './client.mjs';
const fixture = JSON.parse(readFileSync(new URL('./fixture.json', import.meta.url)));
const bearer = 'test_installation_credential_only';
const registration = { v: 1, platform: 'fcm', token: fixture.token, serviceId: fixture.target.serviceId };
function setup(overrides = {}) {
  const sent = [];
  const handle = createAdapter({ verifyInstallation: async token => token === bearer ? { installationId: 'installation_a' } : null,
    authorize: async (_, context) => context.serviceId === 'service_demo', state: createMemoryState(), sender: async m => { sent.push(m); }, ...overrides });
  const call = (operation, body = operation === 'send' ? fixture : registration, headers = { authorization: `Bearer ${bearer}` }) => handle({ method: 'POST', path: PATHS[operation], body, headers });
  return { sent, call, handle };
}
test('register/send/unregister and exact data-only Android contract', async () => {
  const { call, sent } = setup();
  assert.equal((await call('send')).status, 404);
  assert.equal((await call('register')).status, 200);
  assert.equal((await call('send')).status, 201);
  assert.deepEqual(sent[0].data, { v: '1', ...fixture.target, reason: 'finished' });
  assert.deepEqual(sent[0], { token: fixture.token, data: { v: '1', ...fixture.target, reason: 'finished' }, android: { priority: 'high', ttl: 600000 } });
  assert.equal((await call('unregister')).status, 200);
  assert.equal((await call('send')).status, 404);
});
test('closed schema rejects content, unknown nested fields, types and unsafe IDs', () => {
  for (const b of [{ ...fixture, title: 'secret' }, { ...fixture, notification: {} }, { ...fixture, v: '1' }, { ...fixture, locale: 'ja' }, { ...fixture, reason: '__proto__' }, { ...fixture, target: { ...fixture.target, url: 'https://evil.test' } }, { ...fixture, target: { ...fixture.target, threadId: 'private content' } }, { ...fixture, token: 'short' }, null]) assert.equal(validate('send', b), false);
  assert.equal(validate('register', { ...registration, platform: 'apns' }), false);
});
test('auth fails closed and isolates installations and services', async () => {
  const { call, sent } = setup();
  assert.equal((await call('register', registration, {})).status, 401);
  assert.equal((await call('register', registration, { authorization: 'Bearer wrong_credential_0000000' })).status, 401);
  assert.equal((await call('register', { ...registration, serviceId: 'other' })).status, 403);
  const state = createMemoryState();
  const a = setup({ state });
  const b = setup({ state, verifyInstallation: async () => ({ installationId: 'installation_b' }) });
  await a.call('register');
  assert.equal((await b.call('send')).status, 404);
  assert.deepEqual(sent, []);
});
test('target authorization denies registered sender before delivery', async () => {
  const { call, sent } = setup({ authorize: async (_, ctx) => ctx.operation !== 'send' });
  await call('register');
  assert.equal((await call('send')).status, 403);
  assert.equal(sent.length, 0);
});
test('concurrent dedup, TTL expiry, event identity and retry after failure', async () => {
  let now = 0, attempts = 0;
  const state = createMemoryState({ now: () => now, ttlMs: 100 });
  const { call } = setup({ state, sender: async () => { attempts++; await Promise.resolve(); } });
  await call('register');
  const answers = await Promise.all(Array.from({ length: 20 }, () => call('send')));
  assert.equal(attempts, 1);
  assert.equal(answers.filter(x => x.body.duplicate).length, 19);
  now = 101;
  await call('send');
  assert.equal(attempts, 2);
  await call('send', { ...fixture, target: { ...fixture.target, eventId: 'event_2' } });
  assert.equal(attempts, 3);
  let fail = true;
  const retry = setup({ sender: async () => { if (fail) throw new Error('private token'); } });
  await retry.call('register');
  assert.equal((await retry.call('send')).status, 503);
  fail = false;
  assert.equal((await retry.call('send')).status, 201);
});
test('Firebase classifications never expose provider messages', async () => {
  for (const [code, status, action] of [['registration-token-not-registered', 410, 'revoke'], ['invalid-registration-token', 410, 'revoke'], ['invalid-argument', 502, 'pause'], ['mismatched-credential', 502, 'pause'], ['third-party-auth-error', 502, 'pause'], ['message-rate-exceeded', 429, 'retry'], ['internal-error', 503, 'retry']]) {
    const error = { code: `messaging/${code}`, message: 'PRIVATE_TOKEN' };
    const answer = classifyFirebaseError(error);
    assert.equal(answer.status, status); assert.equal(answer.action, action);
    assert.ok(!JSON.stringify(answer).includes('PRIVATE_TOKEN'));
    const { call } = setup({ sender: async () => { throw error; } });
    await call('register');
    assert.equal((await call('send')).status, status);
    if (action === 'revoke') assert.equal((await call('send')).status, 404);
  }
});
test('missing sender and failing authentication/store do not deliver', async () => {
  const off = setup({ sender: undefined }); await off.call('register');
  assert.deepEqual(await off.call('send'), { status: 503, body: { error: 'push_unavailable' } });
  const failed = setup({ verifyInstallation: async () => { throw new Error('secret'); } });
  assert.deepEqual(await failed.call('register'), { status: 503, body: { error: 'upstream_unavailable' } });
});
test('all bot kinds project IDs only and require a stable event ID', () => {
  for (const [kind, reason] of Object.entries({ done: 'finished', approval: 'permission', question: 'attention', 'sign-in': 'attention' })) {
    const frame = { seq: 1, notification: { kind, botId: 'bot_demo', threadId: 'thread_demo', body: 'SECRET', botName: 'SECRET' } };
    const args = { token: fixture.token, serviceId: 'service_demo', locale: 'en', eventId: 'epoch_1' };
    const body = fromBotFrame(frame, args);
    assert.equal(body.reason, reason);
    assert.ok(!JSON.stringify(buildMessage(body)).includes('SECRET'));
    assert.throws(() => fromBotFrame(frame, { ...args, eventId: undefined }));
  }
});
test('client uses exact route, header-only credential, timeout and refuses redirects', async () => {
  let request;
  const client = createRelayClient({ origin: 'https://relay.example', credential: () => bearer, fetchImpl: async (url, options) => { request = { url, ...options }; return new Response('{"error":"rate_limited"}', { status: 429, headers: { 'retry-after': '60' } }); } });
  assert.deepEqual(await client('send', fixture), { status: 429, code: 'rate_limited', retryAfterMs: 60000 });
  assert.equal(request.url, `https://relay.example${PATHS.send}`);
  assert.equal(request.redirect, 'error'); assert.ok(request.signal instanceof AbortSignal);
  assert.ok(!request.body.includes(bearer));
  assert.throws(() => createRelayClient({ origin: 'http://relay.example', credential: () => bearer }));
});
test('route mount and client integrate through injected transport without network', async () => {
  const { handle } = setup(); const routes = new Map();
  mountRoutes({ post: (path, options, fn) => { assert.equal(options.bodyLimit, 4096); routes.set(path, fn); } }, handle);
  const client = createRelayClient({ origin: 'https://relay.example', credential: () => bearer, fetchImpl: async (url, options) => {
    let status, headers = {};
    const reply = { headers: x => { headers = x; }, code: x => { status = x; return reply; }, send: x => new Response(JSON.stringify(x), { status, headers }) };
    return routes.get(new URL(url).pathname)({ headers: options.headers, body: JSON.parse(options.body) }, reply);
  } });
  assert.equal((await client('register', registration)).status, 200);
  assert.equal((await client('send', fixture)).status, 201);
  assert.equal((await client('unregister', registration)).status, 200);
});

test('every locale/reason is data-only with no OS display fields or localized content', () => {
  for (const locale of ['en', 'zh-TW']) for (const reason of ['finished', 'permission', 'attention']) {
    const message = buildMessage({ ...fixture, locale, reason });
    assert.deepEqual(message, {
      token: fixture.token,
      data: { v: '1', ...fixture.target, reason },
      android: { priority: 'high', ttl: 600000 },
    });
    assert.equal(Object.hasOwn(message, 'notification'), false);
    assert.equal(Object.hasOwn(message.android, 'notification'), false);
    assert.equal(Object.hasOwn(message.data, 'locale'), false);
    assert.ok(Object.values(message.data).every(value => typeof value === 'string'));
  }
});
