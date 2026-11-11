"""Run the real About bundle/translation fixture through the CI script gate."""

from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]


class MikaAboutTests(unittest.TestCase):
    def test_installed_version_missing_values_and_languages(self):
        compiler = shutil.which("swiftc")
        self.assertIsNotNone(compiler, "The iOS CI preflight requires the Swift toolchain")
        with tempfile.TemporaryDirectory(prefix="woow-mika-about-") as directory:
            binary = Path(directory) / "CheckMikaAbout"
            build = subprocess.run(
                [compiler, "-swift-version", "5", "-warnings-as-errors",
                 str(ROOT / "Sources/App/AppLanguage.swift"),
                 str(ROOT / "Sources/App/MikaAboutInfo.swift"),
                 str(ROOT / "scripts/CheckMikaAbout.swift"), "-o", str(binary)],
                capture_output=True, text=True, timeout=60,
            )
            self.assertEqual(build.returncode, 0, build.stderr[-4000:])
            result = subprocess.run([str(binary)], capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr[-4000:])
            match = re.fullmatch(r"MikaAbout: (\d+) assertions passed\n?", result.stdout)
            self.assertIsNotNone(match, "The actual bundle fixture must report its checks")
            self.assertGreaterEqual(int(match.group(1)), 25)


if __name__ == "__main__":
    unittest.main()
