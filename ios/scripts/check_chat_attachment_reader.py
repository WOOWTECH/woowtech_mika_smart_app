#!/usr/bin/env python3
"""Compile and run the native chat attachment reader checks with swiftc (no simulator)."""
import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCES = [str(ROOT / 'Sources/App/ChatAttachmentReader.swift'),
           str(ROOT / 'scripts/CheckChatAttachmentReader.swift')]
# Swift 6 mode checks the reader's strict concurrency; the app target itself builds as Swift 5.
FLAGS = ['-swift-version', '6', '-parse-as-library', '-warnings-as-errors']


class ChatAttachmentReaderTests(unittest.TestCase):
    def test_reads_photos_text_pdf_and_rtf(self):
        with tempfile.TemporaryDirectory() as out:
            binary = Path(out) / 'CheckChatAttachmentReader'
            built = subprocess.run(['swiftc', *FLAGS, *SOURCES, '-o', str(binary)],
                                   capture_output=True, text=True, timeout=300)
            self.assertEqual(built.returncode, 0, built.stderr)
            fixtures = Path(out) / 'fixtures'
            fixtures.mkdir()
            result = subprocess.run([str(binary), str(fixtures)], capture_output=True, text=True, timeout=60)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(json.loads(result.stdout), {'assertions': 53})

    def test_typechecks_for_ios_17(self):
        """The macOS run cannot see iOS availability; the app's deployment target is iOS 17."""
        sdk = subprocess.run(['xcrun', '--sdk', 'iphoneos', '--show-sdk-path'],
                             capture_output=True, text=True) if shutil.which('xcrun') else None
        if sdk is None or sdk.returncode != 0:
            self.skipTest('no iOS SDK')
        result = subprocess.run(['swiftc', '-typecheck', *FLAGS, '-sdk', sdk.stdout.strip(),
                                 '-target', 'arm64-apple-ios17.0', *SOURCES],
                                capture_output=True, text=True, timeout=300)
        self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == '__main__':
    unittest.main()
