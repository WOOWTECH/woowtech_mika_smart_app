import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "Sources/App/FreshInstallKeychainReset.swift"


class FreshInstallKeychainResetTests(unittest.TestCase):
    def check(self, *arguments):
        return subprocess.run([sys.executable, str(ROOT / "scripts/check_fresh_install_keychain_reset.py"), *arguments],
                              cwd=ROOT, capture_output=True, text=True, timeout=600)

    def test_decisions_and_probes(self):
        result = self.check()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("PASS fresh install Keychain reset (Debug):", result.stdout)
        self.assertIn("PASS fresh install Keychain reset (Release):", result.stdout)

    def test_mutants_that_would_clear_an_upgrade_fail(self):
        original = SOURCE.read_text()
        for old, new in [("existing = try hasDefaults() || hasFiles()", "existing = try hasFiles()"),
                         ("catch { existing = true }", "catch { existing = false }")]:
            with self.subTest(mutant=new), tempfile.TemporaryDirectory(prefix="woow-keychain-reset-mutant-") as folder:
                self.assertEqual(original.count(old), 1)
                mutant = Path(folder) / SOURCE.name
                mutant.write_text(original.replace(old, new))
                result = self.check("--source", str(mutant))
                self.assertNotEqual(result.returncode, 0, "the check must catch: " + new)
                self.assertIn("FAIL: ", result.stdout)


if __name__ == "__main__":
    unittest.main()
