#!/usr/bin/env python3
"""CI-only candidate seed for ONE compiler artifact; run before any Gradle task.

Gradle v8.11.1 source proof (under platforms/software/dependency-management/src/main/java/):
org/gradle/api/internal/artifacts/ivyservice/CacheLayout.java: modules-2/files-2.1.
org/gradle/api/internal/filestore/DefaultArtifactIdentifierFileStore.java: group/module/version.
org/gradle/internal/resource/local/ivy/LocallyAvailableResourceFinderFactory.java:
  searches current artifact file store first, without a binary metadata index.
org/gradle/api/internal/artifacts/repositories/resolver/ExternalResourceResolver.java
  wires that finder into DefaultExternalResourceArtifactResolver, which passes candidates.
org/gradle/internal/resource/transfer/DefaultCacheAwareExternalResourceAccessor.java:
  remote HEAD + SHA1 (header or .sha1) must match before using a candidate.
GroupedAndNamedUniqueFileStore.java (subprojects/core/src/main/java/org/gradle/internal/resource/local/):
  group/SHA1-with-leading-zeroes-stripped/filename; search uses wildcard checksum.
DefaultExternalResourceFileStore uses a DIFFERENT URL-based grouping; do not seed it.
Source root: https://github.com/gradle/gradle/tree/v8.11.1

SHA256: official JetBrains release API asset 598635327 digest, v2.1.20.
https://api.github.com/repos/JetBrains/kotlin/releases/assets/598635327
SHA1: Maven Central artifact .jar.sha1; size independently agrees with release API.
This is only a verified candidate, NOT proof of Gradle reuse or an offline build.
Remote metadata/checksum can still fail. Original Gradle tasks must succeed in CI;
Gradle --info's 'Found locally available resource with matching checksum' is the
specific reuse witness. No binary metadata, repository settings or tests are changed.
"""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

NAME = 'kotlin-compiler-embeddable-2.1.20.jar'
URL = 'https://repo.maven.apache.org/maven2/org/jetbrains/kotlin/kotlin-compiler-embeddable/2.1.20/' + NAME
SIZE = 56909275
SHA256 = 'c54a00718c8c0e3ee858bf42771c7f401c5e3c1738861e18e9536371042fa1b3'
SHA1 = '4ef56b3316798316bfac7a0ae443391c9e900ea1'


def candidate_path(cache_root):
    return (cache_root / 'caches/modules-2/files-2.1/org.jetbrains.kotlin'
            / 'kotlin-compiler-embeddable/2.1.20' / SHA1.lstrip('0') / NAME)


def verified(path):
    if not path.is_file() or path.stat().st_size != SIZE:
        return False
    sha256, sha1 = hashlib.sha256(), hashlib.sha1()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            sha256.update(block)
            sha1.update(block)
    return sha256.hexdigest() == SHA256 and sha1.hexdigest() == SHA1


def receipt(**fields):
    print(json.dumps(dict(artifact=NAME, **fields), sort_keys=True), flush=True)


def download(target):
    # One bounded official GET; no retry/mirror/auth or inherited curlrc.
    # Never print stderr/effective URL: redirects can carry signed credentials.
    args = ['curl', '-q', '--fail', '--silent', '--location', '--proto', '=https',
            '--proto-redir', '=https', '--max-redirs', '5', '--connect-timeout', '20',
            '--max-time', '150', '--write-out', '%{http_code}', '--output', str(target), URL]
    try:
        result = subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=160)
    except subprocess.TimeoutExpired:
        receipt(stage='GET', outcome='timeout')
        raise RuntimeError('Official compiler GET exceeded160s; stopping') from None
    raw = result.stdout.decode('ascii', errors='replace').strip()
    code = raw if re.fullmatch(r'[0-9]{3}', raw) else 'unknown'
    receipt(stage='GET', http_status=code, curl_exit=result.returncode)
    if result.returncode or code != '200':
        raise RuntimeError('Official compiler GET failed; stopping without cache promotion')


def seed(repo, cache_root):
    if os.environ.get('CI') != 'true' or os.environ.get('GITHUB_ACTIONS') != 'true':
        raise RuntimeError('Compiler seed is restricted to GitHub Actions CI')
    props = (repo / 'gradle/wrapper/gradle-wrapper.properties').read_text()
    catalog = (repo / 'gradle/libs.versions.toml').read_text()
    if ('distributionUrl=https\\://services.gradle.org/distributions/gradle-8.11.1-bin.zip' not in props.splitlines()
            or not re.search(r'^kotlin\s*=\s*"2\.1\.20"\s*$', catalog, re.M)):
        raise RuntimeError('Pinned Gradle/Kotlin configuration changed; review seed before use')
    target = candidate_path(cache_root)
    if verified(target):
        receipt(stage='candidate', outcome='existing_verified', sha256=SHA256, sha1=SHA1, size=SIZE)
        return
    cache_root.mkdir(parents=True, exist_ok=True)
    # Outside modules cache; mismatch/failure never promotes partial bytes.
    with tempfile.TemporaryDirectory(prefix='compiler-seed-', dir=cache_root) as tmp:
        candidate = Path(tmp) / NAME
        download(candidate)
        if not verified(candidate):
            raise RuntimeError('Compiler size/SHA256/SHA1 mismatch; cache not populated')
        target.parent.mkdir(parents=True, exist_ok=True)
        os.replace(candidate, target)  # Same filesystem; no Gradle process may run yet.
    receipt(stage='candidate', outcome='seeded_verified', sha256=SHA256, sha1=SHA1, size=SIZE)


def main():
    try:
        seed(Path(__file__).resolve().parents[2],
             Path(os.environ.get('GRADLE_USER_HOME') or Path.home() / '.gradle').resolve())
    except (RuntimeError, OSError) as error:
        receipt(stage='failure', error=str(error) if isinstance(error, RuntimeError) else type(error).__name__)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
