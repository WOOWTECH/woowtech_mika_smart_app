#!/usr/bin/env python3
"""Run one no-live core diagnostic; keep raw artifacts, never emit a gate receipt."""
import argparse
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import sys

from capture_core_xctest_native import hash_tree
from core_xctest_inventory import TARGETS, read_json


class DiagnosticError(ValueError):
    pass


def clean_environment():
    # No GitHub credentials, service secrets, proxy settings, or test fixtures
    # inherited from the caller. Simulator data is isolated separately by CI.
    keys = ('HOME', 'TMPDIR', 'DEVELOPER_DIR')
    environment = {key: os.environ[key] for key in keys if os.environ.get(key)}
    if 'HOME' not in environment or 'DEVELOPER_DIR' not in environment:
        raise DiagnosticError('HOME and DEVELOPER_DIR are required')
    environment['PATH'] = '/usr/bin:/bin:/usr/sbin:/sbin'
    return environment


def native_command(command, stdout_path, stderr_path, seconds, environment):
    """One attempt; preserve exact bytes and kill the process group on timeout."""
    with stdout_path.open('xb') as stdout, stderr_path.open('xb') as stderr:
        process = subprocess.Popen(command, stdout=stdout, stderr=stderr, env=environment, start_new_session=True)
        try:
            return process.wait(timeout=seconds)
        except subprocess.TimeoutExpired:
            try:
                os.killpg(process.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
            try:
                process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                process.wait()
            return None


def write_manifest(path, data):
    temporary = path.with_name('manifest.tmp')
    temporary.write_text(json.dumps(data, indent=2, sort_keys=True) + '\n')
    os.replace(temporary, path)


def capture(products, simulator, output, metadata, *, run=native_command):
    products = Path(products).absolute()
    output = Path(output).absolute()
    if not re.fullmatch(r'[0-9A-Fa-f]{8}(?:-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}', simulator):
        raise DiagnosticError('invalid simulator UDID')
    if not isinstance(metadata, dict) or set(metadata) != {'source_commit', 'workflow_ref', 'run_id', 'run_attempt', 'xcode', 'runtime', 'device'}:
        raise DiagnosticError('incomplete provenance')
    if not re.fullmatch(r'[0-9a-f]{40}', metadata['source_commit']):
        raise DiagnosticError('invalid source commit')
    if metadata['xcode'] not in ('16.4', '26.2') or not all(isinstance(v, str) and v for v in metadata.values()):
        raise DiagnosticError('unsupported or missing provenance')
    if output == products or products in output.parents:
        raise DiagnosticError('output cannot be inside products')
    environment = clean_environment()
    before = hash_tree(products)
    output.mkdir(parents=True, exist_ok=False)
    result_path = output / 'Tests.xcresult'
    discovery_path = output / 'discovery.json'
    manifest_path = output / 'manifest.json'
    manifest = {'schema': 'core-native-diagnostic-v1', 'purpose': 'diagnostic only; not a gate',
                'native_provenance_verified': False, 'gate_eligible': False,
                'context': metadata, 'simulator_id': simulator, 'targets': list(TARGETS),
                'product_tree_sha256_before': before, 'phases': {}, 'capture_complete': False}
    write_manifest(manifest_path, manifest)
    destination = 'platform=iOS Simulator,id=' + simulator
    common = ['/usr/bin/xcodebuild', 'test-without-building', '-testProductsPath', str(products),
              '-destination', destination, '-parallel-testing-enabled', 'NO',
              *['-only-testing:' + name for name in TARGETS]]

    def phase(name, command, timeout):
        manifest['phases'][name] = {'state': 'started'}
        write_manifest(manifest_path, manifest)
        try:
            code = run(command, output / (name + '.stdout'), output / (name + '.stderr'), timeout, environment)
            manifest['phases'][name] = {'state': 'timed_out' if code is None else 'finished', 'exit_code': code}
        except (OSError, ValueError):
            manifest['phases'][name] = {'state': 'launch_failed', 'exit_code': None}
        write_manifest(manifest_path, manifest)
        return manifest['phases'][name].get('exit_code')

    discovery_exit = phase('discovery', common + ['-enumerate-tests', '-test-enumeration-format', 'json',
                           '-test-enumeration-output-path', str(discovery_path)], 600)
    try:
        manifest['product_tree_sha256_after_discovery'] = hash_tree(products)
    except (OSError, ValueError):
        manifest['product_tree_sha256_after_discovery'] = None
    write_manifest(manifest_path, manifest)
    # Run once even if enumeration fails: the two artifacts diagnose different
    # capabilities, and neither can substitute for the other.
    test_exit = phase('execution', common + ['-resultBundlePath', str(result_path),
                      '-test-timeouts-enabled', 'YES', '-default-test-execution-time-allowance', '240',
                      '-maximum-test-execution-time-allowance', '300',
                      'CODE_SIGN_IDENTITY=-', 'CODE_SIGNING_ALLOWED=YES'], 1800)
    exports = []
    if result_path.is_dir() and not result_path.is_symlink():
        for kind in ('summary', 'tests'):
            exports.append(phase(kind, ['/usr/bin/xcrun', 'xcresulttool', 'get', 'test-results', kind,
                                        '--path', str(result_path)], 120))
    else:
        manifest['phases']['xcresult'] = {'state': 'missing'}
    try:
        after = hash_tree(products)
    except (OSError, ValueError):
        after = None
    manifest['product_tree_sha256_after'] = after
    valid_json = True
    for path in (discovery_path, output / 'summary.stdout', output / 'tests.stdout'):
        try:
            data = read_json(path) if path.is_file() and not path.is_symlink() else None
            if not isinstance(data, (dict, list)) or not data:
                valid_json = False
        except (OSError, ValueError, TypeError):
            valid_json = False
    manifest['capture_complete'] = (discovery_exit == 0 and test_exit == 0 and exports == [0, 0]
                                    and before == manifest['product_tree_sha256_after_discovery'] == after and valid_json)
    write_manifest(manifest_path, manifest)
    return manifest['capture_complete']


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('products', 'simulator', 'output', 'source-commit', 'workflow-ref', 'run-id', 'run-attempt', 'xcode', 'runtime', 'device'):
        parser.add_argument('--' + name, required=True)
    args = parser.parse_args()
    metadata = {'source_commit': args.source_commit, 'workflow_ref': args.workflow_ref,
                'run_id': args.run_id, 'run_attempt': args.run_attempt, 'xcode': args.xcode,
                'runtime': args.runtime, 'device': args.device}
    try:
        complete = capture(args.products, args.simulator, args.output, metadata)
    except (OSError, ValueError) as error:
        print('Diagnostic capture failed: ' + str(error), file=sys.stderr)
        return 1
    print('Diagnostic capture ' + ('complete' if complete else 'incomplete') + '; NOT A TEST GATE')
    return 0 if complete else 1


if __name__ == '__main__':
    sys.exit(main())
