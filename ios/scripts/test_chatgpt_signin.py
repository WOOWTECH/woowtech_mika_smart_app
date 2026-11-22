import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SIGN_IN = "Sources/AssistantModels/ChatGPTSignIn.swift"
ACCOUNTS = "Sources/AssistantModels/ModelAccounts.swift"


class AccountSignInTests(unittest.TestCase):
    def check(self, *arguments):
        return subprocess.run([sys.executable, str(ROOT / "scripts/check_chatgpt_signin.py"), *arguments],
                              cwd=ROOT, capture_output=True, text=True, timeout=1800)

    def test_sign_in_checks(self):
        result = self.check()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("PASS account sign-in (Debug):", result.stdout)
        self.assertIn("PASS account sign-in (Release):", result.stdout)

    def test_mutants_that_would_skip_a_sign_in_check_fail(self):
        for source, old, new in [
                (SIGN_IN, 'guard params["state"] == attempt.state else', 'guard params["state"] != nil else'),
                (SIGN_IN, 'guard claims["nonce"] as? String == nonce else', 'guard claims["nonce"] != nil else'),
                (SIGN_IN, "guard tokens.scopes.contains(planScope) else", "guard !tokens.scopes.isEmpty else"),
                (ACCOUNTS, "nowMs() < session.expiresAtMs - refreshAheadMs", "nowMs() < session.expiresAtMs")]:
            original = (ROOT / source).read_text()
            with self.subTest(mutant=new), tempfile.TemporaryDirectory(prefix="woow-account-mutant-") as folder:
                self.assertEqual(original.count(old), 1)
                mutant = Path(folder) / Path(source).name
                mutant.write_text(original.replace(old, new))
                result = self.check("--replace", source, str(mutant), "--config", "Debug")
                self.assertNotEqual(result.returncode, 0, "the check must catch: " + new)
                self.assertIn("FAIL: ", result.stdout)


if __name__ == "__main__":
    unittest.main()
