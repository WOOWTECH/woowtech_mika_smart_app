import json
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
from check_ai_safety_and_reports import rules_audit  # noqa: E402

EVIDENCE = json.loads((ROOT / 'docs/evidence/play-964d7bec-ai-safety-reports.json').read_text())
DELIVERY = ROOT / 'Sources/App/AIResponseReportDelivery.swift'


def play_key(case):
    """chatReportNeedsRetry -> chat_report_needs_retry"""
    return re.sub(r'(?<!^)(?=[A-Z])', '_', case).lower()


class AISafetyAndReportsTests(unittest.TestCase):
    def check(self, *arguments):
        return subprocess.run([sys.executable, str(ROOT / 'scripts/check_ai_safety_and_reports.py'), *arguments],
                              cwd=ROOT, capture_output=True, text=True, timeout=1800)

    def test_rules_and_reports(self):
        result = self.check()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('PASS AI safety rules: Play 964d7bec text, 11 request sites', result.stdout)
        self.assertIn('PASS AI response reports (Debug):', result.stdout)
        self.assertIn('PASS AI response reports (Release):', result.stdout)

    def test_rules_audit_catches_a_missing_or_unreviewed_site(self):
        chat = (ROOT / 'Sources/App/ChatSession.swift').read_text()
        mutants = {
            'plain chat without the rules': {'Sources/App/ChatSession.swift':
                chat.replace('[AISafetyRules.systemMessage(instructions:', '[Self.chatSystemMessage(instructions:')},
            'the skill tools step without the rules': {'Sources/AssistantSkills/ChatSkillTools.swift':
                (ROOT / 'Sources/AssistantSkills/ChatSkillTools.swift').read_text().replace(
                    'AISafetyRules.appended(to: ChatSkillPrompts.run(', '(ChatSkillPrompts.run(')},
            'a new model request': {'Sources/App/NewRunner.swift':
                'func run() async throws { _ = try await client.complete(messages: [], configuration: c, apiKey: k) }'},
            'other rules text': {'Sources/AssistantModels/AISafetyRules.swift':
                (ROOT / 'Sources/AssistantModels/AISafetyRules.swift').read_text().replace('benign creative work', 'creative work')},
        }
        for label, overrides in mutants.items():
            with self.subTest(mutant=label):
                _, failures = rules_audit(ROOT, overrides)
                self.assertTrue(failures, label)
        self.assertEqual(rules_audit(ROOT)[1], [])

    def test_report_strings_match_play_964d7bec(self):
        catalog = json.loads((ROOT / 'Localization/AppText.json').read_text())
        entries = {e['case']: e for e in catalog['entries'] if e['key'].startswith('chat.report.')}
        # Every reply here has a stable ID, so Android's no-identity state cannot happen.
        expected = set(EVIDENCE['report_strings']) - {'chat_report_no_identity'}
        self.assertEqual({play_key(case) for case in entries}, expected)
        for case, entry in entries.items():
            key = play_key(case)
            for language, play in [('zh-Hant', EVIDENCE['report_strings'][key]), ('en', EVIDENCE['report_strings_en'][key])]:
                self.assertEqual(entry['translations'][language], re.sub(r'%(\d)\$s', r'%\1$@', play), (case, language))
        english = ' '.join(e['translations']['en'] for e in entries.values())
        self.assertIsNone(re.search(r'Mika|woowtech|Woow|渥屋', english, re.I), 'English report text names no app')

    def test_client_limits_match_play(self):
        client = EVIDENCE['report_client']
        reports = (ROOT / 'Sources/App/AIResponseReports.swift').read_text()
        delivery = DELIVERY.read_text()
        sheet = (ROOT / 'Sources/App/AIResponseReportSheet.swift').read_text()
        self.assertIn('static let reasons = ' + json.dumps(client['reasons']), reports)
        self.assertIn(f'@State private var reason = "{client["default_reason"]}"', sheet)
        self.assertIn(f'static let maximumResponse = {client["max_response"]:_}', reports)
        self.assertIn(f'static let maximumNote = {client["max_note"]:_}', reports)
        self.assertIn(f'static let maximumAttempts = {client["max_automatic_attempts"]}', delivery)
        first, later = client['retry_after_ms']
        self.assertIn(f'(updated.attempts == 1 ? {first:_} : {later:_})', reports)
        self.assertIn(f'let window: Int64 = {client["intake_window_days"]} * 24 * 60 * 60 * 1_000', reports)
        self.assertEqual(delivery.count(f'configuration.timeoutIntervalFor'), 2)
        self.assertIn(f'timeoutIntervalForResource = {client["request_timeout_seconds"]}', delivery)
        self.assertIn(f'Task.sleep(nanoseconds: {client["chat_delivery_interval_ms"] // 1000}_000_000_000)', delivery)
        self.assertIn(f'Task.sleep(nanoseconds: {client["dialog_refresh_ms"] // 1000}_000_000_000)', sheet)
        self.assertIn(f'target.response, {client["preview_characters"]}))\n                    .lineLimit({client["preview_lines"]})', sheet)
        self.assertIn(f'take(report.response, {client["history_preview_characters"]})', sheet)
        self.assertEqual(EVIDENCE['relay']['endpoint'], 'https://assistant-relay.woowtech.io/api/v1/ai-reports')
        self.assertIn('URL(string: "' + EVIDENCE['relay']['endpoint'] + '")!', delivery)

    def test_menu_places_report_like_play(self):
        menu = (ROOT / 'Sources/App/ChatMessageActions.swift').read_text()
        order = re.findall(r'item\(\.\w+, text\.\w+, symbol: "[^"]+", id: "(\w+)"\)', menu)
        names = {'copy': 'copy', 'quote': 'quote', 'selectText': 'select', 'report': 'report',
                 'branch': 'branch', 'askAgain': 'branch-retry'}
        play = [entry for entry in EVIDENCE['report_client']['menu_order'] if entry in names.values()]
        self.assertEqual([names[item] for item in order], play)

    def test_mutants_that_would_change_what_leaves_the_device_fail(self):
        original = DELIVERY.read_text()
        for old, new in [('"response": report.response, "created_at_ms": report.createdAtMs]',
                          '"response": report.response, "created_at_ms": report.createdAtMs, "device": "phone"]'),
                         ('&& report.attempts < Self.maximumAttempts', '&& report.attempts <= Self.maximumAttempts'),
                         ('guard !blocked else { continue }', '_ = blocked')]:
            with self.subTest(mutant=new), tempfile.TemporaryDirectory(prefix='woow-ai-reports-mutant-') as folder:
                self.assertEqual(original.count(old), 1, old)
                mutant = Path(folder) / DELIVERY.name
                mutant.write_text(original.replace(old, new))
                result = self.check('--source', str(mutant), '--config', 'Debug')
                self.assertNotEqual(result.returncode, 0, 'the check must catch: ' + new)
                self.assertIn('FAIL: ', result.stdout + result.stderr)


if __name__ == '__main__':
    unittest.main()
