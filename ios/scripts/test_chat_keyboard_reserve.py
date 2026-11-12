#!/usr/bin/env python3
"""Compile and run the pure chat keyboard-reserve geometry checks."""
import json
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class ChatKeyboardReserveTests(unittest.TestCase):
    def test_only_docked_keyboards_reserve_space(self):
        with tempfile.TemporaryDirectory() as out:
            binary = Path(out) / 'CheckChatKeyboardReserve'
            subprocess.run(['swiftc', '-swift-version', '5', '-parse-as-library',
                            str(ROOT / 'Sources/App/ChatKeyboardDock.swift'),
                            str(ROOT / 'scripts/CheckChatKeyboardReserve.swift'), '-o', str(binary)],
                           check=True, capture_output=True, timeout=300)
            result = subprocess.run([str(binary)], check=True, capture_output=True, text=True, timeout=30)
            self.assertEqual(json.loads(result.stdout), {'assertions': 14})


if __name__ == '__main__':
    unittest.main()
