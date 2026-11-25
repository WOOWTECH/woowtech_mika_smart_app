import re
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "Sources/App/MCPToolsView.swift"


class MCPSignInScreenTests(unittest.TestCase):
    def check(self, *arguments):
        return subprocess.run([sys.executable, str(ROOT / "scripts/check_mcp_sign_in_screen.py"), *arguments],
                              cwd=ROOT, capture_output=True, text=True, timeout=60)

    def test_no_secure_field_is_on_the_page_during_a_sign_in(self):
        result = self.check()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("PASS MCP server page:", result.stdout)

    def test_mutants_that_leave_a_secure_field_on_screen_fail(self):
        original = SOURCE.read_text()
        mutants = {
            "the endpoint's placeholder is gone": (r"MCPSecretPlaceholder\(localizer\.text\(\.mcpEndpoint\)\)", 'Text(verbatim: "")'),
            "the client secret's placeholder is gone": (r"MCPSecretPlaceholder\(localizer\.text\(\.mcpClientSecret\)\)", 'Text(verbatim: "")'),
            "the endpoint's guard never holds": (r"if session\.isSigningIn \{(\s*MCPSecretPlaceholder\(localizer\.text\(\.mcpEndpoint)", r"if false {\1"),
            "a new secure field joins the page": (r"SecureField\(localizer\.text\(\.mcpClientSecret\)", "SecureField(localizer.text(.mcpClientID)"),
        }
        for name, (pattern, replacement) in mutants.items():
            with self.subTest(mutant=name), tempfile.TemporaryDirectory(prefix="woow-sign-in-screen-mutant-") as folder:
                mutated, count = re.subn(pattern, replacement, original, count=1)
                self.assertEqual(count, 1, name)
                mutant = Path(folder) / SOURCE.name
                mutant.write_text(mutated)
                result = self.check("--source", str(mutant))
                self.assertNotEqual(result.returncode, 0, "the check must catch: " + name)
                self.assertIn("FAIL: ", result.stderr + result.stdout)


if __name__ == "__main__":
    unittest.main()
