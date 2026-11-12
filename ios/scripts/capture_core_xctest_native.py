#!/usr/bin/env python3
"""Capture raw native core XCTest evidence; never produce a gate pass yet."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import sys

from core_xctest_inventory import TARGETS, read_json


class CaptureError(ValueError):
    pass


def hash_tree(root):
    root = Path(root)
    if root.is_symlink() or not root.is_dir() or root.suffix != '.xctestproducts':
        raise CaptureError('expected a real .xctestproducts directory')
    entries = []
    for parent, dirs, files in os.walk(root, followlinks=False):
        for name in sorted(dirs + files):
            path = Path(parent) / name
            relative = path.relative_to(root).as_posix()
            if path.is_symlink():
                try:
                    target = path.resolve(strict=True)
                except (OSError, RuntimeError) as error:
                    raise CaptureError('invalid product symlink') from error
                if target != root.resolve() and root.resolve() not in target.parents:
                    raise CaptureError('product symlink escapes bundle')
                entries.append([relative, 'link', os.readlink(path)])
            elif path.is_dir():
                entries.append([relative, 'directory'])
            elif path.is_file():
                h = hashlib.sha256()
                with path.open('rb') as stream:
                    for block in iter(lambda: stream.read(1024 * 1024), b''):
                        h.update(block)
                entries.append([relative, 'file', h.hexdigest(), path.stat().st_mode & 0o777])
            else:
                raise CaptureError('unsupported product entry')
    if not entries:
        raise CaptureError('empty product directory')
    return hashlib.sha256(json.dumps(sorted(entries), separators=(',', ':'), ensure_ascii=True).encode()).hexdigest()


def run(command, output, timeout):
    """Write raw process output even on failure, and kill its group on timeout."""
    with output.open('xb') as log:
        process = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
        try:
            return process.wait(timeout=timeout)
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
            raise CaptureError('command timed out')


def checkout_commit(root):
    return subprocess.check_output(['git', '-C', str(root), 'rev-parse', 'HEAD'], text=True).strip()


def check_clean(root):
    # Untracked files in the source tree can participate in XcodeGen sources.
    # CI must place all build outputs in ignored paths or outside the checkout.
    status = subprocess.check_output(['git', '-C', str(root), 'status', '--porcelain', '--untracked-files=all'], text=True)
    if status.strip():
        raise CaptureError('checkout has tracked or untracked changes')


def check_summary(summary, simulator):
    """Validate the observed xcresulttool summary subset; never certify methods."""
    counts = ('totalTestCount', 'passedTests', 'failedTests', 'skippedTests', 'expectedFailures')
    if not isinstance(summary, dict) or any(type(summary.get(k)) is not int or summary[k] < 0 for k in counts):
        raise CaptureError('xcresult summary counts unavailable')
    if (summary.get('result') != 'Passed' or summary['totalTestCount'] == 0
            or summary['passedTests'] != summary['totalTestCount']
            or any(summary[k] for k in ('failedTests', 'skippedTests', 'expectedFailures'))
            or summary.get('testFailures', []) != []):
        raise CaptureError('xcresult summary is incomplete, failed or skipped')
    devices = summary.get('devicesAndConfigurations')
    if not isinstance(devices, list) or len(devices) != 1 or not isinstance(devices[0], dict):
        raise CaptureError('xcresult must contain one destination configuration')
    entry = devices[0]
    device = entry.get('device')
    if (not isinstance(device, dict) or not isinstance(device.get('deviceId'), str)
            or device['deviceId'].lower() != simulator.lower() or device.get('platform') != 'iOS Simulator'):
        raise CaptureError('xcresult destination mismatch')
    for key in ('passedTests', 'failedTests', 'skippedTests', 'expectedFailures'):
        if type(entry.get(key)) is not int or entry[key] != summary[key]:
            raise CaptureError('xcresult destination counts mismatch')


def capture(root, products, simulator, output, runner=run):
    root, products, output = Path(root).resolve(), Path(products).absolute(), Path(output).absolute()
    if not re.fullmatch(r'[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}', simulator):
        raise CaptureError('simulator must be a UDID')
    if output == root or root in output.parents or products == output or products in output.parents:
        raise CaptureError('output must be outside checkout and products')
    check_clean(root)
    head = checkout_commit(root)
    before = hash_tree(products)
    output.mkdir(parents=True, exist_ok=False)
    destination = 'platform=iOS Simulator,id=' + simulator
    selectors = ['-only-testing:' + target for target in TARGETS]
    enumeration = output / 'discovery.json'
    result = output / 'Tests.xcresult'
    common = ['xcodebuild', 'test-without-building', '-testProductsPath', str(products),
              '-destination', destination, '-parallel-testing-enabled', 'NO', *selectors]
    (output / 'capture-context.json').write_text(json.dumps({
        'source_commit': head, 'product_tree_sha256': before, 'destination': destination,
        'targets': list(TARGETS), 'native_provenance_verified': False,
        'note': 'Diagnostic capture only; source/product origin is not established.'
    }, indent=2) + '\n')
    if runner(['xcodebuild', '-version'], output / 'xcode-version.log', 30) != 0:
        raise CaptureError('Xcode version unavailable')
    command = common + ['-enumerate-tests', '-test-enumeration-format', 'json',
                        '-test-enumeration-output-path', str(enumeration)]
    if runner(command, output / 'discovery.log', 600) != 0:
        raise CaptureError('native discovery failed')
    if not enumeration.is_file() or enumeration.is_symlink() or not enumeration.stat().st_size:
        raise CaptureError('native discovery output missing or empty')
    if hash_tree(products) != before:
        raise CaptureError('product changed during discovery')
    command = common + ['-resultBundlePath', str(result), '-test-timeouts-enabled', 'YES',
                        '-default-test-execution-time-allowance', '240',
                        '-maximum-test-execution-time-allowance', '300',
                        'CODE_SIGN_IDENTITY=-', 'CODE_SIGNING_ALLOWED=YES']
    exit_code = runner(command, output / 'tests.log', 1800)
    if result.is_symlink() or not result.is_dir():
        raise CaptureError('xcresult missing')
    # Preserve exports even if the test run failed. No normalization is based on
    # guessed enumeration or xcresult tree structures.
    summary_code = runner(['xcrun', 'xcresulttool', 'get', 'test-results', 'summary', '--path', str(result)],
                          output / 'xcresult-summary.json', 120)
    tests_code = runner(['xcrun', 'xcresulttool', 'get', 'test-results', 'tests', '--path', str(result)],
                        output / 'xcresult-tests.json', 120)
    if hash_tree(products) != before or checkout_commit(root) != head:
        raise CaptureError('product or source commit changed during run')
    check_clean(root)
    if exit_code != 0 or summary_code != 0 or tests_code != 0:
        raise CaptureError('test or xcresult export failed')
    check_summary(read_json(output / 'xcresult-summary.json'), simulator)
    # Crucial: native JSON shapes/semantics and source/product attestation have
    # not been validated on CI Xcode. This command NEVER issues a pass receipt.
    raise CaptureError('native discovery/xcresult parser and provenance not yet verified; capture only')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, required=True)
    parser.add_argument('--products', type=Path, required=True)
    parser.add_argument('--simulator-id', required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    try:
        capture(args.root, args.products, args.simulator_id, args.output)
    except (CaptureError, OSError, ValueError, subprocess.SubprocessError) as error:
        print('Native core evidence not verified: ' + str(error), file=sys.stderr)
        return 1
    # Unreachable unless the safety contract is deliberately changed.
    print('Native core evidence not verified', file=sys.stderr)
    return 1


if __name__ == '__main__':
    raise SystemExit(main())
