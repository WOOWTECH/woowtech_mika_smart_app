#!/usr/bin/env python3
"""Exercise fixture isolation and prove test-only symbols are absent in Release."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
config = root / 'Sources/App/ChatAttachmentComposerFixtureConfiguration.swift'
fixture = root / 'Sources/App/UITestModelFixture.swift'
checks = root / 'Tests/AttachmentComposerStandalone/FixtureConfigurationChecks.swift'
with tempfile.TemporaryDirectory(prefix='woow-attachment-composer-fixture-') as directory:
    out = Path(directory)
    binary = out / 'checks'
    subprocess.run(['swiftc', '-swift-version', '5', '-warnings-as-errors', '-DDEBUG', '-parse-as-library',
                    str(config), str(checks), '-o', str(binary)], check=True, timeout=60)
    subprocess.run([str(binary)], check=True, timeout=30)
    for index, source in enumerate((config, fixture)):
        obj = out / ('release' + str(index) + '.o')
        subprocess.run(['swiftc', '-swift-version', '5', '-warnings-as-errors', '-parse-as-library',
                        '-emit-object', str(source), '-o', str(obj)], check=True, timeout=60)
        data = obj.read_bytes()
        for forbidden in (b'ChatAttachmentComposerUITestFixture', b'-UITestAttachmentComposer',
                          b'Synthetic attachment for offline UI test'):
            if forbidden in data: raise SystemExit('Release contains an attachment fixture marker')
    print('Attachment composer fixture excluded from Release objects')
