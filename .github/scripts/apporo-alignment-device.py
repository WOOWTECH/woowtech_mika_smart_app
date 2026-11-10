#!/usr/bin/env python3
"""Disposable hosted Linux/KVM: Apporo English UI, real accessibility, fake voice.

No live microphone, recognizer, model, phone helper, or OEM Settings UI acceptance.
All subprocesses, boot/instrumentation waits and teardown have deadlines.
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
spec = importlib.util.spec_from_file_location('alignment_startup_helpers', ROOT / 'apporo/tools/startup-smoke.py')
smoke = importlib.util.module_from_spec(spec)
spec.loader.exec_module(smoke)
PACKAGE = 'com.apporo.assistant'
TEST_CLASS = 'com.wangzan101.mika.ui.ApporoAlignmentTest'
COMPONENT = PACKAGE + '.test/androidx.test.runner.AndroidJUnitRunner'
SERIAL = 'emulator-5554'
SCOPE = 'English Apporo Compose UI and real accessibility lifecycle; fake voice events; no live mic/model or OEM Settings UI acceptance'
SHOTS = ('help-off', 'help-enabled-not-running', 'help-on', 'help-large-font', 'voice-released',
         'voice-cancelled', 'voice-cancel-retry', 'voice-error', 'voice-error-retry')
CHECKS = ('accessibility', 'large-font', 'release', 'cancel', 'error')
TEST_FILES = tuple(f'{s}.png' for s in SHOTS) + tuple(f'{c}.json' for c in CHECKS) + ('english-help.txt',)


def attached_devices(output):
    rows, header = [], False
    for raw in output.splitlines():
        line = raw.strip()
        if not line:
            continue
        if line == 'List of devices attached':
            header = True
            continue
        if re.fullmatch(r'\* daemon (?:not running; starting now at tcp:\d+|started successfully)', line):
            continue
        if header and re.fullmatch(r'\S+\s+(?:device|offline|unauthorized|authorizing|connecting|recovery|'
                                  r'sideload|bootloader|host|rescue|unknown|no permissions)(?:\s+.*)?', line):
            rows.append(line)
            continue
        raise RuntimeError('Unrecognised adb device listing; refusing to boot')
    if not header:
        raise RuntimeError('Missing adb devices header')
    return rows


def select_apk(directory, package):
    metadata = json.loads((directory / 'output-metadata.json').read_text())
    if metadata['applicationId'] != package:
        raise RuntimeError(f'Wrong package in {directory}')
    outputs = [e for e in metadata['elements'] if e.get('filters') == []]
    if len(outputs) != 1:
        raise RuntimeError(f'Expected one unsplit/universal APK in {directory}')
    entry = outputs[0]
    if package == PACKAGE and entry.get('versionCode') != 3808:
        raise RuntimeError('Expected Apporo .8 versionCode 3808')
    apk = (directory / entry['outputFile']).resolve()
    if apk.parent != directory.resolve() or apk.suffix != '.apk' or not apk.is_file():
        raise RuntimeError('Invalid APK output path')
    return apk


def apk_receipt(apk):
    digest = hashlib.sha256()
    with apk.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(block)
    return dict(name=apk.name, sha256=digest.hexdigest(), bytes=apk.stat().st_size)


def assert_instrumentation(text, expected_tests=5, expected_class=TEST_CLASS):
    counts = re.findall(r'^OK \((\d+) tests?\)\s*$', text, re.M)
    codes = re.findall(r'^INSTRUMENTATION_CODE: (-?\d+)\s*$', text, re.M)
    completed = re.findall(r'^INSTRUMENTATION_STATUS_CODE: 0\s*$', text, re.M)
    classes = re.findall(r'^INSTRUMENTATION_STATUS: class=(\S+)\s*$', text, re.M)
    failures = re.search(r'INSTRUMENTATION_(?:FAILED|ABORTED)|FAILURES!!!|Process crashed|'
        r'^INSTRUMENTATION_RESULT: (?:shortMsg|longMsg)=|^INSTRUMENTATION_STATUS_CODE: -\d+\s*$|^FAILURE',
        text, re.M | re.I)
    if (failures or counts != [str(expected_tests)] or codes != ['-1'] or len(completed) != expected_tests or
            not classes or set(classes) != {expected_class}):
        raise RuntimeError(f'Expected OK ({expected_tests} tests), matching successful completions, requested class and no failures')
    return expected_tests


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--api', type=int, choices=(35, 36), required=True)
    parser.add_argument('--apks', type=Path, default=ROOT / 'app/build/outputs/apk')
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    if (sys.platform != 'linux' or os.environ.get('GITHUB_ACTIONS') != 'true' or
            os.environ.get('RUNNER_ENVIRONMENT') != 'github-hosted'):
        parser.error('only runs on a disposable GitHub-hosted Linux runner')
    args.out.mkdir(parents=True, exist_ok=True)
    started = time.monotonic()
    receipt = dict(status='FAIL', scope=SCOPE, source_sha=os.environ.get('GITHUB_SHA'),
        api=args.api, abi='x86_64', image_tag='default', package=PACKAGE, version_code=3808,
        test_class=TEST_CLASS, expected_tests=5, stages=[], cleanup=[])
    process = emulator_log = adb = avd_home = None
    instrument_started = False

    def save(name, data):
        path = args.out / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data if isinstance(data, bytes) else data.encode())

    def stage(name):
        receipt['stages'].append(dict(name=name, seconds=round(time.monotonic() - started, 2)))
        save('receipt.json', json.dumps(receipt, indent=2) + '\n')

    def command(name, argv, timeout=30, input_data=None, binary=False):
        try:
            out, err, code = smoke.run(argv, timeout=timeout, check=False, input_data=input_data)
        except subprocess.TimeoutExpired as exc:
            save(name + '.timeout.log', (exc.output or b'') + (exc.stderr or b'') + b'\nCOMMAND TIMEOUT\n')
            raise
        save(name, out if binary else out + err)
        if binary and err:
            save(name + '.stderr.log', err)
        if code:
            raise RuntimeError(f'{name}: exit {code}; see artifact')
        # Diagnostics belong in the log, never in adb device-list/instrumentation parsers.
        return out if binary else out.decode(errors='replace')

    def device(*argv, timeout=30):
        return smoke.run([adb, '-s', SERIAL, *argv], timeout=timeout)[0].decode(errors='replace').strip()

    def interrupted(signum, frame):
        raise smoke.SmokeInterrupted(f'cancelled/overall timeout: signal {signum}')

    for sig in (signal.SIGTERM, signal.SIGINT, signal.SIGALRM):
        signal.signal(sig, interrupted)
    signal.alarm(1500)
    try:
        stage('preflight')
        if not os.access('/dev/kvm', os.R_OK | os.W_OK):
            raise RuntimeError('KVM unavailable; no software emulation fallback')
        sdk_value = os.environ.get('ANDROID_HOME') or os.environ.get('ANDROID_SDK_ROOT')
        if not sdk_value:
            raise RuntimeError('Android SDK environment missing')
        sdk = Path(sdk_value)
        adb = sdk / 'platform-tools/adb'
        emulator = sdk / 'emulator/emulator'
        manager = sdk / 'cmdline-tools/latest/bin'
        app = select_apk(args.apks / 'apporo/debug', PACKAGE)
        test = select_apk(args.apks / 'androidTest/apporo/debug', PACKAGE + '.test')
        receipt['apks'] = dict(app=apk_receipt(app), test=apk_receipt(test))
        stage('sdk-install')
        image = f'system-images;android-{args.api};default;x86_64'
        command('sdk-install.log', [manager / 'sdkmanager', '--channel=0', 'platform-tools', 'emulator', image],
                timeout=480, input_data=b'y\n' * 100)
        for label, path in [('emulator', sdk / 'emulator/source.properties'),
                ('image', sdk / f'system-images/android-{args.api}/default/x86_64/source.properties')]:
            save(label + '-source.properties', path.read_bytes())
        command('accel-check.log', [emulator, '-accel-check'])
        command('adb-version.log', [adb, 'version'])
        listing = command('devices-before.log', [adb, 'devices'])
        receipt['existing_devices'] = attached_devices(listing)
        if receipt['existing_devices']:
            raise RuntimeError('Runner already has devices; refusing to touch them')
        avd_home = Path(tempfile.mkdtemp(prefix='apporo-alignment-', dir=os.environ['RUNNER_TEMP'])).resolve()
        os.environ['ANDROID_AVD_HOME'] = str(avd_home)
        avd = f'apporo-alignment-{args.api}'
        stage('avd-create')
        save('avd-paths.json', json.dumps(dict(avd_home=str(avd_home)), indent=2))
        command('avd-create.log', [manager / 'avdmanager', 'create', 'avd', '--name', avd,
            '--path', avd_home / (avd + '.avd'), '--package', image, '--device', 'pixel_2'],
            timeout=60, input_data=b'no\n')
        smoke.verify_avd(avd_home, avd, command('avd-list.log', [emulator, '-list-avds']))
        save('avd-config.ini', (avd_home / (avd + '.avd') / 'config.ini').read_bytes())
        stage('boot')
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
        if (receipt['device']['api'] != str(args.api) or receipt['device']['abi'] != 'x86_64' or
                'arm64-v8a' in receipt['device']['abilist'].split(',')):
            raise RuntimeError('Wrong API/ABI or ARM translation enabled')
        device('shell', 'input', 'keyevent', 'KEYCODE_WAKEUP')
        device('shell', 'wm', 'dismiss-keyguard')
        for setting in ('window_animation_scale', 'transition_animation_scale', 'animator_duration_scale'):
            device('shell', 'settings', 'put', 'global', setting, '0')
        stage('install')
        for kind, apk in [('app', app), ('test', test)]:
            installed = command(f'install-{kind}.log', [adb, '-s', SERIAL, 'install', '--no-streaming', '-t', str(apk)], timeout=120)
            if not re.search(r'^Success\s*$', installed, re.M):
                raise RuntimeError(f'{kind} install did not report Success')
        components = command('instrumentation-list.log', [adb, '-s', SERIAL, 'shell', 'pm', 'list', 'instrumentation'])
        if re.findall(r'^instrumentation:(\S+) \(target=' + re.escape(PACKAGE) + r'\)\s*$', components, re.M) != [COMPONENT]:
            raise RuntimeError('Unexpected instrumentation target/component')
        command('package.log', [adb, '-s', SERIAL, 'shell', 'dumpsys', 'package', PACKAGE])
        device('logcat', '-b', 'all', '-c')
        stage('instrumentation')
        instrument_started = True
        transcript = command('instrument.log', [adb, '-s', SERIAL, 'shell', 'am', 'instrument',
            '-w', '-r', '-e', 'class', TEST_CLASS, COMPONENT], timeout=300)
        receipt['tests'] = assert_instrumentation(transcript)
        # apporo.6: recovery regressions on real Android in addition to the original suite.
        receipt['recovery_tests'] = []
        for label, selector in (
            ('draft-restoration', 'com.wangzan101.mika.ui.ChatDraftRestorationTest'),
            ('offline-voice-retry', 'com.wangzan101.mika.ui.VoiceHoldTest#offlineLanguageFailureShowsNetworkGuidanceAndAllowsRetry'),
            ('online-language-error', 'com.wangzan101.mika.ui.VoiceHoldTest#onlineLanguageFailureKeepsLanguageSheet'),
        ):
            transcript = command(label + '.log', [adb, '-s', SERIAL, 'shell', 'am', 'instrument',
                '-w', '-r', '-e', 'class', selector, COMPONENT], timeout=120)
            count = assert_instrumentation(transcript, 1, selector.split('#')[0])
            receipt['recovery_tests'].append(dict(name=label, tests=count, status='PASS'))
        stage('collect-test-evidence')
        for name in TEST_FILES:
            data = command('tests/' + name, [adb, '-s', SERIAL, 'exec-out', 'run-as', PACKAGE,
                'cat', 'files/apporo-alignment/' + name], timeout=15, binary=True)
            if name.endswith('.png') and not data.startswith(b'\x89PNG\r\n\x1a\n'):
                raise RuntimeError(f'Invalid screenshot: {name}')
            if name.endswith('.json'):
                check = json.loads(data)
                if (check.get('status') != 'PASS' or check.get('package') != PACKAGE or
                        check.get('api') != args.api or check.get('locale') != 'en' or check.get('automatic_sends') != 0):
                    raise RuntimeError(f'Invalid test receipt: {name}')
        log = command('test-logcat.log', [adb, '-s', SERIAL, 'logcat', '-b', 'all', '-d', '-v', 'threadtime'])
        if smoke.app_crash(log):
            raise RuntimeError('Apporo crash/ANR in test logcat')
        receipt['status'] = 'PASS_ENGLISH_RUNTIME_FAKE_VOICE'
    except (Exception, smoke.SmokeInterrupted) as exc:
        receipt['error'] = f'{type(exc).__name__}: {exc}'
        print(receipt['error'], file=sys.stderr)
    finally:
        signal.alarm(0)
        for sig in (signal.SIGTERM, signal.SIGINT):
            signal.signal(sig, signal.SIG_IGN)
        if process is not None:
            # Preserve screenshots/receipts from tests that completed before a failure or timeout.
            # At most 15 files x 3s; unavailable diagnostics cannot prevent emulator teardown.
            if instrument_started and receipt['status'] != 'PASS_ENGLISH_RUNTIME_FAKE_VOICE':
                for name in TEST_FILES:
                    if (args.out / 'tests' / name).exists():
                        continue
                    try:
                        out, err, code = smoke.run([adb, '-s', SERIAL, 'exec-out', 'run-as', PACKAGE,
                            'cat', 'files/apporo-alignment/' + name], timeout=3, check=False)
                        if code == 0:
                            save('tests/' + name, out)
                    except Exception as exc:
                        receipt['cleanup'].append(dict(partial_test_file=name, error=str(exc)))
            for name, tail, binary in [('final-logcat.log', ['logcat', '-b', 'all', '-d'], False),
                    ('final-screen.png', ['exec-out', 'screencap', '-p'], True),
                    ('emulator-stop.log', ['emu', 'kill'], False)]:
                try:
                    command(name, [adb, '-s', SERIAL, *tail], timeout=10, binary=binary)
                except Exception as exc:
                    receipt['cleanup'].append(dict(command=name, error=str(exc)))
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
                stream.write(f"\n### Apporo alignment API {args.api} x86_64\n\n{receipt['status']}\n\n{SCOPE}.\n")
    return 0 if receipt['status'] == 'PASS_ENGLISH_RUNTIME_FAKE_VOICE' else 1


if __name__ == '__main__':
    sys.exit(main())
