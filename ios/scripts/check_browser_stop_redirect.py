#!/usr/bin/env python3
"""Build a Debug macOS WebKit loopback diagnostic; this is not iOS testing."""
from pathlib import Path
import subprocess, sys, tempfile, uuid

repo = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(repo / 'scripts'))
from check_profile_chat_app import APP_SOURCES, MODULES

out = Path(tempfile.mkdtemp(prefix='woow-stop-redirect-repro-'))
common = ['swiftc', '-swift-version', '5', '-parse-as-library', '-I', str(out), '-L', str(out)]
for name, deps in MODULES:
    files = [str(p) for p in sorted((repo / 'Sources' / name).glob('*.swift'))]
    flags = ['-DDEBUG'] if name == 'AssistantBrowser' else []
    subprocess.run(common + flags + ['-emit-module', '-emit-library', '-module-name', name,
        '-emit-module-path', str(out / (name + '.swiftmodule')), *files,
        *['-l' + d for d in deps], '-o', str(out / ('lib' + name + '.dylib'))], check=True)
apps = [str(repo / 'Sources' / 'App' / (name + '.swift')) for name in APP_SOURCES]
binary = out / 'repro'
subprocess.run(common + ['-DDEBUG', '-DBROWSER_SITE_MODE_APP_STANDALONE',
    *['-l' + m for m, _ in MODULES], '-Xlinker', '-rpath', '-Xlinker', str(out), *apps,
    str(repo / 'Tests/AssistantDomainTests/BrowserUserSiteModesChecks.swift'),
    str(repo / 'scripts/CheckBrowserSiteModesApp.swift'), '-o', str(binary)], check=True)
flags = ['-UITestMode', '-UITestBrowserDownloadedPDF', '-UITestNamespace']
same = subprocess.run([str(binary), *flags, str(uuid.uuid4())], capture_output=True, text=True, timeout=180)
expected = 'REGRESSION positive_new_download=completed old_response_policy=not_cancel isolated_views=pass'
if same.returncode != 1 or expected not in same.stdout:
    raise SystemExit('same-URL diagnostic did not reproduce expected result: ' + same.stdout + same.stderr)
print('same_url_known_red_reproduced=true', flush=True)
subprocess.run([str(binary), *flags, str(uuid.uuid4()), '-UITestBrowserStopRedirect'], check=True, timeout=180)
subprocess.run([str(binary), '-UITestMode', '-UITestBrowserLogin', '-UITestNamespace', str(uuid.uuid4())],
               check=True, timeout=180)
