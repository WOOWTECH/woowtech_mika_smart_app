import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SIGN_IN = "Sources/AssistantModels/ChatGPTSignIn.swift"


class ChatGPTSignInTests(unittest.TestCase):
    def check(self, *arguments):
        return subprocess.run([sys.executable, str(ROOT / "scripts/check_chatgpt_signin.py"), *arguments],
                              cwd=ROOT, capture_output=True, text=True, timeout=1200)

    def test_prototype_checks(self):
        result = self.check()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("PASS ChatGPT sign-in prototype (Debug):", result.stdout)
        self.assertIn("PASS ChatGPT sign-in prototype (Release):", result.stdout)

    def test_mutants_that_would_skip_a_sign_in_check_fail(self):
        original = (ROOT / SIGN_IN).read_text()
        for old, new in [('guard params["state"] == attempt.state else', 'guard params["state"] != nil else'),
                         ('guard claims["nonce"] as? String == nonce else', 'guard claims["nonce"] != nil else'),
                         ("guard tokens.scopes.contains(planScope) else", "guard !tokens.scopes.isEmpty else")]:
            with self.subTest(mutant=new), tempfile.TemporaryDirectory(prefix="woow-chatgpt-mutant-") as folder:
                self.assertEqual(original.count(old), 1)
                mutant = Path(folder) / Path(SIGN_IN).name
                mutant.write_text(original.replace(old, new))
                result = self.check("--replace", SIGN_IN, str(mutant), "--config", "Debug")
                self.assertNotEqual(result.returncode, 0, "the check must catch: " + new)
                self.assertIn("FAIL: ", result.stdout)


if __name__ == "__main__":
    unittest.main()
