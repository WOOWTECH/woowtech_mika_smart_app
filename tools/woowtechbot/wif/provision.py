#!/usr/bin/env python3
"""Provision/verify the explicitly selected test WIF identity. No sender keys or tokens.
Run in an authenticated gcloud environment. Default is read-only; --apply adds resources/bindings.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

PROJECT = 'woowtech-assistant'
NUMBER = '795023111689'
POOL = 'paas-k3s-test'
PROVIDER = 'cluster1'
SA_ID = 'woowtech-assistant-fcm-test'
SA = f'{SA_ID}@{PROJECT}.iam.gserviceaccount.com'
SUBJECT = 'system:serviceaccount:woowtech-assistant-push-test:fcm-relay'
UID = 'cdac85ad-b7c6-4bf6-ab7e-c47e6e1b199b'
ISSUER = 'https://kubernetes.default.svc.cluster.local'
CONDITION = f"assertion.sub == '{SUBJECT}' && assertion['kubernetes.io']['serviceaccount']['uid'] == '{UID}'"
PRINCIPAL = f'principal://iam.googleapis.com/projects/{NUMBER}/locations/global/workloadIdentityPools/{POOL}/subject/{SUBJECT}'
JWKS = Path(__file__).with_name('cluster1-public-jwks.json')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--apply', action='store_true')
    parser.add_argument('--gcloud', default='gcloud')
    args = parser.parse_args()

    def cloud(*parts):
        output = subprocess.check_output([args.gcloud, *parts, '--project='+PROJECT, '--format=json', '--quiet'], text=True)
        return json.loads(output) if output.strip() else None

    def require(condition, message):
        if not condition:
            raise RuntimeError(message)

    canonical = json.dumps(json.loads(JWKS.read_text()), sort_keys=True, separators=(',', ':')).encode()
    require(hashlib.sha256(canonical).hexdigest() == '364c000c6630ea7ff5c9d8425b812754dc4412bef9973f6dcac9e4a6f76fe7c8', 'JWKS checksum mismatch')
    require(str(cloud('projects', 'describe', PROJECT)['projectNumber']) == NUMBER, 'Project number mismatch')
    if args.apply:
        cloud('services', 'enable', 'iam.googleapis.com', 'cloudresourcemanager.googleapis.com',
              'iamcredentials.googleapis.com', 'sts.googleapis.com', 'fcm.googleapis.com')
        pools = cloud('iam', 'workload-identity-pools', 'list', '--location=global')
        if not any(x['name'].endswith('/'+POOL) for x in pools):
            cloud('iam', 'workload-identity-pools', 'create', POOL, '--location=global', '--display-name=WOOWTECH PaaS K3s test')
        providers = cloud('iam', 'workload-identity-pools', 'providers', 'list', '--location=global', '--workload-identity-pool='+POOL)
        if not any(x['name'].endswith('/'+PROVIDER) for x in providers):
            cloud('iam', 'workload-identity-pools', 'providers', 'create-oidc', PROVIDER,
                  '--location=global', '--workload-identity-pool='+POOL, '--issuer-uri='+ISSUER,
                  '--attribute-mapping=google.subject=assertion.sub', '--attribute-condition='+CONDITION,
                  '--jwk-json-path='+str(JWKS))
        accounts = cloud('iam', 'service-accounts', 'list')
        if not any(x['email'] == SA for x in accounts):
            cloud('iam', 'service-accounts', 'create', SA_ID, '--display-name=WOOWTECH Assistant FCM test')

    pool = cloud('iam', 'workload-identity-pools', 'describe', POOL, '--location=global')
    provider = cloud('iam', 'workload-identity-pools', 'providers', 'describe', PROVIDER,
                     '--location=global', '--workload-identity-pool='+POOL)
    require(pool['state'] == 'ACTIVE' and not pool.get('disabled'), 'Pool inactive')
    require(provider['state'] == 'ACTIVE' and not provider.get('disabled'), 'Provider inactive')
    require(provider.get('attributeMapping') == {'google.subject': 'assertion.sub'}, 'Unexpected mapping')
    require(provider.get('attributeCondition') == CONDITION, 'Unexpected subject/UID condition; do not broaden')
    require(provider['oidc']['issuerUri'] == ISSUER and not provider['oidc'].get('allowedAudiences'), 'Unexpected issuer/audience')
    require(json.loads(provider['oidc']['jwksJson']) == json.loads(canonical), 'Provider JWKS differs')
    account = cloud('iam', 'service-accounts', 'describe', SA)
    require(not account.get('disabled'), 'Service account disabled')
    if args.apply:
        cloud('projects', 'add-iam-policy-binding', PROJECT, '--member=serviceAccount:'+SA,
              '--role=roles/firebasecloudmessaging.admin', '--condition=None')
        cloud('iam', 'service-accounts', 'add-iam-policy-binding', SA, '--member='+PRINCIPAL,
              '--role=roles/iam.workloadIdentityUser', '--condition=None')
    project_policy = cloud('projects', 'get-iam-policy', PROJECT)
    roles = {b['role'] for b in project_policy.get('bindings', []) if 'serviceAccount:'+SA in b['members']}
    require(roles == {'roles/firebasecloudmessaging.admin'}, 'Unexpected project roles on test sender')
    sa_policy = cloud('iam', 'service-accounts', 'get-iam-policy', SA)
    bindings = sa_policy.get('bindings', [])
    require(len(bindings) == 1 and bindings[0]['role'] == 'roles/iam.workloadIdentityUser'
            and bindings[0]['members'] == [PRINCIPAL] and not bindings[0].get('condition'), 'Unexpected SA access bindings')
    keys = cloud('iam', 'service-accounts', 'keys', 'list', '--iam-account='+SA, '--managed-by=user')
    require(not keys, 'Test sender has user-managed keys; inspect before proceeding')
    print(json.dumps({'verified': True, 'projectNumber': NUMBER, 'serviceAccount': SA,
                      'audience': f'https://iam.googleapis.com/projects/{NUMBER}/locations/global/workloadIdentityPools/{POOL}/providers/{PROVIDER}',
                      'stsTested': False, 'fcmTested': False}, indent=2))


if __name__ == '__main__':
    main()
