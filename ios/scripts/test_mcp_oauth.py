import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OAUTH = "Sources/AssistantMCP/MCPOAuth.swift"
CLIENT = "Sources/AssistantMCP/MCPClient.swift"
SESSION = "Sources/App/MCPSession.swift"


class MCPOAuthTests(unittest.TestCase):
    def check(self, *arguments):
        return subprocess.run([sys.executable, str(ROOT / "scripts/check_mcp_oauth.py"), *arguments],
                              cwd=ROOT, capture_output=True, text=True, timeout=1800)

    def test_sign_in_checks(self):
        result = self.check()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("PASS MCP OAuth sign-in (Debug):", result.stdout)
        self.assertIn("PASS MCP OAuth sign-in (Release):", result.stdout)

    def test_mutants_that_would_skip_a_sign_in_check_fail(self):
        for source, old, new in [
                (OAUTH, 'guard params["state"] == attempt.state else', 'guard params["state"] != nil else'),
                (OAUTH, '("code_verifier", attempt.verifier)', '("code_verifier", attempt.state)'),
                (OAUTH, "[allowed(challenge?.resourceMetadata), wellKnown(", "[wellKnown("),
                (CLIENT, "let refreshed = try await accessToken(rejected: token)", "let refreshed = token"),
                (SESSION, "if (error as? MCPError) == .signInRequired {", "if (error as? MCPError) == .transportFailure {")]:
            original = (ROOT / source).read_text()
            with self.subTest(mutant=new), tempfile.TemporaryDirectory(prefix="woow-mcp-oauth-mutant-") as folder:
                self.assertEqual(original.count(old), 1)
                mutant = Path(folder) / Path(source).name
                mutant.write_text(original.replace(old, new))
                result = self.check("--replace", source, str(mutant), "--config", "Debug")
                self.assertNotEqual(result.returncode, 0, "the check must catch: " + new)
                self.assertIn("FAIL: ", result.stdout)


if __name__ == "__main__":
    unittest.main()
