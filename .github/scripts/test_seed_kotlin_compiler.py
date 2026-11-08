"""No network/Gradle; exercise verification, atomic promotion and real curl subprocess contract."""
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

spec = importlib.util.spec_from_file_location('seed', Path(__file__).with_name('seed-kotlin-compiler.py'))
s = importlib.util.module_from_spec(spec)
spec.loader.exec_module(s)


class CompilerSeedTest(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.root = Path(tmp.name)
        self.repo = self.root / 'repo'
        self.cache_root = self.root / 'cache'
        source = Path(__file__).resolve().parents[2]
        for relative in ['gradle/wrapper/gradle-wrapper.properties', 'gradle/libs.versions.toml']:
            dest = self.repo / relative
            dest.parent.mkdir(parents=True, exist_ok=True)
            dest.write_bytes((source / relative).read_bytes())
        env = patch.dict(os.environ, CI='true', GITHUB_ACTIONS='true')
        env.start()
        self.addCleanup(env.stop)

    def run_seed(self):
        with contextlib.redirect_stdout(io.StringIO()):
            s.seed(self.repo, self.cache_root)

    def payload(self):
        data = b'tiny deterministic compiler fixture'
        stack = contextlib.ExitStack()
        stack.enter_context(patch.object(s, 'SIZE', len(data)))
        stack.enter_context(patch.object(s, 'SHA256', hashlib.sha256(data).hexdigest()))
        stack.enter_context(patch.object(s, 'SHA1', hashlib.sha1(data).hexdigest()))
        self.addCleanup(stack.close)
        return data

    def test_fixed_gradle_candidate_path_and_leading_zero_rule(self):
        self.assertEqual(s.candidate_path(Path('/cache')).as_posix(),
                         '/cache/caches/modules-2/files-2.1/org.jetbrains.kotlin/kotlin-compiler-embeddable/2.1.20/4ef56b3316798316bfac7a0ae443391c9e900ea1/kotlin-compiler-embeddable-2.1.20.jar')
        with patch.object(s, 'SHA1', '001abc'):
            self.assertEqual(s.candidate_path(self.cache_root).parent.name, '1abc')

    def test_ci_guard_precedes_io(self):
        with patch.dict(os.environ, CI='false'), patch.object(s, 'download') as fetch:
            with self.assertRaisesRegex(RuntimeError, 'restricted'):
                self.run_seed()
            fetch.assert_not_called()
        self.assertFalse(self.cache_root.exists())

    def test_configuration_drift_fails_before_download(self):
        p = self.repo / 'gradle/libs.versions.toml'
        p.write_text(p.read_text().replace('2.1.20', '2.1.21'))
        with patch.object(s, 'download') as fetch:
            with self.assertRaisesRegex(RuntimeError, 'configuration'):
                self.run_seed()
            fetch.assert_not_called()
        self.assertFalse(self.cache_root.exists())

    def test_verified_promotion_then_existing_candidate_skips_network(self):
        data = self.payload()
        target = s.candidate_path(self.cache_root)
        def fetch(path):
            self.assertFalse(target.exists())
            self.assertNotIn('modules-2', path.parts)
            path.write_bytes(data)
        with patch.object(s, 'download', side_effect=fetch) as fetcher:
            self.run_seed()
            self.assertEqual(target.read_bytes(), data)
            self.run_seed()
            fetcher.assert_called_once()
        self.assertFalse(list(self.cache_root.glob('compiler-seed-*')))
        self.assertEqual(list(self.cache_root.rglob('*.jar')), [target])

    def test_same_size_bad_sha_never_promoted_or_overwrites_old_file(self):
        data = self.payload()
        target = s.candidate_path(self.cache_root)
        target.parent.mkdir(parents=True)
        target.write_bytes(b'old')
        with patch.object(s, 'download', side_effect=lambda p: p.write_bytes(b'x' * len(data))):
            with self.assertRaisesRegex(RuntimeError, 'mismatch'):
                self.run_seed()
        self.assertEqual(target.read_bytes(), b'old')
        self.assertFalse(list(self.cache_root.glob('compiler-seed-*')))

    def test_sha1_must_also_match(self):
        data = self.payload()
        p = self.root / 'candidate'
        p.write_bytes(data)
        with patch.object(s, 'SHA1', 'f' * 40):
            self.assertFalse(s.verified(p))

    def test_real_subprocess_504_sanitized_and_stops(self):
        # Fake only the curl executable; exercise actual argv, subprocess and failure propagation.
        bindir = self.root / 'bin'
        bindir.mkdir()
        curl = bindir / 'curl'
        curl.write_text('#!/usr/bin/env python3\nimport sys\nfrom pathlib import Path\na=sys.argv[1:]\nassert a[0]=="-q"\nassert "--retry" not in a\nassert a[a.index("--max-time")+1]=="150"\nassert a[-1].startswith("https://repo.maven.apache.org/")\nPath(a[a.index("--output")+1]).write_bytes(b"partial")\nsys.stderr.write("https://signed.invalid/?secret=HIDDEN")\nprint("504",end="")\nsys.exit(22)\n')
        curl.chmod(0o755)
        capture = io.StringIO()
        with patch.dict(os.environ, PATH=str(bindir)+os.pathsep+os.environ['PATH']), contextlib.redirect_stdout(capture):
            with self.assertRaisesRegex(RuntimeError, 'GET failed'):
                s.seed(self.repo, self.cache_root)
        self.assertIn('"http_status": "504"', capture.getvalue())
        self.assertNotIn('HIDDEN', capture.getvalue())
        self.assertFalse(s.candidate_path(self.cache_root).exists())
        self.assertFalse(list(self.cache_root.glob('compiler-seed-*')))

    def test_timeout_cleans_temp_and_stops(self):
        with patch.object(s.subprocess, 'run', side_effect=subprocess.TimeoutExpired('curl', 160)):
            with self.assertRaisesRegex(RuntimeError, 'exceeded160s'):
                self.run_seed()
        self.assertFalse(s.candidate_path(self.cache_root).exists())
        self.assertFalse(list(self.cache_root.glob('compiler-seed-*')))

    def test_non_status_stdout_never_printed(self):
        result = subprocess.CompletedProcess([], 22, b'https://secret.invalid/TOKEN', b'')
        capture = io.StringIO()
        with patch.object(s.subprocess, 'run', return_value=result), contextlib.redirect_stdout(capture):
            with self.assertRaises(RuntimeError):
                s.download(self.root / 'unused')
        self.assertIn('unknown', capture.getvalue())
        self.assertNotIn('TOKEN', capture.getvalue())


if __name__ == '__main__':
    unittest.main()
