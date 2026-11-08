"""No network/Gradle: exercise cache promotion and real downloader subprocess."""
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

spec = importlib.util.spec_from_file_location('bootstrap', Path(__file__).with_name('bootstrap-gradle.py'))
b = importlib.util.module_from_spec(spec)
spec.loader.exec_module(b)


class BootstrapTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.repo = self.root / 'repo'
        self.cache_root = self.root / 'gradle-cache'
        props = self.repo / 'gradle/wrapper/gradle-wrapper.properties'
        props.parent.mkdir(parents=True)
        original = Path(__file__).resolve().parents[2] / 'gradle/wrapper/gradle-wrapper.properties'
        props.write_bytes(original.read_bytes())
        self.env = patch.dict(os.environ, {'GITHUB_ACTIONS': 'true', 'CI': 'true'})
        self.env.start()
        self.addCleanup(self.env.stop)
        self.target = b.cache_zip(self.cache_root)

    def run_bootstrap(self):
        with contextlib.redirect_stdout(io.StringIO()):
            b.bootstrap(self.repo, self.cache_root)

    def test_official_pathassembler_vector(self):
        self.assertEqual(self.target.relative_to(self.cache_root).as_posix(),
                         'wrapper/dists/gradle-8.11.1-bin/bpt9gzteqjrbo1mjrsomdt32c/gradle-8.11.1-bin.zip')

    def test_ci_guard_precedes_writes_and_network(self):
        with patch.dict(os.environ, {'GITHUB_ACTIONS': 'false'}), patch.object(b, 'download') as fetch:
            with self.assertRaisesRegex(RuntimeError, 'restricted'):
                self.run_bootstrap()
            fetch.assert_not_called()
            self.assertFalse(self.cache_root.exists())

    def test_configuration_drift_fails_closed(self):
        props = self.repo / 'gradle/wrapper/gradle-wrapper.properties'
        props.write_text(props.read_text().replace(b.URL.replace(':', '\\:', 1), 'https://example.invalid/x.zip'))
        with patch.object(b, 'download') as fetch:
            with self.assertRaisesRegex(RuntimeError, 'configuration'):
                self.run_bootstrap()
            fetch.assert_not_called()

    def test_existing_wrapper_install_reused_but_marker_alone_is_not(self):
        lib = self.target.parent / 'gradle-8.11.1/lib'
        lib.mkdir(parents=True)
        self.target.with_suffix('.zip.ok').touch()
        with patch.object(b, 'download', side_effect=RuntimeError('offline')) as fetch:
            with self.assertRaisesRegex(RuntimeError, 'offline'):
                self.run_bootstrap()
            fetch.assert_called_once()
        (lib / 'gradle-launcher-8.11.1.jar').touch()
        self.target.with_suffix('.zip.ok').touch()
        with patch.object(b, 'download') as fetch:
            self.run_bootstrap()
            fetch.assert_not_called()

    def test_checksum_mismatch_never_enters_wrapper_cache(self):
        self.target.parent.mkdir(parents=True)
        self.target.write_bytes(b'stale partial')
        def fetch(path):
            self.assertFalse(self.target.exists())
            self.assertNotEqual(path.parent, self.target.parent)
            path.write_bytes(b'not the release')
        with patch.object(b, 'download', side_effect=fetch):
            with self.assertRaisesRegex(RuntimeError, 'size/SHA-256'):
                self.run_bootstrap()
        self.assertFalse(self.target.exists())
        self.assertFalse(list(self.cache_root.glob('gradle-bootstrap-*')))

    def test_same_size_wrong_digest_rejected(self):
        payload = b'wrong digest'
        with patch.object(b, 'SIZE', len(payload)), patch.object(b, 'download', side_effect=lambda path: path.write_bytes(payload)):
            with self.assertRaisesRegex(RuntimeError, 'size/SHA-256'):
                self.run_bootstrap()
        self.assertFalse(self.target.exists())

    def test_verified_download_promoted_and_zip_reused(self):
        payload = b'small deterministic stand-in for official release'
        def fetch(path):
            path.write_bytes(payload)
            self.assertFalse(self.target.exists())
        with patch.object(b, 'SIZE', len(payload)), patch.object(b, 'SHA256', hashlib.sha256(payload).hexdigest()), patch.object(b, 'check_properties'):
            with patch.object(b, 'download', side_effect=fetch):
                self.run_bootstrap()
            self.assertEqual(self.target.read_bytes(), payload)
            self.assertFalse(self.target.with_suffix('.zip.ok').exists())
            with patch.object(b, 'download') as fetch:
                self.run_bootstrap()
                fetch.assert_not_called()

    def test_real_subprocess_download_failure_is_bounded_and_sanitized(self):
        # Substitute only curl executable; execute the actual subprocess path.
        bin_dir = self.root / 'bin'
        bin_dir.mkdir()
        fake = bin_dir / 'curl'
        fake.write_text('#!/usr/bin/env python3\nimport sys\na=sys.argv[1:]\nassert a[0]=="-q"\nassert a[a.index("--max-time")+1]=="180"\nassert a[a.index("--retry")+1]=="1"\nassert "Accept: application/octet-stream" in a\nprint("504",end="")\nprint("https://release-assets.example/?secret=DO_NOT_LOG",file=sys.stderr)\nsys.exit(22)\n')
        fake.chmod(0o755)
        with patch.dict(os.environ, {'PATH': str(bin_dir) + os.pathsep + os.environ['PATH']}):
            with self.assertRaisesRegex(RuntimeError, 'curl exit 22') as raised:
                self.run_bootstrap()
        self.assertIn('HTTP 504', str(raised.exception))
        self.assertNotIn('DO_NOT_LOG', str(raised.exception))
        self.assertFalse(self.target.exists())
        self.assertFalse(list(self.cache_root.glob('gradle-bootstrap-*')))

    def test_subprocess_timeout_cleans_candidate(self):
        with patch.object(b.subprocess, 'run', side_effect=subprocess.TimeoutExpired('curl', 375)):
            with self.assertRaisesRegex(RuntimeError, '375s'):
                self.run_bootstrap()
        self.assertFalse(self.target.exists())
        self.assertFalse(list(self.cache_root.glob('gradle-bootstrap-*')))


if __name__ == '__main__':
    unittest.main()
