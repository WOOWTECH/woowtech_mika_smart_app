import subprocess
import sys
import unittest
from pathlib import Path


class ChatWebTaskTests(unittest.TestCase):
    def test_policy_commands_pacing_and_runner(self):
        root = Path(__file__).resolve().parents[1]
        result = subprocess.run([sys.executable, str(root / "scripts/check_chat_web_task_core.py")],
                                cwd=root, capture_output=True, text=True, timeout=1200)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("PASS chat web task core:", result.stdout)


if __name__ == "__main__":
    unittest.main()
