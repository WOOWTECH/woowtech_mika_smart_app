"""HTTP acceptance for the one-time code and token revocation boundary.

Since 18.0.1.2.0 (stage B) every endpoint is served only on the relay path;
the bare /oauth2/* paths belong to the WOOW PaaS platform module.
"""

import base64
import hashlib
import re
import secrets
from datetime import timedelta
from urllib.parse import parse_qs, urlencode, urlsplit

from odoo import fields
from odoo.tests import HttpCase, tagged


RELAY = '/apporo-relay/oauth2'
CLIENT_ID = 'apporo-assistant-relay'
CALLBACK = 'https://assistant-relay.apporo.ai/auth/callback'


def _pkce():
    verifier = secrets.token_urlsafe(32)
    challenge = base64.urlsafe_b64encode(
        hashlib.sha256(verifier.encode('ascii')).digest()
    ).rstrip(b'=').decode('ascii')
    return verifier, challenge


@tagged('post_install', '-at_install')
class TestApporoRelayOAuth(HttpCase):
    def _assert_consent_flow(self, prefix):
        self.authenticate('admin', 'admin')
        verifier, challenge = _pkce()
        params = {
            'response_type': 'code',
            'client_id': CLIENT_ID,
            'redirect_uri': CALLBACK,
            'scope': 'relay:identity',
            'state': secrets.token_urlsafe(32),
            'code_challenge_method': 'S256',
            'code_challenge': challenge,
        }
        consent = self.url_open(prefix + '/authorize?' + urlencode(params), allow_redirects=False)
        self.assertEqual(consent.status_code, 200)
        self.assertIn('Allow Apporo Assistant remote access?', consent.text)
        # Chromium applies the consent page's form-action to the POST and to
        # its redirect to the Worker callback, so this page must allow both.
        self.assertIn(
            "form-action 'self' https://assistant-relay.apporo.ai;",
            consent.headers['Content-Security-Policy'],
        )
        self.assertIn('<form action="/apporo-relay/oauth2/authorize" method="post">', consent.text)
        csrf = re.search(r'name="csrf_token" value="([^"]+)"', consent.text)
        self.assertIsNotNone(csrf)

        # No CSRF token, no authorization code.
        forged = self.url_open(prefix + '/authorize', data={**params, 'decision': 'approve'}, allow_redirects=False)
        self.assertEqual(forged.status_code, 400)
        self.assertNotIn('Location', forged.headers)

        approved = self.url_open(prefix + '/authorize', data={
            **params, 'csrf_token': csrf.group(1), 'decision': 'approve',
        }, allow_redirects=False)
        self.assertIn(approved.status_code, (302, 303))
        callback = urlsplit(approved.headers['Location'])
        self.assertEqual(callback.scheme + '://' + callback.netloc + callback.path, params['redirect_uri'])
        query = parse_qs(callback.query)
        self.assertEqual(query['state'], [params['state']])
        self.assertEqual(len(query['code'][0]), 43)

        token = self.url_open(prefix + '/token', data={
            'grant_type': 'authorization_code',
            'client_id': params['client_id'],
            'redirect_uri': params['redirect_uri'],
            'code': query['code'][0],
            'code_verifier': verifier,
        })
        self.assertEqual(token.status_code, 200)
        self.assertEqual(token.json()['scope'], 'relay:identity')

        denied = self.url_open(prefix + '/authorize', data={
            **params, 'state': secrets.token_urlsafe(32),
            'csrf_token': csrf.group(1), 'decision': 'deny',
        }, allow_redirects=False)
        self.assertIn(denied.status_code, (302, 303))
        self.assertEqual(parse_qs(urlsplit(denied.headers['Location']).query)['error'], ['access_denied'])

    def _assert_code_and_token_lifecycle(self, token_prefix, check_prefix):
        verifier, challenge = _pkce()
        code = secrets.token_urlsafe(32)
        self.env['apporo.relay.oauth.code'].sudo().create({
            'code_hash': hashlib.sha256(code.encode('ascii')).hexdigest(),
            'user_id': self.env.ref('base.user_admin').id,
            'code_challenge': challenge,
            'expires_at': fields.Datetime.now() + timedelta(minutes=10),
        })
        self.env.flush_all()  # HttpCase shares its test transaction with HTTP requests.
        base = {
            'grant_type': 'authorization_code',
            'client_id': CLIENT_ID,
            'redirect_uri': CALLBACK,
            'code': code,
        }

        wrong = self.url_open(token_prefix + '/token', data={**base, 'code_verifier': secrets.token_urlsafe(32)})
        self.assertEqual(wrong.status_code, 400)
        self.assertEqual(wrong.json()['error'], 'invalid_grant')

        accepted = self.url_open(token_prefix + '/token', data={**base, 'code_verifier': verifier})
        self.assertEqual(accepted.status_code, 200)
        access_token = accepted.json()['access_token']
        self.assertEqual(len(access_token), 43)

        replay = self.url_open(token_prefix + '/token', data={**base, 'code_verifier': verifier})
        self.assertEqual(replay.status_code, 400)
        self.assertEqual(replay.json()['error'], 'invalid_grant')

        form = {'client_id': CLIENT_ID, 'token': access_token}
        active = self.url_open(check_prefix + '/introspect', data=form)
        self.assertEqual(active.status_code, 200)
        self.assertEqual(active.json()['sub'], str(self.env.ref('base.user_admin').id))
        self.assertTrue(active.json()['active'])

        revoked = self.url_open(check_prefix + '/revoke', data=form)
        self.assertEqual(revoked.status_code, 200)
        inactive = self.url_open(check_prefix + '/introspect', data=form)
        self.assertEqual(inactive.status_code, 200)
        self.assertFalse(inactive.json()['active'])

    def test_real_consent_uses_exact_callback_and_pkce(self):
        self._assert_consent_flow(RELAY)

    def test_code_is_single_use_and_token_can_be_revoked(self):
        self._assert_code_and_token_lifecycle(RELAY, RELAY)
