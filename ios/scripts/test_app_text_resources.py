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

    def test_store_examples_are_the_family_set(self):
        # The App Store build's six examples follow its household audience (owner, 2026-11-23,
        # for App Review 4.3: 渥屋助理 is for families at home). The Play build at 964d7bec keeps
        # its own wording (docs/evidence/play-964d7bec-chat-examples.json) in the same six slots.
        expected = {
            'shellReplyExample': ('幫我寫一則給老師的請假訊息：孩子發燒，明天在家休息一天', 'Write a short note to my child’s teacher: she has a fever and will stay home tomorrow.'),
            'shellNewsExample': ('在內建瀏覽器找這個週末台北適合親子的活動，整理三個給我', 'Find three family-friendly things to do in Taipei this weekend in the built-in browser.'),
            'shellWebExample': ('查台北市垃圾車和資源回收的收運時間，附上來源', 'Look up Taipei’s garbage truck and recycling collection times, with sources.'),
            'shellShoppingExample': ('在 momo 購物找 1,000 元以內、4.5 星以上的兒童保溫瓶，比較三款的優缺點', 'Find three kids’ water bottles under NT$1,000 rated 4.5 stars or more on momo and compare their pros and cons.'),
            'shellRememberExample': ('記住我們家小孩對花生過敏，推薦餐廳或食譜時要避開', 'Remember that our kids are allergic to peanuts, so avoid them in restaurant and recipe ideas.'),
            'shellRecallExample': ('你記得我們家有哪些要注意的事？', 'What do you remember about our family?'),
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

    def test_six_example_slots_match_play_964d7bec_resource_evidence(self):
        # Same six slots as Play 964d7bec; the App Store wording is the family set above.
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
            self.assertTrue(evidence['chat_strings'][key].strip() and evidence['chat_strings_en'][key].strip(), key)
            self.assertTrue(entries[case]['zh-Hant'].strip() and entries[case]['en'].strip(), case)

    def test_generated_assets_are_complete(self):
        generated = outputs(self.catalog)
        root = Path(__file__).resolve().parents[1]
        for path, expected in generated.items(): self.assertEqual((root/path).read_bytes(), expected, path)

if __name__ == '__main__': unittest.main()
