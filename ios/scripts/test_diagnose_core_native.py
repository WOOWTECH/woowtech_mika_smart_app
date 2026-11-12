"""Mocked diagnostic orchestration. Fixtures never enter CI native artifacts."""
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
import diagnose_core_native as diag
import sync_monorepo_workflows as sync
from core_xctest_inventory import TARGETS


class DiagnosticTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='fake-core-diagnostic-')
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.product = self.base / 'Synthetic.xctestproducts'
        self.product.mkdir()
        (self.product / 'synthetic-product').write_bytes(b'never an XCTest product')
        self.output = self.base / 'output'
        self.sim = '00000000-0000-0000-0000-000000000000'
        self.metadata = {'source_commit': 'a' * 40, 'workflow_ref': 'synthetic', 'run_id': '1',
                         'run_attempt': '1', 'xcode': '16.4', 'runtime': 'fixture', 'device': 'fixture'}
        self.commands = []
        self.patcher = patch.dict(os.environ, {'HOME': str(self.base), 'DEVELOPER_DIR': '/synthetic',
                                               'TMPDIR': str(self.base), 'SECRET_EXAMPLE': 'must-not-reach-child'}, clear=True)
        self.patcher.start()
        self.addCleanup(self.patcher.stop)

    def runner(self, command, stdout, stderr, seconds, environment):
        self.commands.append((command, environment))
        stdout.write_text('{"synthetic": true}')
        stderr.write_text('synthetic only')
        if '-enumerate-tests' in command:
            Path(command[command.index('-test-enumeration-output-path') + 1]).write_text('{"synthetic": true}')
        if '-resultBundlePath' in command:
            Path(command[command.index('-resultBundlePath') + 1]).mkdir()
        return 0

    def run_capture(self, runner=None):
        return diag.capture(self.product, self.sim, self.output, self.metadata, run=runner or self.runner)

    def manifest(self):
        return json.loads((self.output / 'manifest.json').read_text())

    def test_capture_is_diagnostic_only_and_never_inherits_secrets(self):
        self.assertTrue(self.run_capture())  # synthetic collection completion only
        manifest = self.manifest()
        self.assertFalse(manifest['gate_eligible'])
        self.assertFalse(manifest['native_provenance_verified'])
        self.assertIn('not a gate', manifest['purpose'])
        self.assertEqual(len(self.commands), 4)
        for command, env in self.commands:
            self.assertEqual(set(env), {'HOME', 'TMPDIR', 'DEVELOPER_DIR', 'PATH'})
            self.assertNotIn('SECRET_EXAMPLE', env)
            if command[0] == '/usr/bin/xcodebuild':
                self.assertEqual([x for x in command if x.startswith('-only-testing:')],
                                 ['-only-testing:' + target for target in TARGETS])
        self.assertFalse((self.output / 'full-receipt.json').exists())

    def test_discovery_failure_does_not_forge_it_and_execution_is_still_collected(self):
        def runner(command, stdout, stderr, seconds, env):
            result = self.runner(command, stdout, stderr, seconds, env)
            return 65 if '-enumerate-tests' in command else result
        self.assertFalse(self.run_capture(runner))
        manifest = self.manifest()
        self.assertEqual(manifest['phases']['discovery']['exit_code'], 65)
        self.assertEqual(manifest['phases']['execution']['exit_code'], 0)
        self.assertTrue((self.output / 'tests.stdout').is_file())
        self.assertFalse(manifest['gate_eligible'])

    def test_failure_timeout_invalid_json_missing_result_or_mutation_fail_capture(self):
        for kind in ('execution', 'timeout', 'missing', 'invalid', 'empty', 'mutation'):
            with self.subTest(kind=kind):
                output = self.base / kind
                def runner(command, stdout, stderr, seconds, env):
                    result = self.runner(command, stdout, stderr, seconds, env)
                    if '-resultBundlePath' in command:
                        path = Path(command[command.index('-resultBundlePath') + 1])
                        if kind == 'missing': path.rmdir()
                        if kind == 'execution': return 1
                        if kind == 'timeout': return None
                        if kind == 'mutation': (self.product / 'synthetic-product').write_bytes(b'changed')
                    if 'xcresulttool' in command and 'tests' in command:
                        if kind == 'invalid': stdout.write_text('bad json')
                        if kind == 'empty': stdout.write_text('{}')
                    return result
                result = diag.capture(self.product, self.sim, output, self.metadata, run=runner)
                self.assertFalse(result)
                manifest = json.loads((output / 'manifest.json').read_text())
                self.assertFalse(manifest['gate_eligible'])
                self.assertFalse(manifest['capture_complete'])

    def test_skip_in_summary_does_not_become_gate_result(self):
        def runner(command, stdout, stderr, seconds, env):
            result = self.runner(command, stdout, stderr, seconds, env)
            if 'xcresulttool' in command and 'summary' in command:
                stdout.write_text('{"result":"Passed","skippedTests":1}')
            return result
        self.assertTrue(self.run_capture(runner))
        self.assertFalse(self.manifest()['gate_eligible'])
        self.assertFalse(self.manifest()['native_provenance_verified'])

    def test_existing_output_and_invalid_configuration_rejected_before_running(self):
        self.output.mkdir()
        with self.assertRaises(FileExistsError): self.run_capture()
        with self.assertRaises(diag.DiagnosticError):
            diag.capture(self.product, 'booted', self.base / 'other', self.metadata, run=self.runner)
        with self.assertRaises(diag.DiagnosticError):
            diag.capture(self.product, self.sim, self.base / 'other', {**self.metadata, 'xcode': '27'}, run=self.runner)
        self.assertEqual(self.commands, [])

    def test_generated_workflow_is_manual_nonlive_and_synchronized(self):
        template = sync.TEMPLATES / 'core-native-diagnostic.yml'
        generated = sync.DESTINATION / 'ios-core-native-diagnostic.yml'
        text = template.read_text()
        self.assertEqual(generated.read_text(), sync.render(template.name))
        self.assertIn('  workflow_dispatch:', text)
        self.assertNotIn('pull_request:', text)
        self.assertNotIn('  push:', text)
        self.assertNotIn('secrets.', text)
        self.assertNotIn('live-model', text)
        self.assertNotIn('live-mcp', text)
        self.assertIn('persist-credentials: false', text)
        self.assertIn('--fresh', text)
        self.assertIn('not a gate', text)
        self.assertIn("xcode: '16.4'", text)
        self.assertIn("xcode: '26.2'", text)
        self.assertIn('if: always()', text)

    def test_actual_subprocess_environment_and_timeout(self):
        environment = diag.clean_environment()
        stdout, stderr = self.base / 'out', self.base / 'err'
        code = diag.native_command([sys.executable, '-c', 'import os; print(os.getenv("SECRET_EXAMPLE", "absent"))'],
                                   stdout, stderr, 5, environment)
        self.assertEqual(code, 0)
        self.assertEqual(stdout.read_text().strip(), 'absent')
        self.assertIsNone(diag.native_command([sys.executable, '-c', 'import time; time.sleep(30)'],
                                              self.base / 'timed-out', self.base / 'timeout-err', 0.1, environment))


if __name__ == '__main__': unittest.main()
