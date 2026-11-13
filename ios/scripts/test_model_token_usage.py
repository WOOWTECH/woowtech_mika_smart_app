import subprocess
import sys
import unittest
from pathlib import Path


class ModelTokenUsageTests(unittest.TestCase):
    def test_intercepted_transport(self):
        root = Path(__file__).resolve().parents[1]
        result = subprocess.run([sys.executable, str(root / "scripts/check_model_token_usage.py")],
                                cwd=root, capture_output=True, text=True, timeout=360)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("PASS model usage:", result.stdout)


if __name__ == "__main__":
    unittest.main()
