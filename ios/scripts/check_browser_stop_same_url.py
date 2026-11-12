#!/usr/bin/env python3
"""Run the Debug WebKit stop/download regression without external network or user data."""
from pathlib import Path
import subprocess, sys, tempfile, uuid
repo = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(repo / 'scripts'))
from check_profile_chat_app import APP_SOURCES, MODULES
out = Path(tempfile.mkdtemp(prefix='woow-stop-same-url-repro-'))
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
result = subprocess.run([str(binary), '-UITestMode', '-UITestBrowserDownloadedPDF',
    '-UITestNamespace', str(uuid.uuid4())])
raise SystemExit(result.returncode)
