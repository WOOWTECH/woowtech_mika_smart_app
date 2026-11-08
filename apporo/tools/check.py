#!/usr/bin/env python3
"""Source contracts for an independent Apporo build; no network or credentials."""
from pathlib import Path
import re
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
RES = ROOT / 'app/src/apporo/res'
upstream = {}
for p in (ROOT / 'app/src/main/res/values').glob('strings*.xml'):
    for e in ET.parse(p).getroot():
        if e.tag == 'string':
            upstream[e.attrib['name']] = ''.join(e.itertext())
placeholder = re.compile(r'%(?:\d+\$)?[dsf]')
for p in RES.rglob('*.xml'):
    tree = ET.parse(p)
    if not p.name.startswith('strings'): continue
    for e in tree.getroot():
        if e.tag != 'string': continue
        key, body = e.attrib['name'], ''.join(e.itertext())
        if key.startswith('woow_lic_'): continue  # Shared OSS resource identifiers.
        assert key in upstream or key == 'app_name', (p, key, 'unknown override')
        if key in upstream:
            assert sorted(placeholder.findall(body)) == sorted(placeholder.findall(upstream[key])), (p, key, 'format mismatch')
        assert not re.search(r'渥屋|woowtech agent|io\.woowtech\.agent|6183[Ff][Cc]', body), (p, key, 'brand leak')
props = (ROOT / 'app/src/apporo/resources/brand.properties').read_text()
android = '{http://schemas.android.com/apk/res/android}'
permissions = {e.attrib[android + 'name']: e.attrib.get(android + 'maxSdkVersion')
               for e in ET.parse(ROOT / 'app/src/apporo/AndroidManifest.xml').getroot()
               if e.tag == 'uses-permission'}
assert permissions == {
    'android.permission.USE_EXACT_ALARM': None,
    'android.permission.SCHEDULE_EXACT_ALARM': '32',
}, 'Apporo exact-alarm permissions must match the woow.4 direct APK'
assert 'releases.api=https://api.github.com/repos/WOOWTECH/apporo-assistant-releases/' in props
assert 'ui.default.language=en' in props
assert 'name.zh=Apporo Assistant' in props
zh = {e.attrib['name']: ''.join(e.itertext()) for e in ET.parse(RES / 'values-b+zh+Hant/strings_apporo.xml').getroot() if e.tag == 'string'}
access_title = next(''.join(e.itertext()) for e in ET.parse(ROOT / 'app/src/main/res/values-b+zh+Hant/strings_appaccess.xml').getroot() if e.attrib.get('name') == 'appaccess_title')
for key in ('task_app_blocked', 'task_app_access_unavailable', 'err_app_unavailable'):
    assert access_title in zh[key], (key, 'recovery guidance must match the settings page title')
for slug in ('apporo-aiot', 'apporo-platform', 'apporo-smart'):
    text = (ROOT / 'core/src/main/resources/knowledge/apps' / slug / 'APP.md').read_text()
    _, meta, body = text.split('---', 2)
    description = re.search(r'^description: (.*)$', meta, re.M).group(1)
    assert len(description) <= 60, slug
    assert len(body) <= 2500, slug
def luminance(rgb):
    values = [int(rgb[i:i+2], 16) / 255 for i in (0, 2, 4)]
    return sum(w * (v / 12.92 if v <= .04045 else ((v + .055) / 1.055) ** 2.4)
               for w, v in zip((.2126, .7152, .0722), values))
properties = dict(line.split('=', 1) for line in props.splitlines() if '=' in line and not line.startswith('#'))
for theme in ('light', 'dark'):
    a, b = sorted(luminance(properties[k][-6:]) for k in (f'accent.{theme}', f'accent.{theme}.on'))
    assert (b + .05) / (a + .05) >= 4.5, (theme, 'button text contrast')
print('Apporo source contracts: OK (XML, format arguments, branding, update isolation, knowledge bounds)')
