import copy
import json
from pathlib import Path
import unittest
from generate_app_text import validate, outputs, stale_tables

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

    def test_simplified_chinese_stays_removed(self):
        # Owner, 2026-11-13: English and Traditional Chinese only, as in the Play build.
        self.reject(lambda c: c.update(languages=['zh-Hant', 'zh-Hans', 'en']))
        self.assertEqual(stale_tables(), [])

    def test_store_example_copy_matches_play_964d7bec(self):
        # The Play edition's woowtech flavor at 964d7bec (2026-11-13) provides Hant and
        # English, the two languages iOS ships; its second example became AI news.
        expected = {
            'shellReplyExample': ('幫我寫一則友善的訊息回覆', 'Help me write a friendly reply to this message.'),
            'shellNewsExample': ('在內建瀏覽器找一篇最近的 AI 新聞，摘要三個重點', 'Find a recent AI news article in the built-in browser and summarize three key points.'),
            'shellWebExample': ('在 104 人力銀行搜尋台北的 AI 產品經理職缺，挑五個幫我比較', 'Search 104 Job Bank for AI product manager jobs in Taipei and compare five of them for me.'),
            'shellShoppingExample': ('在 momo 購物找 1,000 元以內、4.5 星以上的無線耳機，比較三款的優缺點', 'Find three wireless earbuds under NT$1,000 rated 4.5 stars or more on momo and compare their pros and cons.'),
            'shellRememberExample': ('記住我偏好使用繁體中文，回答簡短一點', 'Remember that I prefer concise answers in Traditional Chinese.'),
            'shellRecallExample': ('你記得我有哪些偏好？', 'What preferences have I told you to remember?'),
        }
        entries = {e['case']: e['translations'] for e in self.catalog['entries']}
        for case, (hant, english) in expected.items():
            self.assertEqual(entries[case]['zh-Hant'], hant, case)
            self.assertEqual(entries[case]['en'], english, case)

    def test_six_examples_match_play_964d7bec_resource_evidence(self):
        root = Path(__file__).resolve().parents[1]
        evidence = json.loads((root / 'docs/evidence/play-964d7bec-chat-examples.json').read_text())
        self.assertEqual(evidence['source_commit'], '964d7becff9a0daa228f24cc5c8e2664fde8b7d9')
        mapping = {'chat_example_follow': 'shellReplyExample',
                   'chat_example_group_summary': 'shellNewsExample',
                   'chat_example_jobs': 'shellWebExample',
                   'chat_example_multi_step': 'shellShoppingExample',
                   'chat_example_alarms': 'shellRememberExample',
                   'chat_example_ai_apps': 'shellRecallExample'}
        entries = {e['case']: e['translations'] for e in self.catalog['entries']}
        for key, case in mapping.items():
            self.assertEqual(entries[case]['zh-Hant'], evidence['chat_strings'][key], key)
            self.assertEqual(entries[case]['en'], evidence['chat_strings_en'][key], key)

    def test_generated_assets_are_complete(self):
        generated = outputs(self.catalog)
        root = Path(__file__).resolve().parents[1]
        for path, expected in generated.items(): self.assertEqual((root/path).read_bytes(), expected, path)

if __name__ == '__main__': unittest.main()
