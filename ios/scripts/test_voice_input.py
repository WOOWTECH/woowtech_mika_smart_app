import plistlib
import re
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]


class VoiceInputStandaloneTests(unittest.TestCase):
    def test_voice_ui_fixture_and_release_exclusion(self):
        result = subprocess.run(["python3", str(ROOT / "scripts/check_voice_ui_fixture.py")],
                                cwd=ROOT, text=True, capture_output=True, timeout=90)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("PASS voice UI fixture excluded from Release object", result.stdout)

    def test_chat_composer_with_fake_driver(self):
        result = subprocess.run(["bash", str(ROOT / "scripts/check_chat_voice.sh")],
                                cwd=ROOT, text=True, capture_output=True, timeout=90)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("PASS ChatVoice composer semantics", result.stdout)

    def test_localized_permission_prompts_exist(self):
        resources = ROOT / "Sources/App/Resources"
        for language in ("en", "zh-Hant"):
            source = (resources / (language + ".lproj") / "InfoPlist.strings").read_text()
            with self.subTest(language=language):
                self.assertIn('"NSMicrophoneUsageDescription"', source)
                self.assertIn('"NSSpeechRecognitionUsageDescription"', source)
        # No Simplified Chinese interface (2026-11-13): iOS still picks zh-Hans.lproj
        # for a Simplified Chinese system, and it must hold the Traditional prompts and
        # nothing else. Without it iOS would show English prompts and run the app, and
        # Locale.current with it, in English.
        simplified = resources / "zh-Hans.lproj"
        self.assertEqual([p.name for p in simplified.iterdir() if not p.name.startswith(".")], ["InfoPlist.strings"])
        header, end, body = (simplified / "InfoPlist.strings").read_text().partition("*/\n")
        self.assertTrue(header.startswith("/*") and end, "zh-Hans.lproj/InfoPlist.strings explains itself")
        self.assertEqual(body, (resources / "zh-Hant.lproj/InfoPlist.strings").read_text())

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

    def test_mixed_voice_lifecycle_with_fake_session(self):
        result = subprocess.run(["bash", str(ROOT / "scripts/check_mixed_voice_audio.sh")],
                                cwd=ROOT, text=True, capture_output=True, timeout=90)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("PASS MixedVoiceAudioCoordinator:", result.stdout)

    def test_mixed_apple_adapter_static_policy(self):
        source = (ROOT / "Sources/App/AppleMixedVoiceAudioSession.swift").read_text()
        self.assertIn(".playAndRecord", source)
        self.assertIn(".mixWithOthers", source)
        self.assertIn(".allowBluetoothA2DP", source)
        self.assertNotIn(".defaultToSpeaker", source)
        self.assertNotRegex(source, r"setActive\s*\(\s*false")
        self.assertIn("AppleVoiceInputDriver(audioCoordinator: coordinator)", source)
        driver = (ROOT / "Sources/App/AppleVoiceInputDriver.swift").read_text()
        for notification in ("interruptionNotification", "routeChangeNotification", "mediaServicesWereResetNotification"):
            self.assertIn(notification, driver)

    def test_direct_webview_construction_inventory_requires_audio_review(self):
        # This is a source inventory guard, not proof of WebKit quiescence.
        constructors = set()
        for path in (ROOT / "Sources").rglob("*.swift"):
            if re.search(r"\bWKWebView\s*\(", path.read_text()):
                constructors.add(path.relative_to(ROOT).as_posix())
        self.assertEqual(constructors, {
            "Sources/App/BrowserSession.swift",
            "Sources/App/ChatWebTaskTab.swift",
        }, "Review the audio admission inventory when a new direct constructor appears")

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
        speech_auth = source[source.index("private func speechAuthorization"):source.index("private func microphoneAuthorization")]
        microphone_auth = source[source.index("private func microphoneAuthorization"):source.index("private func permittedToStart")]
        self.assertIn("guard permittedToStart(id: id)", speech_auth)
        self.assertLess(microphone_auth.index("guard permittedToStart(id: id)"), microphone_auth.index("audioLease.activateForRecording()"))
        self.assertLess(microphone_auth.index("newEngine.prepare()"), microphone_auth.rindex("guard permittedToStart(id: id)"))
        self.assertLess(microphone_auth.rindex("guard permittedToStart(id: id)"), microphone_auth.index("try newEngine.start()"))
        self.assertIn("UIApplication.shared.applicationState == .active", source)
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
