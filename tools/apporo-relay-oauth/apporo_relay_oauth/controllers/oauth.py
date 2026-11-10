"""A deliberately narrow OAuth provider for one Apporo relay client.

The relay receives a short-lived identity token, never the Odoo password or
session cookie. Phone pairing and MCP authorization are separate credentials.
"""

import base64
import hashlib
import html
import json
import re
import secrets
from datetime import datetime, timedelta, timezone
from urllib.parse import urlencode

from odoo import fields, http
from odoo.http import request


CLIENT_ID = 'apporo-assistant-relay'
CALLBACK = 'https://assistant-relay.apporo.ai/auth/callback'
SCOPE = 'relay:identity'
STATE = re.compile(r'[A-Za-z0-9_-]{32,128}\Z')
CHALLENGE = re.compile(r'[A-Za-z0-9_-]{43}\Z')
VERIFIER = re.compile(r'[A-Za-z0-9_-]{43,128}\Z')
CODE = re.compile(r'[A-Za-z0-9_-]{43}\Z')
CODE_LIFETIME = timedelta(minutes=10)
TOKEN_LIFETIME = timedelta(hours=1)


def _digest(value):
    return hashlib.sha256(value.encode('ascii')).hexdigest()


def _challenge(verifier):
    raw = hashlib.sha256(verifier.encode('ascii')).digest()
    return base64.urlsafe_b64encode(raw).rstrip(b'=').decode('ascii')


def _headers():
    return [
        ('Cache-Control', 'no-store'),
        ('Pragma', 'no-cache'),
        ('X-Content-Type-Options', 'nosniff'),
        ('Referrer-Policy', 'no-referrer'),
        ('Content-Security-Policy', "default-src 'none'; style-src 'unsafe-inline'; form-action 'self'; frame-ancestors 'none'; base-uri 'none'"),
    ]


def _page(title, body, status=200):
    title = html.escape(title)
    document = f'''<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>{title} · Apporo</title><style>:root{{--bg:#f7f7f5;--ink:#1c1c1e;--muted:#555;--gold:#9d7938;--card:#fff}}*{{box-sizing:border-box}}body{{background:var(--bg);color:var(--ink);font:16px/1.6 system-ui,sans-serif;margin:0}}main{{max-width:580px;margin:6vh auto;padding:24px}}.brand{{letter-spacing:.15em;color:var(--gold);font-weight:800}}.card{{background:var(--card);border:1px solid #e8e3d8;border-radius:18px;padding:24px;margin-top:24px}}h1{{line-height:1.15}}p{{color:var(--muted)}}.actions{{display:flex;flex-wrap:wrap;gap:12px}}button{{border:0;border-radius:10px;padding:12px 20px;background:var(--gold);color:white;font:600 16px system-ui,sans-serif;cursor:pointer}}button.secondary{{background:#e8e3d8;color:var(--ink)}}:focus-visible{{outline:3px solid var(--gold);outline-offset:3px}}@media(prefers-color-scheme:dark){{:root{{--bg:#1c1c1e;--ink:#f5f5f3;--muted:#bbb;--gold:#c5a15c;--card:#252527}}}}</style></head><body><main><div class="brand">APPORO</div><div class="card">{body}</div></main></body></html>'''
    return http.Response(document, status=status, content_type='text/html; charset=utf-8', headers=_headers())


def _json(data, status=200):
    return http.Response(json.dumps(data), status=status, content_type='application/json', headers=_headers())


def _parameters(value):
    return (
        value.get('response_type') == 'code'
        and value.get('client_id') == CLIENT_ID
        and value.get('redirect_uri') == CALLBACK
        and value.get('scope') == SCOPE
        and isinstance(value.get('state'), str)
        and bool(STATE.fullmatch(value['state']))
        and value.get('code_challenge_method') == 'S256'
        and isinstance(value.get('code_challenge'), str)
        and bool(CHALLENGE.fullmatch(value['code_challenge']))
    )


def _callback(**params):
    # CALLBACK is fixed, so no caller-controlled redirect destination exists.
    return request.redirect(CALLBACK + '?' + urlencode(params), local=False)


def _form():
    if request.httprequest.headers.get('Origin'):
        return None, _json({'error': 'invalid_request'}, 403)
    if request.httprequest.content_length and request.httprequest.content_length > 4096:
        return None, _json({'error': 'invalid_request'}, 413)
    if request.httprequest.mimetype != 'application/x-www-form-urlencoded':
        return None, _json({'error': 'invalid_request'}, 415)
    return request.httprequest.form, None


class ApporoRelayOAuth(http.Controller):
    @http.route('/oauth2/authorize', type='http', auth='user', methods=['GET'], website=False)
    def authorize_get(self, **params):
        if not _parameters(params):
            return _page('Invalid request', '<h1>Unable to authorize</h1><p>The relay request is invalid. Start again from the Apporo Assistant relay website.</p>', 400)
        user = request.env.user
        if not user.active:
            return _page('Account unavailable', '<h1>Account unavailable</h1><p>This account cannot authorize the relay.</p>', 403)
        hidden = ''.join(
            f'<input type="hidden" name="{name}" value="{html.escape(params[name], quote=True)}">'
            for name in ('response_type', 'client_id', 'redirect_uri', 'scope', 'state', 'code_challenge', 'code_challenge_method')
        )
        csrf = html.escape(request.csrf_token(), quote=True)
        name = html.escape(user.name or 'Apporo user')
        body = f'''<h1>Allow Apporo Assistant remote access?</h1><p>Signed in as {name}.</p><p>This lets the Apporo relay confirm your account identity and keep your phone connection separate from other users. It does not grant access to your Odoo records. Pairing a phone and authorizing a computer are separate steps.</p><form action="/oauth2/authorize" method="post"><input type="hidden" name="csrf_token" value="{csrf}">{hidden}<div class="actions"><button name="decision" value="approve">Allow</button><button class="secondary" name="decision" value="deny">Cancel</button></div></form>'''
        return _page('Authorize relay', body)

    @http.route('/oauth2/authorize', type='http', auth='user', methods=['POST'], website=False, csrf=True)
    def authorize_post(self, **params):
        if not _parameters(params):
            return _page('Invalid request', '<h1>Unable to authorize</h1><p>The relay request is invalid. Start again from the relay website.</p>', 400)
        if params.get('decision') == 'deny':
            return _callback(error='access_denied', state=params['state'])
        if params.get('decision') != 'approve' or not request.env.user.active:
            return _page('Invalid request', '<h1>Unable to authorize</h1>', 400)
        code = secrets.token_urlsafe(32)
        request.env['apporo.relay.oauth.code'].sudo().create({
            'code_hash': _digest(code),
            'user_id': request.env.user.id,
            'code_challenge': params['code_challenge'],
            'expires_at': fields.Datetime.now() + CODE_LIFETIME,
        })
        return _callback(code=code, state=params['state'])

    @http.route('/oauth2/token', type='http', auth='public', methods=['POST'], csrf=False, save_session=False)
    def token(self, **_kwargs):
        form, error = _form()
        if error:
            return error
        if (form.get('grant_type') != 'authorization_code' or form.get('client_id') != CLIENT_ID
                or form.get('redirect_uri') != CALLBACK or not CODE.fullmatch(form.get('code', ''))
                or not VERIFIER.fullmatch(form.get('code_verifier', ''))):
            return _json({'error': 'invalid_request'}, 400)
        code_hash = _digest(form['code'])
        request.env.cr.execute(
            'SELECT id, user_id, code_challenge, expires_at, is_used '
            'FROM apporo_relay_oauth_code WHERE code_hash = %s FOR UPDATE', (code_hash,)
        )
        row = request.env.cr.fetchone()
        if not row:
            return _json({'error': 'invalid_grant'}, 400)
        code_id, user_id, challenge, expires_at, is_used = row
        if (is_used or expires_at <= fields.Datetime.now()
                or not secrets.compare_digest(_challenge(form['code_verifier']), challenge)):
            return _json({'error': 'invalid_grant'}, 400)
        user = request.env['res.users'].sudo().browse(user_id)
        if not user.exists() or not user.active:
            return _json({'error': 'invalid_grant'}, 400)
        request.env.cr.execute('UPDATE apporo_relay_oauth_code SET is_used = true WHERE id = %s', (code_id,))
        access_token = secrets.token_urlsafe(32)
        request.env['apporo.relay.oauth.token'].sudo().create({
            'token_hash': _digest(access_token),
            'user_id': user_id,
            'expires_at': fields.Datetime.now() + TOKEN_LIFETIME,
        })
        return _json({'access_token': access_token, 'token_type': 'Bearer', 'expires_in': 3600, 'scope': SCOPE})

    @http.route('/oauth2/introspect', type='http', auth='public', methods=['POST'], csrf=False, save_session=False)
    def introspect(self, **_kwargs):
        form, error = _form()
        if error:
            return error
        token = form.get('token', '')
        if form.get('client_id') != CLIENT_ID or not CODE.fullmatch(token):
            return _json({'active': False})
        row = request.env['apporo.relay.oauth.token'].sudo().search([('token_hash', '=', _digest(token))], limit=1)
        if not row or row.is_revoked or row.expires_at <= fields.Datetime.now() or not row.user_id.active:
            return _json({'active': False})
        expires = row.expires_at.replace(tzinfo=timezone.utc)
        return _json({'active': True, 'sub': str(row.user_id.id), 'client_id': CLIENT_ID,
                      'scope': SCOPE, 'exp': int(expires.timestamp())})

    @http.route('/oauth2/revoke', type='http', auth='public', methods=['POST'], csrf=False, save_session=False)
    def revoke(self, **_kwargs):
        form, error = _form()
        if error:
            return error
        if form.get('client_id') != CLIENT_ID:
            return _json({'error': 'invalid_client'}, 400)
        token = form.get('token', '')
        if CODE.fullmatch(token):
            row = request.env['apporo.relay.oauth.token'].sudo().search([('token_hash', '=', _digest(token))], limit=1)
            if row:
                row.write({'is_revoked': True})
        return _json({})
