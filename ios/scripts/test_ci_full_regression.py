"""Local contracts for source-bound, two-build full CI regression."""
import copy
import itertools
import json
import re
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

import ci_full_regression as ci
from release_ios17 import ui_inventory

ROOT = Path(__file__).resolve().parents[1]


class FullRegressionPlanTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.catalog = ui_inventory(ROOT)
        cls.plan = ci.make_plan(ROOT)

    def test_exact_three_devices_15_shards_core_and_ipad(self):
        ci.verify_plan(self.plan, self.catalog)
        rows = self.plan['rows']
        self.assertEqual((len(rows), sum(len(r['slices']) for r in rows)), (28, 64))
        all_methods = {x for shard in self.catalog['shards'].values() for x in shard['tests']}
        self.assertEqual((len(self.catalog['shards']), len(all_methods)),
                         (15, self.catalog['non_live_test_count']))
        for device in ci.IPHONES:
            slices = [s for r in rows if r['label'] == device['label'] for s in r['slices']]
            self.assertEqual({s['scope'] for s in slices}, set(self.catalog['shards']) | {'core'})
            methods = [x for s in slices for x in s['methods']]
            self.assertEqual((len(methods), set(methods)), (len(all_methods) - 1,
                                                            all_methods - {ci.IPAD_ONLY}))
        ipad = [r for r in rows if r['label'] == ci.IPAD['label']]
        self.assertEqual(len(ipad), len(ci.COHORTS))
        ipad_slices = [s for row in ipad for s in row['slices']]
        ipad_methods = [method for sl in ipad_slices for method in sl['methods']]
        self.assertEqual({s['scope'] for s in ipad_slices}, set(self.catalog['shards']) | {'core'})
        self.assertEqual((len(ipad_methods), set(ipad_methods)), (len(all_methods), all_methods))
        self.assertEqual(ipad_methods.count(ci.IPAD_ONLY), 1)

    def test_plan_mutations_fail_closed(self):
        variants = []
        for mutation in ('missing', 'duplicate', 'wrong_scope', 'wrong_device', 'wrong_hash', 'extra'):
            plan = copy.deepcopy(self.plan)
            row = plan['rows'][1]; sl = row['slices'][0]
            if mutation == 'missing':
                sl['methods'].pop(); sl['selectors'].pop()
            elif mutation == 'duplicate':
                sl['methods'].append(sl['methods'][0]); sl['selectors'].append(sl['selectors'][0])
            elif mutation == 'wrong_scope':
                sl['scope'] = 'ui-browser'
            elif mutation == 'wrong_device':
                row['device'] = 'iPhone 17'
            elif mutation == 'wrong_hash':
                plan['inventory_sha256'] = '0' * 64
            else:
                plan['rows'].append(copy.deepcopy(row))
            variants.append(plan)
        for plan in variants:
            with self.assertRaises(ValueError):
                ci.verify_plan(plan, self.catalog)

        plan = copy.deepcopy(self.plan)
        ipad = next(row for row in plan['rows'] if row['label'] == ci.IPAD['label'])
        ipad['slices'][0]['methods'].remove(ci.IPAD_ONLY)
        ipad['slices'][0]['selectors'].remove('-only-testing:' + ci.IPAD_ONLY)
        with self.assertRaises(ValueError):
            ci.verify_plan(plan, self.catalog)

    def test_all_manual_selector_combinations_keep_existing_precedence(self):
        for current, compact, large in itertools.product((False, True), repeat=3):
            with self.subTest(current=current, compact=compact, large=large):
                selection = ('current' if current else 'compact' if compact else
                             'large' if large else 'all')
                self.assertEqual(ci.selection_from_flags(current, compact, large), selection)
                plan = ci.make_plan(ROOT, current_only=current, compact_only=compact,
                                    large_only=large, fresh_simulator=False)
                ci.verify_plan(plan, self.catalog)
                devices = ci.SELECTIONS[selection]
                self.assertEqual(plan['selection'], selection)
                self.assertIs(plan['fresh_simulator'], False)
                self.assertEqual(plan['iphone_labels'], [device['label'] for device in devices])
                self.assertEqual(len(plan['rows']), 28 if selection == 'all' else 7)
                self.assertEqual(sum(len(row['slices']) for row in plan['rows']),
                                 64 if selection == 'all' else 16)
                self.assertEqual({row['xcode'] for row in plan['rows']},
                                 {device['xcode'] for device in devices})
                self.assertEqual(any(row['label'] == ci.IPAD['label'] for row in plan['rows']),
                                 selection == 'all')
                with self.assertRaises(ValueError):
                    ci.require_full(plan)

    def test_fresh_simulator_is_recorded_and_pr_push_require_full_fresh_plan(self):
        ci.require_full(self.plan)
        manual_all = ci.make_plan(ROOT, fresh_simulator=False)
        ci.verify_plan(manual_all, self.catalog)
        self.assertEqual(len(manual_all['rows']), 28)
        with self.assertRaises(ValueError):
            ci.require_full(manual_all)
        selected = ci.make_plan(ROOT, current_only=True)
        with self.assertRaises(ValueError):
            ci.require_full(selected)
        with tempfile.TemporaryDirectory() as folder:
            row = manual_all['rows'][0]
            ci.materialize(ROOT, row, Path(folder))
            changed = copy.deepcopy(row); changed['fresh_simulator'] = 'true'
            with self.assertRaises(ValueError):
                ci.materialize(ROOT, changed, Path(folder))

    def test_cli_emits_only_required_xcode_build_and_test_matrices(self):
        for flags, selection, builds, jobs in (
                ([], 'all', ['16.4', '26.2'], 28),
                (['--current-only'], 'current', ['26.2'], 7),
                (['--compact-only'], 'compact', ['16.4'], 7),
                (['--large-only'], 'large', ['16.4'], 7),
                (['--current-only', '--compact-only', '--large-only', '--existing-simulator'],
                 'current', ['26.2'], 7)):
            with self.subTest(flags=flags), tempfile.TemporaryDirectory() as folder:
                output = Path(folder) / 'plan.json'; gh = Path(folder) / 'github-output.txt'
                subprocess.run([sys.executable, str(Path(ci.__file__)), 'plan',
                                '--output', str(output), '--github-output', str(gh), *flags],
                               check=True, stdout=subprocess.DEVNULL)
                plan = json.loads(output.read_text())
                values = dict(line.split('=', 1) for line in gh.read_text().splitlines())
                self.assertEqual(plan['selection'], selection)
                self.assertEqual(len(plan['rows']), jobs)
                self.assertEqual(json.loads(values['build_matrix'])['xcode'], builds)
                self.assertEqual(json.loads(values['matrix'])['include'], plan['rows'])
                self.assertIs(plan['fresh_simulator'], '--existing-simulator' not in flags)

    def test_materialize_exact_row_and_portable_product(self):
        with tempfile.TemporaryDirectory() as folder:
            output = Path(folder); row = self.plan['rows'][0]
            ci.materialize(ROOT, row, output)
            self.assertEqual(json.loads((output / 'full-row.json').read_text()), row)
            changed = copy.deepcopy(row); changed['slices'][0]['selectors'].pop()
            with self.assertRaises(ValueError):
                ci.materialize(ROOT, changed, output)
            bundle = output / 'Tests.xctestproducts'
            app = bundle / 'Binaries/0/Debug-iphonesimulator/WoowAssistant.app'
            app.mkdir(parents=True)
            self.assertEqual(ci.product_directory(bundle), app.parent)
            (bundle / 'other/WoowAssistant.app').mkdir(parents=True)
            with self.assertRaises(ValueError):
                ci.product_directory(bundle)

    def test_xcode_command_is_test_only_and_exact(self):
        sl = self.plan['rows'][0]['slices'][0]
        cmd = ci.test_command(Path('build/Tests.xctestproducts'), 'simulator-id',
                              Path('build/Tests.xcresult'), sl)
        self.assertEqual(cmd[:2], ['xcodebuild', 'test-without-building'])
        self.assertIn('-testProductsPath', cmd)
        self.assertEqual([x for x in cmd if x.startswith('-only-testing:')], sl['selectors'])
        self.assertEqual(cmd[cmd.index('-maximum-test-execution-time-allowance') + 1], '300')
        workspace = next(s for r in self.plan['rows'] for s in r['slices'] if s['scope'] == 'ui-workspace')
        self.assertIn('420', ci.test_command(Path('p'), 'id', Path('r'), workspace))

    def test_completion_rejects_missing_skips_nonzero_exit_and_wrong_core_suites(self):
        row = self.plan['rows'][1]; sl = row['slices'][0]
        core_row = self.plan['rows'][3]; core = core_row['slices'][-1]
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder); summary = root / 'summary.json'; log = root / 'tests.log'
            self.assertFalse(ci.finish(row, sl, summary, log, 0)['verified'])
            events = ["Test Case '-[WoowAssistantUITests.%s %s]' passed (0.1 seconds).\n" %
                      tuple(method.split('/')[1:]) for method in sl['methods']]
            log.write_text(''.join(events))
            valid = {'result': 'Passed', 'totalTestCount': len(events), 'passedTests': len(events),
                     'failedTests': 0, 'skippedTests': 0, 'expectedFailures': 0}
            summary.write_text(json.dumps(valid))
            self.assertTrue(ci.finish(row, sl, summary, log, 0)['verified'])
            self.assertFalse(ci.finish(row, sl, summary, log, 65)['verified'])
            log.write_text(''.join(events[:-1]))
            self.assertFalse(ci.finish(row, sl, summary, log, 0)['verified'])
            summary.write_text(json.dumps(dict(valid, skippedTests=1)))
            self.assertFalse(ci.finish(row, sl, summary, log, 0)['verified'])
            core_log = ''.join("Test Suite '%s.xctest' passed at 2026-01-01.\n" % x
                               for x in ci.TEST_SCOPES['core'][:-1])
            log.write_text(core_log)
            summary.write_text(json.dumps(dict(valid, totalTestCount=100, passedTests=100)))
            self.assertFalse(ci.finish(core_row, core, summary, log, 0)['verified'])
            log.write_text(core_log + "Test Suite '%s.xctest' passed at 2026-01-01.\n" %
                           ci.TEST_SCOPES['core'][-1])
            self.assertTrue(ci.finish(core_row, core, summary, log, 0)['verified'])

    def test_aggregate_rejects_missing_duplicate_and_mixed_source(self):
        row = self.plan['rows'][0]
        plan = {**self.plan, 'rows': [row]}
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            def write(sl, name, sha=None):
                path = root / name; path.mkdir()
                (path / 'full-receipt.json').write_text(json.dumps({
                    'id': row['id'] + ':' + sl['scope'], 'source_sha': sha or row['source_sha'],
                    'inventory_sha256': row['inventory_sha256'], 'expected_methods': sl['methods'],
                    'exit_code': 0, 'verified': True}))
            write(row['slices'][0], 'one')
            self.assertEqual(len(ci.aggregate(plan, root)['missing']), 1)
            write(row['slices'][1], 'two')
            self.assertTrue(ci.aggregate(plan, root)['verified'])
            write(row['slices'][0], 'duplicate')
            self.assertFalse(ci.aggregate(plan, root)['verified'])
            (root / 'duplicate/full-receipt.json').unlink()
            receipt = json.loads((root / 'two/full-receipt.json').read_text())
            receipt['source_sha'] = '0' * 40
            (root / 'two/full-receipt.json').write_text(json.dumps(receipt))
            self.assertFalse(ci.aggregate(plan, root)['verified'])

    def test_full_aggregate_requires_64_matching_receipts(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            for row in self.plan['rows']:
                for sl in row['slices']:
                    path = root / row['id'] / sl['scope']
                    path.mkdir(parents=True)
                    (path / 'full-receipt.json').write_text(json.dumps({
                        'id': row['id'] + ':' + sl['scope'], 'source_sha': row['source_sha'],
                        'inventory_sha256': row['inventory_sha256'], 'expected_methods': sl['methods'],
                        'exit_code': 0, 'verified': True}))
            report = ci.aggregate(self.plan, root)
            self.assertEqual((report['verified'], report['planned_slices'], report['received_slices']),
                             (True, 64, 64))
            (root / self.plan['rows'][0]['id'] / 'ui-startup/full-receipt.json').unlink()
            self.assertFalse(ci.aggregate(self.plan, root)['verified'])

    def test_failed_shards_keep_separate_receipts_without_retry(self):
        row = self.plan['rows'][0]
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            def fail_once(command, log, seconds):
                log.write_text('native test failed\n')
                return 65
            with mock.patch.object(ci, 'bounded_process', side_effect=fail_once) as command:
                receipts = ci.execute(row, root / 'Products.xctestproducts', 'simulator-id', root)
            self.assertEqual(command.call_count, 2)
            self.assertEqual([r['verified'] for r in receipts], [False, False])
            for sl in row['slices']:
                path = root / sl['scope'] / 'full-receipt.json'
                self.assertEqual(json.loads(path.read_text())['exit_code'], 65)

    def test_document_shard_has_its_own_bounded_window_without_retries(self):
        row = self.plan['rows'][1]
        self.assertEqual([sl['scope'] for sl in row['slices']], ['ui-documents', 'ui-download-pdf'])
        self.assertLess(ci.DOCUMENTS_COHORT_SECONDS, 72 * 60)  # Workflow step limit.
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            def finish_once(command, log, seconds):
                log.write_text('native test failed\n')
                return 65
            with mock.patch.object(ci, 'bounded_process', side_effect=finish_once) as process:
                receipts = ci.execute(row, root / 'Products.xctestproducts', 'simulator-id', root)
            self.assertEqual(process.call_count, 2)
            self.assertEqual([receipt['exit_code'] for receipt in receipts], [65, 65])
            durations = [call.args[2] for call in process.call_args_list]
            self.assertAlmostEqual(durations[0], ci.DOCUMENTS_SLICE_SECONDS, delta=1)
            self.assertAlmostEqual(durations[1], ci.SLICE_SECONDS, delta=1)

    def test_hung_child_is_terminated_without_retry(self):
        with tempfile.TemporaryDirectory() as folder:
            log = Path(folder) / 'hung.log'
            result = ci.bounded_process([sys.executable, '-c', 'import time; time.sleep(5)'], log, 0.1)
            self.assertIsNone(result)
            self.assertTrue(log.is_file())

    def test_workflow_two_prebuilds_and_bounded_test_only_jobs(self):
        source = (ROOT / '.github/workflows/ios.yml').read_text()
        full = source.split('  full-regression-plan:\n', 1)[1].split('  build-and-test:\n', 1)[0]
        self.assertIn('build_matrix: ${{ steps.plan.outputs.build_matrix }}', full)
        self.assertIn('matrix: ${{ fromJSON(needs.full-regression-plan.outputs.build_matrix) }}', full)
        self.assertEqual(full.count('build-for-testing CODE_SIGN_IDENTITY'), 1)
        self.assertIn('ci_full_regression.py execute', full)
        self.assertIn('max-parallel: 9', full)
        self.assertIn('ios-full-receipt-', full)
        self.assertIn('full-regression-gate:', full)
        self.assertIn('testProductsPath', full)
        self.assertIn('needs.full-regression-test.result', full)
        self.assertIn("WOOW_CURRENT_ONLY: ${{ github.event_name == 'workflow_dispatch' && inputs.current_only", full)
        self.assertIn("WOOW_COMPACT_ONLY: ${{ github.event_name == 'workflow_dispatch' && inputs.compact_only", full)
        self.assertIn("WOOW_LARGE_ONLY: ${{ github.event_name == 'workflow_dispatch' && inputs.large_only", full)
        self.assertIn("WOOW_EXISTING_SIMULATOR: ${{ github.event_name == 'workflow_dispatch' && !inputs.fresh_simulator", full)
        self.assertIn('plan_options+=(--existing-simulator)', full)
        self.assertIn("WOOW_FRESH_SIMULATOR: ${{ matrix.fresh_simulator && 'true' || 'false' }}", full)
        self.assertIn('simulator_options+=(--fresh)', full)
        self.assertIn('aggregate_options+=(--require-full)', full)
        self.assertIn("inputs.test_scope != 'all'", source)

    def test_live_service_acceptance_is_manual_and_limited_to_trusted_refs(self):
        source = (ROOT / '.github/workflows/ios.yml').read_text()
        for kind in ('model', 'mcp'):
            match = re.search(rf'(?ms)^  live-{kind}-acceptance:\n(.*?)(?=^  [\w-]+:|\Z)', source)
            self.assertIsNotNone(match)
            job = match.group(1)
            self.assertIn("github.event_name == 'workflow_dispatch'", job)
            self.assertIn(f"inputs.test_scope == 'live-{kind}'", job)
            self.assertIn("github.ref == 'refs/heads/ios/integrate-woow-assistant'", job)
            self.assertIn(f'uses: ./.github/workflows/ios-live-{kind}.yml', job)
            self.assertIn("ios_version: ${{ inputs.live_ios_version || '18.5' }}", job)
            workflow = (ROOT / f'.github/workflows/live-{kind}.yml').read_text()
            self.assertIn('  workflow_call:\n', workflow)
            self.assertIn("github.event_name == 'workflow_dispatch'", workflow)
            self.assertIn("github.ref == 'refs/heads/ios/integrate-woow-assistant'", workflow)
            self.assertIn('WOOW_MODEL_TEST_API_KEY:', workflow)
        self.assertIn("!contains(fromJSON('[\"live-model\",\"live-mcp\",\"runner-probe\"]'), inputs.test_scope)", source)
        self.assertIn("startsWith(inputs.test_scope || '', 'live-') && inputs.live_ios_version", source)


if __name__ == '__main__':
    unittest.main()
