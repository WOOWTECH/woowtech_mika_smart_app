#!/usr/bin/env python3
"""Check the packaged identity rather than assuming the flavor merged correctly."""
import os
from pathlib import Path
import subprocess
import sys
import zipfile

sdk = Path(os.environ.get('ANDROID_HOME') or os.environ.get('ANDROID_SDK_ROOT') or Path.home() / 'Library/Android/sdk')
tools = sorted(sdk.glob('build-tools/*/aapt2'))
if not tools:
    raise SystemExit('aapt2 is required')
for argument in sys.argv[1:]:
    apk = Path(argument)
    badging = subprocess.check_output([str(tools[-1]), 'dump', 'badging', str(apk)], text=True)
    assert "package: name='com.apporo.assistant'" in badging, 'wrong package'
    assert "application-label:'Apporo Assistant'" in badging, 'wrong default name'
    for line in badging.splitlines():
        if line.startswith('application-label'):
            assert line.endswith(":'Apporo Assistant'"), line
    with zipfile.ZipFile(apk) as archive:
        props = archive.read('brand.properties').decode('utf-8')
        assert 'name=Apporo Assistant' in props
        assert '/apporo-assistant-releases/releases/latest' in props
        assert 'ui.default.language=en' in props
        assert 'accent.dark.on=FF1C1C1E' in props
    print(apk.name + ': Apporo package, localized labels, runtime identity and update channel OK')
