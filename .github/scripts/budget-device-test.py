#!/usr/bin/env python3
"""Disposable GitHub Linux/KVM only: deterministic models on real Android API 36.

No keys, external model calls, live gateway validation, or full UI acceptance.
Builds are performed by the workflow; this script installs and tests both brands.
"""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('budget_startup_helpers', ROOT / 'apporo/tools/startup-smoke.py')
smoke = importlib.util.module_from_spec(spec)
spec.loader.exec_module(smoke)
TEST_CLASS = 'com.wangzan101.mika.task.TaskBudgetDeviceTest'
BRANDS = {'apporo': 'com.apporo.assistant', 'woowtech': 'io.woowtech.agent'}
SERIAL = 'emulator-5554'
SCOPE = 'Deterministic model / real Android runtime; not live gateway or full UI acceptance'


def attached_devices(output):
    """Parse adb rows, not line counts; daemon startup diagnostics are not devices.

    Unknown output fails closed instead of treating an unrecognised transport as safe.
    Also accept the historical combined stdout/stderr log for regression checking.
    """
    rows = []
    header = False
    for raw in output.splitlines():
        line = raw.strip()
        if not line:
            continue
        if line == 'List of devices attached':
            header = True
            continue
        if re.fullmatch(r'\* daemon (?:not running; starting now at tcp:\d+|started successfully)', line):
            continue
        if header and re.fullmatch(
                r'\S+\s+(?:device|offline|unauthorized|authorizing|connecting|recovery|'
                r'sideload|bootloader|host|rescue|unknown|no permissions)(?:\s+.*)?', line):
            rows.append(line)
            continue
        raise RuntimeError('Unrecognised adb devices output; see devices-before.log')
    if not header:
        raise RuntimeError('Missing adb devices header; see devices-before.log')
    return rows


def select_apk(directory, package):
    """Unsplit debug APKs are universal too; never select an ABI-specific output."""
    metadata = json.loads((directory / 'output-metadata.json').read_text())
    if metadata['applicationId'] != package:
        raise RuntimeError(f'Unexpected APK package in {directory}')
    candidates = [e for e in metadata['elements'] if e.get('filters') == []]
    if len(candidates) != 1:
        raise RuntimeError(f'Expected one universal/unfiltered APK in {directory}')
    apk = (directory / candidates[0]['outputFile']).resolve()
    if apk.parent != directory.resolve() or not apk.is_file() or apk.suffix != '.apk':
        raise RuntimeError(f'Invalid APK output path in {directory}')
    return apk


def apk_receipt(apk):
    digest = hashlib.sha256()
    with apk.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(block)
    return dict(path=str(apk.relative_to(ROOT)), sha256=digest.hexdigest(), bytes=apk.stat().st_size)


def assert_instrumentation(text):
    counts = re.findall(r'^OK \((\d+) tests?\)\s*$', text, re.M)
    failed = re.search(
        r'INSTRUMENTATION_(?:FAILED|ABORTED)|FAILURES!!!|Process crashed|'
        r'^INSTRUMENTATION_RESULT: (?:shortMsg|longMsg)=|'
        r'^INSTRUMENTATION_STATUS_CODE: -\d+\s*$|^FAILURE', text, re.M | re.I)
    codes = re.findall(r'^INSTRUMENTATION_CODE: (-?\d+)\s*$', text, re.M)
    completed = re.findall(r'^INSTRUMENTATION_STATUS_CODE: 0\s*$', text, re.M)
    classes = re.findall(r'^INSTRUMENTATION_STATUS: class=(\S+)\s*$', text, re.M)
    if (failed or len(counts) != 1 or int(counts[0]) < 1 or codes != ['-1'] or
            len(completed) != int(counts[0]) or not classes or set(classes) != {TEST_CLASS}):
        raise RuntimeError('Instrumentation did not report exclusively successful requested tests; see instrument.log')
    return int(counts[0])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out', type=Path, default=ROOT / 'budget-device-evidence')
    args = parser.parse_args()
    if sys.platform != 'linux' or os.environ.get('GITHUB_ACTIONS') != 'true':
        parser.error('only runs on a disposable GitHub Actions Linux runner')
    args.out.mkdir(parents=True, exist_ok=True)
    started = time.monotonic()
    receipt = dict(status='FAIL', scope=SCOPE, source_sha=os.environ.get('GITHUB_SHA'),
                   api=36, abi='x86_64', image_tag='default', test_class=TEST_CLASS,
                   brands={}, stages=[], cleanup=[])
    process = emulator_log = adb = avd_home = None

    def save(name, data):
        path = args.out / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data if isinstance(data, bytes) else data.encode())

    def checkpoint(stage):
        receipt['stages'].append(dict(name=stage, seconds=round(time.monotonic() - started, 2)))
        save('receipt.json', json.dumps(receipt, indent=2) + '\n')

    def command(name, argv, timeout=30, input_data=None):
        try:
            out, err, code = smoke.run(argv, timeout=timeout, check=False, input_data=input_data)
        except subprocess.TimeoutExpired as exc:
            save(name, (exc.output or b'') + (exc.stderr or b'') + b'\nCOMMAND TIMEOUT\n')
            raise
        save(name, out + err)
        if code:
            raise RuntimeError(f'{name}: exit {code}; see artifact')
        # Keep stderr in evidence, but never feed daemon diagnostics into stdout parsers.
        return out.decode(errors='replace')

    def device(*argv, timeout=30):
        return smoke.run([adb, '-s', SERIAL, *argv], timeout=timeout)[0].decode(errors='replace').strip()

    def interrupted(signum, frame):
        raise smoke.SmokeInterrupted(f'cancelled/overall timeout: signal {signum}')

    for sig in (signal.SIGTERM, signal.SIGINT, signal.SIGALRM):
        signal.signal(sig, interrupted)
    signal.alarm(1500)
    try:
        checkpoint('preflight')
        if not os.access('/dev/kvm', os.R_OK | os.W_OK):
            raise RuntimeError('KVM unavailable; software emulation is not allowed')
        sdk_value = os.environ.get('ANDROID_HOME') or os.environ.get('ANDROID_SDK_ROOT')
        if not sdk_value:
            raise RuntimeError('Android SDK environment missing')
        sdk = Path(sdk_value)
        adb = sdk / 'platform-tools/adb'
        emulator = sdk / 'emulator/emulator'
        manager = sdk / 'cmdline-tools/latest/bin'
        apks = {}
        for brand, package in BRANDS.items():
            app = select_apk(ROOT / f'app/build/outputs/apk/{brand}/debug', package)
            test = select_apk(ROOT / f'app/build/outputs/apk/androidTest/{brand}/debug', package + '.test')
            apks[brand] = (app, test)
            receipt['brands'][brand] = dict(status='NOT_RUN', package=package,
                app=apk_receipt(app), test=apk_receipt(test))
        checkpoint('sdk-install')
        image = 'system-images;android-36;default;x86_64'
        command('sdk-install.log', [manager / 'sdkmanager', '--channel=0', 'platform-tools', 'emulator', image],
                timeout=480, input_data=b'y\n' * 100)
        for label, path in [('emulator', sdk / 'emulator/source.properties'),
                            ('image', sdk / 'system-images/android-36/default/x86_64/source.properties')]:
            save(label + '-source.properties', path.read_bytes())
        command('accel-check.log', [emulator, '-accel-check'])
        command('adb-version.log', [adb, 'version'])
        devices = command('devices-before.log', [adb, 'devices'])
        receipt['existing_devices'] = attached_devices(devices)
        if receipt['existing_devices']:
            raise RuntimeError('Runner already has devices; refusing to touch them')
        avd_home = Path(tempfile.mkdtemp(prefix='task-budget-avd-', dir=os.environ['RUNNER_TEMP'])).resolve()
        os.environ['ANDROID_AVD_HOME'] = str(avd_home)
        avd = 'task-budget-api36'
        checkpoint('avd-create')
        save('avd-paths.json', json.dumps(dict(avd_home=str(avd_home)), indent=2))
        command('avd-create.log', [manager / 'avdmanager', 'create', 'avd', '--name', avd,
                '--path', avd_home / (avd + '.avd'), '--package', image, '--device', 'pixel_2'],
                timeout=60, input_data=b'no\n')
        listing = command('avd-list.log', [emulator, '-list-avds'])
        smoke.verify_avd(avd_home, avd, listing)
        save('avd-config.ini', (avd_home / (avd + '.avd') / 'config.ini').read_bytes())
        checkpoint('boot')
        emulator_log = (args.out / 'emulator.log').open('wb')
        process = subprocess.Popen([str(emulator), '-avd', avd, '-port', '5554',
            '-no-window', '-no-audio', '-no-boot-anim', '-no-snapshot', '-wipe-data',
            '-accel', 'on', '-gpu', 'swiftshader', '-memory', '2048', '-cores', '2',
            '-camera-back', 'none', '-camera-front', 'none'],
            stdout=emulator_log, stderr=subprocess.STDOUT, start_new_session=True)
        deadline = time.monotonic() + 300
        while time.monotonic() < deadline:
            if process.poll() is not None:
                raise RuntimeError('Emulator exited before boot')
            try:
                if device('shell', 'getprop', 'sys.boot_completed', timeout=10) == '1':
                    break
            except (RuntimeError, subprocess.TimeoutExpired):
                pass
            time.sleep(2)
        else:
            raise RuntimeError('Boot timeout (300s)')
        receipt['device'] = {key: device('shell', 'getprop', prop) for key, prop in (
            ('api', 'ro.build.version.sdk'), ('abi', 'ro.product.cpu.abi'),
            ('abilist', 'ro.product.cpu.abilist'), ('fingerprint', 'ro.build.fingerprint'))}
        if (receipt['device']['api'] != '36' or receipt['device']['abi'] != 'x86_64' or
                'arm64-v8a' in receipt['device']['abilist'].split(',')):
            raise RuntimeError('Wrong API/ABI or ARM translation enabled')
        for brand, package in BRANDS.items():
            result = receipt['brands'][brand]
            checkpoint(brand + '-install-test')
            try:
                for kind, apk in zip(('app', 'test'), apks[brand]):
                    installed = command(f'{brand}/install-{kind}.log',
                        [adb, '-s', SERIAL, 'install', '--no-streaming', '-t', str(apk)], timeout=120)
                    if not re.search(r'^Success\s*$', installed, re.M):
                        raise RuntimeError(f'{kind} APK install did not report Success')
                listing = command(f'{brand}/instrumentation-list.log',
                    [adb, '-s', SERIAL, 'shell', 'pm', 'list', 'instrumentation'])
                components = re.findall(r'^instrumentation:(\S+) \(target=' + re.escape(package) + r'\)\s*$', listing, re.M)
                expected = package + '.test/androidx.test.runner.AndroidJUnitRunner'
                if components != [expected]:
                    raise RuntimeError(f'Unexpected instrumentation for {package}: {components}')
                device('logcat', '-b', 'all', '-c')
                text = command(f'{brand}/instrument.log', [adb, '-s', SERIAL, 'shell', 'am',
                    'instrument', '-w', '-r', '-e', 'class', TEST_CLASS, expected], timeout=240)
                result.update(status='PASS', tests=assert_instrumentation(text), component=expected)
            except Exception as exc:
                result.update(status='FAIL', error=f'{type(exc).__name__}: {exc}')
            finally:
                # Best-effort diagnostics and force-stop are independently bounded.
                for name, tail in [('logcat.log', ['logcat', '-b', 'all', '-d']),
                                   ('force-stop.log', ['shell', 'am', 'force-stop', package])]:
                    try:
                        command(f'{brand}/{name}', [adb, '-s', SERIAL, *tail], timeout=10)
                    except Exception as exc:
                        result.setdefault('diagnostic_errors', []).append(str(exc))
                save(f'{brand}/receipt.json', json.dumps(dict(scope=SCOPE, **result), indent=2) + '\n')
        if all(r['status'] == 'PASS' for r in receipt['brands'].values()):
            receipt['status'] = 'PASS_DETERMINISTIC_ANDROID_RUNTIME'
    except (Exception, smoke.SmokeInterrupted) as exc:
        receipt['error'] = f'{type(exc).__name__}: {exc}'
        print(receipt['error'], file=sys.stderr)
    finally:
        signal.alarm(0)
        for sig in (signal.SIGTERM, signal.SIGINT):
            signal.signal(sig, signal.SIG_IGN)
        if process is not None:
            try:
                command('emulator-stop.log', [adb, '-s', SERIAL, 'emu', 'kill'], timeout=10)
            except Exception as exc:
                receipt['cleanup'].append(str(exc))
            for sig, wait in ((signal.SIGTERM, 10), (signal.SIGKILL, 5)):
                try:
                    os.killpg(process.pid, sig)
                except ProcessLookupError:
                    pass
                try:
                    process.wait(timeout=wait)
                except subprocess.TimeoutExpired:
                    pass
            receipt['cleanup'].append(dict(emulator_returncode=process.poll()))
            if process.poll() is None:
                receipt.update(status='FAIL', error='Emulator did not terminate')
        if emulator_log:
            emulator_log.close()
        if avd_home:
            try:
                command('avd-cleanup.log', ['rm', '-rf', '--', str(avd_home)], timeout=20)
            except Exception as exc:
                receipt.update(status='FAIL', cleanup_error=str(exc))
        receipt['elapsed_seconds'] = round(time.monotonic() - started, 2)
        save('receipt.json', json.dumps(receipt, indent=2) + '\n')
        if os.environ.get('GITHUB_STEP_SUMMARY'):
            with open(os.environ['GITHUB_STEP_SUMMARY'], 'a') as stream:
                stream.write(f"\n### Task budget API 36 x86_64\n\n{receipt['status']}\n\n{SCOPE}.\n")
    return 0 if receipt['status'] == 'PASS_DETERMINISTIC_ANDROID_RUNTIME' else 1


if __name__ == '__main__':
    sys.exit(main())
