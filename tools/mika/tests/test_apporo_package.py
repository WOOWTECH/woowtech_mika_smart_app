"""Apporo detection across USB and URL connections; existing brands remain stable."""
import importlib.util
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location('apporo_cli_test', Path(__file__).parents[1] / 'scripts/mika_cli.py')
cli = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cli)

class ApporoPackageTest(unittest.TestCase):
    def test_url_identity_and_existing_brands(self):
        for version, name in [('0.1.37-apporo.1', 'Apporo Assistant'), ('0.1.37-woow.3', 'woowtech agent'), ('0.1.37', 'Mika')]:
            cli.APP.update(name='unknown', package=None)
            cli.identify({'server_version': version})
            self.assertEqual(cli.APP['name'], name)

    def test_explicit_package_keeps_identity(self):
        cli.APP.update(name=cli.PACKAGES['com.apporo.assistant'], package='com.apporo.assistant')
        cli.identify({'server_version': 'unknown'})
        self.assertEqual(cli.app_text('Open Mika once'), 'Open Apporo Assistant once')
        self.assertEqual(cli.phone_file('com.apporo.assistant', 'mcp-usb.json'), '/sdcard/Android/data/com.apporo.assistant/files/mcp-usb.json')
