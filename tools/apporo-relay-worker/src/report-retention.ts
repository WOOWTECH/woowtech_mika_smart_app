/** Reports become unreadable at expires_at_ms; the alarm removes their stored copies. */
export const REPORT_RETENTION_MS = 30 * 24 * 60 * 60 * 1000;
const PAGE_SIZE = 1000;

export async function purgeExpiredReports(
  list: (prefix: string, startAfter?: string) => Promise<Map<string, { expires_at_ms: number }>>,
  remove: (key: string) => Promise<unknown>,
  schedule: (at: number) => Promise<unknown>,
  now: number,
): Promise<void> {
  for (const prefix of ['report:', 'rate:']) {
    let startAfter: string | undefined;
    while (true) {
      const entries = await list(prefix, startAfter);
      for (const [key, value] of entries) if (value.expires_at_ms <= now) await remove(key);
      if (entries.size < PAGE_SIZE) break;
      startAfter = [...entries.keys()].at(-1);
    }
  }
  await schedule(now + 60 * 60 * 1000);
}
