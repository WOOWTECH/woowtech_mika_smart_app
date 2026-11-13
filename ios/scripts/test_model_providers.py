import subprocess
import sys
import unittest
from pathlib import Path


class ModelProvidersTests(unittest.TestCase):
    def test_document_import_keychain_and_consent(self):
        root = Path(__file__).resolve().parents[1]
        result = subprocess.run([sys.executable, str(root / "scripts/check_model_providers.py")],
                                cwd=root, capture_output=True, text=True, timeout=600)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("PASS model providers:", result.stdout)


if __name__ == "__main__":
    unittest.main()
