"""Portable regression for empty-state scrolling and transcript follow."""
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
POLICY = ROOT / 'Sources/App/ChatScrollFollowPolicy.swift'
CHECKS = ROOT / 'scripts/CheckChatScrollFollow.swift'
VIEW = ROOT / 'Sources/App/ContentView.swift'


def between(source, start, end):
    first = source.index(start)
    return source[first:source.index(end, first)]


def header_declaration_problems(source):
    """ContentView needs a device to run, so this reads its source. A row above the transcript moves
    the transcript's top edge, which geometry alone reads as the reader scrolling away: every row of
    the chat header must be declared as a layout change, like the composer's."""
    header = between(source, '@ViewBuilder private var chatHeader: some View {', "/// Android's NeedCard")
    declared = between(source, 'private var headerRows: HeaderRows {', '\n    }\n')
    # The notes declare their own rows; the diagnostics are the activity row's accessibility value
    # and a send in flight only disables the results button.
    exempt = {'learning', 'mcpDiagnostics', 'isSubmitting'}
    shown = set(re.findall(r'session\.(\w+)', header)) - exempt
    problems = [f'chatHeader shows session.{name} without declaring it in headerRows'
                for name in sorted(shown - set(re.findall(r'session\.(\w+)', declared)))]
    if 'creatingFile' in header:
        problems.append('a file being made is a line of the working row, not a header row')
    for needle, rule in [('.onChange(of: headerRows) { _, _ in composerLayoutChanged() }', 'the header rows are declared as layout changes'),
                         ('onLayoutChange: { composerLayoutChanged() })', 'the notes call back into the view'),
                         ('.onChange(of: rows) { _, _ in onLayoutChange() }', 'the notes declare their own rows')]:
        if needle not in source:
            problems.append(rule)
    return problems


class ChatScrollFollowTests(unittest.TestCase):
    def compile_and_run(self, source):
        with tempfile.TemporaryDirectory(prefix='woow-chat-scroll-test-') as folder:
            folder = Path(folder)
            policy = folder / 'ChatScrollFollowPolicy.swift'
            binary = folder / 'checks'
            policy.write_text(source)
            compiled = subprocess.run(['swiftc', '-swift-version', '5', '-warnings-as-errors',
                                       str(policy), str(CHECKS), '-o', str(binary)],
                                      capture_output=True, text=True, timeout=120)
            self.assertEqual(compiled.returncode, 0, compiled.stderr)
            return subprocess.run([str(binary)], capture_output=True, text=True, timeout=30)

    def test_empty_state_and_existing_follow(self):
        result = self.compile_and_run(POLICY.read_text())
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('status=PASS', result.stdout)

    def test_mutation_restoring_empty_state_tail_follow_fails(self):
        source = POLICY.read_text()
        guard = 'guard hasTranscript, current.isValid else { return false }'
        self.assertGreaterEqual(source.count(guard), 1)
        result = self.compile_and_run(source.replace(guard, 'guard current.isValid else { return false }'))
        self.assertNotEqual(result.returncode, 0, 'The old empty-state tail behavior must fail the regression')


    def test_mutation_removing_the_scroll_budget_fails(self):
        source = POLICY.read_text()
        budget = 'guard wanted, tailScrollsWithoutGrowth < Self.maximumTailScrollsWithoutGrowth else { return false }'
        self.assertEqual(source.count(budget), 2)
        result = self.compile_and_run(source.replace(budget, 'guard wanted else { return false }'))
        self.assertNotEqual(result.returncode, 0, 'Endless tail scrolls without new content must fail the regression')

    def test_mutation_not_counting_a_created_files_card_fails(self):
        source = POLICY.read_text()
        rule = 'mutating func createdFilesChanged() { value &+= 1 }'
        self.assertEqual(source.count(rule), 1)
        result = self.compile_and_run(source.replace(rule, 'mutating func createdFilesChanged() {}'))
        self.assertNotEqual(result.returncode, 0, 'A card that no longer renews the tail-scroll budget must fail the regression')

    def test_header_rows_are_declared_as_layout_changes(self):
        self.assertEqual(header_declaration_problems(VIEW.read_text()), [])

    def test_mutations_removing_a_header_declaration_fail(self):
        source = VIEW.read_text()
        receipt = '        if session.profileReceipt != nil {\n'
        for old, new in [
            ('            .onChange(of: headerRows) { _, _ in composerLayoutChanged() }\n', ''),
            ('        .onChange(of: rows) { _, _ in onLayoutChange() }\n', ''),
            ('onLayoutChange: { composerLayoutChanged() })', ')'),
            ('profileReceipt: session.profileReceipt != nil, ', ''),
            (receipt, '        if session.creatingFile {\n            Text(verbatim: "Creating")\n        }\n' + receipt),
            (receipt, '        if session.newStepLine != nil {\n            Text(verbatim: "Step")\n        }\n' + receipt),
        ]:
            self.assertEqual(source.count(old), 1, old)
            self.assertNotEqual(header_declaration_problems(source.replace(old, new)), [], old)


if __name__ == '__main__':
    unittest.main()
