#!/usr/bin/env python3
"""CI-only Gradle 8.11.1 bootstrap; never executes Gradle or skips tests.

Official cache semantics (pinned to our wrapper version):
https://github.com/gradle/gradle/blob/v8.11.1/platforms/core-runtime/wrapper-shared/src/main/java/org/gradle/wrapper/PathAssembler.java
https://github.com/gradle/gradle/blob/v8.11.1/platforms/core-runtime/wrapper-shared/src/main/java/org/gradle/wrapper/Install.java
The API is an alternate official entry point, not a mirror. Its redirects and
credentials must never appear in logs. Run before any concurrent wrapper use.
"""
import hashlib
import os
from pathlib import Path
import subprocess
import sys
import tempfile

VERSION = '8.11.1'
URL = 'https://services.gradle.org/distributions/gradle-8.11.1-bin.zip'
ASSET = 'https://api.github.com/repos/gradle/gradle-distributions/releases/assets/207876967'
SIZE = 136920070
SHA256 = 'f397b287023acdba1e9f6fc5ea72d22dd63669d59ed4a289a29b1a76eee151c6'


def cache_zip(gradle_home):
    # PathAssembler: positive MD5 integer of safe URL ASCII, encoded base36.
    number = int.from_bytes(hashlib.md5(URL.encode('ascii')).digest(), 'big')
    digits = ''
    while number:
        number, digit = divmod(number, 36)
        digits = '0123456789abcdefghijklmnopqrstuvwxyz'[digit] + digits
    return gradle_home / 'wrapper/dists' / f'gradle-{VERSION}-bin' / digits / f'gradle-{VERSION}-bin.zip'


def check_properties(path):
    props = {}
    for line in path.read_text().splitlines():
        if '=' in line and not line.lstrip().startswith(('#', '!')):
            key, value = line.split('=', 1)
            props[key.strip()] = value.strip().replace('\\:', ':')
    expected = dict(distributionUrl=URL, distributionSha256Sum=SHA256,
                    distributionBase='GRADLE_USER_HOME', zipStoreBase='GRADLE_USER_HOME',
                    distributionPath='wrapper/dists', zipStorePath='wrapper/dists')
    if any(props.get(k) != v for k, v in expected.items()):
        raise RuntimeError('Wrapper configuration differs from pinned bootstrap; update both explicitly')


def verified_zip(path):
    if not path.is_file() or path.stat().st_size != SIZE:
        return False
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(block)
    return digest.hexdigest() == SHA256


def installed_cache(zip_path):
    # Match Install.verifyDistributionRoot + BootstrapMainStarter launcher lookup.
    # This is the existing Actions-cache trust boundary, not a fresh SHA proof
    # of extracted files. Gradle itself rechecks the root on the subsequent run.
    if not zip_path.with_suffix('.zip.ok').is_file():
        return False
    dirs = [p for p in zip_path.parent.iterdir() if p.is_dir()]
    return (len(dirs) == 1 and dirs[0].name == f'gradle-{VERSION}'
            and len(list((dirs[0] / 'lib').glob('gradle-launcher-*.jar'))) == 1)


def download(target):
    # curl -q disables ~/.curlrc; no auth required for this public asset.
    # Two attempts maximum, each capped at180s; subprocess adds a hard ceiling.
    # Capture all output: even curl errors can contain signed redirect URLs.
    command = ['curl', '-q', '--fail', '--silent', '--location',
               '--proto', '=https', '--proto-redir', '=https', '--max-redirs', '5',
               '--connect-timeout', '30', '--max-time', '180',
               '--retry', '1', '--retry-delay', '2', '--retry-max-time', '365',
               '--header', 'Accept: application/octet-stream',
               '--header', 'X-GitHub-Api-Version: 2022-11-28',
               '--write-out', '%{http_code}', '--output', str(target), ASSET]
    try:
        result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=375)
    except subprocess.TimeoutExpired:
        raise RuntimeError('Official Gradle API download exceeded375s limit') from None
    if result.returncode:
        status = result.stdout.decode('ascii', errors='ignore').strip()
        status = status if len(status) == 3 and status.isdigit() else 'unknown'
        raise RuntimeError(f'Official Gradle API download failed (curl exit {result.returncode}, HTTP {status}); no further retry')


def bootstrap(repo, gradle_home):
    if os.environ.get('GITHUB_ACTIONS') != 'true' or os.environ.get('CI') != 'true':
        raise RuntimeError('Bootstrap is restricted to GitHub Actions CI')
    check_properties(repo / 'gradle/wrapper/gradle-wrapper.properties')
    target = cache_zip(gradle_home)
    if installed_cache(target):
        print('Gradle bootstrap: reuse wrapper-installed Actions cache (root/marker checked)')
        return
    if verified_zip(target):
        print('Gradle bootstrap: reuse SHA-verified ZIP')
        return
    target.parent.mkdir(parents=True, exist_ok=True)
    # Remove an invalid ZIP/marker so a later wrapper cannot trust them.
    target.unlink(missing_ok=True)
    target.with_suffix('.zip.ok').unlink(missing_ok=True)
    # Temporary download is outside wrapper cache; only verified bytes are moved.
    with tempfile.TemporaryDirectory(prefix='gradle-bootstrap-', dir=gradle_home) as tmp:
        candidate = Path(tmp) / target.name
        download(candidate)
        if not verified_zip(candidate):
            raise RuntimeError('Official Gradle asset size/SHA-256 mismatch; cache not populated')
        os.replace(candidate, target)  # Same filesystem, atomic promotion.
    print(f'Gradle bootstrap: official asset207876967 verified bytes={SIZE} sha256={SHA256}')


def main():
    repo = Path(__file__).resolve().parents[2]
    gradle_home = Path(os.environ.get('GRADLE_USER_HOME') or Path.home() / '.gradle').resolve()
    try:
        bootstrap(repo, gradle_home)
    except (RuntimeError, OSError) as error:
        # OSError may contain environment-specific paths; don't dump exception URLs.
        message = str(error) if isinstance(error, RuntimeError) else type(error).__name__
        print('Gradle bootstrap failed: ' + message, file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
