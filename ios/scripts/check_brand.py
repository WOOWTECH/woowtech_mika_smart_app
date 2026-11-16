#!/usr/bin/env python3
"""Fail when user-visible WOOWTECH branding is left in a branded iOS tree.

Two scopes, both read-only:

- app: what ships. project.yml, the Configuration plists and privacy manifests,
  everything under Sources/ (Swift string literals, .strings, .stringsdict, JSON,
  privacy manifests) and Localization/AppText.json. Any 渥屋, woow… or
  designsmart inside a string is a finding unless an internal identifier pattern
  or a listed notice covers it (INTERNAL, NOTICES).
- tests: what the tests expect. Tests/ and scripts/ (Swift and Python string
  literals). Only the user-visible terms count there (渥屋, woowtech agent,
  WOOW TECH, designsmart, the WOOWTECH relay host and support address, the
  WOOWTECH bundle ID): test target names, environment variables and temporary
  folder prefixes are internal.

Comments and Python docstrings are not scanned; they never reach the user.

With --brand, or when Configuration/Brand/APPLIED.json names a brand, the
brand's own values from brands/<brand>/brand.json are verified as well
(bundle IDs, display name, version, team, endpoints, icon, accent).

The WOOWTECH tree itself fails this check by design. Exit status 1 on findings.
"""
import argparse
import ast
import bisect
import json
import plistlib
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
STAMP = 'Configuration/Brand/APPLIED.json'
# The brand tooling names the WOOWTECH strings it replaces; it is not part of the App.
TOOLING = frozenset({'scripts/apply_brand.py', 'scripts/check_brand.py', 'scripts/render_brand_icon.py',
                     'scripts/test_apply_brand.py', 'scripts/test_check_brand.py',
                     'scripts/test_render_brand_icon.py'})

APP_FILES = ('project.yml', 'Configuration/*.plist', 'Configuration/PrivacyManifests/**/*.xcprivacy',
             'Sources/**/*.swift', 'Sources/**/*.strings', 'Sources/**/*.stringsdict', 'Sources/**/*.json',
             'Sources/**/*.xcprivacy', 'Localization/AppText.json')
TEST_FILES = ('Tests/**/*.swift', 'scripts/*.swift', 'scripts/*.py')

APP_TERMS = re.compile(r'woow|渥屋|designsmart', re.I)
TEST_TERMS = re.compile(r'渥屋|woowtech agent|WOOW TECH|designsmart|assistant-relay\.woowtech\.io|woowtech@', re.I)
# The WOOWTECH App's own identity is never an internal identifier.
WOOWTECH_BUNDLE_ID = 'io.woowtech.assistant'

# Internal identifiers the user never sees; renaming them would orphan stored
# data or break the fixtures and tooling that use them.
INTERNAL = (
    (re.compile(r'io\.woowtech\.[A-Za-z0-9][A-Za-z0-9.\-]*'),
     'Keychain service, defaults suite, queue label or encryption context'),
    (re.compile(r'(?<![A-Za-z0-9])_{0,2}WOOW_[A-Z0-9_]*'), 'environment variable, fixture marker or masking token'),
    (re.compile(r'-Woow[A-Z][A-Za-z]*'), 'Debug launch argument'),
    (re.compile(r'__woow[A-Z][A-Za-z]*'), 'script global inside the in-app browser page'),
    (re.compile(r'woow\.task\.v1\.'), 'notification request identifier prefix'),
    (re.compile(r'woow_login_fixture'), 'Debug sign-in fixture cookie'),
    (re.compile(r'woowSearchProbe'), 'search template validation probe'),
    (re.compile(r'WoowSpeech-'), 'multipart boundary prefix'),
)
# Target, scheme and module names (project.yml only).
PROJECT_INTERNAL = ((re.compile(r'WoowAssistant[A-Za-z]*'), 'target, scheme or module name'),)
# Notices that must keep naming WOOW TECH, as the Android Apporo flavor does.
NOTICES = {
    'Sources/AssistantSkills/Resources/MikaBundledSkills.json': (
        ('adaptation: WOOW iOS text-only adaptation', 'Apache-2.0 4(b) notice: WOOW TECH changed the upstream skill'),
        ('WOOW 將此版本改寫為 iOS 文字參考', 'Apache-2.0 4(b) notice: WOOW TECH changed the upstream skill'),
    ),
    'Sources/App/MikaAboutInfo.swift': (
        ('本 App 由 WOOW TECH CO., LTD. 修改與發行。', 'developer credit (Licenses page)'),
        ('This app is modified and distributed by WOOW TECH CO., LTD.', 'developer credit (Licenses page)'),
    ),
}
TEST_NOTICES = {
    'scripts/CheckChatAttachmentReader.swift': (('渥屋', 'CJK text extraction sample, not branding'),),
    'scripts/test_ai_safety_and_reports.py': (
        ('Mika|Apporo|woowtech|Woow|渥屋', 'negative assertion: English report text names no app'),),
}


class Finding(dict):
    """scope, file, where, term, text and why."""


def _line_of(starts, index):
    return bisect.bisect_right(starts, index) + 1


def _skip_block_comment(text, i):
    depth, n = 0, len(text)
    while i < n:
        if text.startswith('/*', i):
            depth += 1; i += 2
        elif text.startswith('*/', i):
            depth -= 1; i += 2
            if depth == 0:
                return i
        else:
            i += 1
    return n


def _scan_code(text, i, out, interpolation):
    n, depth = len(text), 0
    while i < n:
        c = text[i]
        if text.startswith('//', i):
            end = text.find('\n', i)
            i = n if end < 0 else end
            continue
        if text.startswith('/*', i):
            i = _skip_block_comment(text, i)
            continue
        if c in '#"':
            j = i
            while j < n and text[j] == '#':
                j += 1
            if j < n and text[j] == '"':
                i = _scan_string(text, i, j, j - i, out)
                continue
            i = max(j, i + 1)
            continue
        if interpolation:
            if c == '(':
                depth += 1
            elif c == ')':
                if depth == 0:
                    return i + 1
                depth -= 1
        i += 1
    return i


def _scan_string(text, start, quote, hashes, out):
    n = len(text)
    multiline = text.startswith('"""', quote)
    k = quote + (3 if multiline else 1)
    close = ('"""' if multiline else '"') + '#' * hashes
    escape = '\\' + '#' * hashes
    parts, segment = [], k
    while k < n:
        if text.startswith(close, k):
            parts.append(text[segment:k])
            out.append((start, ''.join(parts)))
            return k + len(close)
        if text.startswith(escape, k):
            after = k + len(escape)
            if after < n and text[after] == '(':
                parts.append(text[segment:k])
                parts.append('…')
                k = _scan_code(text, after + 1, out, True)
                segment = k
                continue
            k = after + 1
            continue
        if not multiline and text[k] == '\n':
            break
        k += 1
    parts.append(text[segment:k])
    out.append((start, ''.join(parts)))
    return k


def swift_strings(text):
    """(line, content) of every string literal outside comments, interpolated
    literals included. Escapes stay as written; an interpolation reads as …."""
    found = []
    _scan_code(text, 0, found, False)
    starts = [m.end() for m in re.finditer('\n', text)]
    return [(_line_of(starts, index), value) for index, value in sorted(found)]


def python_strings(text, filename='<string>'):
    """(line, value) of every str constant except docstrings."""
    tree = ast.parse(text, filename=filename)
    docstrings = {id(node.value) for node in ast.walk(tree)
                  if isinstance(node, ast.Expr) and isinstance(node.value, ast.Constant)
                  and isinstance(node.value.value, str)}
    rows = []
    for node in ast.walk(tree):
        if isinstance(node, ast.Constant) and isinstance(node.value, str) and id(node) not in docstrings:
            rows.append((node.lineno, node.value))
    return sorted(rows)


def _walk(value, path, rows):
    if isinstance(value, dict):
        for key in value:
            _walk(value[key], path + '/' + str(key), rows)
    elif isinstance(value, list):
        for index, item in enumerate(value):
            _walk(item, f'{path}[{index}]', rows)
    elif isinstance(value, str):
        rows.append((path or '/', value))


def json_strings(text):
    rows = []
    _walk(json.loads(text), '', rows)
    return rows


def plist_strings(data):
    rows = []
    _walk(plistlib.loads(data), '', rows)
    return rows


def yaml_lines(text):
    """project.yml: every line without its comment (the file has no # in values)."""
    rows = []
    for number, line in enumerate(text.splitlines(), 1):
        value = line.split('#', 1)[0].rstrip()
        if value.strip():
            rows.append((number, value))
    return rows


def strings_of(relative, data):
    if relative.endswith('.swift') or relative.endswith('.strings'):
        return swift_strings(data.decode('utf-8'))
    if relative.endswith('.py'):
        return python_strings(data.decode('utf-8'), relative)
    if relative.endswith('.json'):
        return json_strings(data.decode('utf-8'))
    if relative.endswith(('.plist', '.stringsdict', '.xcprivacy')):
        return plist_strings(data)
    if relative.endswith('.yml'):
        return yaml_lines(data.decode('utf-8'))
    raise ValueError('no reader for ' + relative)


def files(root, patterns):
    chosen = set()
    for pattern in patterns:
        for path in root.glob(pattern):
            if path.is_file() and not path.is_symlink():
                relative = path.relative_to(root).as_posix()
                if relative not in TOOLING and '/.build/' not in '/' + relative:
                    chosen.add(relative)
    return sorted(chosen)


def _covered(value, allowances):
    spans = []
    for pattern, _ in allowances:
        if isinstance(pattern, str):
            start = value.find(pattern)
            while start >= 0:
                spans.append((start, start + len(pattern)))
                start = value.find(pattern, start + 1)
        else:
            spans.extend(match.span() for match in pattern.finditer(value))
    return spans


def string_findings(scope, relative, where, value, terms, allowances):
    rows = []
    if value.strip() == WOOWTECH_BUNDLE_ID:
        rows.append(Finding(scope=scope, file=relative, where=where, term=WOOWTECH_BUNDLE_ID, text=value,
                            why='the WOOWTECH App bundle ID'))
        return rows
    spans = _covered(value, allowances)
    for match in terms.finditer(value):
        if not any(start <= match.start() and match.end() <= end for start, end in spans):
            rows.append(Finding(scope=scope, file=relative, where=where, term=match.group(0),
                                text=value if len(value) <= 160 else value[:157] + '...',
                                why='user-visible WOOWTECH branding'))
    return rows


def scan(root=ROOT):
    """Every finding in both scopes, as a list of Finding."""
    root = Path(root)
    rows = []
    for relative in files(root, APP_FILES):
        if relative == 'project.yml':
            allowances = PROJECT_INTERNAL
        else:
            allowances = INTERNAL + NOTICES.get(relative, ())
        for where, value in strings_of(relative, (root / relative).read_bytes()):
            rows.extend(string_findings('app', relative, where, value, APP_TERMS, allowances))
    for relative in files(root, TEST_FILES):
        for where, value in strings_of(relative, (root / relative).read_bytes()):
            rows.extend(string_findings('tests', relative, where, value, TEST_TERMS, TEST_NOTICES.get(relative, ())))
    return rows


def _rgb(hex_color):
    value = hex_color.lstrip('#')
    return tuple(int(value[i:i + 2], 16) for i in (0, 2, 4))


def conformance(root, brand_dir):
    """The brand's own values, as (check, passed) pairs."""
    root, brand_dir = Path(root), Path(brand_dir)
    brand = json.loads((brand_dir / 'brand.json').read_text(encoding='utf-8'))
    identity = brand['identity']

    def read(relative):
        path = root / relative
        return path.read_text(encoding='utf-8') if path.is_file() else ''

    project = read('project.yml')
    bundle_ids = re.findall(r'^\s*PRODUCT_BUNDLE_IDENTIFIER:\s*(\S+)\s*$', project, re.M)
    names = {e['key']: e['translations'] for e in json.loads(read('Localization/AppText.json') or '{"entries": []}')['entries']}
    light, dark = _rgb(identity['accent']['light']), _rgb(identity['accent']['dark'])
    accent_line = 'var accent: Color { dark ? rgb(%d, %d, %d) : rgb(%d, %d, %d) }' % (dark + light)
    icon = (brand_dir / brand['icon']['png']).read_bytes() if (brand_dir / brand['icon']['png']).is_file() else None
    checks = [
        ('project.yml bundleIdPrefix is ' + identity['bundle_id_prefix'],
         re.search(r'^\s*bundleIdPrefix:\s*' + re.escape(identity['bundle_id_prefix']) + r'\s*$', project, re.M) is not None),
        ('every PRODUCT_BUNDLE_IDENTIFIER is under ' + identity['bundle_id'],
         bool(bundle_ids) and all(b == identity['bundle_id'] or b.startswith(identity['bundle_id'] + '.') for b in bundle_ids)),
        ('the App target is ' + identity['bundle_id'], bundle_ids.count(identity['bundle_id']) == 1),
        ('display name is ' + identity['display_name'],
         re.search(r'^\s*INFOPLIST_KEY_CFBundleDisplayName:\s*' + re.escape(identity['display_name']) + r'\s*$', project, re.M) is not None),
        ('MARKETING_VERSION is ' + identity['marketing_version'],
         re.search(r'^\s*MARKETING_VERSION:\s*"' + re.escape(identity['marketing_version']) + r'"\s*$', project, re.M) is not None),
        ('CURRENT_PROJECT_VERSION is ' + identity['build'],
         re.search(r'^\s*CURRENT_PROJECT_VERSION:\s*"' + re.escape(identity['build']) + r'"\s*$', project, re.M) is not None),
        ('English home screen name is ' + identity['display_name'],
         '"CFBundleDisplayName" = "%s";' % identity['display_name'] in read('Sources/App/Resources/en.lproj/InfoPlist.strings')),
        ('App Store export team is ' + identity['team_id'],
         '<key>teamID</key>\n\t<string>%s</string>' % identity['team_id'] in read('Configuration/ExportOptions-AppStore.plist')),
        ('release script expects ' + identity['bundle_id'],
         'BUNDLE_ID = "%s"' % identity['bundle_id'] in read('scripts/release_ios.py')),
        ('AI reports go to ' + identity['ai_report_endpoint'],
         'URL(string: "%s")!' % identity['ai_report_endpoint'] in read('Sources/App/AIResponseReportDelivery.swift')),
        ('privacy policy is ' + identity['privacy_policy_url'],
         'URL(string: "%s")!' % identity['privacy_policy_url'] in read('Sources/App/MikaAboutInfo.swift')),
        ('feedback goes to ' + identity['support_email'], identity['support_email'] in read('Sources/App/MikaAboutInfo.swift')),
        ('the App title is ' + identity['display_name'] + ' in every language',
         set(names.get('shell.brandTitle', {}).values()) == {identity['display_name']}),
        ('the accent is %s / %s' % (identity['accent']['light'], identity['accent']['dark']),
         accent_line in read('Sources/App/ContentView.swift')),
        ('AppIcon is the brand icon',
         icon is not None and (root / 'Sources/App/Assets.xcassets/AppIcon.appiconset/AppIcon.png').is_file()
         and (root / 'Sources/App/Assets.xcassets/AppIcon.appiconset/AppIcon.png').read_bytes() == icon),
        ('About icon is the brand icon',
         icon is not None and (root / 'Sources/App/Assets.xcassets/AboutBrandIcon.imageset/AppIcon.png').is_file()
         and (root / 'Sources/App/Assets.xcassets/AboutBrandIcon.imageset/AppIcon.png').read_bytes() == icon),
    ]
    return checks


def applied_brand(root):
    stamp = Path(root) / STAMP
    if not stamp.is_file():
        return None
    return json.loads(stamp.read_text(encoding='utf-8')).get('brand')


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--root', type=Path, default=ROOT, help='the ios/ folder to check')
    parser.add_argument('--brand', help='also verify this brand\'s values (default: the applied brand, if any)')
    parser.add_argument('--json', action='store_true', help='print the result as JSON')
    args = parser.parse_args(argv)
    root = args.root.resolve()
    rows = scan(root)
    brand = args.brand or applied_brand(root)
    checks = conformance(root, root / 'brands' / brand) if brand else []
    failed = [name for name, passed in checks if not passed]
    if args.json:
        print(json.dumps({'brand': brand, 'findings': rows, 'conformance': [{'check': n, 'passed': p} for n, p in checks]},
                         ensure_ascii=False, indent=2))
    else:
        for row in rows:
            print('FAIL [%s] %s:%s: %r in %r (%s)' % (row['scope'], row['file'], row['where'], row['term'], row['text'], row['why']))
        for name, passed in checks:
            print(('PASS' if passed else 'FAIL') + ' [brand] ' + name)
        app = sum(r['scope'] == 'app' for r in rows)
        print('check_brand: %d app findings, %d test findings, %d/%d brand checks passed%s'
              % (app, len(rows) - app, len(checks) - len(failed), len(checks), ' (' + brand + ')' if brand else ''))
    return 1 if rows or failed else 0


if __name__ == '__main__':
    sys.exit(main())
