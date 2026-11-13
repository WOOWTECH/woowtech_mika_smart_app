import assert from 'node:assert/strict';
import { purgeExpiredReports, REPORT_RETENTION_MS } from '../src/report-retention.ts';

const day = 24 * 60 * 60 * 1000;
const now = Date.UTC(2026, 10, 12);
const entries = new Map([
  ['report:expired', { expires_at_ms: now }],
  ['report:live', { expires_at_ms: now + day }],
  ['rate:expired', { expires_at_ms: now - 1 }],
  ['rate:live', { expires_at_ms: now + 1 }],
]);
for (let i = 0; i < 1001; i++) entries.set(`report:page${String(i).padStart(4, '0')}`, { expires_at_ms: now });
let nextAlarm;
await purgeExpiredReports(
  async (prefix, startAfter) => new Map([...entries].sort(([a], [b]) => a.localeCompare(b))
    .filter(([key]) => key.startsWith(prefix) && (!startAfter || key > startAfter)).slice(0, 1000)),
  async key => entries.delete(key),
  async at => { nextAlarm = at; },
  now,
);
assert.deepEqual([...entries.keys()], ['report:live', 'rate:live']);
assert.equal(nextAlarm, now + 60 * 60 * 1000);
assert.equal(REPORT_RETENTION_MS, 30 * day, 'retention interval used by report intake');
console.log('report retention cleanup passed');
