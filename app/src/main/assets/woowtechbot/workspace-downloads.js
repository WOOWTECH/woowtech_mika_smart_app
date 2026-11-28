/* Downloads the page makes itself (owner 2026-11-28: every file type must download). The website fetches a file, turns
   the Blob into an object URL, clicks an <a download> and revokes the URL at once; by the time the app hears of the
   download the URL is gone. This keeps the Blob behind each object URL for 60 s after it is revoked, notes each anchor's
   download name, and hands one Blob to the app in chunks when the app asks for it with a token of its own.
   No native interface: the app polls these functions with evaluateJavascript. Reads nothing by itself. */
(function () {
  if (window.__woowDownloads) return true;
  const kept = new Map();
  const names = new Map();
  const recent = [];
  const create = URL.createObjectURL;
  const revoke = URL.revokeObjectURL;
  URL.createObjectURL = function (object) {
    const url = create.apply(this, arguments);
    try {
      if (object instanceof Blob) {
        kept.set(url, object);
        if (kept.size > 256) kept.delete(kept.keys().next().value);
      }
    } catch (e) { /* the page's own call result stays as it was */ }
    return url;
  };
  URL.revokeObjectURL = function (url) {
    if (kept.has(url)) setTimeout(() => kept.delete(url), 60000);
    return revoke.apply(this, arguments);
  };
  function note(anchor) {
    try {
      if (anchor && anchor.hasAttribute && anchor.hasAttribute('download') && anchor.href) {
        const name = anchor.getAttribute('download') || '';
        names.set(anchor.href, name);
        if (names.size > 64) names.delete(names.keys().next().value);
        // The app sees only the URL of a direct or data: download, so it asks by the URL's start and length.
        recent.unshift({ prefix: anchor.href.slice(0, 128), length: anchor.href.length, name, at: Date.now() });
        recent.length = Math.min(recent.length, 8);
      }
    } catch (e) { /* nothing to note */ }
  }
  document.addEventListener('click', (event) => {
    const target = event.target;
    note(target && target.closest ? target.closest('a[download]') : null);
  }, true);
  const click = HTMLAnchorElement.prototype.click;
  HTMLAnchorElement.prototype.click = function () {
    note(this);
    return click.apply(this, arguments);
  };
  const jobs = new Map();
  window.__woowDownloads = {
    start(token, url) {
      if (jobs.size >= 4) jobs.clear();
      const job = { state: 'pending' };
      jobs.set(token, job);
      const known = kept.get(url);
      (known ? Promise.resolve(known) : fetch(url).then((response) => response.blob()))
        .then((blob) => { job.blob = blob; job.state = 'ready'; }, () => { job.state = 'failed'; });
      return 'started';
    },
    info(token, url) {
      const job = jobs.get(token);
      if (!job) return 'unknown';
      if (job.state !== 'ready') return job.state;
      return JSON.stringify({ size: job.blob.size, type: job.blob.type || '', name: names.get(url) || job.blob.name || '' });
    },
    read(token, index, size) {
      const job = jobs.get(token);
      if (!job || job.state !== 'ready') return 'unknown';
      job.chunk = null;
      const reader = new FileReader();
      reader.onload = () => {
        const text = String(reader.result);
        job.chunk = { index, data: text.slice(text.indexOf(',') + 1) };
      };
      reader.onerror = () => { job.chunk = { index, error: true }; };
      reader.readAsDataURL(job.blob.slice(index * size, (index + 1) * size));
      return 'reading';
    },
    take(token, index) {
      const job = jobs.get(token);
      if (!job) return 'unknown';
      const chunk = job.chunk;
      if (!chunk || chunk.index !== index) return null;
      job.chunk = null;
      return chunk.error ? 'error' : chunk.data;
    },
    end(token) {
      jobs.delete(token);
      return true;
    },
    named(prefix, length) {
      const now = Date.now();
      const hit = recent.find((r) => r.prefix === prefix && r.length === length && now - r.at < 10000);
      return hit && hit.name ? hit.name : null;
    },
  };
  return true;
})()
