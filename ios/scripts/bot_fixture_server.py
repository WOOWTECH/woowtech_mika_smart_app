#!/usr/bin/env python3
"""LAN-only UI fixture for the direct iOS variant; never connects to a real bot.

Use a private interface address, then explicitly opt into HTTP for that service
in the app. Two registrations of this same origin must keep cookies/localStorage
independent. Session tokens remain only in this process and HttpOnly cookies.
"""
import argparse
import html
import ipaddress
import json
import pathlib
import secrets
import time
from http.cookies import SimpleCookie
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlsplit

SESSIONS = {}
REVOKED = []
NOTE = b"WOOW iOS isolated service download fixture\n"
# --list-workspace: a signed-in session gets the website's phone workspace (bot_list_fixture.html, the same structure and
# timeline as Android's tools/woowtechbot-ui/list-fixture.html), which logs what it did to /test/list-events.
LIST_PAGE = None
LIST_EVENTS = []
DL_EVENTS = []
REQUESTS = []
# --files DIR: /downloads, a page with one button per type and per way the website downloads (owner 2026-11-28: every kind
# of file downloads in the app). Files are served from DIR at /files/<name> (their own type) and /attach/<name> (attachment).
FILES = None
TYPES = {".png": "image/png", ".jpg": "image/jpeg", ".mp4": "video/mp4", ".m4a": "audio/mp4", ".mp3": "audio/mpeg",
         ".pdf": "application/pdf", ".html": "text/html; charset=utf-8", ".txt": "text/plain; charset=utf-8",
         ".csv": "text/csv; charset=utf-8", ".zip": "application/zip",
         ".docx": "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
         ".xlsx": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"}
DOWNLOADS_PAGE = """<!doctype html><html lang="en"><meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<title>Download tests</title><style>body{font:14px system-ui;padding:8px;padding-top:calc(8px + env(safe-area-inset-top))}
h1{font-size:20px;margin:4px 0 8px}.grid{display:grid;grid-template-columns:1fr 1fr;gap:6px}
button,a{display:block;font:inherit;padding:8px 6px;margin:0;width:100%;box-sizing:border-box;text-align:left}</style>
<h1>Download tests</h1><div class="grid">
<button onclick="blobDl('sample-image.png')">blob image png</button>
<button onclick="blobDl('sample-photo.jpg')">blob photo jpg</button>
<button onclick="blobDl('sample-video.mp4')">blob video mp4</button>
<button onclick="blobDl('sample-audio.m4a')">blob audio m4a</button>
<button onclick="blobDl('sample-audio.mp3')">blob audio mp3</button>
<button onclick="blobDl('sample-document.pdf')">blob pdf</button>
<button onclick="blobDl('sample-report.docx')">blob word docx</button>
<button onclick="blobDl('sample-sheet.xlsx')">blob excel xlsx</button>
<button onclick="blobDl('sample-page.html', 'sample-page.html', 'application/octet-stream')">blob html octet</button>
<button onclick="blobDl('sample-archive.zip')">blob zip</button>
<button onclick="blobDl('sample-notes.txt')">blob text txt</button>
<button onclick="blobDl('sample-table.csv')">blob table csv</button>
<button onclick="blobDl('sample-document.pdf', 'report-no-extension')">blob pdf without extension</button>
<button onclick="dataDl()">data image png</button>
<button onclick="shareSave()">share html save</button>
<a href="/files/sample-archive.zip" download>direct zip download</a>
<a href="/files/sample-document.pdf">direct pdf link</a>
<a href="/attach/sample-photo.jpg">attachment jpg link</a></div>
<script>
const log = what => navigator.sendBeacon('/test/dl-event', what);
window.addEventListener('error', e => log('error ' + e.message));
log('loaded revoke=' + String(URL.revokeObjectURL).slice(0, 40) + ' share=' + (navigator.canShare ? String(navigator.canShare).slice(0, 30) : 'none'));
document.addEventListener('click', e => log('click ' + (e.target && e.target.textContent || '').slice(0, 30) + ' trusted=' + e.isTrusted), true);
['touchstart', 'touchend', 'mousedown', 'mouseover'].forEach(n => document.addEventListener(n, e => log(n + ' ' + (e.target && e.target.textContent || '').slice(0, 20)), true));
async function blobDl(name, save, type) {
  log('start ' + name);
  const r = await fetch('/files/' + name, {method: 'POST'});
  log('fetched ' + r.status);
  let b = await r.blob();
  if (type) b = new Blob([b], {type: type});
  const u = URL.createObjectURL(b);
  const a = document.createElement('a'); a.href = u; a.download = save || name;
  document.body.appendChild(a); a.click(); a.remove();
  log('clicked ' + u.slice(0, 40));
  setTimeout(() => URL.revokeObjectURL(u), 0);
}
function dataDl() {
  fetch('/files/sample-image.png').then(r => r.blob()).then(b => {
    const reader = new FileReader();
    reader.onload = () => { const a = document.createElement('a'); a.href = reader.result; a.download = 'data-image.png'; a.click(); };
    reader.readAsDataURL(b);
  });
}
async function shareSave() {
  const html = '<!doctype html><meta charset="utf-8"><title>share</title><p>share save</p>';
  const file = new File([html], 'share-page.html', {type: 'text/html'});
  if (matchMedia('(pointer: coarse)').matches && navigator.canShare && navigator.canShare({files: [file]})) {
    await navigator.share({files: [file]}); return;
  }
  const u = URL.createObjectURL(new Blob([html], {type: 'application/octet-stream'}));
  const a = document.createElement('a'); a.href = u; a.download = 'share-page.html'; a.click();
  setTimeout(() => URL.revokeObjectURL(u), 0);
}
</script></html>"""


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass  # Request URLs and Cookie headers never enter a test log.

    def parse_request(self):
        ok = super().parse_request()
        # Paths only (no query, cookie or header), for the download tests' evidence at /test/requests.
        if ok and len(REQUESTS) < 1000:
            REQUESTS.append({"t": round(time.time(), 3), "method": self.command, "path": urlsplit(self.path).path})
        return ok

    def token(self):
        cookie = SimpleCookie()
        try:
            cookie.load(self.headers.get("Cookie", ""))
            return cookie["bot_fixture"].value if "bot_fixture" in cookie else ""
        except Exception:
            return ""

    def send(self, body, status=200, content_type="text/html; charset=utf-8", headers=None):
        if isinstance(body, str):
            body = body.encode()
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        for key, value in (headers or {}).items():
            self.send_header(key, value)
        self.end_headers()
        self.wfile.write(body)

    def serve_file(self, path):
        for prefix, attachment in (("/files/", False), ("/attach/", True)):
            if FILES is not None and path.startswith(prefix):
                name = path[len(prefix):]
                target = FILES / name
                if "/" in name or not name or not target.is_file():
                    self.send("not found", 404)
                    return True
                extension = target.suffix.lower()
                headers = {"Content-Disposition": f'attachment; filename="{name}"'} if attachment else {}
                self.send(target.read_bytes(), content_type=TYPES.get(extension, "application/octet-stream"), headers=headers)
                return True
        return False

    def do_GET(self):
        path = urlsplit(self.path)
        if path.path == "/test/requests":
            return self.send(json.dumps(REQUESTS[-200:]), content_type="application/json")
        if path.path == "/test/dl-events":
            return self.send(json.dumps(DL_EVENTS), content_type="application/json")
        if FILES is not None and path.path == "/downloads":
            return self.send(DOWNLOADS_PAGE)
        if self.serve_file(path.path):
            return
        if path.path == "/note.txt":
            return self.send(NOTE, content_type="text/plain", headers={"Content-Disposition": 'attachment; filename="ios-bot-note.txt"'})
        if path.path == "/redirect-note":
            return self.send("", 302, headers={"Location": "https://example.com/forbidden-download.txt"})
        if path.path == "/test/audit":
            return self.send(json.dumps({"active": sorted(SESSIONS.values()), "revoked": REVOKED}), content_type="application/json")
        if path.path == "/test/list-events":
            events = list(LIST_EVENTS)
            if "reset" in parse_qs(path.query):
                LIST_EVENTS.clear()
            return self.send(json.dumps(events), content_type="application/json")
        identity = SESSIONS.get(self.token(), "Signed out")
        if LIST_PAGE is not None and identity != "Signed out":
            LIST_EVENTS.append({"server_ms": int(time.time() * 1000), "what": "page"})
            return self.send(LIST_PAGE)
        query = parse_qs(path.query)
        target = html.escape("bot=" + query.get("bot", [""])[0][:128] + " thread=" + query.get("thread", [""])[0][:128])
        # Like the real woowtechbot app, the sidebar (and the slot the native workspace controls
        # attach to) exists only after sign-in; the sign-in page has none, so the native toolbar
        # fallback stays visible there.
        shell_open, shell_close = ("", "")
        if identity != "Signed out":
            shell_open = ('<div data-look="app"><aside id="sidebar"><header data-sidebar-top-slot>'
                          '<button type="button" id="original">New conversation</button></header></aside><main>')
            shell_close = "</main></div>"
        self.send('''<!doctype html><html lang="en"><meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<title>iOS service fixture</title><style>:root[data-skin="midnight"]{--color-ink:#f5f5f5;--color-card:#1f1f1f;--color-hairline:#383838;--color-app:#121212}:root[data-skin="daylight"]{--color-ink:#1c1c1c;--color-card:#efefef;--color-hairline:#c6c6c6;--color-app:#fcfcfc}body{font:18px system-ui;padding:16px;padding-top:calc(16px + env(safe-area-inset-top));background:var(--color-app,#fafafa);color:var(--color-ink,#111)}button,a,textarea{display:block;font:inherit;padding:14px;margin:12px 0;box-sizing:border-box;max-width:100%}textarea{width:100%;height:90px}</style>
''' + shell_open + '''<h1>iOS service fixture</h1><p>Independent website storage test</p><p>Session: ''' + html.escape(identity) + '''</p>
<form method="post" action="/pair"><button name="identity" value="iOS A">Sign in as iOS A</button><button name="identity" value="iOS B">Sign in as iOS B</button></form>
<label>Web draft<textarea aria-label="Web draft" id="draft"></textarea></label>
<a href="/note.txt" download="ios-bot-note.txt">Download test note</a>
<a href="/downloads">Download tests</a>
<a href="https://example.com/">External link</a><p>''' + target + '''</p>
<input type="file" aria-label="Attach file">''' + shell_close + '''<script>const input=document.getElementById('draft');input.value=localStorage.getItem('fixture.draft')||'';input.oninput=()=>localStorage.setItem('fixture.draft',input.value);</script></html>''')

    def do_POST(self):
        path = urlsplit(self.path).path
        if self.serve_file(path):
            return
        if path == "/test/dl-event":
            size = int(self.headers.get("Content-Length", "0"))
            if size <= 512 and len(DL_EVENTS) < 500:
                DL_EVENTS.append({"t": round(time.time(), 3), "what": self.rfile.read(size).decode("utf-8", "replace")})
            return self.send("", 204)
        if path == "/test/list-event":
            size = int(self.headers.get("Content-Length", "0"))
            if size > 512 or len(LIST_EVENTS) > 2000:
                return self.send("too large", 413)
            try:
                event = json.loads(self.rfile.read(size).decode())
            except ValueError:
                return self.send("invalid event", 400)
            LIST_EVENTS.append({"server_ms": int(time.time() * 1000), **{k: event.get(k) for k in ("what", "open", "selected", "ms")}})
            return self.send("", 204)
        if path == "/api/auth/logout":
            identity = SESSIONS.pop(self.token(), None)
            if identity:
                REVOKED.append(identity)
            return self.send('{"ok":true}', content_type="application/json", headers={"Set-Cookie": "bot_fixture=; Path=/; Max-Age=0; HttpOnly; SameSite=Lax"})
        if path == "/pair":
            size = int(self.headers.get("Content-Length", "0"))
            if size > 512:
                return self.send("too large", 413)
            identity = parse_qs(self.rfile.read(size).decode()).get("identity", [""])[0]
            if identity not in ("iOS A", "iOS B"):
                return self.send("invalid fixture identity", 400)
            token = secrets.token_urlsafe(24)
            SESSIONS[token] = identity
            return self.send("", 303, headers={"Location": "/", "Set-Cookie": "bot_fixture=" + token + "; Path=/; Max-Age=86400; HttpOnly; SameSite=Lax"})
        self.send("not found", 404)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", required=True)
    parser.add_argument("--port", type=int, default=8767)
    parser.add_argument("--files", help="serve /downloads and the test files in this folder")
    parser.add_argument("--list-workspace", action="store_true",
                        help="serve the phone bot-list workspace (bot_list_fixture.html) to signed-in sessions")
    args = parser.parse_args()
    if args.files:
        FILES = pathlib.Path(args.files).resolve()
    if args.list_workspace:
        LIST_PAGE = (pathlib.Path(__file__).resolve().parent / "bot_list_fixture.html").read_text()
    address = ipaddress.ip_address(args.host)
    if not address.is_private or address.is_loopback or address.is_link_local:
        parser.error("Use a private LAN interface, not loopback or link-local")
    print("Serving dedicated iOS UI fixture on", args.host, args.port, flush=True)
    ThreadingHTTPServer((args.host, args.port), Handler).serve_forever()
