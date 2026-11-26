# WOOWTECH Assistant test sender WIF

This is the user-selected, keyless test identity for PaaS K3s cluster1.
`cluster1-public-jwks.json` is a public verification key supplied by the PaaS coordinator,
not a Google service-account private key.

From an authenticated Google Cloud CLI environment:

```sh
python3 tools/woowtechbot/wif/provision.py --apply
python3 tools/woowtechbot/wif/provision.py
```

Default is read-only verification. `--apply` enables the required APIs, creates missing
resources and adds the exact two IAM bindings. It never creates a service-account key,
changes billing, replaces a project policy, deploys a relay, sends FCM or accesses a phone token.
Existing provider drift fails verification rather than silently broadening its policy.
A custom CLI executable may be supplied with `--gcloud /path/to/gcloud`.

The configured principal is the exact KSA subject and its pinned UID. The provider uses
uploaded JWKS because its issuer is private. A recreated KSA or signing-key rotation needs
an explicit coordinated configuration update. On success, the script reports verified GCP
configuration only; the PaaS coordinator must still separately test STS, impersonation,
negative identity cases, and real FCM delivery.

Reference: https://docs.cloud.google.com/iam/docs/workload-identity-federation-with-kubernetes
