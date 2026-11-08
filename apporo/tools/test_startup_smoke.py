"""Lightweight host tests only: no Android SDK/device/model required."""
import importlib.util
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
import xml.etree.ElementTree as ET

spec = importlib.util.spec_from_file_location('startup_smoke', Path(__file__).with_name('startup-smoke.py'))
smoke = importlib.util.module_from_spec(spec)
spec.loader.exec_module(smoke)


class StartupEvidenceTest(unittest.TestCase):
    def test_avd_requires_registration_config_and_emulator_discovery(self):
        with tempfile.TemporaryDirectory() as directory:
            avd_root = Path(directory).resolve()
            name = 'apporo-smoke-35'
            avd = avd_root / (name + '.avd')
            avd.mkdir()
            registration = avd_root / (name + '.ini')
            registration.write_text('path=' + str(avd) + '\n')
            with self.assertRaisesRegex(RuntimeError, 'missing'):
                smoke.verify_avd(avd_root, name, name + '\n')
            (avd / 'config.ini').write_text('AvdId=' + name + '\n')
            with self.assertRaisesRegex(RuntimeError, 'discovery mismatch'):
                smoke.verify_avd(avd_root, name, 'other-avd\n')
            registration.write_text('path=/wrong/avd\n')
            with self.assertRaisesRegex(RuntimeError, 'discovery mismatch'):
                smoke.verify_avd(avd_root, name, name + '\n')
            registration.write_text('path=' + str(avd) + '\n')
            smoke.verify_avd(avd_root, name, name + '\n')
            registration.unlink()
            with self.assertRaisesRegex(RuntimeError, 'missing'):
                smoke.verify_avd(avd_root, name, name + '\n')

    def test_brand_and_action_must_belong_to_app(self):
        def xml(package, title, action):
            root = ET.Element('hierarchy')
            for text in (title, action):
                ET.SubElement(root, 'node', package=package, text=text)
            return ET.tostring(root)
        self.assertTrue(smoke.welcome_visible(xml(smoke.PACKAGE, *smoke.WELCOME)))
        self.assertFalse(smoke.welcome_visible(xml('com.android.launcher3', *smoke.WELCOME)))
        self.assertFalse(smoke.welcome_visible(xml(smoke.PACKAGE, 'Hi, I’m Mika', 'Get started')))
        self.assertFalse(smoke.welcome_visible(xml(smoke.PACKAGE, 'Meet Apporo Assistant', '')))
        with self.assertRaises(ET.ParseError):
            smoke.welcome_visible('<hierarchy>')

    def test_expected_text_matches_real_resources(self):
        root = Path(__file__).resolve().parents[2]
        brand = ET.parse(root / 'app/src/apporo/res/values/strings_apporo.xml')
        upstream = ET.parse(root / 'app/src/main/res/values/strings_setup.xml')
        self.assertEqual(smoke.WELCOME[0], brand.find("string[@name='welcome_title']").text)
        self.assertEqual(smoke.WELCOME[1], upstream.find("string[@name='welcome_start']").text)

    def test_java_native_anr_and_subprocess_crashes_fail_not_unrelated_apps(self):
        for line in ('AndroidRuntime: Process: com.apporo.assistant, PID: 42',
                     'DEBUG: pid: 42, tid: 42 >>> com.apporo.assistant <<<',
                     'ActivityManager: ANR in com.apporo.assistant',
                     'am_crash: [0,42,com.apporo.assistant,123,error]',
                     'am_anr: [0,42,com.apporo.assistant,123,error]',
                     'AndroidRuntime: Process: com.apporo.assistant:worker, PID: 43'):
            with self.subTest(line=line):
                self.assertTrue(smoke.app_crash(line))
        for line in ('ActivityManager: Start proc 42:com.apporo.assistant/u0a123',
                     'FATAL EXCEPTION: main\nProcess: com.android.launcher3, PID: 9',
                     'Process: com.apporo.assistant.other, PID: 7',
                     'am_anr: [0,7,com.apporo.assistant.other,123,error]'):
            with self.subTest(line=line):
                self.assertFalse(smoke.app_crash(line))

    def test_real_subprocess_timeout_and_exit_status(self):
        with self.assertRaises(subprocess.TimeoutExpired):
            smoke.run([sys.executable, '-c', 'import time; time.sleep(60)'], timeout=0.1)
        with self.assertRaises(RuntimeError):
            smoke.run([sys.executable, '-c', 'raise SystemExit(3)'])
        self.assertEqual(smoke.run([sys.executable, '-c', 'print("ok")'])[0], b'ok\n')


if __name__ == '__main__':
    unittest.main()
