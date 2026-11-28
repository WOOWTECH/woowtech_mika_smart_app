#!/usr/bin/env python3
"""Download test page for the woowtechbot service screen (owner 2026-11-28: every file type must download on iOS and Android).

    python3 tools/woowtechbot-ui/downloads-fixture.py --host 192.168.2.30 --port 8766

Then add http://<host>:<port> as a woowtechbot service with the trusted-LAN option (Android) or open it in the iOS bot app.
Every type comes four ways: a direct link with `download`, a Content-Disposition attachment, a redirect, and the
woowtechbot website's own way (POST → Blob → object URL → <a download> → revoked at once). Plus data: URLs, a Chinese
file name, another site's https file (asks first) and a download that starts 70 s after the last tap (must be blocked).
Sample files are generated at start (ffmpeg for media when available); nothing is downloaded from the internet.
"""
import argparse
import html
import io
import json
import math
import mimetypes
import shutil
import struct
import subprocess
import tempfile
import urllib.parse
import wave
import zipfile
import zlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

TYPES = {
    'png': 'image/png', 'jpg': 'image/jpeg', 'gif': 'image/gif', 'webp': 'image/webp', 'svg': 'image/svg+xml',
    'mp4': 'video/mp4', 'mov': 'video/quicktime', 'webm': 'video/webm',
    'mp3': 'audio/mpeg', 'm4a': 'audio/mp4', 'wav': 'audio/wav',
    'pdf': 'application/pdf', 'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'html': 'text/html', 'txt': 'text/plain', 'csv': 'text/csv', 'json': 'application/json', 'md': 'text/markdown',
    'zip': 'application/zip',
}
FOREIGN = 'https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf'


def png(path):
    raw = b''.join(b'\x00' + bytes([200, 60, 60, 255] * 8) for _ in range(8))
    def chunk(tag, data):
        return struct.pack('>I', len(data)) + tag + data + struct.pack('>I', zlib.crc32(tag + data) & 0xffffffff)
    path.write_bytes(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', 8, 8, 8, 6, 0, 0, 0)) +
                     chunk(b'IDAT', zlib.compress(raw)) + chunk(b'IEND', b''))


def pdf(path, text='woowtechbot download test'):
    stream = f'BT /F1 24 Tf 40 100 Td ({text}) Tj ET'.encode()
    objs = [b'<< /Type /Catalog /Pages 2 0 R >>', b'<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
            b'<< /Type /Page /Parent 2 0 R /MediaBox [0 0 420 200] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>',
            b'<< /Length %d >>\nstream\n' % len(stream) + stream + b'\nendstream',
            b'<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>']
    out, offsets = io.BytesIO(), []
    out.write(b'%PDF-1.4\n')
    for i, body in enumerate(objs, 1):
        offsets.append(out.tell()); out.write(b'%d 0 obj\n' % i + body + b'\nendobj\n')
    xref = out.tell()
    out.write(b'xref\n0 %d\n0000000000 65535 f \n' % (len(objs) + 1) + b''.join(b'%010d 00000 n \n' % o for o in offsets))
    out.write(b'trailer\n<< /Size %d /Root 1 0 R >>\nstartxref\n%d\n%%%%EOF\n' % (len(objs) + 1, xref))
    path.write_bytes(out.getvalue())


def docx(path):
    with zipfile.ZipFile(path, 'w', zipfile.ZIP_DEFLATED) as z:
        z.writestr('[Content_Types].xml', '<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>')
        z.writestr('_rels/.rels', '<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>')
        z.writestr('word/document.xml', '<?xml version="1.0" encoding="UTF-8"?><w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body><w:p><w:r><w:t>woowtechbot 下載測試 Word</w:t></w:r></w:p></w:body></w:document>')


def xlsx(path):
    with zipfile.ZipFile(path, 'w', zipfile.ZIP_DEFLATED) as z:
        z.writestr('[Content_Types].xml', '<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/></Types>')
        z.writestr('_rels/.rels', '<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>')
        z.writestr('xl/workbook.xml', '<?xml version="1.0" encoding="UTF-8"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="測試" sheetId="1" r:id="rId1"/></sheets></workbook>')
        z.writestr('xl/_rels/workbook.xml.rels', '<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/></Relationships>')
        z.writestr('xl/worksheets/sheet1.xml', '<?xml version="1.0" encoding="UTF-8"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData><row r="1"><c r="A1" t="inlineStr"><is><t>項目</t></is></c><c r="B1"><v>42</v></c></row></sheetData></worksheet>')


def wav(path):
    with wave.open(str(path), 'wb') as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(8000)
        w.writeframes(b''.join(struct.pack('<h', int(8000 * math.sin(2 * math.pi * 440 * i / 8000))) for i in range(8000)))


def make(folder):
    made = {}
    png(folder / 'sample.png'); made['png'] = 'sample.png'
    pdf(folder / 'sample.pdf'); made['pdf'] = 'sample.pdf'
    docx(folder / 'sample.docx'); made['docx'] = 'sample.docx'
    xlsx(folder / 'sample.xlsx'); made['xlsx'] = 'sample.xlsx'
    wav(folder / 'sample.wav'); made['wav'] = 'sample.wav'
    (folder / 'sample.svg').write_text('<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64"><circle cx="32" cy="32" r="28" fill="#7c5cff"/></svg>'); made['svg'] = 'sample.svg'
    (folder / 'sample.html').write_text('<!doctype html><meta charset="utf-8"><title>測試網頁</title><h1>woowtechbot 下載測試 HTML</h1>', encoding='utf-8'); made['html'] = 'sample.html'
    (folder / 'sample.txt').write_text('woowtechbot 下載測試 純文字\n', encoding='utf-8'); made['txt'] = 'sample.txt'
    (folder / 'sample.csv').write_text('項目,數量\n蘋果,3\n', encoding='utf-8'); made['csv'] = 'sample.csv'
    (folder / 'sample.json').write_text(json.dumps({'test': '下載', 'ok': True}, ensure_ascii=False), encoding='utf-8'); made['json'] = 'sample.json'
    (folder / 'sample.md').write_text('# 下載測試\n\n- Markdown\n', encoding='utf-8'); made['md'] = 'sample.md'
    with zipfile.ZipFile(folder / 'sample.zip', 'w') as z:
        z.writestr('讀我.txt', '壓縮檔裡的文字\n')
    made['zip'] = 'sample.zip'
    shutil.copy(folder / 'sample.pdf', folder / '中文檔名 測試.pdf'); made['pdf-zh'] = '中文檔名 測試.pdf'
    # A known valid 1×1 lossless WebP, for machines whose ffmpeg has no WebP encoder.
    (folder / 'sample.webp').write_bytes(__import__('base64').b64decode('UklGRhoAAABXRUJQVlA4TA0AAAAvAAAAEAcQERGIiP4HAA=='))
    made['webp'] = 'sample.webp'
    if shutil.which('ffmpeg'):
        media = {
            'jpg': ['-f', 'lavfi', '-i', 'color=c=0x3b82f6:s=64x64', '-frames:v', '1'],
            'gif': ['-f', 'lavfi', '-i', 'testsrc=size=64x64:rate=5', '-t', '1'],
            'mp4': ['-f', 'lavfi', '-i', 'testsrc=size=160x120:rate=10', '-t', '2', '-pix_fmt', 'yuv420p', '-c:v', 'libx264'],
            'mov': ['-f', 'lavfi', '-i', 'testsrc=size=160x120:rate=10', '-t', '2', '-pix_fmt', 'yuv420p', '-c:v', 'libx264'],
            'webm': ['-f', 'lavfi', '-i', 'testsrc=size=160x120:rate=10', '-t', '2', '-c:v', 'libvpx'],
            'mp3': ['-f', 'lavfi', '-i', 'sine=frequency=440:duration=1', '-c:a', 'libmp3lame'],
            'm4a': ['-f', 'lavfi', '-i', 'sine=frequency=440:duration=1', '-c:a', 'aac'],
        }
        for ext, args in media.items():
            out = folder / f'sample.{ext}'
            done = subprocess.run(['ffmpeg', '-loglevel', 'error', '-y', *args, str(out)], capture_output=True)
            if done.returncode == 0 and out.exists():
                made[ext] = out.name
    return made


PAGE = '''<!doctype html><html lang="zh-Hant"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>下載測試</title><style>
body{font:15px system-ui;margin:12px;background:#141414;color:#eee}h1{font-size:18px}h2{font-size:15px;margin:18px 0 6px;color:#9a9a9e}
.row{display:flex;flex-wrap:wrap;gap:6px;align-items:center;margin:6px 0}.row b{width:70px}a,button{color:#eee;background:#2c2c2e;border:1px solid #3a3a3c;
border-radius:10px;padding:8px 10px;font:inherit;text-decoration:none}#log{color:#9a9a9e;font-size:13px;white-space:pre-wrap}</style>
<h1>woowtechbot 下載測試</h1><p>每種類型四種方式：直接、附件標頭、轉址、網站方式（POST→blob→立刻作廢）。</p><div id="log"></div>
%ROWS%
<h2>其他</h2>
<div class="row"><a href="%DATACSV%" download="data-表格.csv">data: CSV</a><a href="%DATAPNG%" download="data-圖片.png">data: PNG</a>
<a href="/files/%ZH%" download>中文檔名（直接）</a><button onclick="site('%ZH%')">中文檔名（網站方式）</button></div>
<div class="row"><a href="%FOREIGN%">其他網站的 PDF（應先詢問）</a><button onclick="later()">70 秒後自動下載（應被擋下）</button></div>
<script>
const log = (t) => document.getElementById('log').textContent = new Date().toLocaleTimeString() + ' ' + t;
async function site(name) {
  // The woowtechbot website's way (2026-11-27): POST, Blob, object URL, <a download>, revoke at once.
  const r = await fetch('/post-file', {method: 'POST', headers: {'content-type': 'application/json'}, body: JSON.stringify({path: name})});
  if (!r.ok) return log('POST 失敗 ' + r.status);
  const blob = await r.blob(), url = URL.createObjectURL(blob);
  const a = document.createElement('a'); a.href = url; a.download = name; a.style.display = 'none'; document.body.append(a);
  try { a.click(); } finally { a.remove(); setTimeout(() => URL.revokeObjectURL(url), 0); }
  log('已觸發 ' + name + '（' + blob.size + ' bytes）');
}
function later() { log('70 秒後觸發，期間不要碰畫面'); setTimeout(() => site('sample.txt'), 70000); }
</script></html>'''


def page(made):
    rows = []
    for ext in TYPES:
        name = made.get(ext)
        if not name:
            rows.append(f'<div class="row"><b>{ext}</b><span>（這台電腦沒有產生這種樣本）</span></div>'); continue
        q = urllib.parse.quote(name)
        rows.append(f'<div class="row"><b>{ext}</b><a href="/files/{q}" download>直接</a><a href="/attach/{q}">附件標頭</a>'
                    f'<a href="/redirect/{q}">轉址</a><button onclick="site(\'{html.escape(name)}\')">網站方式</button></div>')
    data_csv = 'data:text/csv;charset=utf-8,' + urllib.parse.quote('項目,數量\n蘋果,3\n')
    data_png = 'data:image/png;base64,' + __import__('base64').b64encode((FOLDER / made['png']).read_bytes()).decode()
    return (PAGE.replace('%ROWS%', '\n'.join(rows)).replace('%DATACSV%', data_csv).replace('%DATAPNG%', data_png)
            .replace('%ZH%', made['pdf-zh']).replace('%FOREIGN%', FOREIGN))


class Handler(BaseHTTPRequestHandler):
    def send_file(self, name, attach):
        path = (FOLDER / name).resolve()
        if path.parent != FOLDER.resolve() or not path.is_file():
            return self.send_error(404)
        data = path.read_bytes()
        kind = TYPES.get(path.suffix.lstrip('.'), mimetypes.guess_type(path.name)[0] or 'application/octet-stream')
        self.send_response(200)
        self.send_header('Content-Type', kind)
        self.send_header('Content-Length', str(len(data)))
        if attach:
            ascii_name = name.encode('ascii', 'replace').decode().replace('?', '_')
            self.send_header('Content-Disposition', f'attachment; filename="{ascii_name}"; filename*=UTF-8\'\'{urllib.parse.quote(name)}')
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        path = urllib.parse.unquote(self.path.split('?')[0])
        if path == '/':
            body = page(MADE).encode()
            self.send_response(200); self.send_header('Content-Type', 'text/html; charset=utf-8')
            self.send_header('Content-Length', str(len(body))); self.end_headers(); self.wfile.write(body)
        elif path.startswith('/files/'): self.send_file(path[7:], attach=False)
        elif path.startswith('/attach/'): self.send_file(path[8:], attach=True)
        elif path.startswith('/redirect/'):
            self.send_response(302); self.send_header('Location', '/files/' + urllib.parse.quote(path[10:])); self.end_headers()
        else: self.send_error(404)

    def do_POST(self):
        if self.path != '/post-file': return self.send_error(404)
        length = int(self.headers.get('Content-Length') or 0)
        name = json.loads(self.rfile.read(length) or b'{}').get('path', '')
        self.send_file(name, attach=True)


if __name__ == '__main__':
    ap = argparse.ArgumentParser()
    ap.add_argument('--host', default='127.0.0.1'); ap.add_argument('--port', type=int, default=8766)
    a = ap.parse_args()
    FOLDER = Path(tempfile.mkdtemp(prefix='woowtechbot-downloads-'))
    MADE = make(FOLDER)
    print(f'samples: {", ".join(sorted(MADE))} in {FOLDER}')
    print(f'serving http://{a.host}:{a.port}/')
    ThreadingHTTPServer((a.host, a.port), Handler).serve_forever()
