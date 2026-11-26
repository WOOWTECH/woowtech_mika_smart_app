const result = (status, error, action, headers) => ({ status, body: { error }, action, ...(headers ? { headers } : {}) });
// Adapted from smart-notify.js: ambiguous FCM failures never revoke tokens.
export function classifyFirebaseError(error) {
  const code = error?.code;
  const message = typeof error?.message === 'string' ? error.message.trim() : '';
  if (['messaging/registration-token-not-registered', 'messaging/invalid-registration-token'].includes(code) ||
      (code === 'messaging/invalid-argument' && message === 'The registration token is not a valid FCM registration token')) return result(410, 'push_device_unregistered', 'revoke');
  // A wrong project is an operator/configuration issue here: keep the assistant registration.
  if (['messaging/mismatched-credential', 'messaging/third-party-auth-error', 'messaging/authentication-error', 'messaging/invalid-argument'].includes(code)) return result(502, 'push_unavailable', 'pause');
  if (['messaging/message-rate-exceeded', 'messaging/device-message-rate-exceeded', 'messaging/quota-exceeded'].includes(code)) return result(429, 'rate_limited', 'retry', { 'retry-after': '60' });
  return result(503, 'upstream_unavailable', 'retry');
}
