#!/usr/bin/env python3
"""Exercise exact ChatSession sources with isolated files, stores and fake clients."""
from pathlib import Path
import hashlib
import subprocess
import tempfile
from check_task_notifications import APPS, MODULES

root = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='woow-attachment-session-check-') as folder:
    out = Path(folder); snapshot = out / 'source'; hashes = {}
    def copy(path):
        rel = path.relative_to(root); target = snapshot / rel
        target.parent.mkdir(parents=True, exist_ok=True)
        data = path.read_bytes(); target.write_bytes(data)
        hashes[path] = hashlib.sha256(data).digest()
        return target
    def run(label, command, timeout=180):
        result = subprocess.run(command, capture_output=True, text=True, timeout=timeout)
        if result.returncode:
            print(label + ' failed:\n' + result.stdout[-4000:] + result.stderr[-8000:], flush=True)
            raise SystemExit(result.returncode)
        if result.stdout: print(result.stdout.strip(), flush=True)
        print(label + ': passed', flush=True)
    modules = {name: [copy(p) for p in sorted((root / 'Sources' / name).glob('*.swift'))] for name, _ in MODULES}
    apps = [copy(root / 'Sources/App' / (name + '.swift')) for name in [*APPS, 'RecentConversationAccess', 'NewConversationProtection']]
    harness = copy(root / 'scripts/CheckChatAttachmentSession.swift')
    protocol_fixture = copy(root / 'Tests/AssistantModelsTests/ModelProtocolFixture.swift')
    view = copy(root / 'Sources/App/ChatAttachmentPickerView.swift')
    common = ['swiftc', '-swift-version', '5', '-parse-as-library', '-I', str(out), '-L', str(out)]
    for name, dependencies in MODULES:
        run(name + ' build', [*common, '-enable-testing', '-emit-library', '-emit-module', '-module-name', name,
            '-emit-module-path', str(out / (name + '.swiftmodule')), *map(str, modules[name]),
            *['-l' + dep for dep in dependencies], '-o', str(out / ('lib' + name + '.dylib'))])
    for label, flags in [('Debug', ['-DDEBUG']), ('Release', [])]:
        binary = out / ('checks-' + label)
        run(label + ' iOS syntax', ['swiftc', '-frontend', '-parse', '-target', 'arm64-apple-ios17.0',
            *flags, *map(str, apps), str(view), str(protocol_fixture), str(harness)])
        run(label + ' compile', [*common, *flags, *['-l' + name for name, _ in MODULES],
            '-Xlinker', '-rpath', '-Xlinker', str(out), *map(str, apps), str(protocol_fixture), str(harness), '-o', str(binary)])
        run(label + ' session checks', [str(binary)], timeout=90)
    if any(hashlib.sha256(path.read_bytes()).digest() != digest for path, digest in hashes.items()):
        raise SystemExit('Sources changed during check; result is not current')
    print('Source snapshot remained unchanged; native iOS execution not performed')
