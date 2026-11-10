"""HTTP acceptance for the one-time code and token revocation boundary."""

import base64
import hashlib
import re
import secrets
from datetime import timedelta
from urllib.parse import parse_qs, urlencode, urlsplit

from odoo import fields
from odoo.tests import HttpCase, tagged


@tagged('post_install', '-at_install')
class TestApporoRelayOAuth(HttpCase):
    def test_real_consent_uses_exact_callback_and_pkce(self):
        self.authenticate('admin', 'admin')
        verifier = secrets.token_urlsafe(32)
        challenge = base64.urlsafe_b64encode(
            hashlib.sha256(verifier.encode('ascii')).digest()
        ).rstrip(b'=').decode('ascii')
        params = {
            'response_type': 'code',
            'client_id': 'apporo-assistant-relay',
            'redirect_uri': 'https://assistant-relay.apporo.ai/auth/callback',
            'scope': 'relay:identity',
            'state': secrets.token_urlsafe(32),
            'code_challenge_method': 'S256',
            'code_challenge': challenge,
        }
        consent = self.url_open('/oauth2/authorize?' + urlencode(params), allow_redirects=False)
        self.assertEqual(consent.status_code, 200)
        self.assertIn('Allow Apporo Assistant remote access?', consent.text)
        self.assertIn(
            "form-action 'self' https://assistant-relay.apporo.ai;",
            consent.headers['Content-Security-Policy'],
        )
        csrf = re.search(r'name="csrf_token" value="([^"]+)"', consent.text)
        self.assertIsNotNone(csrf)

        approved = self.url_open('/oauth2/authorize', data={
            **params, 'csrf_token': csrf.group(1), 'decision': 'approve',
        }, allow_redirects=False)
        self.assertIn(approved.status_code, (302, 303))
        self.assertIn(
            "form-action 'self' https://assistant-relay.apporo.ai;",
            approved.headers['Content-Security-Policy'],
        )
        callback = urlsplit(approved.headers['Location'])
        self.assertEqual(callback.scheme + '://' + callback.netloc + callback.path, params['redirect_uri'])
        query = parse_qs(callback.query)
        self.assertEqual(query['state'], [params['state']])
        self.assertEqual(len(query['code'][0]), 43)

        token = self.url_open('/oauth2/token', data={
            'grant_type': 'authorization_code',
            'client_id': params['client_id'],
            'redirect_uri': params['redirect_uri'],
            'code': query['code'][0],
            'code_verifier': verifier,
        })
        self.assertEqual(token.status_code, 200)
        self.assertEqual(token.json()['scope'], 'relay:identity')

        denied = self.url_open('/oauth2/authorize', data={
            **params, 'state': secrets.token_urlsafe(32),
            'csrf_token': csrf.group(1), 'decision': 'deny',
        }, allow_redirects=False)
        self.assertIn(denied.status_code, (302, 303))
        self.assertEqual(parse_qs(urlsplit(denied.headers['Location']).query)['error'], ['access_denied'])

    def test_code_is_single_use_and_token_can_be_revoked(self):
        verifier = secrets.token_urlsafe(32)
        code = secrets.token_urlsafe(32)
        challenge = base64.urlsafe_b64encode(
            hashlib.sha256(verifier.encode('ascii')).digest()
        ).rstrip(b'=').decode('ascii')
        record = self.env['apporo.relay.oauth.code'].sudo().create({
            'code_hash': hashlib.sha256(code.encode('ascii')).hexdigest(),
            'user_id': self.env.ref('base.user_admin').id,
            'code_challenge': challenge,
            'expires_at': fields.Datetime.now() + timedelta(minutes=10),
        })
        self.env.flush_all()  # HttpCase shares its test transaction with HTTP requests.
        base = {
            'grant_type': 'authorization_code',
            'client_id': 'apporo-assistant-relay',
            'redirect_uri': 'https://assistant-relay.apporo.ai/auth/callback',
            'code': code,
        }

        wrong = self.url_open('/oauth2/token', data={**base, 'code_verifier': secrets.token_urlsafe(32)})
        self.assertEqual(wrong.status_code, 400)
        self.assertEqual(wrong.json()['error'], 'invalid_grant')

        accepted = self.url_open('/oauth2/token', data={**base, 'code_verifier': verifier})
        self.assertEqual(accepted.status_code, 200)
        access_token = accepted.json()['access_token']
        self.assertEqual(len(access_token), 43)

        replay = self.url_open('/oauth2/token', data={**base, 'code_verifier': verifier})
        self.assertEqual(replay.status_code, 400)
        self.assertEqual(replay.json()['error'], 'invalid_grant')

        form = {'client_id': 'apporo-assistant-relay', 'token': access_token}
        active = self.url_open('/oauth2/introspect', data=form)
        self.assertEqual(active.status_code, 200)
        self.assertEqual(active.json()['sub'], str(self.env.ref('base.user_admin').id))
        self.assertTrue(active.json()['active'])

        revoked = self.url_open('/oauth2/revoke', data=form)
        self.assertEqual(revoked.status_code, 200)
        inactive = self.url_open('/oauth2/introspect', data=form)
        self.assertEqual(inactive.status_code, 200)
        self.assertFalse(inactive.json()['active'])
