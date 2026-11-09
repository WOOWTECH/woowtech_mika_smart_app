#!/usr/bin/env python3
"""GitHub Linux/KVM only: fresh Apporo welcome, force-stop/relaunch, evidence.

No onboarding clicks, model keys, helper, sandbox or functional parity claims.
See startup-smoke.md. All subprocesses, boot/UI retries and cleanup are bounded.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import time
import xml.etree.ElementTree as ET
import zipfile

PACKAGE = 'com.apporo.assistant'
COMPONENT = PACKAGE + '/com.wangzan101.mika.ui.MainActivity'
WELCOME = ('Meet Apporo Assistant', 'Get started')


class SmokeInterrupted(BaseException):
    """Cancellation must bypass transient boot/UI retry handlers."""


def welcome_visible(xml):
    nodes = [n for n in ET.fromstring(xml).iter('node') if n.get('package') == PACKAGE]
    texts = {n.get('text') for n in nodes}
    return all(text in texts for text in WELCOME)


def system_ui_wait_target(xml):
    """Recognize only the AOSP System UI ANR dialog, never an app or security dialog."""
    nodes = list(ET.fromstring(xml).iter('node'))
    titles = [n for n in nodes if n.get('resource-id') == 'android:id/alertTitle']
    if (len(titles) != 1 or titles[0].get('package') != 'android' or
            titles[0].get('text') != "System UI isn't responding"):
        return None
    buttons = [n for n in nodes if n.get('resource-id') == 'android:id/aerr_wait' and
               n.get('package') == 'android' and n.get('text') == 'Wait' and
               n.get('enabled') == 'true' and n.get('clickable') == 'true']
    if len(buttons) != 1:
        return None
    match = re.fullmatch(r'\[(\d+),(\d+)\]\[(\d+),(\d+)\]', buttons[0].get('bounds', ''))
    if not match:
        return None
    x1, y1, x2, y2 = map(int, match.groups())
    return ((x1 + x2) // 2, (y1 + y2) // 2) if x2 > x1 and y2 > y1 else None


def app_crash(log):
    # AndroidRuntime Java crashes, debuggerd native crashes, ActivityManager events.
    name = re.escape(PACKAGE) + r'(?=[:\s,\]>]|$)'
    return any(re.search(pattern, log, re.M) for pattern in (
        r'Process:\s*' + name,
        r'>>>\s*' + re.escape(PACKAGE) + r'(?::[^ ]+)?\s*<<<',
        r'ANR in\s+' + name,
        r'am_(?:crash|anr)\s*:.*\b' + name,
    ))


def verify_avd(avd_home, name, listing):
    """Do not attempt boot unless creation and emulator discovery agree."""
    registration = avd_home / (name + '.ini')
    config = avd_home / (name + '.avd') / 'config.ini'
    if not registration.is_file() or not config.is_file():
        raise RuntimeError('AVD registration/config missing; see avd-paths.json')
    paths = [line.partition('=')[2].strip() for line in registration.read_text().splitlines()
             if line.startswith('path=')]
    if paths != [str(config.parent)] or name not in listing.splitlines():
        raise RuntimeError('AVD registration/discovery mismatch; see avd-paths.json and avd-list.log')


def run(argv, timeout=30, check=True, input_data=None):
    """Kill the whole command group on timeout/cancellation (including SDK Java)."""
    proc = subprocess.Popen([str(x) for x in argv], stdin=subprocess.PIPE,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            start_new_session=True)
    try:
        out, err = proc.communicate(input_data, timeout=timeout)
    except BaseException:
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        proc.communicate(timeout=5)
        raise
    if check and proc.returncode:
        raise RuntimeError(f'{argv[0]} exited {proc.returncode}: ' + err.decode(errors='replace')[-2000:])
    return out, err, proc.returncode


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--api', type=int, choices=(30, 32, 35, 36), required=True)
    parser.add_argument('--apk', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    # Never accidentally use a developer's local emulator or physical device.
    if sys.platform != 'linux' or os.environ.get('GITHUB_ACTIONS') != 'true':
        parser.error('only runs on a disposable GitHub Actions Linux runner')
    args.out.mkdir(parents=True, exist_ok=True)
    started = time.monotonic()
    receipt = dict(status='FAIL', api=args.api, abi='x86_64', image_tag='default', package=PACKAGE,
                   source_sha=os.environ.get('GITHUB_SHA'), stages=[],
                   scope='fresh English welcome + force-stop/relaunch only',
                   excluded=['helper/sandbox (arm64 only)', 'model/API calls',
                             'permission flows', 'full UI or ABI functional parity'])
    emulator_proc = None
    emulator_log = None
    adb = None
    avd = f'apporo-smoke-{args.api}'
    sdk = None

    def save(name, data):
        (args.out / name).write_bytes(data if isinstance(data, bytes) else data.encode())

    def stage(name):
        receipt['stages'].append(dict(name=name, elapsed_seconds=round(time.monotonic() - started, 2)))
        save('receipt.json', json.dumps(receipt, indent=2))

    def command_log(name, argv, timeout=30, input_data=None):
        try:
            out, err, code = run(argv, timeout, check=False, input_data=input_data)
        except subprocess.TimeoutExpired as exc:
            save(name, (exc.output or b'') + (exc.stderr or b'') + b'\nCOMMAND TIMEOUT\n')
            raise
        save(name, out + err)
        if code:
            raise RuntimeError(f'{name}: exit {code}; see artifact')
        return out.decode(errors='replace')

    def device(*argv, timeout=30, check=True):
        return run([adb, '-s', 'emulator-5554', *argv], timeout, check)[0].decode(errors='replace').strip()

    def read_ui(name):
        device('shell', 'rm', '-f', '/sdcard/apporo-smoke.xml', timeout=5)
        device('shell', 'uiautomator', 'dump', '/sdcard/apporo-smoke.xml', timeout=15)
        xml = device('shell', 'cat', '/sdcard/apporo-smoke.xml', timeout=10)
        save(name, xml)
        return xml

    def interrupted(signum, frame):
        raise SmokeInterrupted(f'interrupted/overall timeout: signal {signum}')

    for sig in (signal.SIGTERM, signal.SIGINT, signal.SIGALRM):
        signal.signal(sig, interrupted)
    signal.alarm(1200)
    try:
        stage('preflight')
        sdk_value = os.environ.get('ANDROID_HOME') or os.environ.get('ANDROID_SDK_ROOT')
        if not sdk_value:
            raise RuntimeError('ANDROID_HOME/ANDROID_SDK_ROOT missing')
        sdk = Path(sdk_value)
        adb = sdk / 'platform-tools/adb'
        manager = sdk / 'cmdline-tools/latest/bin/sdkmanager'
        avdmanager = sdk / 'cmdline-tools/latest/bin/avdmanager'
        if not os.access('/dev/kvm', os.R_OK | os.W_OK):
            raise RuntimeError('/dev/kvm is not accessible; no software VM fallback')
        apks = list(args.apk.glob('*.apk')) if args.apk.is_dir() else [args.apk]
        if len(apks) != 1 or not apks[0].is_file():
            raise RuntimeError('exactly one universal debug APK required')
        apk = apks[0].resolve()
        receipt['apk'] = dict(name=apk.name, sha256=hashlib.sha256(apk.read_bytes()).hexdigest(), bytes=apk.stat().st_size)
        with zipfile.ZipFile(apk) as z:
            receipt['apk']['native_abis'] = sorted({n.split('/')[1] for n in z.namelist() if n.startswith('lib/') and n.endswith('.so')})
        # Explicit packages, stable channel; tool/image revisions are recorded below.
        stage('sdk-install')
        # Official AOSP image: Google APIs images may advertise translated arm64
        # and trigger the app's automatic runtime preparation.
        image = f'system-images;android-{args.api};default;x86_64'
        command_log('sdk-install.log', [manager, '--channel=0', 'platform-tools', 'emulator', image],
                    timeout=480, input_data=b'y\n' * 100)
        for label, path in [('emulator', sdk / 'emulator/source.properties'),
                            ('image', sdk / f'system-images/android-{args.api}/default/x86_64/source.properties')]:
            save(label + '-source.properties', path.read_bytes())
        emulator = sdk / 'emulator/emulator'
        command_log('accel-check.log', [emulator, '-accel-check'])
        command_log('adb-version.txt', [adb, 'version'])
        devices = command_log('devices-before.txt', [adb, 'devices'])
        if len(devices.strip().splitlines()) != 1:
            raise RuntimeError('runner already has devices; refusing to touch them')
        stage('avd-create')
        # Do not rely on differing Java/native tool defaults or alter HOME.
        path_keys = ('HOME', 'ANDROID_HOME', 'ANDROID_SDK_ROOT', 'ANDROID_SDK_HOME',
                     'ANDROID_USER_HOME', 'ANDROID_EMULATOR_HOME', 'ANDROID_AVD_HOME', 'RUNNER_TEMP')
        original_paths = {key: os.environ.get(key) for key in path_keys}
        avd_home = (Path(os.environ['RUNNER_TEMP']) / 'apporo-smoke-avd').resolve()
        avd_home.mkdir(parents=True, exist_ok=True)
        os.environ['ANDROID_AVD_HOME'] = str(avd_home)
        avd_path = avd_home / (avd + '.avd')
        save('avd-paths.json', json.dumps(dict(original=original_paths,
             effective_avd_home=str(avd_home), avd_path=str(avd_path)), indent=2))
        command_log('avd-create.log', [avdmanager, 'create', 'avd', '--force', '--name', avd,
                                      '--path', avd_path, '--package', image, '--device', 'pixel_2'],
                    input_data=b'no\n', timeout=60)
        listing = command_log('avd-list.log', [emulator, '-list-avds'])
        for label, path in [('avd-registration.ini', avd_home / (avd + '.ini')),
                            ('avd-config.ini', avd_path / 'config.ini')]:
            if path.is_file():
                save(label, path.read_bytes())
        verify_avd(avd_home, avd, listing)
        stage('boot')
        emulator_log = (args.out / 'emulator.log').open('wb')
        emulator_proc = subprocess.Popen([str(emulator), '-avd', avd, '-port', '5554',
            '-no-window', '-no-audio', '-no-boot-anim', '-no-snapshot', '-wipe-data',
            '-accel', 'on', '-gpu', 'swiftshader', '-memory', '2048', '-cores', '2',
            '-camera-back', 'none', '-camera-front', 'none'],
            stdout=emulator_log, stderr=subprocess.STDOUT, start_new_session=True)
        deadline = time.monotonic() + 300
        while time.monotonic() < deadline:
            if emulator_proc.poll() is not None:
                raise RuntimeError('emulator exited before boot')
            try:
                if device('shell', 'getprop', 'sys.boot_completed', timeout=10) == '1':
                    break
            except (RuntimeError, subprocess.TimeoutExpired):
                pass
            time.sleep(2)
        else:
            raise RuntimeError('boot timeout (300s)')
        receipt['device'] = {k: device('shell', 'getprop', prop) for k, prop in (
            ('api', 'ro.build.version.sdk'), ('abi', 'ro.product.cpu.abi'),
            ('fingerprint', 'ro.build.fingerprint'), ('locale', 'persist.sys.locale'),
            ('abilist', 'ro.product.cpu.abilist'))}
        if receipt['device']['api'] != str(args.api) or receipt['device']['abi'] != 'x86_64':
            raise RuntimeError('wrong emulator API/ABI')
        if 'arm64-v8a' in receipt['device']['abilist'].split(','):
            raise RuntimeError('image advertises arm64 translation: refusing automatic sandbox preparation')
        device('shell', 'input', 'keyevent', 'KEYCODE_WAKEUP')
        device('shell', 'wm', 'dismiss-keyguard')
        for setting in ('window_animation_scale', 'transition_animation_scale', 'animator_duration_scale'):
            device('shell', 'settings', 'put', 'global', setting, '0')
        stage('install')
        command_log('install.log', [adb, '-s', 'emulator-5554', 'install', '--no-streaming', str(apk)], timeout=120)
        save('package.txt', device('shell', 'dumpsys', 'package', PACKAGE))
        # Fresh AVD, no clear-data or permission grants. Start log window before app launch.
        device('logcat', '-b', 'all', '-c')
        system_ui_recovered = False
        for attempt in ('cold-start', 'relaunch'):
            stage(attempt)
            if attempt == 'relaunch':
                device('shell', 'am', 'force-stop', PACKAGE)
                if device('shell', 'pidof', PACKAGE, check=False):
                    raise RuntimeError('force-stop left app process alive')
            launch = device('shell', 'am', 'start', '-W', '-n', COMPONENT, timeout=45)
            save(attempt + '-launch.txt', launch)
            if not re.search(r'^Status:\s*ok\s*$', launch, re.M):
                raise RuntimeError('am start did not report Status: ok')
            deadline = time.monotonic() + 90
            while time.monotonic() < deadline:
                try:
                    xml = read_ui(attempt + '.xml')
                    target = system_ui_wait_target(xml)
                    visible = welcome_visible(xml)
                except (RuntimeError, subprocess.TimeoutExpired, ET.ParseError):
                    time.sleep(2)
                    continue
                if target and not system_ui_recovered:
                    # Disposable AOSP sometimes stalls System UI during first boot.
                    # Preserve the obstruction, allow one normal Wait action, and keep
                    # the original deadline and all app-crash/stability requirements.
                    log = device('logcat', '-b', 'all', '-d', '-v', 'threadtime')
                    save('system-ui-before-wait.log', log)
                    if app_crash(log):
                        raise RuntimeError('Apporo crash/ANR before System UI recovery')
                    save('system-ui-before-wait.xml', xml)
                    save('system-ui-before-wait.png', run([adb, '-s', 'emulator-5554', 'exec-out', 'screencap', '-p'])[0])
                    system_ui_recovered = True
                    receipt.setdefault('environment_recoveries', []).append(dict(
                        stage=attempt, dialog="System UI isn't responding", action='Wait once',
                        deadline_extended=False, app_crash_detected=False))
                    save('receipt.json', json.dumps(receipt, indent=2))
                    device('shell', 'input', 'tap', str(target[0]), str(target[1]))
                elif target is not None:
                    raise RuntimeError('System UI obstruction remained or returned after the single Wait')
                elif target is None and visible:
                    break
                time.sleep(2)
            else:
                raise RuntimeError('English Apporo welcome not visible within90s')
            pid = device('shell', 'pidof', PACKAGE)
            if not pid:
                raise RuntimeError('no app process')
            time.sleep(5)
            if device('shell', 'pidof', PACKAGE) != pid:
                raise RuntimeError('process died/restarted during startup observation')
            observed_xml = read_ui(attempt + '.xml')
            if system_ui_wait_target(observed_xml) is not None or not welcome_visible(observed_xml):
                raise RuntimeError('welcome disappeared during startup observation')
            activities = device('shell', 'dumpsys', 'activity', 'activities')
            save(attempt + '-activities.txt', activities)
            if not any(PACKAGE in line and re.search(r'(?:mResumedActivity|topResumedActivity)', line)
                       for line in activities.splitlines()):
                raise RuntimeError('Apporo is not the resumed activity')
            png = run([adb, '-s', 'emulator-5554', 'exec-out', 'screencap', '-p'])[0]
            save(attempt + '.png', png)
            if not png.startswith(b'\x89PNG\r\n\x1a\n'):
                raise RuntimeError('screencap did not return PNG')
            log = device('logcat', '-b', 'all', '-d', '-v', 'threadtime')
            save(attempt + '-logcat.txt', log)
            if app_crash(log):
                raise RuntimeError('Apporo crash/ANR found in logcat')
            exits = device('shell', 'dumpsys', 'activity', 'exit-info', PACKAGE)
            save(attempt + '-exit-info.txt', exits)
            if re.search(r'reason=(?:4|5|6)\b', exits):
                raise RuntimeError('Apporo crash/native-crash/ANR exit reason')
            receipt.setdefault('observations', []).append(dict(stage=attempt, pid=pid,
                welcome=list(WELCOME), observation_seconds=5, crash_or_anr_detected=False))
        receipt['status'] = 'PASS_STARTUP_ONLY'
    except (Exception, SmokeInterrupted) as exc:
        receipt['error'] = f'{type(exc).__name__}: {exc}'
        print(receipt['error'], file=sys.stderr)
    finally:
        signal.alarm(0)
        # Do not let a second cancellation interrupt the short bounded cleanup.
        for sig in (signal.SIGTERM, signal.SIGINT):
            signal.signal(sig, signal.SIG_IGN)
        cleanup = []
        if emulator_proc is not None:
            if receipt['status'] != 'PASS_STARTUP_ONLY':
                for name, argv in [('failure.png', ['exec-out', 'screencap', '-p']),
                                   ('failure-window.txt', ['shell', 'dumpsys', 'window']),
                                   ('failure-last-ui.xml', ['shell', 'cat', '/sdcard/apporo-smoke.xml'])]:
                    try:
                        out, err, code = run([adb, '-s', 'emulator-5554', *argv], timeout=10, check=False)
                        if code == 0:
                            save(name, out)
                    except Exception:
                        pass  # Diagnostics cannot prevent emulator cleanup/receipt.
            for name, argv in [('final-logcat.txt', [adb, '-s', 'emulator-5554', 'logcat', '-b', 'all', '-d']),
                               ('emulator-stop.txt', [adb, '-s', 'emulator-5554', 'emu', 'kill'])]:
                try:
                    out, err, code = run(argv, timeout=10, check=False)
                    save(name, out + err)
                    cleanup.append(dict(command=name, exit=code))
                except Exception as exc:
                    cleanup.append(dict(command=name, error=str(exc)))
            try:
                # Kill group even when launcher exited, so child QEMU cannot linger.
                os.killpg(emulator_proc.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
            try:
                emulator_proc.wait(timeout=10)
            except subprocess.TimeoutExpired:
                pass
            try:
                os.killpg(emulator_proc.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            try:
                emulator_proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                receipt['status'] = 'FAIL'
                receipt['error'] = 'emulator did not terminate after SIGKILL'
            cleanup.append(dict(emulator_returncode=emulator_proc.returncode))
        if emulator_log:
            emulator_log.close()
        receipt['cleanup'] = cleanup
        receipt['elapsed_seconds'] = round(time.monotonic() - started, 2)
        save('receipt.json', json.dumps(receipt, indent=2) + '\n')
        summary = os.environ.get('GITHUB_STEP_SUMMARY')
        if summary:
            with open(summary, 'a') as f:
                f.write(f"\n### API {args.api} x86_64 startup smoke\n\n{receipt['status']}\n\n"
                        'See receipt/screenshots/XML/logs artifact. No helper, sandbox, permission-flow or model parity claim.\n')
    return 0 if receipt['status'] == 'PASS_STARTUP_ONLY' else 1


if __name__ == '__main__':
    sys.exit(main())
