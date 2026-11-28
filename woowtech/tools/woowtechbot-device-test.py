#!/usr/bin/env python3
"""GitHub Linux/KVM only: boot an AOSP emulator, install the woowtech debug app and its device tests, run the woowtechbot
device tests and keep the evidence (owner 2026-11-28: test on an emulator or on GitHub).

Usage: woowtechbot-device-test.py --api 36 --apks <dir with the app and androidTest APKs> --out <evidence dir>
Exit 0 only when every listed test ran and none failed; tests skipped by an assumption are reported, not passed.
"""
import argparse
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import time

TESTS = [
    'com.wangzan101.mika.woowbot.push.BotPushNotificationsTest',
    'com.wangzan101.mika.woowbot.push.BotPushConnectionsDeviceTest',
    'com.wangzan101.mika.woowbot.BotResumeDeviceTest',
    'com.wangzan101.mika.woowbot.BotProfileIsolationTest',
    'com.wangzan101.mika.woowbot.BotDownloadsDeviceTest',
]
SERIAL = 'emulator-5554'
# am instrument -r status codes per test.
STATUS = {'0': 'passed', '-1': 'error', '-2': 'failed', '-3': 'ignored', '-4': 'skipped (assumption)'}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--api', type=int, required=True)
    parser.add_argument('--apks', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    signal.alarm(2100)
    sdk = Path(os.environ['ANDROID_HOME'])
    adb = str(sdk / 'platform-tools/adb')
    manager = str(sdk / 'cmdline-tools/latest/bin/sdkmanager')
    avdmanager = str(sdk / 'cmdline-tools/latest/bin/avdmanager')
    emulator = str(sdk / 'emulator/emulator')
    summary = dict(api=args.api, source_sha=os.environ.get('GITHUB_SHA'), tests={})

    def save(name, data):
        (args.out / name).write_bytes(data if isinstance(data, bytes) else data.encode())

    def run(name, argv, timeout=120, input_data=None, check=True):
        result = subprocess.run(argv, input=input_data, capture_output=True, timeout=timeout)
        save(name, result.stdout + result.stderr)
        if check and result.returncode:
            raise RuntimeError(f'{name}: exit {result.returncode}')
        return result.stdout.decode(errors='replace')

    def device(*argv, timeout=60):
        return subprocess.run([adb, '-s', SERIAL, *argv], capture_output=True, timeout=timeout).stdout.decode(errors='replace').strip()

    apks = sorted(args.apks.rglob('*.apk'))
    tests_apk = [p for p in apks if p.name.endswith('-androidTest.apk')]
    app_apk = [p for p in apks if p.name.endswith('-debug.apk')]
    if len(tests_apk) != 1 or len(app_apk) != 1:
        raise SystemExit(f'expected one app and one test APK, found {[p.name for p in apks]}')

    image = f'system-images;android-{args.api};default;x86_64'
    run('sdk-install.log', [manager, '--channel=0', 'platform-tools', 'emulator', image], timeout=600, input_data=b'y\n' * 100)
    avd_home = Path(os.environ['RUNNER_TEMP']) / 'woowtechbot-avd'
    avd_home.mkdir(parents=True, exist_ok=True)
    os.environ['ANDROID_AVD_HOME'] = str(avd_home)
    run('avd-create.log', [avdmanager, 'create', 'avd', '--force', '--name', 'woowtechbot', '--path',
                           str(avd_home / 'woowtechbot.avd'), '--package', image, '--device', 'pixel_6'], input_data=b'no\n')
    emulator_log = (args.out / 'emulator.log').open('wb')
    proc = subprocess.Popen([emulator, '-avd', 'woowtechbot', '-port', '5554', '-no-window', '-no-audio', '-no-boot-anim',
                             '-no-snapshot', '-wipe-data', '-accel', 'on', '-gpu', 'swiftshader', '-memory', '2560', '-cores', '2',
                             '-camera-back', 'none', '-camera-front', 'none'],
                            stdout=emulator_log, stderr=subprocess.STDOUT, start_new_session=True)
    try:
        deadline = time.monotonic() + 420
        while time.monotonic() < deadline:
            if proc.poll() is not None:
                raise RuntimeError('emulator exited before boot')
            try:
                if device('shell', 'getprop', 'sys.boot_completed', timeout=10) == '1':
                    break
            except subprocess.TimeoutExpired:
                pass
            time.sleep(3)
        else:
            raise RuntimeError('boot timeout (420 s)')
        device('shell', 'input', 'keyevent', 'KEYCODE_WAKEUP')
        device('shell', 'wm', 'dismiss-keyguard')
        for setting in ('window_animation_scale', 'transition_animation_scale', 'animator_duration_scale'):
            device('shell', 'settings', 'put', 'global', setting, '0')
        summary['device'] = {k: device('shell', 'getprop', p) for k, p in (
            ('api', 'ro.build.version.sdk'), ('abi', 'ro.product.cpu.abi'), ('fingerprint', 'ro.build.fingerprint'))}
        save('webview.txt', device('shell', 'dumpsys', 'webviewupdate'))
        summary['webview'] = re.findall(r'Current WebView package \(name, version\): \(([^)]*)\)', (args.out / 'webview.txt').read_text())

        run('install-app.log', [adb, '-s', SERIAL, 'install', '-r', '-t', str(app_apk[0])], timeout=180)
        run('install-tests.log', [adb, '-s', SERIAL, 'install', '-r', '-t', str(tests_apk[0])], timeout=180)
        instrumentations = device('shell', 'pm', 'list', 'instrumentation')
        save('instrumentations.txt', instrumentations)
        match = re.search(r'instrumentation:(\S+)/(\S+) \(target=(\S+)\)', instrumentations)
        if not match:
            raise RuntimeError('test instrumentation not installed')
        test_package, runner, target = match.groups()
        summary['packages'] = dict(app=target, tests=test_package)
        device('shell', 'pm', 'grant', target, 'android.permission.POST_NOTIFICATIONS')

        out = run('instrument.txt', [adb, '-s', SERIAL, 'shell', 'am', 'instrument', '-w', '-r', '-e', 'class', ','.join(TESTS),
                                     f'{test_package}/{runner}'], timeout=1500, check=False)
        current = {}
        for line in out.splitlines():
            m = re.match(r'INSTRUMENTATION_STATUS: (class|test)=(.*)', line)
            if m:
                current[m.group(1)] = m.group(2)
            m = re.match(r'INSTRUMENTATION_STATUS_CODE: (-?\d+)', line)
            if m and m.group(1) != '1' and 'test' in current:
                name = current.get('class', '?').rsplit('.', 1)[-1] + '.' + current['test']
                summary['tests'][name] = STATUS.get(m.group(1), m.group(1))
        summary['instrumentation_ok'] = 'INSTRUMENTATION_CODE: -1' in out and 'FAILURES!!!' not in out
        save('screen-end.png', subprocess.run([adb, '-s', SERIAL, 'exec-out', 'screencap', '-p'], capture_output=True, timeout=30).stdout)
    finally:
        try:
            save('logcat.txt', subprocess.run([adb, '-s', SERIAL, 'logcat', '-d', '-b', 'all'], capture_output=True, timeout=60).stdout)
            subprocess.run([adb, '-s', SERIAL, 'emu', 'kill'], capture_output=True, timeout=30)
        except Exception:
            pass
        try:
            os.killpg(proc.pid, signal.SIGTERM)
            proc.wait(timeout=20)
        except Exception:
            pass
        save('summary.json', json.dumps(summary, indent=2))

    results = summary['tests'].values()
    passed = sum(1 for r in results if r == 'passed')
    bad = [n for n, r in summary['tests'].items() if r in ('failed', 'error')]
    lines = [f'### woowtechbot device tests, API {args.api}', f'WebView: {", ".join(summary["webview"]) or "unknown"}', '',
             '| Test | Result |', '| --- | --- |'] + [f'| {n} | {r} |' for n, r in summary['tests'].items()]
    if os.environ.get('GITHUB_STEP_SUMMARY'):
        with open(os.environ['GITHUB_STEP_SUMMARY'], 'a') as step:
            step.write('\n'.join(lines) + '\n')
    print('\n'.join(lines))
    if bad or not passed or not summary['instrumentation_ok']:
        raise SystemExit(f'device tests failed: {bad or "instrumentation did not finish"}')


if __name__ == '__main__':
    main()
