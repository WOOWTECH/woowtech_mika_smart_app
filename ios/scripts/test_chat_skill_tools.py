import subprocess
import sys
import unittest
from pathlib import Path


class ChatSkillToolsTests(unittest.TestCase):
    def test_skill_tools_catalog_save_and_flow_entry(self):
        root = Path(__file__).resolve().parents[1]
        result = subprocess.run([sys.executable, str(root / "scripts/check_chat_skill_tools.py"), "--configuration", "Debug"],
                                cwd=root, capture_output=True, text=True, timeout=900)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("PASS chat skill tools:", result.stdout)


if __name__ == "__main__":
    unittest.main()
