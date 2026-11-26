// Development/single-process reference only. Shared production stores must provide atomic run().
export function createMemoryState({ now = Date.now, ttlMs = 600000, capacity = 10000 } = {}) {
  const registrations = new Set(), events = new Map();
  return {
    async has(key) { return registrations.has(key); },
    async register(key) {
      if (!registrations.has(key) && registrations.size >= capacity) throw new Error('capacity');
      registrations.add(key);
    },
    async unregister(key) { registrations.delete(key); },
    async run(key, work) {
      for (const [k, v] of events) if (v.expires <= now()) events.delete(k);
      if (events.has(key)) {
        const answer = await events.get(key).promise;
        return answer.status < 300 ? { status: 200, body: { ok: true, duplicate: true } } : answer;
      }
      if (events.size >= capacity) return { status: 503, body: { error: 'upstream_unavailable' } };
      const entry = { expires: Infinity };
      // Publish before work starts, making concurrent identical requests share the result.
      entry.promise = Promise.resolve().then(work);
      events.set(key, entry);
      try {
        const answer = await entry.promise;
        if (answer.status < 300) entry.expires = now() + ttlMs;
        else events.delete(key);
        return answer;
      } catch (error) { events.delete(key); throw error; }
    },
  };
}
