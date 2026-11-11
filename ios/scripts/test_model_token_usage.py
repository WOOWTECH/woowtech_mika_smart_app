import subprocess
import unittest
from pathlib import Path


class ModelTokenUsageTests(unittest.TestCase):
    def test_intercepted_transport(self):
        root = Path(__file__).resolve().parents[1]
        result = subprocess.run(["python3", str(root / "scripts/check_model_token_usage.py")],
                                cwd=root, capture_output=True, text=True, timeout=240)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("PASS model usage:", result.stdout)
