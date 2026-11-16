#!/usr/bin/env python3
"""Apply a brand from brands/<brand>/brand.json to the WOOWTECH iOS tree.

    python3 scripts/apply_brand.py apporo              # apply; refuses a dirty tree
    python3 scripts/apply_brand.py apporo --dry-run    # list what would change
    python3 scripts/apply_brand.py apporo --allow-dirty

The steps, in order, over the files the brand's "scope" selects:

1. edits: exact replacements in one file, each found exactly "count" times.
2. phrases: exact replacements across the scope, found at least "min" times.
3. names: the product name, with a half-width space where it meets a CJK
   character, a letter or a digit, and none next to punctuation or a space.
4. regenerate: Localization/AppText.json is never paired with hand edits of
   its outputs; AppText.swift and the App.strings tables are rebuilt with
   scripts/generate_app_text.py.
5. files: copies from the brand folder (icon, provenance, evidence...), and
   remove: files that belong only to the base brand.
6. Configuration/Brand/APPLIED.json records the brand and brand.json's hash.

Deterministic: the result depends only on the base tree and brand.json.
Idempotent: on a tree that already carries this brand.json, every rule must
find nothing left to replace, and nothing is written. Atomic: every change is
computed and checked before the first file is written; a rule that does not
match the base exactly stops the run, so a changed base is never half-branded.
"""
import argparse
import fnmatch
import hashlib
import importlib.util
import json
import os
import subprocess
import sys
import unicodedata
from pathlib import Path, PurePosixPath

ROOT = Path(__file__).resolve().parents[1]
STAMP = 'Configuration/Brand/APPLIED.json'
APP_TEXT = 'Localization/AppText.json'
# The brand tooling itself names the strings it replaces; never brand it.
TOOLING = ('scripts/apply_brand.py', 'scripts/check_brand.py', 'scripts/render_brand_icon.py',
           'scripts/test_apply_brand.py', 'scripts/test_check_brand.py', 'scripts/test_render_brand_icon.py')


class BrandError(Exception):
    pass


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def _relative(value, what):
    path = PurePosixPath(value)
    if not value or path.is_absolute() or '..' in path.parts or '\\' in value:
        raise BrandError(what + ' must be a relative path inside the tree: ' + repr(value))
    return path.as_posix()


def _word(character):
    return bool(character) and unicodedata.category(character)[0] in 'LN'


def replace_name(text, find, replace):
    """Replace every `find`, adding a half-width space where the name meets a
    CJK character, a letter or a digit; none beside punctuation, a space or the
    string's edge. A letter after a backslash is an escape such as \\n."""
    pieces, index, count, tail = [], 0, 0, ''
    while True:
        at = text.find(find, index)
        if at < 0:
            break
        pieces.append(text[index:at])
        # Decide on what is already written, so two names in a row get one space.
        tail = (tail + text[index:at])[-2:]
        before = tail[-1:]
        if len(tail) == 2 and tail[0] == '\\' and before.isalpha():
            before = ''
        end = at + len(find)
        after = text[end] if end < len(text) else ''
        piece = (' ' if _word(before) else '') + replace + (' ' if _word(after) else '')
        pieces.append(piece)
        tail = (tail + piece)[-2:]
        index, count = end, count + 1
    pieces.append(text[index:])
    return ''.join(pieces), count


def _phrase_pass(text, brand):
    for phrase in brand['phrases']:
        text = text.replace(phrase['find'], phrase['replace'])
    for name in brand['names']:
        text = replace_name(text, name['find'], name['replace'])[0] if name.get('cjk_spacing') else \
            text.replace(name['find'], name['replace'])
    return text


def validate(brand, name, folder):
    if brand.get('schema_version') != 1 or brand.get('brand') != name:
        raise BrandError('brand.json: schema_version must be 1 and brand must be ' + repr(name))
    for key, kind in (('identity', dict), ('base', dict), ('scope', dict), ('edits', list), ('phrases', list),
                      ('names', list), ('files', dict), ('remove', list), ('regenerate', list)):
        if not isinstance(brand.get(key), kind):
            raise BrandError('brand.json: %s must be a %s' % (key, kind.__name__))
    if not brand['scope'].get('include') or not isinstance(brand['scope'].get('exclude', []), list):
        raise BrandError('brand.json: scope needs include (and an optional exclude list)')
    seen = set()
    for kind in ('edits', 'phrases', 'names'):
        for rule in brand[kind]:
            if not isinstance(rule.get('id'), str) or rule['id'] in seen:
                raise BrandError('brand.json: every rule needs a unique id: %r' % rule.get('id'))
            seen.add(rule['id'])
            if not isinstance(rule.get('find'), str) or not rule['find'] or not isinstance(rule.get('replace'), str):
                raise BrandError(rule['id'] + ': find must be a non-empty string and replace a string')
            if kind == 'edits':
                _relative(rule.get('file', ''), rule['id'] + ' file')
                if not isinstance(rule.get('count'), int) or rule['count'] < 1:
                    raise BrandError(rule['id'] + ': count must be a positive integer')
            else:
                if not isinstance(rule.get('min'), int) or rule['min'] < 1:
                    raise BrandError(rule['id'] + ': min must be a positive integer')
                if rule['find'] in rule['replace']:
                    raise BrandError(rule['id'] + ': replace must not contain find (it would not be idempotent)')
    for edit in brand['edits']:
        if _phrase_pass(edit['replace'], brand) != edit['replace']:
            raise BrandError(edit['id'] + ': its replacement would be changed again by a phrase or name rule')
    for target, source in brand['files'].items():
        _relative(target, 'files target')
        if not (folder / _relative(source, 'files source')).is_file():
            raise BrandError('files: missing brand file ' + source)
    for target in brand['remove']:
        _relative(target, 'remove')
    unknown = set(brand['regenerate']) - {'app_text'}
    if unknown:
        raise BrandError('regenerate: unknown step ' + ', '.join(sorted(unknown)))


def load_brand(root, name):
    folder = Path(root) / 'brands' / name
    path = folder / 'brand.json'
    if not path.is_file():
        raise BrandError('no brand.json for ' + repr(name) + ' under ' + str(folder))
    raw = path.read_bytes()
    try:
        brand = json.loads(raw.decode('utf-8'))
    except ValueError as error:
        raise BrandError('brand.json is not valid JSON: ' + str(error)) from None
    validate(brand, name, folder)
    return brand, folder, sha256(raw)


def _generator(root):
    path = Path(root) / 'scripts' / 'generate_app_text.py'
    spec = importlib.util.spec_from_file_location('brand_generate_app_text', path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def scope_files(root, scope, excluded=()):
    root = Path(root)
    chosen = set()
    for pattern in scope['include']:
        for path in root.glob(pattern):
            if path.is_file() and not path.is_symlink():
                chosen.add(path.relative_to(root).as_posix())
    skip = list(scope.get('exclude', [])) + list(TOOLING) + list(excluded)
    return sorted(r for r in chosen if not any(fnmatch.fnmatchcase(r, pattern) for pattern in skip))


def git_dirty(root):
    result = subprocess.run(['git', '-C', str(root), 'status', '--porcelain=v1', '--untracked-files=all', '--', '.'],
                            capture_output=True, text=True, timeout=60)
    if result.returncode != 0:
        raise BrandError('cannot read git status (use --allow-dirty outside a work tree): ' + result.stderr.strip())
    return [line for line in result.stdout.splitlines() if line.strip()]


def state_of(root, name, digest):
    stamp = Path(root) / STAMP
    if not stamp.is_file():
        return 'base'
    recorded = json.loads(stamp.read_text(encoding='utf-8'))
    if recorded.get('brand') != name:
        raise BrandError('this tree already carries the %r brand; start from the base tree' % recorded.get('brand'))
    if recorded.get('brand_json_sha256') != digest:
        raise BrandError('brand.json changed after it was applied here; apply it to a fresh base tree instead')
    return 'applied'


def plan(root, name):
    """Every change as {relative path: bytes, or None to delete}, the steps
    taken, and the tree's state ('base' or 'applied'). Writes nothing."""
    root = Path(root)
    brand, folder, digest = load_brand(root, name)
    state = state_of(root, name, digest)
    generated = ()
    generator = None
    if 'app_text' in brand['regenerate']:
        generator = _generator(root)
        generated = tuple(generator.outputs(json.loads((root / APP_TEXT).read_text(encoding='utf-8'))))
    paths = scope_files(root, brand['scope'], generated)
    original = {}
    for relative in paths:
        try:
            original[relative] = (root / relative).read_bytes().decode('utf-8')
        except UnicodeDecodeError:
            raise BrandError(relative + ' is in scope but is not UTF-8 text') from None
    texts = dict(original)
    steps = []

    for edit in brand['edits']:
        relative = edit['file']
        if relative not in texts:
            raise BrandError('%s: %s is not in the brand scope' % (edit['id'], relative))
        text = texts[relative]
        found, done = text.count(edit['find']), (text.count(edit['replace']) if edit['replace'] else 0)
        if state == 'base':
            if found != edit['count'] or done:
                raise BrandError('%s: expected %d of the base text in %s, found %d (and %d already replaced)'
                                 % (edit['id'], edit['count'], relative, found, done))
            texts[relative] = text.replace(edit['find'], edit['replace'])
            steps.append({'rule': edit['id'], 'file': relative, 'count': found})
        else:
            left = done * edit['replace'].count(edit['find']) if edit['replace'] else 0
            if (edit['replace'] and done != edit['count']) or found != left:
                raise BrandError('%s: %s is not in the applied state (base text %d, replaced %d)'
                                 % (edit['id'], relative, found - left, done))

    for kind in ('phrases', 'names'):
        for rule in brand[kind]:
            total, where = 0, []
            for relative in sorted(texts):
                if rule['find'] not in texts[relative]:
                    continue
                if kind == 'names' and rule.get('cjk_spacing'):
                    texts[relative], count = replace_name(texts[relative], rule['find'], rule['replace'])
                else:
                    count = texts[relative].count(rule['find'])
                    texts[relative] = texts[relative].replace(rule['find'], rule['replace'])
                total += count
                where.append(relative)
            if state == 'base' and total < rule['min']:
                raise BrandError('%s: expected at least %d of %r, found %d' % (rule['id'], rule['min'], rule['find'], total))
            if state == 'applied' and total:
                raise BrandError('%s: %d unbranded %r left in an applied tree (%s)'
                                 % (rule['id'], total, rule['find'], ', '.join(where)))
            if total:
                steps.append({'rule': rule['id'], 'count': total, 'files': where})

    changes = {relative: text.encode('utf-8') for relative, text in texts.items() if text != original[relative]}

    if generator is not None:
        catalog_text = texts[APP_TEXT] if APP_TEXT in texts else (root / APP_TEXT).read_text(encoding='utf-8')
        catalog = json.loads(catalog_text)
        if json.dumps(catalog, ensure_ascii=False, indent=2) + '\n' != catalog_text:
            raise BrandError(APP_TEXT + ' is not in its canonical JSON form after branding')
        try:
            outputs = generator.outputs(catalog)
        except ValueError as error:
            raise BrandError(APP_TEXT + ' fails generate_app_text validation after branding: ' + str(error)) from None
        rebuilt = []
        for relative, data in outputs.items():
            path = root / relative
            if not path.is_file() or path.read_bytes() != data:
                changes[relative] = data
                rebuilt.append(relative)
        if rebuilt:
            steps.append({'rule': 'regenerate app_text', 'files': sorted(rebuilt)})

    for target, source in sorted(brand['files'].items()):
        data = (folder / source).read_bytes()
        path = root / target
        if not path.is_file() or path.read_bytes() != data:
            changes[target] = data
            steps.append({'rule': 'copy', 'file': target, 'from': 'brands/%s/%s' % (name, source)})
    for target in brand['remove']:
        exists = (root / target).exists()
        if state == 'base' and not exists:
            raise BrandError('remove: %s is not in the base tree' % target)
        if exists:
            changes[target] = None
            steps.append({'rule': 'remove', 'file': target})

    if state == 'base':
        stamp = {'brand': name, 'brand_json_sha256': digest, 'base': brand['base']}
        changes[STAMP] = (json.dumps(stamp, ensure_ascii=False, indent=2) + '\n').encode('utf-8')
    elif changes:
        raise BrandError('the applied tree differs from what brand.json produces: ' + ', '.join(sorted(changes)))
    return changes, steps, state


def write(root, changes):
    """Write and remove files, the stamp last: a run that stops halfway is not
    recorded as applied."""
    root = Path(root)

    def put(relative, data):
        path = root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        temporary = path.with_name('.' + path.name + '.brand-tmp')
        temporary.write_bytes(data)
        if path.exists():
            os.chmod(temporary, path.stat().st_mode & 0o777)
        os.replace(temporary, path)

    for relative, data in sorted(changes.items()):
        if data is not None and relative != STAMP:
            put(relative, data)
    for relative, data in sorted(changes.items()):
        if data is None and (root / relative).exists():
            (root / relative).unlink()
    if changes.get(STAMP) is not None:
        put(STAMP, changes[STAMP])


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('brand')
    parser.add_argument('--root', type=Path, default=ROOT, help='the ios/ folder (default: this checkout)')
    parser.add_argument('--dry-run', action='store_true', help='show the changes without writing them')
    parser.add_argument('--allow-dirty', action='store_true', help='run even with uncommitted changes under the root')
    parser.add_argument('--json', action='store_true', help='print the result as JSON')
    args = parser.parse_args(argv)
    root = args.root.resolve()
    try:
        if not args.allow_dirty and not args.dry_run:
            dirty = git_dirty(root)
            if dirty:
                print('apply_brand: uncommitted changes under %s (commit them or pass --allow-dirty):' % root, file=sys.stderr)
                for line in dirty[:20]:
                    print('  ' + line, file=sys.stderr)
                return 2
        changes, steps, state = plan(root, args.brand)
        if not args.dry_run:
            write(root, changes)
    except BrandError as error:
        print('apply_brand: ' + str(error), file=sys.stderr)
        return 1
    summary = {'brand': args.brand, 'state': state, 'dry_run': args.dry_run,
               'changed': sorted(k for k, v in changes.items() if v is not None),
               'removed': sorted(k for k, v in changes.items() if v is None), 'steps': steps}
    if args.json:
        print(json.dumps(summary, ensure_ascii=False, indent=2))
    else:
        for step in steps:
            detail = step.get('file') or ', '.join(step.get('files', [])[:4]) + (' ...' if len(step.get('files', [])) > 4 else '')
            print('%-34s %s%s' % (step['rule'], detail, ' x%d' % step['count'] if 'count' in step else ''))
        if state == 'applied':
            print('apply_brand: %s is already applied; nothing to change' % args.brand)
        else:
            print('apply_brand: %s %s: %d files changed, %d removed' % (
                'would apply' if args.dry_run else 'applied', args.brand, len(summary['changed']), len(summary['removed'])))
    return 0


if __name__ == '__main__':
    sys.exit(main())
