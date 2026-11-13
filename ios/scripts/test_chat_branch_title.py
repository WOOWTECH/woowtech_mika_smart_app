#!/usr/bin/env python3
"""Compile and run the pure branch-title checks for the chat message menu."""
import json
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class ChatBranchTitleTests(unittest.TestCase):
    def test_branch_titles_match_android_and_the_archive(self):
        with tempfile.TemporaryDirectory() as out:
            binary = Path(out) / 'CheckChatBranchTitle'
            subprocess.run(['swiftc', '-swift-version', '5', '-parse-as-library',
                            str(ROOT / 'Sources/App/ChatMessageActions.swift'),
                            str(ROOT / 'scripts/CheckChatBranchTitle.swift'), '-o', str(binary)],
                           check=True, capture_output=True, timeout=300)
            result = subprocess.run([str(binary)], check=True, capture_output=True, text=True, timeout=30)
            self.assertEqual(json.loads(result.stdout), {'assertions': 22})


if __name__ == '__main__':
    unittest.main()
