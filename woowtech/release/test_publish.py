import hashlib
import io
from pathlib import Path
import tempfile
import unittest
from unittest.mock import Mock, patch
import zipfile
from publish import successful_run, unpack_verified, version_from_sources, version_key, publish, Redirect, find_release
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
        gh.request.side_effect=lambda path: [] if path.startswith('/releases?') else {'object':{'sha':'abc'}}
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
        gh.request.side_effect=[{'object':{'sha':'abc'}},[],{'workflow_runs':[]}]
        publish(gh,Path('/unused'))
        self.assertEqual(3,gh.request.call_count)

    def test_check_mode_never_downloads_or_publishes(self):
        gh=self.gh();gh.optional.side_effect=[None,{'tag_name':'v0.1.37-woow.4'}]
        gh.request.side_effect=[{'object':{'sha':'abc'}},[],{'workflow_runs':[self.run_record()]},{'workflow_runs':[self.run_record()]}]
        publish(gh,Path('/unused'),check=True)
        self.assertEqual(4,gh.request.call_count)

class PublicationTest(unittest.TestCase):
    def exercise(self, fail_upload=False, advanced=False, existing_draft=False, starter=False):
        gh = Mock()
        sha = 'abc'
        events = []
        runs = dict(head_sha=sha, head_branch='main', event='push', run_number=1,
                    status='completed', conclusion='success', id=10)
        gh.source.side_effect = ['versionCode = 38\nversionName = "0.1.37"', 'val woowtechRevision = 5', 'notes']
        gh.optional.side_effect = [None, {'tag_name': 'v0.1.37-woow.4'}]
        draft = dict(id=11, tag_name='v0.1.37-woow.5', draft=True, target_commitish=sha, assets_url='/assets', upload_url='https://uploads.github.com/assets{?name}')
        heads = 0
        def request(path, body=None, method=None, **kw):
            nonlocal heads
            events.append((path, method))
            if path == '/git/ref/heads/main':
                heads += 1
                return {'object': {'sha': 'new' if advanced and heads > 1 else sha}}
            if path.startswith('/releases?'): return [draft] if existing_draft else []
            if path.startswith('/actions/workflows/'):
                return {'workflow_runs': [runs]}
            if path == '/releases':
                return draft
            if path == '/assets': return [dict(name='SHA256SUMS.txt', state='starter', id=99)] if starter else []
            if path == '/releases/assets/99' and method == 'DELETE': return None
            if path.startswith('https://uploads.github.com/'):
                if fail_upload: raise ValueError('simulated upload failure')
                return dict(size=len(body), digest='sha256:' + hashlib.sha256(body).hexdigest())
            if path == '/releases/11': return {}
            if path == '/releases/latest': return dict(tag_name='v0.1.37-woow.5', html_url='https://github.com/release')
            raise AssertionError(path)
        gh.request.side_effect = request
        def fake_artifact(gh, run, name, dest):
            dest.mkdir()
            if name.startswith('gpl'):
                (dest/'mika-0.1.37-woow.5-gpl-sources.tar.gz').write_bytes(b'x'*1_000_001)
        def fake_sign(source, out, version, code):
            for suffix in ('-arm64',''):
                (out/f'woowtech-agent-v{version}{suffix}.apk').write_bytes(b'signed')
        with tempfile.TemporaryDirectory() as tmp, patch('publish.artifact', side_effect=fake_artifact), patch('publish.sign_apks', side_effect=fake_sign):
            if fail_upload:
                with self.assertRaises(ValueError): publish(gh, Path(tmp))
            else: publish(gh, Path(tmp))
        return events

    def test_draft_tag_404_resumes_without_creating_duplicate_release(self):
        events=self.exercise(existing_draft=True)
        self.assertNotIn(('/releases',None),events)
        self.assertIn(('/releases/11','PATCH'),events)

    def test_orphaned_starter_asset_can_be_retried(self):
        events=self.exercise(existing_draft=True,starter=True)
        self.assertIn(('/releases/assets/99','DELETE'),events)
        self.assertIn(('/releases/11','PATCH'),events)

    def test_paginated_draft_lookup(self):
        gh=Mock();gh.optional.return_value=None
        draft={'tag_name':'v0.1.37-woow.5','draft':True}
        gh.request.side_effect=[[{'tag_name':'other'}]*100,[draft]]
        self.assertEqual(draft,find_release(gh,draft['tag_name']))
        self.assertEqual('/releases?per_page=100&page=2',gh.request.call_args.args[0])

    def test_complete_assets_before_publication(self):
        events=self.exercise()
        upload_indices=[i for i,(p,m) in enumerate(events) if p.startswith('https://uploads.github.com/')]
        self.assertEqual(4,len(upload_indices))
        self.assertGreater(events.index(('/releases/11','PATCH')),max(upload_indices))

    def test_upload_failure_stays_draft(self):
        self.assertNotIn(('/releases/11','PATCH'),self.exercise(fail_upload=True))

    def test_superseded_main_is_not_published(self):
        self.assertNotIn(('/releases',None),self.exercise(advanced=True))

if __name__=='__main__': unittest.main()
