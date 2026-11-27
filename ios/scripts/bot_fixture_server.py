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
import secrets
from http.cookies import SimpleCookie
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlsplit

SESSIONS = {}
REVOKED = []
NOTE = b"WOOW iOS isolated service download fixture\n"


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass  # Request URLs and Cookie headers never enter a test log.

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

    def do_GET(self):
        path = urlsplit(self.path)
        if path.path == "/note.txt":
            return self.send(NOTE, content_type="text/plain", headers={"Content-Disposition": 'attachment; filename="ios-bot-note.txt"'})
        if path.path == "/redirect-note":
            return self.send("", 302, headers={"Location": "https://example.com/forbidden-download.txt"})
        if path.path == "/test/audit":
            return self.send(json.dumps({"active": sorted(SESSIONS.values()), "revoked": REVOKED}), content_type="application/json")
        identity = SESSIONS.get(self.token(), "Signed out")
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
<a href="https://example.com/">External link</a><p>''' + target + '''</p>
<input type="file" aria-label="Attach file">''' + shell_close + '''<script>const input=document.getElementById('draft');input.value=localStorage.getItem('fixture.draft')||'';input.oninput=()=>localStorage.setItem('fixture.draft',input.value);</script></html>''')

    def do_POST(self):
        path = urlsplit(self.path).path
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
    args = parser.parse_args()
    address = ipaddress.ip_address(args.host)
    if not address.is_private or address.is_loopback or address.is_link_local:
        parser.error("Use a private LAN interface, not loopback or link-local")
    print("Serving dedicated iOS UI fixture on", args.host, args.port, flush=True)
    ThreadingHTTPServer((args.host, args.port), Handler).serve_forever()
