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

    def test_store_example_copy_matches_apporo_play_6dc10a4e(self):
        # The Apporo Play edition (apporoplay flavor) at 6dc10a4e (2026-11-13) provides
        # Hant and English, the two languages iOS ships. Every example works on iOS:
        # writing, the built-in browser and memory.
        expected = {
            'shellReplyExample': ('幫我草擬一封友善的電子郵件，邀請團隊參加週五的規劃會議。', 'Draft a friendly email inviting my team to Friday’s planning meeting.'),
            'shellNewsExample': ('在內建瀏覽器找一篇最近關於智慧建築的文章，摘要三個重點。', 'Find a recent article about smart buildings in the built-in browser and summarize three key points.'),
            'shellWebExample': ('上網搜尋設施管理職缺，挑五個幫我比較。', 'Search the web for facility manager jobs and compare five of them for me.'),
            'shellShoppingExample': ('比較三款適合會議室的空氣品質監測器，附上來源、價格與仍需確認的資訊。', 'Compare three air quality monitors for a meeting room. Include sources, prices and what still needs checking.'),
            'shellRememberExample': ('記住我偏好簡短、先講重點的回答。', 'Remember that I prefer short answers with the key point first.'),
            'shellRecallExample': ('你記得我有哪些偏好？', 'What preferences have I asked you to remember?'),
        }
        entries = {e['case']: e['translations'] for e in self.catalog['entries']}
        for case, (hant, english) in expected.items():
            self.assertEqual(entries[case]['zh-Hant'], hant, case)
            self.assertEqual(entries[case]['en'], english, case)

    def test_chat_wording_matches_play_964d7bec(self):
        # Play 964d7bec, woowtech flavor: greetings from strings_woowtech_wording.xml,
        # chat_empty_prompt from strings_woowtech.xml, the rest from strings_chat.xml
        # (chat_stop, all_ready, pin/unpin, drawer_pinned(_mark), drawer_rename(_title)).
        expected = {
            'shellGreetingMorning': ('早安', 'Good morning'),
            'shellGreetingNoon': ('午安', 'Good afternoon'),
            'shellGreetingAfternoon': ('午安', 'Good afternoon'),
            'shellGreetingEvening': ('晚安', 'Good evening'),
            'shellGreetingNight': ('夜深了', 'Up late'),
            'shellWhatToDo': ('想聊什麼，或需要幫忙查找什麼？', 'What would you like help with?'),
            'shellStop': ('停止', 'Stop'),
            'drawerStatusReady': ('一切就緒', 'All set'),
            'chatSendBlockedTitle': ('還不能開始任務', 'Can’t start tasks yet'),
            'drawerRecentPin': ('置頂', 'Pin'),
            'drawerRecentUnpin': ('取消置頂', 'Unpin'),
            'drawerRecentPinned': ('置頂', 'Pinned'),
            'drawerRecentPinnedMark': ('已置頂', 'Pinned'),
            'drawerRecentRename': ('改名', 'Rename'),
            'drawerRecentRenameTitle': ('改名', 'Rename chat'),
        }
        entries = {e['case']: e['translations'] for e in self.catalog['entries']}
        for case, (hant, english) in expected.items():
            self.assertEqual(entries[case]['zh-Hant'], hant, case)
            self.assertEqual(entries[case]['en'], english, case)

    def test_six_examples_match_apporo_play_6dc10a4e_resource_evidence(self):
        root = Path(__file__).resolve().parents[1]
        evidence = json.loads((root / 'docs/evidence/apporo-play-6dc10a4e-chat-examples.json').read_text())
        self.assertEqual(evidence['source_commit'], '6dc10a4e4d7d3ca49a314100836ff421042bece9')
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
