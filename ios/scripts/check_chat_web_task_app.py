#!/usr/bin/env python3
"""Run chat web tasks in real WebKit on macOS against loopback pages.

Debug and Release check the task tab's rules and the runner on real pages;
Debug also runs the whole chat path with the Debug model fixture and the Debug
loopback website. No external site, model provider, Keychain or user data.
"""
import json
import subprocess
import tempfile
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlsplit

from check_task_notifications import APPS, MODULES

ROOT = Path(__file__).resolve().parents[1]


def page(title, body):
    return ("<!doctype html><html lang='zh-Hant'><head><meta charset='utf-8'>"
            "<meta name='viewport' content='width=device-width, initial-scale=1'><title>%s</title></head>"
            "<body><nav><a href='/'>網站首頁</a> <a href='/help'>說明</a> <a href='/account/login'>登入</a></nav>"
            "<main>%s</main><footer><a href='/about'>關於我們</a></footer></body></html>" % (title, body))


class Pages(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def send(self, status, body="", headers=()):
        data = body.encode("utf-8")
        self.send_response(status)
        for name, value in headers:
            self.send_header(name, value)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        parts = urlsplit(self.path)
        query = {k: v[0] for k, v in parse_qs(parts.query).items()}
        html = [("Content-Type", "text/html; charset=utf-8")]
        keyword = query.get("keyword", "").replace("<", "").replace("'", "")
        if parts.path == "/jobs/search":
            items = "".join("<li><a href='/jobs/job/%d'>%s 工程師（測試公司 %d）</a>：月薪 %d,000 元</li>" % (n, keyword, n, 45 + n * 5)
                            for n in range(1, 7))
            return self.send(200, page("「%s」工作 - 測試人力銀行" % keyword, "<h1>搜尋共 6 筆職缺</h1><ol>%s</ol>" % items), html)
        if parts.path.startswith("/jobs/job/"):
            n = parts.path.rsplit("/", 1)[-1]
            return self.send(200, page("工程師（測試公司 %s）" % n, "<h1>職缺 %s</h1><p>條件：熟悉 Swift 與 SwiftUI。</p>" % n), html)
        if parts.path == "/shop/search":
            first = "".join("<li>%s 型號 %d</li>" % (keyword, n) for n in range(1, 5))
            script = ("<script>let more=false;addEventListener('scroll',()=>{if(more||scrollY<200)return;more=true;"
                      "const l=document.getElementById('list');for(let i=5;i<=8;i++){const li=document.createElement('li');"
                      "li.textContent='型號 '+i;l.appendChild(li);}});</script>")
            return self.send(200, page("商品", "<ul id='list'>%s</ul><div style='height:3000px'></div>%s" % (first, script)), html)
        if parts.path == "/go-logout":
            return self.send(302, "", [("Location", "/account/logout")])
        if parts.path in ("/account/login", "/account/logout"):
            return self.send(200, page("帳號", "<form><input type='password'></form>"), html)
        if parts.path == "/download":
            return self.send(200, "binary", [("Content-Type", "application/octet-stream"),
                                             ("Content-Disposition", "attachment; filename=a.bin")])
        if parts.path == "/dialog":
            return self.send(200, page("對話框", "<p>內容</p><script>alert('fixture alert')</script>"), html)
        if parts.path == "/members/signon":
            return self.send(200, page("會員", "<p>請輸入密碼</p><input type='password' name='pw'>"), html)
        if parts.path == "/captcha":
            return self.send(200, page("驗證", "<p>請完成驗證</p><div class='g-recaptcha' style='width:300px;height:80px'></div>"), html)
        return self.send(404, page("找不到", "<p>找不到頁面</p>"), html)


class QuietServer(ThreadingHTTPServer):
    def handle_error(self, request, client_address):
        pass  # WebKit closes connections it no longer needs; that is not a failure.


def main():
    server = QuietServer(("127.0.0.1", 0), Pages)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    origin = "http://127.0.0.1:%d" % server.server_address[1]
    try:
        with tempfile.TemporaryDirectory(prefix="woow-chat-web-app-") as folder:
            out = Path(folder)
            common = ["swiftc", "-swift-version", "5", "-parse-as-library", "-I", str(out), "-L", str(out)]
            for name, deps in MODULES:
                subprocess.run(common + ["-emit-module", "-emit-library", "-module-name", name,
                                         "-emit-module-path", str(out / (name + ".swiftmodule")),
                                         *map(str, sorted((ROOT / "Sources" / name).glob("*.swift"))),
                                         *["-l" + d for d in deps], "-o", str(out / ("lib" + name + ".dylib"))],
                               check=True, timeout=900)
            apps = [str(ROOT / "Sources/App" / (name + ".swift")) for name in APPS]
            counts = {}
            for config, flags, extra in [("Release", [], []), ("Debug", ["-DDEBUG"], ["-UITestMode", "-UITestChatWeb"])]:
                binary = out / ("checks-" + config)
                subprocess.run(common + flags + ["-DCHAT_WEB_TASK_APP_STANDALONE", *["-l" + m for m, _ in MODULES],
                                                 "-Xlinker", "-rpath", "-Xlinker", str(out), *apps,
                                                 str(ROOT / "scripts/CheckChatWebTaskApp.swift"), "-o", str(binary)],
                               check=True, timeout=900)
                result = subprocess.run([str(binary), origin, *extra], capture_output=True, text=True, timeout=300)
                if result.returncode:
                    print(result.stdout[-4000:] + result.stderr[-4000:])
                    raise SystemExit(config + " WebKit checks failed")
                counts[config] = json.loads(result.stdout.strip().splitlines()[-1])["assertions"]
            if counts["Debug"] <= counts["Release"]:
                raise SystemExit("Debug did not run the chat path")
            print("PASS chat web task app: " + json.dumps(counts))
    finally:
        server.shutdown()


if __name__ == "__main__":
    main()
