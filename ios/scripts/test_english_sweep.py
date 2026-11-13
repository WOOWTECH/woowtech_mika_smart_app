"""English sweep guard: screens moved to AppText keep no Chinese literals, and every
stored message the App translates at display time still exists where it is produced.

With the App in English (every non-Chinese system), a Chinese literal on these screens
would show untranslated. Debug-only test fixtures stay Chinese; other intentional
literals are listed in ALLOWED with the reason. The skill template's section
headings in SkillAuthoringView are a multi-line string the validator requires.
"""
import json
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / 'Sources/App'
CJK = re.compile('[㐀-鿿＀-￯　-〿]')
LITERAL = re.compile(r'"((?:[^"\\]|\\.)*)"')

SWEPT = [
    'UserProfileView', 'UserProfileToolReviewView', 'WebsiteDataView', 'ConversationArchiveView',
    'MemoryToolReviewView', 'BrowserDownloadsView', 'BrowserLibraryView', 'BrowserSearchSettingsView',
    'SkillAuthoringView', 'SkillAgentView', 'SkillAgentSession', 'SkillExecutionView', 'DocumentQueryView',
    'TranscriptView', 'TranscriptBrowserView', 'SkillPDFAssemblyView', 'MultiSourceResearchView',
    'ResearchSourceDiscoveryView',
]

# (file, literal) -> why it stays Chinese.
ALLOWED = {
    ('SkillExecutionView', 'PDF文字'): 'initial export name, replaced before the exporter opens',
}
# The shared view model below the iOS view keeps its Chinese status text for the
# macOS harnesses; the view shows it through AppLocalizer.stored.
SHARED_MODEL_MARKER = {'SkillExecutionView': 'final class SkillExecutionViewModel'}

# Formats the stores build from two literals, e.g. "搜尋找到 \(n) 處" + "。".
COMPOSED = {'documentQueryStatusFound', 'documentQueryStatusFoundMore'}


def literal_lines(name):
    """CJK literals outside comments, #if DEBUG blocks and shared view models."""
    text = (APP / (name + '.swift')).read_text()
    marker = SHARED_MODEL_MARKER.get(name)
    if marker:
        text = text.split(marker)[0]
    rows, depth, debug_depth = [], 0, None
    for number, line in enumerate(text.splitlines(), 1):
        stripped = line.strip()
        if stripped.startswith('#if'):
            depth += 1
            if debug_depth is None and stripped.startswith('#if DEBUG'):
                debug_depth = depth
            continue
        if stripped.startswith('#else') and debug_depth == depth:
            debug_depth = None
            continue
        if stripped.startswith('#endif'):
            if debug_depth == depth:
                debug_depth = None
            depth -= 1
            continue
        if debug_depth is not None or stripped.startswith('//') or stripped.startswith('///'):
            continue
        for literal in LITERAL.findall(line.split(' // ')[0]):
            if CJK.search(literal):
                rows.append((number, literal))
    return rows


class EnglishSweepTests(unittest.TestCase):
    def test_swept_screens_have_no_chinese_literals(self):
        problems = []
        for name in SWEPT:
            for number, literal in literal_lines(name):
                if not any(name == file and literal.startswith(prefix) for file, prefix in ALLOWED):
                    problems.append(f'{name}.swift:{number}: {literal}')
        self.assertEqual(problems, [], 'Chinese literal on an English-swept screen; add an AppText key')

    def test_stored_messages_exist_where_they_are_produced(self):
        catalog = {e['case']: e for e in json.loads((ROOT / 'Localization/AppText.json').read_text())['entries']}
        adapter = (APP / 'AppStoredText.swift').read_text()
        fixed = re.findall(r'\.([a-zA-Z0-9]+)', re.search(r'storedFixed: \[AppText\] = \[(.*?)\n    \]', adapter, re.S)[1])
        patterns = re.findall(r'\(\.([a-zA-Z0-9]+)\(', re.search(r'storedPatterns: .*?= \[(.*?)\n    \]', adapter, re.S)[1])
        self.assertGreater(len(fixed), 100)
        sources = '\n'.join(path.read_text() for path in (ROOT / 'Sources').rglob('*.swift') if path.name != 'AppText.swift')
        missing = []
        for case in fixed:
            text = catalog[case]['translations']['zh-Hant']
            if '"' + text + '"' not in sources and f'.{case}.traditionalFallback' not in sources:
                missing.append(case)
        for case in patterns:
            if case in COMPOSED:
                continue
            for piece in re.split(r'%\d+\$(?:@|lld)', catalog[case]['translations']['zh-Hant']):
                if piece and piece.replace('\n', '\\n') not in sources:
                    missing.append(case)
        self.assertEqual(missing, [], 'stored message no longer produced as written; update AppText.json')

    def test_composed_formats_still_compose(self):
        session = (APP / 'DocumentQuerySession.swift').read_text()
        self.assertIn('"搜尋找到 \\(count) 處" + (truncated ? "；尚有其他符合位置。" : "。")', session)


if __name__ == '__main__':
    unittest.main()
