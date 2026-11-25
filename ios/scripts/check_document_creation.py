#!/usr/bin/env python3
"""Make every file format the assistant creates and open it with independent libraries.

swiftc builds AssistantDocuments with the App's DocumentPDFRenderer.swift for
Mac Catalyst, where UIKit runs on this Mac, in Debug and Release with
-warnings-as-errors. scripts/CheckDocumentCreation.swift makes the samples
(Chinese text, XML's special characters, empty and edge cases, the limits) and
checks file_create's parsing and limits; scripts/validate_created_files.py then
opens them with zipfile, python-docx, openpyxl, python-pptx and pypdf through
uv. The same sources also typecheck for iOS 17. No simulator, Keychain or user
data; uv may fetch the four Python packages into its cache the first time.

Run it under the shared compiler lock:
/usr/bin/lockf -k /tmp/woow-swiftc.lock python3 scripts/check_document_creation.py
"""
import json
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
PACKAGES = ['python-docx', 'openpyxl', 'python-pptx', 'pypdf']


def sdk(name):
    return subprocess.run(['xcrun', '--sdk', name, '--show-sdk-path'], capture_output=True, text=True, check=True).stdout.strip()


def run(command, **options):
    result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=900, **options)
    if result.returncode:
        raise SystemExit(' '.join(map(str, command[:3])) + ' failed:\n' + result.stdout + result.stderr)
    return result.stdout


def main():
    sources = [str(p) for p in sorted((ROOT / 'Sources/AssistantDocuments').glob('*.swift'))]
    renderer = str(ROOT / 'Sources/App/DocumentPDFRenderer.swift')
    harness = str(ROOT / 'scripts/CheckDocumentCreation.swift')
    mac = sdk('macosx')
    catalyst = ['-target', 'arm64-apple-ios17.0-macabi', '-sdk', mac,
                '-Fsystem', mac + '/System/iOSSupport/System/Library/Frameworks',
                '-L', mac + '/System/iOSSupport/usr/lib/swift', '-I', mac + '/System/iOSSupport/usr/lib/swift']
    counts = {}
    with tempfile.TemporaryDirectory(prefix='woow-document-creation-') as scratch:
        scratch = Path(scratch)
        for config, flags in [('Debug', ['-Onone', '-DDEBUG']), ('Release', ['-O'])]:
            build = scratch / config
            samples = scratch / (config + '-samples')
            build.mkdir()
            common = ['swiftc', '-swift-version', '5', '-parse-as-library', '-warnings-as-errors', *flags, *catalyst]
            run([*common, '-emit-module', '-emit-library', '-module-name', 'AssistantDocuments',
                 '-emit-module-path', str(build / 'AssistantDocuments.swiftmodule'),
                 '-Xlinker', '-install_name', '-Xlinker', '@rpath/libAssistantDocuments.dylib',
                 *sources, '-o', str(build / 'libAssistantDocuments.dylib')])
            run([*common, '-I', str(build), '-L', str(build), '-lAssistantDocuments',
                 '-Xlinker', '-rpath', '-Xlinker', str(build), renderer, harness, '-o', str(build / 'check')])
            made = json.loads(run([str(build / 'check'), str(samples)]))
            opened = json.loads(run(['uv', 'run', '--quiet', *[f'--with={p}' for p in PACKAGES], 'python', '-I',
                                     str(ROOT / 'scripts/validate_created_files.py'), str(samples)]).splitlines()[-1])
            counts[config] = {'swift_assertions': made['assertions'], 'files': made['files'], 'opened_checks': opened['checks']}
            print(f'{config}: {json.dumps(counts[config])}', flush=True)
        if counts['Debug'] != counts['Release']:
            raise SystemExit('Debug and Release ran different checks')
        # iOS 17: the writers as a module, then the renderer against it.
        ios = scratch / 'ios'
        ios.mkdir()
        device = ['-sdk', sdk('iphoneos'), '-target', 'arm64-apple-ios17.0']
        run(['swiftc', '-swift-version', '5', '-parse-as-library', '-warnings-as-errors', *device, '-emit-module',
             '-module-name', 'AssistantDocuments', '-emit-module-path', str(ios / 'AssistantDocuments.swiftmodule'), *sources])
        run(['swiftc', '-typecheck', '-swift-version', '5', '-parse-as-library', '-warnings-as-errors', *device,
             '-I', str(ios), renderer])
        # Swift 6's strict concurrency over the new writers.
        run(['swiftc', '-typecheck', '-swift-version', '6', '-parse-as-library', *device, *sources])
    print('PASS document creation: ' + json.dumps(counts['Release']) + '; iOS 17 typecheck; Swift 6 typecheck')


if __name__ == '__main__':
    main()
