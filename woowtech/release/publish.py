#!/usr/bin/env python3
"""Trusted release-machine worker. CI never receives the signing key.
Run periodically with --state DIR; --check performs no downloads/signing/writes.
Install a reviewed copy, not a script auto-executed from a remote branch.
"""
import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import urllib.error
import urllib.parse
import urllib.request
import zipfile

REPO = 'WOOWTECH/woowtech_mika_smart_app'
API = 'https://api.github.com/repos/' + REPO
CERT = '806b3db808ecbb4d2d032b34624baa7e193802f17a07afbde2a03e78da9474c8'
WORKFLOWS = ('ci.yml', 'woowtech.yml')


def version_from_sources(build, brand):
    upstream = re.search(r'^\s*versionName = "([0-9.]+)"', build, re.M).group(1)
    base = int(re.search(r'^\s*versionCode = (\d+)', build, re.M).group(1))
    revision = int(re.search(r'^val woowtechRevision = (\d+)', brand, re.M).group(1))
    if not 1 <= revision < 100:
        raise ValueError('woowtechRevision must be 1..99')
    return f'{upstream}-woow.{revision}', base * 100 + revision


def version_key(tag):
    match = re.fullmatch(r'v?(\d+)\.(\d+)\.(\d+)-woow\.(\d+)', tag)
    if not match:
        raise ValueError('Not a stable WOOW version: ' + tag)
    return tuple(map(int, match.groups()))


def successful_run(runs, sha):
    # Latest attempt wins: an earlier successful attempt cannot mask a failed rerun.
    matching = [r for r in runs if r['head_sha'] == sha and r['head_branch'] == 'main' and r['event'] == 'push']
    if not matching:
        return None
    run = max(matching, key=lambda r: (r['run_number'], r.get('run_attempt', 1)))
    return run if run['status'] == 'completed' and run['conclusion'] == 'success' else None


class Redirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        redirected = super().redirect_request(req, fp, code, msg, headers, newurl)
        if urllib.parse.urlsplit(newurl).hostname != urllib.parse.urlsplit(req.full_url).hostname:
            redirected.remove_header('Authorization')
        return redirected


class GitHub:
    def __init__(self):
        token = os.environ.get('GH_TOKEN')
        if not token:
            hosts = Path.home() / '.config/gh/hosts.yml'
            match = re.search(r'^\s*oauth_token:\s*(\S+)', hosts.read_text(), re.M) if hosts.exists() else None
            token = match.group(1) if match else None
        if not token:
            result = subprocess.run(['git', 'credential', 'fill'], input='protocol=https\nhost=github.com\n\n',
                                    text=True, capture_output=True, check=True, timeout=15)
            token = dict(line.split('=', 1) for line in result.stdout.splitlines() if '=' in line)['password']
        self.headers = {'Authorization': 'Bearer ' + token, 'Accept': 'application/vnd.github+json',
                        'User-Agent': 'woow-release-worker', 'X-GitHub-Api-Version': '2022-11-28'}
        self.opener = urllib.request.build_opener(Redirect())

    def request(self, path, body=None, method=None, binary=False):
        url = path if path.startswith('https://') else API + path
        host = urllib.parse.urlsplit(url).hostname
        if host not in ('api.github.com', 'uploads.github.com'):
            raise ValueError('Unexpected GitHub API host')
        headers = dict(self.headers)
        if isinstance(body, bytes):
            headers['Content-Type'] = 'application/octet-stream'
        elif body is not None:
            body = json.dumps(body).encode()
            headers['Content-Type'] = 'application/json'
        with self.opener.open(urllib.request.Request(url, data=body, headers=headers, method=method), timeout=180) as response:
            data = response.read()
        return data if binary else json.loads(data)

    def optional(self, path):
        try:
            return self.request(path)
        except urllib.error.HTTPError as error:
            if error.code != 404:
                raise
            return None

    def source(self, path, sha):
        import base64
        obj = self.request('/contents/' + path + '?ref=' + sha)
        return base64.b64decode(obj['content']).decode()


def unpack_verified(data, digest, destination):
    if digest != 'sha256:' + hashlib.sha256(data).hexdigest():
        raise ValueError('Artifact archive digest mismatch or missing digest')
    archive = destination.with_suffix('.zip')
    archive.write_bytes(data)
    with zipfile.ZipFile(archive) as z:
        for entry in z.infolist():
            path = Path(entry.filename)
            if path.is_absolute() or '..' in path.parts or (entry.external_attr >> 16) & 0o170000 == 0o120000:
                raise ValueError('Unsafe artifact entry')
        z.extractall(destination)


def artifact(gh, run, name, directory):
    items = gh.request(f"/actions/runs/{run['id']}/artifacts?per_page=100")['artifacts']
    matches = [a for a in items if a['name'] == name and not a['expired']]
    if len(matches) != 1:
        raise ValueError('Missing or ambiguous artifact: ' + name)
    a = matches[0]
    unpack_verified(gh.request(a['archive_download_url'], binary=True), a.get('digest'), directory)


def sign_apks(source, output, version, code):
    sdk = Path(os.environ.get('ANDROID_HOME', str(Path.home() / 'Library/Android/sdk')))
    bt = sdk / 'build-tools/35.0.0'
    key = Path.home() / 'keystores/woowtech-agent-release.p12'
    password = Path.home() / '.woow-upload-key/woowtech-agent-release-store-password.secret'
    for abi, suffix in [('arm64-v8a', '-arm64'), ('universal', '')]:
        apk = source / f'release/app-woowtech-{abi}-release-unsigned.apk'
        badging = subprocess.check_output([str(bt / 'aapt'), 'dump', 'badging', str(apk)], text=True)
        expected = f"package: name='io.woowtech.agent' versionCode='{code}' versionName='{version}'"
        if not badging.startswith(expected):
            raise ValueError('APK package/version mismatch')
        subprocess.run([str(bt / 'zipalign'), '-c', '-P', '16', '4', str(apk)], check=True, capture_output=True)
        target = output / f'woowtech-agent-v{version}{suffix}.apk'
        subprocess.run([str(bt / 'apksigner'), 'sign', '--ks', str(key), '--ks-type', 'PKCS12',
                        '--ks-key-alias', 'woowtech-agent-release', '--ks-pass', 'file:' + str(password),
                        '--v4-signing-enabled', 'false', '--out', str(target), str(apk)], check=True, capture_output=True)
        verified = subprocess.check_output([str(bt / 'apksigner'), 'verify', '--print-certs', str(target)], text=True)
        if f'Signer #1 certificate SHA-256 digest: {CERT}' not in verified:
            raise ValueError('Signing certificate mismatch')


def publish(gh, state, check=False):
    sha = gh.request('/git/ref/heads/main')['object']['sha']
    version, code = version_from_sources(gh.source('app/build.gradle.kts', sha), gh.source('app/brand.gradle.kts', sha))
    tag = 'v' + version
    release = gh.optional('/releases/tags/' + tag)
    if release and not release['draft']:
        print(tag, 'already published', flush=True)
        return
    latest = gh.optional('/releases/latest')
    if latest and version_key(tag) <= version_key(latest['tag_name']):
        raise ValueError('New version must be newer than latest stable release')
    runs = {}
    for workflow in WORKFLOWS:
        result = gh.request(f'/actions/workflows/{workflow}/runs?branch=main&event=push&head_sha={sha}&per_page=100')
        run = successful_run(result['workflow_runs'], sha)
        if not run:
            print(tag, 'waiting for successful main CI:', workflow, sha, flush=True)
            return
        runs[workflow] = run
    print(tag, 'eligible', sha, flush=True)
    if check:
        return
    # A private persistent directory supports safe retry after an interrupted upload.
    folder = state / tag / sha
    folder.mkdir(parents=True, exist_ok=True)
    signed = folder / 'signed'
    signed.mkdir(exist_ok=True)
    if not (folder / 'prepared.json').exists():
        with tempfile.TemporaryDirectory(dir=folder) as temp:
            tmp = Path(temp)
            artifact(gh, runs['woowtech.yml'], 'woowtech-apk-' + sha, tmp / 'apks')
            artifact(gh, runs['woowtech.yml'], 'gpl-sources-' + sha, tmp / 'gpl')
            gpl = tmp / 'gpl' / f'mika-{version}-gpl-sources.tar.gz'
            if not gpl.is_file() or gpl.stat().st_size < 1_000_000:
                raise ValueError('Corresponding source archive missing')
            sign_apks(tmp / 'apks', signed, version, code)
            (signed / gpl.name).write_bytes(gpl.read_bytes())
        sums = ''.join(hashlib.sha256(p.read_bytes()).hexdigest() + '  ' + p.name + '\n'
                       for p in sorted(signed.iterdir()) if p.name != 'SHA256SUMS.txt')
        (signed / 'SHA256SUMS.txt').write_text(sums)
        (folder / 'prepared.json').write_text(json.dumps({'sha': sha, 'version': version, 'code': code}))
    expected_files = {f'woowtech-agent-v{version}-arm64.apk', f'woowtech-agent-v{version}.apk',
                      f'mika-{version}-gpl-sources.tar.gz', 'SHA256SUMS.txt'}
    if {p.name for p in signed.iterdir()} != expected_files:
        raise ValueError('Incomplete or unexpected prepared files')
    sums = (signed / 'SHA256SUMS.txt').read_text().splitlines()
    if len(sums) != 3:
        raise ValueError('Incomplete checksum manifest')
    for line in sums:
        digest, name = line.split('  ', 1)
        if name not in expected_files - {'SHA256SUMS.txt'} or hashlib.sha256((signed / name).read_bytes()).hexdigest() != digest:
            raise ValueError('Prepared file checksum mismatch')
    # Refuse superseded main builds; retry on the current commit on the next poll.
    if gh.request('/git/ref/heads/main')['object']['sha'] != sha:
        print('main advanced; deferring publication', flush=True)
        return
    notes = gh.source(f'docs-woowtech/releases/{tag}.md', sha)
    notes += f'\n\n來源 commit：`{sha}`。版本代碼：`{code}`。同一正式簽章，可保留資料覆蓋更新。\n'
    if release is None:
        release = gh.request('/releases', {'tag_name': tag, 'target_commitish': sha, 'name': '渥屋助理 ' + version,
                                         'body': notes, 'draft': True, 'prerelease': False, 'make_latest': 'false'})
    # Never reuse a draft belonging to a different commit.
    if release['target_commitish'] != sha:
        raise ValueError('Existing draft points to another commit; review it manually')
    assets = {a['name']: a for a in gh.request(release['assets_url'])}
    for path in sorted(signed.iterdir()):
        data = path.read_bytes()
        digest = 'sha256:' + hashlib.sha256(data).hexdigest()
        a = assets.get(path.name)
        if a is None:
            a = gh.request(release['upload_url'].split('{')[0] + '?name=' + urllib.parse.quote(path.name), data, 'POST')
        if a['size'] != len(data) or a.get('digest') != digest:
            raise ValueError('Uploaded asset mismatch: ' + path.name)
    if set(assets) - {p.name for p in signed.iterdir()}:
        raise ValueError('Unexpected existing release assets')
    if gh.request('/git/ref/heads/main')['object']['sha'] != sha:
        raise ValueError('main advanced during upload; leave draft for review')
    gh.request('/releases/' + str(release['id']), {'draft': False, 'prerelease': False, 'make_latest': 'true'}, 'PATCH')
    latest = gh.request('/releases/latest')
    if latest['tag_name'] != tag:
        raise ValueError('Published release is not latest')
    (folder / 'published.json').write_text(json.dumps(latest, ensure_ascii=False, indent=2))
    print('published', latest['html_url'], flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--state', type=Path, required=True)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    os.umask(0o077)
    args.state.mkdir(parents=True, exist_ok=True)
    with (args.state / 'worker.lock').open('w') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return
        publish(GitHub(), args.state, args.check)


if __name__ == '__main__':
    main()
