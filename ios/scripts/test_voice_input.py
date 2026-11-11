import plistlib
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]


class VoiceInputStandaloneTests(unittest.TestCase):
    def test_pure_state_machine_with_fake_driver(self):
        result = subprocess.run(["bash", str(ROOT / "scripts/check_voice_input.sh")],
                                cwd=ROOT, text=True, capture_output=True, timeout=90)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("PASS VoiceInput:", result.stdout)

    def test_isolated_coordinator_with_fake_fence_and_session(self):
        result = subprocess.run(["bash", str(ROOT / "scripts/check_voice_audio_coordinator.sh")],
                                cwd=ROOT, text=True, capture_output=True, timeout=90)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("PASS SharedVoiceAudioCoordinator:", result.stdout)

    def test_revocation_type_rejects_synchronous_nonisolated_call(self):
        with tempfile.TemporaryDirectory() as directory:
            invalid = Path(directory) / "Nonisolated.swift"
            invalid.write_text("func invalid(_ revoke: @escaping VoiceAudioRevocation) { revoke() }\n")
            result = subprocess.run(
                ["swiftc", "-typecheck", "-strict-concurrency=complete", "-warnings-as-errors",
                 str(ROOT / "Sources/App/VoiceAudioLease.swift"), str(invalid)],
                cwd=ROOT, text=True, capture_output=True, timeout=30)
            self.assertNotEqual(result.returncode, 0, "nonisolated callback unexpectedly compiled")
            self.assertIn("main actor-isolated", result.stderr)

    def test_apple_adapter_statically_requires_lease_and_does_not_mutate_global_audio(self):
        source = (ROOT / "Sources/App/AppleVoiceInputDriver.swift").read_text()
        self.assertIn("UnavailableVoiceAudioCoordinator()", source)
        self.assertLess(source.index("audioLease.acquire("), source.index("SFSpeechRecognizer.requestAuthorization"))
        self.assertLess(source.index("audioLease.activateForRecording()"), source.index("AVAudioEngine()"))
        self.assertNotRegex(source, r"\.\s*setCategory\s*\(")
        self.assertNotRegex(source, r"\.\s*setActive\s*\(")
        cleanup = source[source.index("private func cleanup()"):]
        self.assertLess(cleanup.index("engine.stop()"), cleanup.index("audioLease.release()"))
        finish = source[source.index("    func finish(id:"):source.index("    func cancel(id:")]
        self.assertLess(finish.index("engine.stop()"), finish.index("audioLease.release()"))

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
