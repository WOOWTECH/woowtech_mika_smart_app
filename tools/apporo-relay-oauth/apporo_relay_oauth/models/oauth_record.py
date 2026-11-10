from odoo import fields, models


class RelayAuthorizationCode(models.Model):
    _name = 'apporo.relay.oauth.code'
    _description = 'Apporo relay one-time authorization code'
    _order = 'create_date desc'
    _log_access = True

    code_hash = fields.Char(required=True, index=True, copy=False)
    user_id = fields.Many2one('res.users', required=True, ondelete='cascade', index=True)
    code_challenge = fields.Char(required=True, copy=False)
    expires_at = fields.Datetime(required=True, index=True)
    is_used = fields.Boolean(default=False, copy=False)

    _sql_constraints = [
        ('code_hash_unique', 'unique(code_hash)', 'Authorization code hashes must be unique.'),
    ]

    def _cleanup_expired(self):
        """Keep short-lived OAuth records from accumulating indefinitely."""
        now = fields.Datetime.now()
        self.sudo().search(['|', ('expires_at', '<', now), ('is_used', '=', True)]).unlink()
        self.env['apporo.relay.oauth.token'].sudo().search(
            ['|', ('expires_at', '<', now), ('is_revoked', '=', True)]
        ).unlink()


class RelayAccessToken(models.Model):
    _name = 'apporo.relay.oauth.token'
    _description = 'Apporo relay identity token'
    _order = 'create_date desc'
    _log_access = True

    token_hash = fields.Char(required=True, index=True, copy=False)
    user_id = fields.Many2one('res.users', required=True, ondelete='cascade', index=True)
    expires_at = fields.Datetime(required=True, index=True)
    is_revoked = fields.Boolean(default=False, copy=False)

    _sql_constraints = [
        ('token_hash_unique', 'unique(token_hash)', 'Identity token hashes must be unique.'),
    ]
