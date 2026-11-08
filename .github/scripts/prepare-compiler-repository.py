#!/usr/bin/env python3
"""CI-only private Maven repository for exactly one compiler version.
JAR SHA256/size: official JetBrains asset API598635327; SHA1: Maven Central.
POM SHA256 pins the unmodified official Maven POM (including all transitives).
No dependency cache/binary metadata writes, mirrors, retries, or Gradle execution.
Publish GITHUB_ENV only after both files verify; init script rechecks them before use.
This is the final single-coordinate workaround, not an offline-build guarantee.
"""
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

NAME = 'kotlin-compiler-embeddable-2.1.20.jar'
URL = 'https://repo.maven.apache.org/maven2/org/jetbrains/kotlin/kotlin-compiler-embeddable/2.1.20/' + NAME
SIZE = 56909275
SHA256 = 'c54a00718c8c0e3ee858bf42771c7f401c5e3c1738861e18e9536371042fa1b3'
SHA1 = '4ef56b3316798316bfac7a0ae443391c9e900ea1'


POM_NAME = NAME.removesuffix('.jar') + '.pom'
POM_URL = URL.removesuffix('.jar') + '.pom'
API_URL = 'https://api.github.com/repos/JetBrains/kotlin/releases/assets/598635327'
POM_SHA256 = '227404eac6d809bc0d94def89336dfdf7d9a7d538792a234d52bdbafc2ae85af'
POM_SIZE = 2666
MODULE_PATH = Path('org/jetbrains/kotlin/kotlin-compiler-embeddable/2.1.20')


def verified(path, size, sha256, sha1=None):
    if not path.is_file() or path.stat().st_size != size:
        return False
    digests = [hashlib.sha256(), hashlib.sha1()]
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            for digest in digests:
                digest.update(block)
    return digests[0].hexdigest() == sha256 and (sha1 is None or digests[1].hexdigest() == sha1)


def receipt(**fields):
    print(json.dumps(fields, sort_keys=True), flush=True)


def download(target, url, api=False):
    args = ['curl', '-q', '--fail', '--silent', '--location', '--proto', '=https',
            '--proto-redir', '=https', '--max-redirs', '5', '--connect-timeout', '20',
            '--max-time', '150', '--write-out', '%{http_code}', '--output', str(target)]
    if api:
        args += ['--header', 'Accept: application/octet-stream', '--header', 'X-GitHub-Api-Version: 2022-11-28']
    args.append(url)
    try:
        result = subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=160)
    except subprocess.TimeoutExpired:
        receipt(stage='GET', artifact=target.name, outcome='timeout')
        raise RuntimeError('Official GET exceeded160s; stopping') from None
    raw = result.stdout.decode('ascii', errors='replace').strip()
    code = raw if re.fullmatch(r'[0-9]{3}', raw) else 'unknown'
    receipt(stage='GET', artifact=target.name, http_status=code, curl_exit=result.returncode)
    if result.returncode or code != '200':
        raise RuntimeError('Official GET failed; private repository not enabled')


def prepare(repo):
    if os.environ.get('CI') != 'true' or os.environ.get('GITHUB_ACTIONS') != 'true':
        raise RuntimeError('Compiler repository is restricted to GitHub Actions CI')
    props = (repo / 'gradle/wrapper/gradle-wrapper.properties').read_text()
    catalog = (repo / 'gradle/libs.versions.toml').read_text()
    if ('distributionUrl=https\\://services.gradle.org/distributions/gradle-8.11.1-bin.zip' not in props.splitlines()
            or not re.search(r'^kotlin\s*=\s*"2\.1\.20"\s*$', catalog, re.M)):
        raise RuntimeError('Pinned Gradle/Kotlin configuration changed')
    if not os.environ.get('RUNNER_TEMP') or not os.environ.get('GITHUB_ENV'):
        raise RuntimeError('RUNNER_TEMP and GITHUB_ENV required')
    root = Path(os.environ['RUNNER_TEMP']).resolve()
    if not root.is_dir() or any(c in str(root) for c in '\r\n'):
        raise RuntimeError('Invalid RUNNER_TEMP')
    private = Path(tempfile.mkdtemp(prefix='verified-compiler-', dir=root))  # mode0700
    try:
        stage = private / 'staging'
        stage.mkdir()
        download(stage / NAME, API_URL, api=True)
        if not verified(stage / NAME, SIZE, SHA256, SHA1):
            raise RuntimeError('Compiler JAR size/checksum mismatch')
        download(stage / POM_NAME, POM_URL)
        if not verified(stage / POM_NAME, POM_SIZE, POM_SHA256):
            raise RuntimeError('Compiler POM size/checksum mismatch')
        destination = private / 'repository' / MODULE_PATH
        destination.parent.mkdir(parents=True)
        os.replace(stage, destination)  # Publish only the complete verified pair.
        with Path(os.environ['GITHUB_ENV']).open('a') as env:
            env.write('CI_VERIFIED_COMPILER_REPO=' + str(private / 'repository') + '\n')
        receipt(stage='repository_ready', jar_sha256=SHA256, jar_sha1=SHA1,
                pom_sha256=POM_SHA256, scope='org.jetbrains.kotlin:kotlin-compiler-embeddable:2.1.20 only')
        return private / 'repository'
    except BaseException:
        shutil.rmtree(private)
        raise


def main():
    try:
        prepare(Path(__file__).resolve().parents[2])
    except (RuntimeError, OSError) as error:
        receipt(stage='failure', error=str(error) if isinstance(error, RuntimeError) else type(error).__name__)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
