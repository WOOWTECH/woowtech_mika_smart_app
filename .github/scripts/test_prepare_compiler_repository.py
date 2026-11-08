"""Offline protocol/atomic-publication checks; no Gradle or real downloads."""
import contextlib
import hashlib
import importlib.util
import io
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('prepare', Path(__file__).with_name('prepare-compiler-repository.py'))
s = importlib.util.module_from_spec(spec)
spec.loader.exec_module(s)


class RepositoryTest(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.root = Path(tmp.name)
        self.repo = self.root / 'repo'
        self.runner_temp = self.root / 'runner'
        self.runner_temp.mkdir()
        self.env_file = self.root / 'github-env'
        self.env_file.touch()
        source = Path(__file__).resolve().parents[2]
        for relative in ['gradle/wrapper/gradle-wrapper.properties', 'gradle/libs.versions.toml']:
            target = self.repo / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes((source / relative).read_bytes())
        self.stack = contextlib.ExitStack()
        self.addCleanup(self.stack.close)
        self.stack.enter_context(patch.dict(os.environ, CI='true', GITHUB_ACTIONS='true',
                                          RUNNER_TEMP=str(self.runner_temp), GITHUB_ENV=str(self.env_file)))
        self.data = {s.NAME: b'fixture compiler', s.POM_NAME: b'<project>unchanged fixture dependencies</project>'}
        for key, value in [('SIZE', len(self.data[s.NAME])), ('SHA256', hashlib.sha256(self.data[s.NAME]).hexdigest()),
                           ('SHA1', hashlib.sha1(self.data[s.NAME]).hexdigest()), ('POM_SIZE', len(self.data[s.POM_NAME])),
                           ('POM_SHA256', hashlib.sha256(self.data[s.POM_NAME]).hexdigest())]:
            self.stack.enter_context(patch.object(s, key, value))

    def fetch(self, target, url, api=False):
        self.assertEqual(self.env_file.read_text(), '')
        self.assertFalse(list(self.runner_temp.glob('*/repository')))
        self.assertEqual(url, s.API_URL if api else s.POM_URL)
        target.write_bytes(self.data[target.name])

    def run_prepare(self):
        with contextlib.redirect_stdout(io.StringIO()):
            return s.prepare(self.repo)

    def test_only_verified_pair_published_and_each_invocation_private(self):
        with patch.object(s, 'download', side_effect=self.fetch) as fetch:
            first = self.run_prepare()
            self.assertEqual(fetch.call_count, 2)
        self.assertEqual(self.env_file.read_text(), 'CI_VERIFIED_COMPILER_REPO='+str(first)+'\n')
        self.assertEqual((first.parent.stat().st_mode & 0o777), 0o700)
        for name, data in self.data.items():self.assertEqual((first / s.MODULE_PATH / name).read_bytes(), data)
        self.env_file.write_text('')
        # Separate invocations/jobs do not share or mutate an earlier private repo.
        with patch.object(s, 'download', side_effect=lambda p,u,api=False:p.write_bytes(self.data[p.name])):
            second = self.run_prepare()
        self.assertNotEqual(first, second)
        self.assertEqual(len([p for p in first.rglob('*') if p.is_file()]), 2)

    def test_failed_pom_or_checksum_never_enables_repo(self):
        for failure in ['network', 'digest']:
            def fetch(target, url, api=False):
                if not api:
                    if failure == 'network':raise RuntimeError('offline')
                    target.write_bytes(b'x' * s.POM_SIZE)
                else:self.fetch(target,url,api)
            with patch.object(s, 'download', side_effect=fetch), self.assertRaises(RuntimeError):self.run_prepare()
            self.assertEqual(self.env_file.read_text(), '')
            self.assertEqual(list(self.runner_temp.iterdir()), [])

    def test_bad_jar_stops_before_pom(self):
        with patch.object(s, 'download', side_effect=lambda p,u,api=False:p.write_bytes(b'x'*s.SIZE)) as fetch:
            with self.assertRaisesRegex(RuntimeError, 'JAR'):self.run_prepare()
            fetch.assert_called_once()
        self.assertEqual(list(self.runner_temp.iterdir()), [])
        self.assertEqual(self.env_file.read_text(), '')

    def test_guard_and_version_drift_before_network(self):
        for variable in ['CI', 'GITHUB_ACTIONS']:
            with patch.dict(os.environ, {variable:'false'}), patch.object(s,'download') as fetch:
                with self.assertRaisesRegex(RuntimeError,'CI'):self.run_prepare()
                fetch.assert_not_called()
        for relative, old, new in [('gradle/libs.versions.toml','2.1.20','2.1.21'),
                                   ('gradle/wrapper/gradle-wrapper.properties','8.11.1','8.12')]:
            p=self.repo/relative;original=p.read_text();p.write_text(original.replace(old,new))
            with patch.object(s,'download') as fetch:
                with self.assertRaisesRegex(RuntimeError,'configuration'):self.run_prepare()
                fetch.assert_not_called()
            p.write_text(original)

    def test_timeout_cleans_private_directory(self):
        with patch.object(s.subprocess,'run',side_effect=subprocess.TimeoutExpired('curl',160)):
            with self.assertRaisesRegex(RuntimeError,'exceeded160s'):self.run_prepare()
        self.assertEqual(list(self.runner_temp.iterdir()), [])
        self.assertEqual(self.env_file.read_text(), '')

    def test_missing_runner_environment_rejected(self):
        with patch.dict(os.environ,RUNNER_TEMP=''),patch.object(s,'download') as fetch:
            with self.assertRaisesRegex(RuntimeError,'required'):self.run_prepare()
            fetch.assert_not_called()

    def test_real_curl_subprocess_api_headers_and_504_privacy(self):
        bindir=self.root/'bin';bindir.mkdir();curl=bindir/'curl'
        curl.write_text('#!/usr/bin/env python3\nimport sys\na=sys.argv[1:]\nassert a[0]=="-q"\nassert "Accept: application/octet-stream" in a\nassert "--retry" not in a\nassert a[-1]=="https://api.github.com/repos/JetBrains/kotlin/releases/assets/598635327"\nsys.stderr.write("https://signed.invalid/?SECRET")\nprint("504",end="")\nsys.exit(22)\n')
        curl.chmod(0o755);out=io.StringIO()
        with patch.dict(os.environ,PATH=str(bindir)+os.pathsep+os.environ['PATH']),contextlib.redirect_stdout(out):
            with self.assertRaisesRegex(RuntimeError,'GET failed'):s.prepare(self.repo)
        self.assertIn('"http_status": "504"',out.getvalue());self.assertNotIn('SECRET',out.getvalue())
        self.assertEqual(self.env_file.read_text(),'');self.assertEqual(list(self.runner_temp.iterdir()),[])

    def test_bad_status_not_exposed(self):
        result=subprocess.CompletedProcess([],22,b'https://signed.invalid/SECRET',b'')
        out=io.StringIO()
        with patch.object(s.subprocess,'run',return_value=result),contextlib.redirect_stdout(out):
            with self.assertRaises(RuntimeError):s.download(self.root/'unused',s.POM_URL)
        self.assertIn('unknown',out.getvalue());self.assertNotIn('SECRET',out.getvalue())


if __name__ == '__main__':unittest.main()
