import plistlib
from pathlib import Path
import subprocess
import unittest


ROOT = Path(__file__).resolve().parents[1]


class VoiceInputStandaloneTests(unittest.TestCase):
    def test_pure_state_machine_with_fake_driver(self):
        result = subprocess.run(["bash", str(ROOT / "scripts/check_voice_input.sh")],
                                cwd=ROOT, text=True, capture_output=True, timeout=90)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("PASS VoiceInput:", result.stdout)

    def test_apple_adapter_statically_requires_lease_and_does_not_mutate_global_audio(self):
        source = (ROOT / "Sources/App/AppleVoiceInputDriver.swift").read_text()
        self.assertIn("UnavailableVoiceAudioCoordinator()", source)
        self.assertLess(source.index("audioLease.acquire("), source.index("SFSpeechRecognizer.requestAuthorization"))
        self.assertLess(source.index("audioLease.activateForRecording()"), source.index("AVAudioEngine()"))
        self.assertNotRegex(source, r"\.\s*setCategory\s*\(")
        self.assertNotRegex(source, r"\.\s*setActive\s*\(")
        self.assertIn("audioLease.release()", source[source.index("private func cleanup()"):])

    def test_source_plists_explain_microphone_and_speech_in_both_configurations(self):
        for config in ("Debug", "Release"):
            with self.subTest(config=config):
                info = plistlib.loads((ROOT / "Configuration" / f"Info-{config}.plist").read_bytes())
                mic = info["NSMicrophoneUsageDescription"]
                speech = info["NSSpeechRecognitionUsageDescription"]
                self.assertIn("聊天", mic)
                self.assertIn("網站", mic)
                self.assertIn("聊天", speech)
                self.assertIn("裝置上", speech)


if __name__ == "__main__":
    unittest.main()
