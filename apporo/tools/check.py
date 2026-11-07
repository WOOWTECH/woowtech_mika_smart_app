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
assert 'releases.api=https://api.github.com/repos/WOOWTECH/apporo-assistant-releases/' in props
assert 'ui.default.language=en' in props
assert 'name.zh=Apporo Assistant' in props
for slug in ('apporo-aiot', 'apporo-platform', 'apporo-smart'):
    text = (ROOT / 'core/src/main/resources/knowledge/apps' / slug / 'APP.md').read_text()
    _, meta, body = text.split('---', 2)
    description = re.search(r'^description: (.*)$', meta, re.M).group(1)
    assert len(description) <= 60, slug
    assert len(body) <= 2500, slug
print('Apporo source contracts: OK (XML, format arguments, branding, update isolation, knowledge bounds)')
