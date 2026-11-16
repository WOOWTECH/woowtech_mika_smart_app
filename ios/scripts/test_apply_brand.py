"""apply_brand.py: deterministic, idempotent, atomic, and in step with brands/apporo/brand.json."""
import contextlib
import io
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

import apply_brand
import check_brand

ROOT = Path(__file__).resolve().parents[1]

DEMO = {
    'schema_version': 1, 'brand': 'demo', 'identity': {}, 'base': {'brand': 'base', 'revision': '0'},
    'scope': {'include': ['project.yml', 'Sources/**/*.swift', 'scripts/*.py', 'scripts/*.swift'], 'exclude': []},
    'edits': [{'id': 'prefix', 'file': 'project.yml', 'find': '  bundleIdPrefix: io.base\n',
               'replace': '  bundleIdPrefix: com.demo\n', 'count': 1}],
    'phrases': [{'id': 'ua', 'find': 'WoowAssistant/0.1', 'replace': 'DemoAssistant/0.1', 'min': 1},
                {'id': 'en', 'find': 'woowtech agent', 'replace': 'Demo App', 'min': 1}],
    'names': [{'id': 'zh', 'find': '渥屋助理', 'replace': 'Demo App', 'min': 1, 'cjk_spacing': True}],
    'regenerate': [], 'files': {'Sources/App/new.txt': 'files/new.txt'}, 'remove': ['scripts/old.swift'],
}
BASE = {
    'project.yml': 'options:\n  bundleIdPrefix: io.base\n',
    'Sources/App/A.swift': 'let a = "開啟渥屋助理查看結果。"\nlet b = "woowtech agent can help"\n// 渥屋助理 comment\n',
    'Sources/App/B.swift': 'let c = "WoowAssistant/0.1"\n',
    'scripts/check_brand.py': 'X = "渥屋助理"\n',
    'scripts/old.swift': 'print("old")\n',
    'brands/demo/files/new.txt': 'new\n',
}


class DemoTree:
    def __init__(self, brand=DEMO, files=BASE):
        self.folder = tempfile.TemporaryDirectory(prefix='apply-brand-')
        self.root = Path(self.folder.name)
        for relative, content in dict(files, **{'brands/demo/brand.json': json.dumps(brand, ensure_ascii=False)}).items():
            self.write(relative, content)

    def write(self, relative, content):
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(content if isinstance(content, bytes) else content.encode('utf-8'))

    def read(self, relative):
        return (self.root / relative).read_text(encoding='utf-8')

    def snapshot(self):
        return {p.relative_to(self.root).as_posix(): p.read_bytes() for p in self.root.rglob('*') if p.is_file()}

    def apply(self):
        changes, steps, state = apply_brand.plan(self.root, 'demo')
        apply_brand.write(self.root, changes)
        return changes, steps, state

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        self.folder.cleanup()


def quiet(function, *args):
    with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
        return function(*args)


class NameSpacingTests(unittest.TestCase):
    def test_spaces_beside_cjk_and_words_never_beside_punctuation(self):
        cases = {
            '開啟渥屋助理查看結果。': '開啟 Apporo Assistant 查看結果。',
            '你好，我是渥屋助理': '你好，我是 Apporo Assistant',
            '引用渥屋助理：%1$@': '引用 Apporo Assistant：%1$@',
            '"渥屋助理在等你：%1$@"': '"Apporo Assistant 在等你：%1$@"',
            '("渥屋助理")': '("Apporo Assistant")',
            '路徑：設定 › 通知 › 渥屋助理': '路徑：設定 › 通知 › Apporo Assistant',
            '時，渥屋助理才會': '時，Apporo Assistant 才會',
            '「渥屋助理」': '「Apporo Assistant」',
            'app渥屋助理2': 'app Apporo Assistant 2',
            '第一行\\n渥屋助理會': '第一行\\nApporo Assistant 會',
            '渥屋助理渥屋助理': 'Apporo Assistant Apporo Assistant',
        }
        for before, after in cases.items():
            with self.subTest(before=before):
                self.assertEqual(apply_brand.replace_name(before, '渥屋助理', 'Apporo Assistant'), (after, before.count('渥屋助理')))


class ApplyTests(unittest.TestCase):
    def test_apply_then_reapply_is_a_no_op(self):
        with DemoTree() as tree:
            changes, _, state = tree.apply()
            self.assertEqual(state, 'base')
            self.assertEqual(tree.read('project.yml'), 'options:\n  bundleIdPrefix: com.demo\n')
            self.assertEqual(tree.read('Sources/App/A.swift'),
                             'let a = "開啟 Demo App 查看結果。"\nlet b = "Demo App can help"\n// Demo App comment\n')
            self.assertEqual(tree.read('Sources/App/B.swift'), 'let c = "DemoAssistant/0.1"\n')
            self.assertEqual(tree.read('scripts/check_brand.py'), 'X = "渥屋助理"\n', 'tooling is never branded')
            self.assertEqual(tree.read('Sources/App/new.txt'), 'new\n')
            self.assertFalse((tree.root / 'scripts/old.swift').exists())
            stamp = json.loads(tree.read(apply_brand.STAMP))
            self.assertEqual(stamp['brand'], 'demo')
            self.assertEqual(stamp['brand_json_sha256'], apply_brand.sha256((tree.root / 'brands/demo/brand.json').read_bytes()))
            before = tree.snapshot()
            changes, steps, state = tree.apply()
            self.assertEqual((changes, steps, state), ({}, [], 'applied'))
            self.assertEqual(tree.snapshot(), before)

    def test_same_input_same_output(self):
        with DemoTree() as first, DemoTree() as second:
            first.apply()
            second.apply()
            self.assertEqual(first.snapshot(), second.snapshot())

    def test_dry_run_writes_nothing(self):
        with DemoTree() as tree:
            before = tree.snapshot()
            self.assertEqual(quiet(apply_brand.main, ['demo', '--root', str(tree.root), '--dry-run']), 0)
            self.assertEqual(tree.snapshot(), before)

    def test_a_changed_base_stops_before_anything_is_written(self):
        for relative, content in [('project.yml', 'options:\n  bundleIdPrefix: io.other\n'),
                                  ('Sources/App/B.swift', 'let c = "Other/0.1"\n')]:
            with self.subTest(relative=relative), DemoTree() as tree:
                tree.write(relative, content)
                before = tree.snapshot()
                with self.assertRaises(apply_brand.BrandError):
                    apply_brand.plan(tree.root, 'demo')
                self.assertEqual(quiet(apply_brand.main, ['demo', '--root', str(tree.root), '--allow-dirty']), 1)
                self.assertEqual(tree.snapshot(), before)

    def test_applied_tree_with_new_base_text_is_refused(self):
        with DemoTree() as tree:
            tree.apply()
            tree.write('Sources/App/B.swift', 'let c = "DemoAssistant/0.1"\nlet d = "渥屋助理"\n')
            with self.assertRaisesRegex(apply_brand.BrandError, 'unbranded'):
                apply_brand.plan(tree.root, 'demo')

    def test_changed_brand_json_or_other_brand_is_refused(self):
        with DemoTree() as tree:
            tree.apply()
            tree.write('brands/demo/brand.json', json.dumps(dict(DEMO, remove=[]), ensure_ascii=False))
            with self.assertRaisesRegex(apply_brand.BrandError, 'changed after it was applied'):
                apply_brand.plan(tree.root, 'demo')
            tree.write(apply_brand.STAMP, json.dumps({'brand': 'other'}))
            with self.assertRaisesRegex(apply_brand.BrandError, 'already carries'):
                apply_brand.plan(tree.root, 'demo')

    def test_invalid_rules_are_rejected(self):
        bad = [
            dict(DEMO, phrases=[{'id': 'x', 'find': 'agent', 'replace': 'agent two', 'min': 1}]),
            dict(DEMO, edits=[dict(DEMO['edits'][0], replace='  bundleIdPrefix: woowtech agent\n')]),
            dict(DEMO, files={'../outside.txt': 'files/new.txt'}),
            dict(DEMO, files={'Sources/x.txt': 'files/missing.txt'}),
            dict(DEMO, edits=[dict(DEMO['edits'][0], id='ua')]),
            dict(DEMO, regenerate=['icons']),
            dict(DEMO, brand='other'),
        ]
        for brand in bad:
            with self.subTest(brand=brand), DemoTree(brand=brand) as tree:
                with self.assertRaises(apply_brand.BrandError):
                    apply_brand.plan(tree.root, 'demo')

    @unittest.skipUnless(shutil.which('git'), 'git is not installed')
    def test_a_dirty_tree_is_refused_unless_allowed(self):
        with DemoTree() as tree:
            git = ['git', '-C', str(tree.root), '-c', 'user.name=t', '-c', 'user.email=t@example.invalid']
            subprocess.run(git + ['init', '-q'], check=True)
            subprocess.run(git + ['add', '-A'], check=True)
            subprocess.run(git + ['commit', '-q', '-m', 'base'], check=True)
            tree.write('Sources/App/B.swift', 'let c = "WoowAssistant/0.1"\nlet e = 1\n')
            self.assertEqual(quiet(apply_brand.main, ['demo', '--root', str(tree.root)]), 2)
            self.assertEqual(tree.read('project.yml'), BASE['project.yml'])
            self.assertEqual(quiet(apply_brand.main, ['demo', '--root', str(tree.root), '--allow-dirty']), 0)
            self.assertEqual(tree.read('project.yml'), 'options:\n  bundleIdPrefix: com.demo\n')

    def test_app_text_outputs_are_regenerated_not_edited(self):
        catalog = {'schema_version': 1, 'fallback': 'zh-Hant', 'languages': ['zh-Hant', 'en'], 'entries': [
            {'case': 'brandTitle', 'key': 'shell.brandTitle', 'parameters': [],
             'translations': {'zh-Hant': '渥屋助理', 'en': 'woowtech agent'}},
            {'case': 'quote', 'key': 'chat.quote', 'parameters': [{'name': 'text', 'type': 'String'}],
             'translations': {'zh-Hant': '引用渥屋助理：%1$@', 'en': 'Quoting woowtech agent: %1$@'}}]}
        brand = dict(DEMO, scope={'include': ['Localization/AppText.json', 'Sources/**/*.swift', 'Sources/**/*.strings'],
                                  'exclude': []}, edits=[], phrases=[DEMO['phrases'][1]], files={}, remove=[],
                     regenerate=['app_text'])
        files = {'scripts/generate_app_text.py': (ROOT / 'scripts/generate_app_text.py').read_bytes(),
                 'Localization/AppText.json': json.dumps(catalog, ensure_ascii=False, indent=2) + '\n',
                 'Sources/App/AppText.swift': '// stale 渥屋助理\n',
                 'Sources/App/Resources/en.lproj/App.strings': '"x" = "woowtech agent";\n'}
        with DemoTree(brand=brand, files=files) as tree:
            tree.apply()
            branded = json.loads(tree.read('Localization/AppText.json'))
            self.assertEqual(branded['entries'][1]['translations'], {'zh-Hant': '引用 Demo App：%1$@', 'en': 'Quoting Demo App: %1$@'})
            generator = apply_brand._generator(tree.root)
            for relative, data in generator.outputs(branded).items():
                self.assertEqual((tree.root / relative).read_bytes(), data, relative)
            self.assertEqual(apply_brand.plan(tree.root, 'demo')[0], {})


class LiveBrandTests(unittest.TestCase):
    """brands/apporo/brand.json against this checkout: the WOOWTECH base or the branded tree."""

    def test_brand_json_is_in_step_with_this_tree(self):
        changes, _, state = apply_brand.plan(ROOT, 'apporo')
        if state == 'applied':
            self.assertEqual(changes, {})
        else:
            self.assertIn(apply_brand.STAMP, changes)

    def test_the_base_tree_brands_cleanly(self):
        if apply_brand.plan(ROOT, 'apporo')[2] == 'applied':
            self.skipTest('already branded; the result is checked by test_check_brand')
        with tempfile.TemporaryDirectory(prefix='apply-brand-live-') as folder:
            copy = Path(folder) / 'ios'
            shutil.copytree(ROOT, copy, ignore=shutil.ignore_patterns('docs', '.build', '__pycache__', 'build', 'DerivedData'))
            changes, _, _ = apply_brand.plan(copy, 'apporo')
            apply_brand.write(copy, changes)
            self.assertEqual(check_brand.scan(copy), [])
            self.assertEqual([n for n, ok in check_brand.conformance(copy, copy / 'brands/apporo') if not ok], [])
            self.assertEqual(apply_brand.plan(copy, 'apporo')[:3:2], ({}, 'applied'))


if __name__ == '__main__':
    unittest.main()
