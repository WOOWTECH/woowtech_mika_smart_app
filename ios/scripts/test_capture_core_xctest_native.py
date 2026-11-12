"""Synthetic subprocess fixtures; no native XCTest evidence is produced."""
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
import capture_core_xctest_native as capture
from core_xctest_inventory import TARGETS


class CaptureTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='core-native-capture-')
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name)
        self.root = self.base / 'checkout'
        self.root.mkdir()
        subprocess.run(['git', 'init', '-q', str(self.root)], check=True)
        (self.root / 'source').write_text('source')
        subprocess.run(['git', '-C', str(self.root), 'add', 'source'], check=True)
        subprocess.run(['git', '-C', str(self.root), '-c', 'user.name=Fixture', '-c',
                        'user.email=fixture@example.invalid', 'commit', '-qm', 'fixture'], check=True)
        self.products = self.base / 'Fixture.xctestproducts'
        self.products.mkdir()
        (self.products / 'testbundle').write_bytes(b'synthetic fixture')
        self.output = self.base / 'capture'
        self.simulator = '00000000-0000-0000-0000-000000000000'
        self.commands = []

    def runner(self, cmd, output, timeout):
        self.commands.append(cmd)
        output.write_text('synthetic subprocess output; not native evidence')
        if '-enumerate-tests' in cmd:
            Path(cmd[cmd.index('-test-enumeration-output-path') + 1]).write_text('{}')
        if '-resultBundlePath' in cmd:
            Path(cmd[cmd.index('-resultBundlePath') + 1]).mkdir()
        if 'xcresulttool' in cmd and 'summary' in cmd:
            output.write_text(json.dumps(self.summary()))
        return 0

    def summary(self):
        counts = {'passedTests': 1, 'failedTests': 0, 'skippedTests': 0, 'expectedFailures': 0}
        return {'result': 'Passed', 'totalTestCount': 1, **counts,
                'devicesAndConfigurations': [{'device': {'deviceId': self.simulator, 'platform': 'iOS Simulator'}, **counts}]}

    def call(self, runner=None):
        return capture.capture(self.root, self.products, self.simulator, self.output, runner or self.runner)

    def test_even_fake_success_fails_closed_and_commands_are_scoped(self):
        with self.assertRaisesRegex(capture.CaptureError, 'not yet verified'): self.call()
        self.assertEqual(len(self.commands), 5)
        enumerate_cmd, test_cmd = self.commands[1:3]
        self.assertIn('-enumerate-tests', enumerate_cmd)
        self.assertNotIn('-enumerate-tests', test_cmd)
        for cmd in (enumerate_cmd, test_cmd):
            self.assertEqual([a for a in cmd if a.startswith('-only-testing:')],
                             ['-only-testing:' + t for t in TARGETS])
            self.assertEqual(cmd[cmd.index('-parallel-testing-enabled') + 1], 'NO')
        self.assertEqual(self.commands[3][1:4], ['xcresulttool', 'get', 'test-results'])
        self.assertFalse(json.loads((self.output / 'capture-context.json').read_text())['native_provenance_verified'])
        self.assertFalse((self.output / 'full-receipt.json').exists())

    def test_discovery_failure_and_empty_output_prevent_execution(self):
        for mode in ('failure', 'empty', 'missing'):
            with self.subTest(mode=mode):
                def runner(cmd, log, timeout):
                    log.write_text('fake')
                    if '-enumerate-tests' in cmd:
                        if mode == 'empty': Path(cmd[-1]).write_text('')
                        return 1 if mode == 'failure' else 0
                    self.assertNotIn('-resultBundlePath', cmd)
                    return 0
                with self.assertRaises(capture.CaptureError):
                    capture.capture(self.root, self.products, self.simulator, self.base / mode, runner)

    def test_failed_run_missing_result_or_export_never_pass(self):
        for mode in ('run', 'result', 'summary', 'tests'):
            with self.subTest(mode=mode):
                def runner(cmd, log, timeout):
                    log.write_text('fake')
                    if '-enumerate-tests' in cmd: Path(cmd[-1]).write_text('{}')
                    if '-resultBundlePath' in cmd:
                        if mode != 'result': Path(cmd[cmd.index('-resultBundlePath') + 1]).mkdir()
                        return 1 if mode == 'run' else 0
                    if mode in ('summary', 'tests') and mode in cmd: return 1
                    return 0
                with self.assertRaises(capture.CaptureError):
                    capture.capture(self.root, self.products, self.simulator, self.base / mode, runner)

    def test_product_mutation_after_discovery_or_execution_fails(self):
        for phase in ('discovery', 'execution'):
            with self.subTest(phase=phase):
                def runner(cmd, log, timeout):
                    code = self.runner(cmd, log, timeout)
                    if (phase == 'discovery' and '-enumerate-tests' in cmd or
                            phase == 'execution' and '-resultBundlePath' in cmd):
                        (self.products / 'testbundle').write_bytes(phase.encode())
                    return code
                with self.assertRaisesRegex(capture.CaptureError, 'product'):
                    capture.capture(self.root, self.products, self.simulator, self.base / phase, runner)

    def test_dirty_checkout_invalid_udid_and_existing_output_fail(self):
        (self.root / 'new-untracked').write_text('test')
        with self.assertRaisesRegex(capture.CaptureError, 'checkout'): self.call()
        (self.root / 'new-untracked').unlink()
        with self.assertRaisesRegex(capture.CaptureError, 'UDID'):
            capture.capture(self.root, self.products, 'booted', self.output, self.runner)
        self.output.mkdir()
        with self.assertRaises(FileExistsError): self.call()

    def test_tree_hash_sees_symlink_target_and_contents(self):
        link = self.products / 'link'
        (self.products / 'other').write_text('other')
        link.symlink_to('testbundle')
        first = capture.hash_tree(self.products)
        link.unlink()
        link.symlink_to('other')
        self.assertNotEqual(first, capture.hash_tree(self.products))
        link.unlink()
        (self.products / 'testbundle').write_text('changed')
        self.assertNotEqual(first, capture.hash_tree(self.products))
        link.symlink_to(self.root / 'source')
        with self.assertRaisesRegex(capture.CaptureError, 'escapes'): capture.hash_tree(self.products)

    def test_xcresult_summary_rejects_skips_and_wrong_or_missing_destination(self):
        good = self.summary()
        capture.check_summary(good, self.simulator)
        for change in ({'skippedTests': 1}, {'expectedFailures': 1}, {'failedTests': 1},
                       {'result': 'Failed'}, {'totalTestCount': 0}, {'passedTests': True},
                       {'devicesAndConfigurations': []}, {'testFailures': [{}]}):
            with self.subTest(change=change), self.assertRaises(capture.CaptureError):
                capture.check_summary({**good, **change}, self.simulator)
        with self.assertRaises(capture.CaptureError):
            capture.check_summary(good, '11111111-1111-1111-1111-111111111111')


if __name__ == '__main__': unittest.main()
