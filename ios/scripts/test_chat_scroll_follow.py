"""Portable regression for empty-state scrolling and transcript follow."""
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
POLICY = ROOT / 'Sources/App/ChatScrollFollowPolicy.swift'
CHECKS = ROOT / 'scripts/CheckChatScrollFollow.swift'


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
        self.assertEqual(source.count(guard), 1)
        result = self.compile_and_run(source.replace(guard, 'guard current.isValid else { return false }'))
        self.assertNotEqual(result.returncode, 0, 'The old empty-state tail behavior must fail the regression')


if __name__ == '__main__':
    unittest.main()
