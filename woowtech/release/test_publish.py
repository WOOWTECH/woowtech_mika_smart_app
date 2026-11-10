import hashlib
import io
from pathlib import Path
import tempfile
import unittest
from unittest.mock import Mock
import zipfile
from publish import successful_run, unpack_verified, version_from_sources, version_key, publish, Redirect
import urllib.request

class ReleaseTest(unittest.TestCase):
    def test_version_and_code(self):
        self.assertEqual(('0.1.37-woow.5', 3805), version_from_sources('versionCode = 38\nversionName = "0.1.37"', 'val woowtechRevision = 5'))
        for revision in (0, 100):
            with self.assertRaises(ValueError):
                version_from_sources('versionCode = 38\nversionName = "0.1.37"', f'val woowtechRevision = {revision}')

    def test_stable_order(self):
        self.assertGreater(version_key('v0.1.37-woow.10'), version_key('v0.1.37-woow.9'))
        self.assertGreater(version_key('v0.1.38-woow.1'), version_key('v0.1.37-woow.99'))
        for tag in ('v0.1.37-woow.4-browser.20261110', 'v0.1.37-apporo.7'):
            with self.assertRaises(ValueError): version_key(tag)

    def run_record(self, **kw):
        return dict(dict(head_sha='abc', head_branch='main', event='push', run_number=1,
                         run_attempt=1, status='completed', conclusion='success'), **kw)

    def test_ci_requires_exact_successful_main_push(self):
        self.assertIsNotNone(successful_run([self.run_record()], 'abc'))
        for kw in ({'head_sha':'other'}, {'head_branch':'feature'}, {'event':'pull_request'},
                   {'status':'in_progress'}, {'conclusion':'failure'}, {'conclusion':'cancelled'}, {'conclusion':'skipped'}):
            self.assertIsNone(successful_run([self.run_record(**kw)], 'abc'))
        self.assertIsNone(successful_run([], 'abc'))

    def test_failed_rerun_cannot_reuse_success(self):
        self.assertIsNone(successful_run([self.run_record(), self.run_record(run_attempt=2, conclusion='failure')], 'abc'))

    def zip_bytes(self, name='release/a.apk'):
        stream=io.BytesIO()
        with zipfile.ZipFile(stream,'w') as z: z.writestr(name,b'apk')
        return stream.getvalue()

    def test_verified_zip(self):
        data=self.zip_bytes()
        with tempfile.TemporaryDirectory() as tmp:
            dest=Path(tmp)/'out'
            unpack_verified(data,'sha256:'+hashlib.sha256(data).hexdigest(),dest)
            self.assertEqual(b'apk',(dest/'release/a.apk').read_bytes())

    def test_tampered_or_unverified_zip(self):
        data=self.zip_bytes()
        with tempfile.TemporaryDirectory() as tmp:
            for digest in (None,'sha256:wrong'):
                with self.assertRaises(ValueError): unpack_verified(data,digest,Path(tmp)/'out')

    def test_unsafe_zip(self):
        with tempfile.TemporaryDirectory() as tmp:
            for name in ('../escape.apk','/tmp/escape.apk'):
                data=self.zip_bytes(name)
                with self.assertRaises(ValueError): unpack_verified(data,'sha256:'+hashlib.sha256(data).hexdigest(),Path(tmp)/'out')

    def test_redirect_never_leaks_token(self):
        req=urllib.request.Request('https://api.github.com/file',headers={'Authorization':'secret'})
        redirect=Redirect().redirect_request(req,None,302,'',{},'https://example.com/download')
        self.assertFalse(redirect.has_header('Authorization'))

    def gh(self):
        gh=Mock()
        gh.source.side_effect=['versionCode = 38\nversionName = "0.1.37"','val woowtechRevision = 5']
        gh.request.return_value={'object':{'sha':'abc'}}
        return gh

    def test_published_version_is_idempotent(self):
        gh=self.gh();gh.optional.return_value={'draft':False}
        publish(gh,Path('/unused'))
        self.assertEqual(1,gh.request.call_count)

    def test_downgrade_rejected(self):
        gh=self.gh();gh.optional.side_effect=[None,{'tag_name':'v0.1.37-woow.6'}]
        with self.assertRaises(ValueError): publish(gh,Path('/unused'))

    def test_missing_ci_does_not_publish(self):
        gh=self.gh();gh.optional.side_effect=[None,{'tag_name':'v0.1.37-woow.4'}]
        gh.request.side_effect=[{'object':{'sha':'abc'}},{'workflow_runs':[]}]
        publish(gh,Path('/unused'))
        self.assertEqual(2,gh.request.call_count)

    def test_check_mode_never_downloads_or_publishes(self):
        gh=self.gh();gh.optional.side_effect=[None,{'tag_name':'v0.1.37-woow.4'}]
        gh.request.side_effect=[{'object':{'sha':'abc'}},{'workflow_runs':[self.run_record()]},{'workflow_runs':[self.run_record()]}]
        publish(gh,Path('/unused'),check=True)
        self.assertEqual(3,gh.request.call_count)

if __name__=='__main__': unittest.main()
