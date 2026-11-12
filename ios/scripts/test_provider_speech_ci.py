"""Verify the non-Live CI gate runs every fixture and propagates failures."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


class ProviderSpeechCIGateTest(unittest.TestCase):
    def run_fixture(self, failure=None):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            scripts = root / "scripts"
            scripts.mkdir()
            shutil.copy(Path(__file__).with_name("check_provider_speech_ci.sh"), scripts)
            names = ["check_provider_speech", "check_provider_speech_settings",
                     "check_configured_provider_speech", "check_provider_pcm"]
            for name in names:
                code = 17 if name == failure else 0
                (scripts / (name + ".sh")).write_text(f'echo "fixture {name}"\nexit {code}\n')
            binary = root / "bin"
            binary.mkdir()
            git = binary / "git"
            git.write_text('#!/bin/sh\necho fixture-commit\n')
            git.chmod(0o755)
            (root / "build").mkdir()
            (root / "build" / "check_provider_pcm.log").write_text("stale success\n")
            env = dict(os.environ, PATH=str(binary) + os.pathsep + os.environ.get("PATH", ""))
            result = subprocess.run(["bash", str(scripts / "check_provider_speech_ci.sh")],
                                    text=True, capture_output=True, env=env, timeout=10)
            logs = {path.name: path.read_text() for path in (root / "build").glob("*.log")}
            return result, logs

    def test_all_synthetic_checks_leave_separate_evidence(self):
        result, logs = self.run_fixture()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(logs.pop("provider-speech-source-commit.log"), "fixture-commit\n")
        self.assertEqual(set(logs), {name + ".log" for name in (
            "check_provider_speech", "check_provider_speech_settings",
            "check_configured_provider_speech", "check_provider_pcm")})
        self.assertTrue(all(value.startswith("fixture ") for value in logs.values()))

    def test_failure_is_not_hidden_by_tee_or_following_checks(self):
        result, logs = self.run_fixture("check_provider_speech_settings")
        self.assertEqual(result.returncode, 17)
        self.assertIn("fixture check_provider_speech_settings", logs["check_provider_speech_settings.log"])
        self.assertNotIn("check_provider_pcm.log", logs)


if __name__ == "__main__":
    unittest.main()
