import { DurableObject } from 'cloudflare:workers';

const RETENTION_MS = 30 * 24 * 60 * 60 * 1000;
const RATE_MS = 60 * 60 * 1000;
const MAX_PER_IP = 5;
const encoder = new TextEncoder();
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const REASONS = new Set(['incorrect', 'unsafe', 'offensive', 'privacy', 'other']);
type ReportInput = { id: string; reason: string; note: string; response: string; created_at_ms: number };
type StoredReport = ReportInput & { received_at_ms: number; expires_at_ms: number; receipt_hash: string };

function result(value: unknown, status = 200): Response {
  return Response.json(value, { status, headers: { 'cache-control': 'no-store' } });
}
function error(code: string, status: number): Response { return result({ error: { code, message: code } }, status); }
async function hash(value: string): Promise<string> {
  return [...new Uint8Array(await crypto.subtle.digest('SHA-256', encoder.encode(value)))].map(x => x.toString(16).padStart(2, '0')).join('');
}
function same(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}
function receipt(): string {
  return btoa(String.fromCharCode(...crypto.getRandomValues(new Uint8Array(32)))).replaceAll('+', '-').replaceAll('/', '_').replaceAll('=', '');
}
function valid(value: unknown): value is ReportInput {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return false;
  const v = value as Record<string, unknown>;
  return Object.keys(v).length === 5 && ['id', 'reason', 'note', 'response', 'created_at_ms'].every(k => k in v)
    && typeof v.id === 'string' && UUID.test(v.id)
    && typeof v.reason === 'string' && REASONS.has(v.reason)
    && typeof v.note === 'string' && v.note.length <= 2000
    && typeof v.response === 'string' && v.response.length > 0 && v.response.length <= 12000
    && typeof v.created_at_ms === 'number' && Number.isSafeInteger(v.created_at_ms)
    && Math.abs(Date.now() - v.created_at_ms) <= 7 * 24 * 60 * 60 * 1000;
}

/** Private Worker-facing inbox. No device pairing or phone connection is involved. */
export class ReportInbox extends DurableObject {
  async alarm(): Promise<void> {
    const now = Date.now();
    for (const prefix of ['report:', 'rate:']) {
      const entries = await this.ctx.storage.list<StoredReport | { expires_at_ms: number }>({ prefix });
      for (const [key, value] of entries) if (value.expires_at_ms <= now) await this.ctx.storage.delete(key);
    }
    await this.ctx.storage.setAlarm(now + 60 * 60 * 1000);
  }

  async fetch(request: Request): Promise<Response> {
    const path = new URL(request.url).pathname;
    if (path === '/intake' && request.method === 'POST') return this.intake(request);
    if (path === '/review' && request.method === 'GET') return this.review(request);
    if (path.startsWith('/delete/') && request.method === 'DELETE') return this.delete(request, path.slice('/delete/'.length));
    return error('not_found', 404);
  }

  private async intake(request: Request): Promise<Response> {
    const ip = request.headers.get('x-report-ip') || '';
    if (!ip || ip.length > 64) return error('unavailable', 503);
    const rateKey = 'rate:' + await hash(ip);
    const now = Date.now();
    const allowed = await this.ctx.storage.transaction(async tx => {
      let rate = await tx.get<{ count: number; expires_at_ms: number }>(rateKey);
      if (!rate || rate.expires_at_ms <= now) rate = { count: 0, expires_at_ms: now + RATE_MS };
      rate.count++;
      await tx.put(rateKey, rate);
      return rate.count <= MAX_PER_IP;
    });
    if (!allowed) return error('rate_limited', 429);
    const body = await request.json().catch(() => null);
    if (!valid(body)) return error('invalid_report', 400);
    const key = 'report:' + body.id.toLowerCase();
    // A lost 201 response may be retried. A UUID already accepted is still acknowledged,
    // without reissuing its deletion credential or replacing stored content.
    if (await this.ctx.storage.get(key)) return result({ id: body.id.toLowerCase(), accepted: true }, 201);
    const deletionReceipt = receipt();
    await this.ctx.storage.put(key, { ...body, id: body.id.toLowerCase(), received_at_ms: now,
      expires_at_ms: now + RETENTION_MS, receipt_hash: await hash(deletionReceipt) } satisfies StoredReport);
    if (!await this.ctx.storage.getAlarm()) await this.ctx.storage.setAlarm(now + 60 * 60 * 1000);
    return result({ id: body.id.toLowerCase(), accepted: true, deletion_receipt: deletionReceipt }, 201);
  }

  private async review(request: Request): Promise<Response> {
    if (request.headers.get('x-report-owner') !== 'yes') return error('access_denied', 403);
    const cursor = new URL(request.url).searchParams.get('cursor');
    if (cursor && !/^report:[0-9a-f-]{36}$/.test(cursor)) return error('invalid_cursor', 400);
    const entries = await this.ctx.storage.list<StoredReport>({ prefix: 'report:', startAfter: cursor || undefined, limit: 50 });
    const reports = [...entries.values()].filter(v => v.expires_at_ms > Date.now()).map(({ receipt_hash: _, ...v }) => v);
    return result({ reports, next_cursor: entries.size === 50 ? [...entries.keys()].at(-1) : null });
  }

  private async delete(request: Request, id: string): Promise<Response> {
    if (!UUID.test(id)) return error('not_found', 404);
    const key = 'report:' + id.toLowerCase();
    const report = await this.ctx.storage.get<StoredReport>(key);
    if (!report || report.expires_at_ms <= Date.now()) return error('not_found', 404);
    const owner = request.headers.get('x-report-owner') === 'yes';
    const token = request.headers.get('x-report-receipt') || '';
    if (!owner && (!/^[A-Za-z0-9_-]{43}$/.test(token) || !same(await hash(token), report.receipt_hash))) return error('access_denied', 403);
    await this.ctx.storage.delete(key);
    return result({ id: id.toLowerCase(), deleted: true });
  }
}
