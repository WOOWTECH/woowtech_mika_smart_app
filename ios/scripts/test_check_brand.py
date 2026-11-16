"""check_brand.py: what counts as leftover WOOWTECH branding, and what does not."""
import json
from pathlib import Path
import plistlib
import tempfile
import unittest

import check_brand

ROOT = Path(__file__).resolve().parents[1]


def tree(files):
    """A temporary ios/ folder with {relative path: text or bytes}."""
    folder = tempfile.TemporaryDirectory(prefix='check-brand-')
    root = Path(folder.name)
    for relative, content in files.items():
        path = root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(content if isinstance(content, bytes) else content.encode('utf-8'))
    return folder, root


class SwiftLexerTests(unittest.TestCase):
    def values(self, source):
        return [value for _, value in check_brand.swift_strings(source)]

    def test_comments_are_skipped_and_slashes_in_strings_are_not_comments(self):
        source = ('// "in a line comment"\n/* "block" /* "nested" */ "still comment" */\n'
                  'let url = "https://example.com/a" // "trailing"\n/// "doc"\nlet b = "two"\n')
        self.assertEqual(self.values(source), ['https://example.com/a', 'two'])

    def test_escapes_multiline_and_raw_strings(self):
        source = ('let a = "say \\"hi\\" \\\\"\n'
                  'let b = """\n    line one "quoted"\n    """\n'
                  'let c = #"raw "quoted" \\(not interpolated)"#\n'
                  '#if DEBUG\nlet d = "debug"\n#endif\n')
        self.assertEqual(self.values(source), ['say \\"hi\\" \\\\', '\n    line one "quoted"\n    ',
                                               'raw "quoted" \\(not interpolated)', 'debug'])

    def test_interpolation_keeps_both_the_outer_and_the_inner_literals(self):
        source = 'let a = "before \\(f("inner", g("deep"))) after" + "next"\n'
        self.assertEqual(self.values(source), ['before \u2026 after', 'inner', 'deep', 'next'])

    def test_line_numbers(self):
        rows = check_brand.swift_strings('let a = 1\n\nlet b = "x"\n')
        self.assertEqual(rows, [(3, 'x')])


class PythonStringTests(unittest.TestCase):
    def test_docstrings_are_skipped(self):
        source = '"""module 渥屋助理"""\ndef f():\n    """doc 渥屋助理"""\n    return "visible", f"x{1}y"\n'
        values = [value for _, value in check_brand.python_strings(source)]
        self.assertIn('visible', values)
        self.assertFalse(any('渥屋' in value for value in values))


class ScanTests(unittest.TestCase):
    def findings(self, files):
        folder, root = tree(files)
        with folder:
            return check_brand.scan(root)

    def test_user_visible_names_in_app_strings_are_findings(self):
        rows = self.findings({
            'Sources/App/A.swift': 'let a = "開啟渥屋助理查看結果。"\n// 渥屋助理 in a comment\nlet b = "About woowtech agent"\n',
            'Sources/App/Resources/en.lproj/InfoPlist.strings': '/* woowtech agent */\n"CFBundleDisplayName" = "woowtech agent";\n',
            'Localization/AppText.json': json.dumps({'entries': [{'translations': {'en': 'Hi, I’m woowtech agent'}}]}),
            'Configuration/Info-Release.plist': plistlib.dumps({'NSCameraUsageDescription': '渥屋助理會使用相機'}),
        })
        self.assertEqual(sorted((r['file'], r['term']) for r in rows), [
            ('Configuration/Info-Release.plist', '渥屋'), ('Localization/AppText.json', 'woow'),
            ('Sources/App/A.swift', 'woow'), ('Sources/App/A.swift', '渥屋'),
            ('Sources/App/Resources/en.lproj/InfoPlist.strings', 'woow')])

    def test_internal_identifiers_are_allowed(self):
        rows = self.findings({'Sources/App/B.swift': '\n'.join([
            'let a = "io.woowtech.assistant.model-credentials.v1"', 'let b = "io.woowtech.chat-web-fixture"',
            'let c = env["WOOW_LIVE_MODEL"]', 'let d = "__WOOW_MISSING_TRANSLATION__"', 'let e = "⟦WOOW_URL_"',
            'let f = "-WoowSkipOnboarding"', 'let g = "globalThis.__woowTask = {}"', 'let h = "woow.task.v1."',
            'let i = "woow_login_fixture"', 'let j = "woowSearchProbe"', 'let k = "WoowSpeech-" + id', ''])})
        self.assertEqual(rows, [])

    def test_the_woowtech_bundle_id_is_never_internal(self):
        rows = self.findings({'Sources/App/C.swift': 'let id = "io.woowtech.assistant"\n',
                              'scripts/release_ios.py': 'BUNDLE_ID = "io.woowtech.assistant"\n',
                              'project.yml': 'options:\n  bundleIdPrefix: io.woowtech\ntargets:\n  WoowAssistant:\n'})
        self.assertEqual(sorted((r['file'], r['term']) for r in rows), [
            ('Sources/App/C.swift', 'io.woowtech.assistant'), ('project.yml', 'woow'),
            ('scripts/release_ios.py', 'io.woowtech.assistant')])

    def test_user_agent_and_mcp_client_name_are_findings(self):
        rows = self.findings({'Sources/AssistantMCP/MCPClient.swift':
                              'let ua = "WoowAssistant/0.1"\nlet name = "WoowAssistant-iOS"\n'})
        self.assertEqual(len(rows), 2)

    def test_listed_notices_only_cover_their_exact_text(self):
        skills = json.dumps({'entries': [{'adaptationMarkdown': 'adaptation: WOOW iOS text-only adaptation; x\n'
                                                                'WOOW 將此版本改寫為 iOS 文字參考。'},
                                         {'title': 'WOOW 的技能'}]}, ensure_ascii=False)
        about = ('let a = ("本 App 由 WOOW TECH CO., LTD. 修改與發行。記憶…", '
                 '"This app is modified and distributed by WOOW TECH CO., LTD. The memory…")\n'
                 'let b = "© 2026 WOOW TECH CO., LTD."\n')
        rows = self.findings({'Sources/AssistantSkills/Resources/MikaBundledSkills.json': skills,
                              'Sources/App/MikaAboutInfo.swift': about,
                              'Sources/App/Other.swift': 'let c = "This app is modified and distributed by WOOW TECH CO., LTD."\n'})
        self.assertEqual(sorted((r['file'], r['text']) for r in rows), [
            ('Sources/App/MikaAboutInfo.swift', '© 2026 WOOW TECH CO., LTD.'),
            ('Sources/App/Other.swift', 'This app is modified and distributed by WOOW TECH CO., LTD.'),
            ('Sources/AssistantSkills/Resources/MikaBundledSkills.json', 'WOOW 的技能')])

    def test_tests_scope_counts_only_user_visible_terms(self):
        rows = self.findings({
            'Tests/UITests/A.swift': 'XCTAssertEqual(label, "關於渥屋助理")\nlet x = "WoowAssistant"\n'
                                     'app.launchArguments = ["-WoowSkipOnboarding"]\n',
            'scripts/check_x.py': 'ENV = "WOOW_LIVE_MODEL"\nPREFIX = "woow-check-"\nMAIL = "woowtech@designsmart.com.tw"\n'
                                  'HOST = "https://assistant-relay.woowtech.io/api"\n',
            'scripts/CheckChatAttachmentReader.swift': 'writePDF(["Woowtech 渥屋"])\n',
        })
        self.assertEqual(sorted((r['file'], r['term']) for r in rows), [
            ('Tests/UITests/A.swift', '渥屋'), ('scripts/check_x.py', 'assistant-relay.woowtech.io'),
            ('scripts/check_x.py', 'designsmart'), ('scripts/check_x.py', 'woowtech@')])

    def test_brand_tooling_is_not_scanned(self):
        rows = self.findings({'scripts/apply_brand.py': 'FIND = "渥屋助理"\n',
                              'scripts/test_check_brand.py': 'X = "woowtech agent"\n'})
        self.assertEqual(rows, [])


class ConformanceTests(unittest.TestCase):
    def test_brand_values_are_checked(self):
        brand = {'identity': {'display_name': 'Demo App', 'bundle_id': 'com.demo.app', 'bundle_id_prefix': 'com.demo',
                              'marketing_version': '1.0.0', 'build': '1', 'team_id': 'ABCDE12345',
                              'support_email': 'help@demo.example', 'privacy_policy_url': 'https://demo.example/privacy',
                              'ai_report_endpoint': 'https://demo.example/reports',
                              'accent': {'light': '#102030', 'dark': '#405060'}},
                 'icon': {'png': 'icon/AppIcon.png'}}
        icon = b'\x89PNG fake'
        good = {
            'brands/demo/brand.json': json.dumps(brand), 'brands/demo/icon/AppIcon.png': icon,
            'project.yml': ('options:\n  bundleIdPrefix: com.demo\nsettings:\n  base:\n    MARKETING_VERSION: "1.0.0"\n'
                            '    CURRENT_PROJECT_VERSION: "1"\ntargets:\n  A:\n    settings:\n      base:\n'
                            '        PRODUCT_BUNDLE_IDENTIFIER: com.demo.app.models\n  B:\n    settings:\n      base:\n'
                            '        PRODUCT_BUNDLE_IDENTIFIER: com.demo.app\n        INFOPLIST_KEY_CFBundleDisplayName: Demo App\n'),
            'Sources/App/Resources/en.lproj/InfoPlist.strings': '"CFBundleDisplayName" = "Demo App";\n',
            'Configuration/ExportOptions-AppStore.plist': '<key>teamID</key>\n\t<string>ABCDE12345</string>\n',
            'scripts/release_ios.py': 'BUNDLE_ID = "com.demo.app"\n',
            'Sources/App/AIResponseReportDelivery.swift': 'URL(string: "https://demo.example/reports")!\n',
            'Sources/App/MikaAboutInfo.swift': 'URL(string: "https://demo.example/privacy")!\n"help@demo.example"\n',
            'Localization/AppText.json': json.dumps({'entries': [{'key': 'shell.brandTitle',
                                                                  'translations': {'zh-Hant': 'Demo App', 'en': 'Demo App'}}]}),
            'Sources/App/ContentView.swift': '    var accent: Color { dark ? rgb(64, 80, 96) : rgb(16, 32, 48) }\n',
            'Sources/App/Assets.xcassets/AppIcon.appiconset/AppIcon.png': icon,
            'Sources/App/Assets.xcassets/AboutBrandIcon.imageset/AppIcon.png': icon,
        }
        folder, root = tree(good)
        with folder:
            checks = check_brand.conformance(root, root / 'brands/demo')
            self.assertEqual([name for name, passed in checks if not passed], [])
            (root / 'scripts/release_ios.py').write_text('BUNDLE_ID = "io.woowtech.assistant"\n')
            (root / 'Sources/App/Assets.xcassets/AppIcon.appiconset/AppIcon.png').write_bytes(b'other')
            failed = [name for name, passed in check_brand.conformance(root, root / 'brands/demo') if not passed]
            self.assertEqual(failed, ['release script expects com.demo.app', 'AppIcon is the brand icon'])


class LiveTreeTests(unittest.TestCase):
    def test_a_branded_tree_has_no_findings(self):
        brand = check_brand.applied_brand(ROOT)
        if brand is None:
            self.skipTest('the WOOWTECH tree is the base brand; check_brand applies to branded trees')
        self.assertEqual(check_brand.scan(ROOT), [])
        failed = [name for name, passed in check_brand.conformance(ROOT, ROOT / 'brands' / brand) if not passed]
        self.assertEqual(failed, [])


if __name__ == '__main__':
    unittest.main()
