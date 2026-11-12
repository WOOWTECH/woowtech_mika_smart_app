import copy
import json
from pathlib import Path
import re
import unittest
from generate_app_text import validate, outputs

class AppTextResourceTests(unittest.TestCase):
    def setUp(self):
        self.catalog = json.loads((Path(__file__).resolve().parents[1] / 'Localization/AppText.json').read_text())

    def reject(self, mutate):
        c = copy.deepcopy(self.catalog); mutate(c)
        with self.assertRaises(ValueError): validate(c)

    def test_missing_or_extra_language_rejected(self):
        self.reject(lambda c: c['entries'][0]['translations'].pop('en'))
        self.reject(lambda c: c['entries'][0]['translations'].update(ja='unsupported'))

    def test_empty_translation_rejected(self):
        self.reject(lambda c: c['entries'][0]['translations'].update(en='  '))

    def test_duplicate_key_or_case_rejected(self):
        self.reject(lambda c: c['entries'].append(copy.deepcopy(c['entries'][0])))

    def test_parameter_removal_type_and_unknown_format_rejected(self):
        e = next(i for i,x in enumerate(self.catalog['entries']) if x['case'] == 'configurationChanged')
        for bad in ['No parameter', '%1$lld', '%1$@ %n', '%1$@ %1$@', '%2$@']:
            self.reject(lambda c: c['entries'][e]['translations'].update(en=bad))

    def test_plural_requires_language_categories_and_integer(self):
        e = next(i for i,x in enumerate(self.catalog['entries']) if x.get('plural'))
        self.reject(lambda c: c['entries'][e]['translations']['en'].pop('one'))
        self.reject(lambda c: c['entries'][e]['translations']['zh-Hant'].update(one='%lld 個步驟'))
        self.reject(lambda c: c['entries'][e]['parameters'][0].update(type='String'))
        self.reject(lambda c: c['entries'][e]['translations']['en'].update(other='%@ steps'))

    def test_fallback_cannot_silently_change(self):
        self.reject(lambda c: c.update(fallback='en'))

    def test_generated_assets_are_complete(self):
        generated = outputs(self.catalog)
        root = Path(__file__).resolve().parents[1]
        for path, expected in generated.items(): self.assertEqual((root/path).read_bytes(), expected, path)

    def test_learning_tool_reviews_use_localized_labels_and_keep_review_fields(self):
        root = Path(__file__).resolve().parents[1]
        entries = {e['case']: e for e in self.catalog['entries']}
        cases = {
            'MemoryToolReviewView.swift': ['memoryTool.operation', 'memoryTool.kind', 'memoryTool.quote',
                                           'memoryTool.before', 'memoryTool.after', 'memoryTool.keywords',
                                           'memoryTool.decline', 'memoryTool.approve'],
            'UserProfileToolReviewView.swift': ['profileTool.operation', 'profileTool.quote',
                                                'profileTool.before', 'profileTool.after',
                                                'profileTool.decline', 'profileTool.approve'],
        }
        for filename, identifiers in cases.items():
            source = (root / 'Sources/App' / filename).read_text()
            self.assertIn('@Environment(\\.appLocalizer)', source)
            self.assertNotRegex(source, r'\b(?:Text|Button|navigationTitle)\s*\(\s*"')
            for identifier in identifiers: self.assertIn('"' + identifier + '"', source)
            referenced = (re.findall(r'localizer\.text\(\.([A-Za-z][A-Za-z0-9]*)\)', source)
                          + re.findall(r'return \.(toolReview[A-Za-z0-9]+)', source))
            for case in referenced:
                self.assertIn(case, entries)
                for language in ('zh-Hant', 'zh-Hans', 'en'):
                    self.assertTrue(entries[case]['translations'][language].strip())

if __name__ == '__main__': unittest.main()
