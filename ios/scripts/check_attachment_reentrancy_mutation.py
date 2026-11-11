#!/usr/bin/env python3
"""Prove synchronous discard and replace probes reject a stale-task mutation."""
from pathlib import Path
import os
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
presenter = root / 'Sources/AssistantAttachments/ChatAttachmentPresenter.swift'
source = presenter.read_text()
guard = '''        guard generation == id, session === next else {
            Task.detached { reader.cancel() }
            Task { await next.discard() }
            return
        }
'''
if source.count(guard) != 1:
    raise SystemExit('Expected exactly one generation guard to mutate')

with tempfile.TemporaryDirectory(prefix='woow-attachment-mutation-') as folder:
    out = Path(folder)
    models = sorted((root / 'Sources/AssistantModels').glob('*.swift'))
    attachments = sorted((root / 'Sources/AssistantAttachments').glob('*.swift'))
    common = ['swiftc', '-warnings-as-errors', '-parse-as-library', '-enable-testing', '-emit-library', '-emit-module']
    subprocess.run(common + ['-module-name', 'AssistantModels', *map(str, models), '-emit-module-path', str(out / 'AssistantModels.swiftmodule'), '-o', str(out / 'libAssistantModels.dylib')], check=True, timeout=120)
    for variant in ('fixed', 'mutated'):
        selected = attachments
        if variant == 'mutated':
            replacement = out / 'ChatAttachmentPresenter.swift'
            replacement.write_text(source.replace(guard, '', 1))
            selected = [replacement if item == presenter else item for item in attachments]
        subprocess.run(common + ['-module-name', 'AssistantAttachments', '-I', str(out), '-L', str(out), '-lAssistantModels', *map(str, selected), '-emit-module-path', str(out / 'AssistantAttachments.swiftmodule'), '-o', str(out / 'libAssistantAttachments.dylib')], check=True, timeout=120)
        binary = out / ('check-' + variant)
        subprocess.run(['swiftc', '-warnings-as-errors', '-parse-as-library', '-I', str(out), '-L', str(out), '-lAssistantModels', '-lAssistantAttachments', str(root / 'scripts/CheckChatAttachmentPresenter.swift'), '-o', str(binary)], check=True, timeout=120)
        for scenario, marker in [('discard', 'STALE_DISCARD_TASK_SCHEDULED'), ('replace', 'STALE_REPLACEMENT_TASK_SCHEDULED')]:
            env = {**os.environ, 'DYLD_LIBRARY_PATH': str(out), 'WOOW_ATTACHMENT_REENTRANCY_PROBE': scenario, 'SWIFT_BACKTRACE': 'disable'}
            result = subprocess.run([str(binary), folder], env=env, capture_output=True, text=True, timeout=20)
            if variant == 'fixed' and result.returncode != 0:
                raise SystemExit('Fixed ' + scenario + ' probe failed: ' + result.stderr[-2000:])
            if variant == 'mutated' and (result.returncode == 0 or marker not in result.stderr + result.stdout):
                raise SystemExit('Mutation was not rejected by ' + scenario + ' probe: ' + result.stderr[-2000:])
            print(variant + ' ' + scenario + (': passed' if variant == 'fixed' else ': rejected at ' + marker))
