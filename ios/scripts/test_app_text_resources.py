import copy
import json
from pathlib import Path
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
        e = next(i for i,x in enumerate(self.catalog['entries']) if x['case'] == 'chatQuotingYou')
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

    def test_store_example_copy_matches_audited_420b1d26(self):
        # 420b1d26 woowtech flavor provides Hant and English; Simplified
        # is an iOS translation, not an Android store resource.
        expected = {
            'shellReplyExample': ('幫我寫一則友善的訊息回覆', 'Help me write a friendly reply to this message.'),
            'shellDocumentExample': ('幫我摘要附上的文件，列出重點', 'Summarize the document I attach and list its key points.'),
            'shellWebExample': ('在 104 人力銀行搜尋台北的 AI 產品經理職缺，挑五個幫我比較', 'Search 104 Job Bank for AI product manager jobs in Taipei and compare five of them for me.'),
            'shellShoppingExample': ('在 momo 購物找 1,000 元以內、4.5 星以上的無線耳機，比較三款的優缺點', 'Find three wireless earbuds under NT$1,000 rated 4.5 stars or more on momo and compare their pros and cons.'),
            'shellRememberExample': ('記住我偏好使用繁體中文，回答簡短一點', 'Remember that I prefer concise answers in Traditional Chinese.'),
            'shellRecallExample': ('你記得我有哪些偏好？', 'What preferences have I told you to remember?'),
        }
        entries = {e['case']: e['translations'] for e in self.catalog['entries']}
        for case, (hant, english) in expected.items():
            self.assertEqual(entries[case]['zh-Hant'], hant, case)
            self.assertEqual(entries[case]['en'], english, case)

    def test_six_examples_match_supplied_unsigned_apk_resource_evidence(self):
        root = Path(__file__).resolve().parents[1]
        evidence = json.loads((root / 'docs/evidence/craft-play-420b1d26-chat.json').read_text())
        self.assertEqual(evidence['source_commit'], '420b1d26f99110635d6a2827ee9414541c7a6c35')
        self.assertEqual(evidence['artifact_sha256'], 'a53e5386811b8c3df3a8d70164c3c984188afe71329b5671d4595bd7432fc50c')
        mapping = {'chat_example_follow': 'shellReplyExample',
                   'chat_example_group_summary': 'shellDocumentExample',
                   'chat_example_jobs': 'shellWebExample',
                   'chat_example_multi_step': 'shellShoppingExample',
                   'chat_example_alarms': 'shellRememberExample',
                   'chat_example_ai_apps': 'shellRecallExample'}
        entries = {e['case']: e['translations'] for e in self.catalog['entries']}
        for key, case in mapping.items():
            self.assertEqual(entries[case]['zh-Hant'], evidence['chat_strings'][key], key)

    def test_generated_assets_are_complete(self):
        generated = outputs(self.catalog)
        root = Path(__file__).resolve().parents[1]
        for path, expected in generated.items(): self.assertEqual((root/path).read_bytes(), expected, path)

if __name__ == '__main__': unittest.main()
