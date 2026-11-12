"""Portable provider PCM/source fixture; never requests audio or network access."""
import shutil
import subprocess
import sys
import unittest
from pathlib import Path


@unittest.skipUnless(sys.platform == "darwin" and shutil.which("swiftc"), "requires macOS Swift toolchain")
class ProviderPCMStandaloneTest(unittest.TestCase):
    def test_synthetic_capture_resampling_and_lifecycle(self):
        script = Path(__file__).resolve().with_name("check_provider_pcm.sh")
        result = subprocess.run(["bash", str(script)], text=True, capture_output=True, timeout=180, check=False)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("PASS provider PCM:", result.stdout)
        print(result.stdout, end="")


if __name__ == "__main__":
    unittest.main()
