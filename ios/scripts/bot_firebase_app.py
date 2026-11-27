#!/usr/bin/env python3
"""Inspect/create only the dedicated Bot iOS Firebase app; never print credentials.

Uses gcloud's selected account (honors CLOUDSDK_CONFIG). Creation requires --apply.
Does not create projects, service account keys, APNs keys, or change Android apps.
"""
import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import plistlib
import subprocess
import time
import urllib.error
import urllib.request

PROJECT = 'woowtech-assistant'
NUMBER = '795023111689'
BUNDLE = 'io.woowtech.assistant.bot'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--apply', action='store_true')
    parser.add_argument('--gcloud', default='gcloud')
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    result = subprocess.run([args.gcloud, 'auth', 'print-access-token'], capture_output=True, text=True)
    if result.returncode or not result.stdout.strip():
        raise SystemExit('Google authentication unavailable. Sign in with gcloud first.')
    headers = {'Authorization': 'Bearer ' + result.stdout.strip(),
               'x-goog-user-project': PROJECT, 'Content-Type': 'application/json'}

    def request(path, body=None):
        req = urllib.request.Request('https://firebase.googleapis.com/v1beta1/' + path,
            headers=headers, data=json.dumps(body).encode() if body is not None else None)
        try:
            with urllib.request.urlopen(req, timeout=30) as response:
                return json.load(response)
        except urllib.error.HTTPError as error:
            raise RuntimeError(f'Firebase operation failed: HTTP {error.code}') from None

    project = request('projects/' + PROJECT)
    if str(project.get('projectNumber')) != NUMBER:
        raise SystemExit('Firebase project number mismatch.')
    parent = 'projects/' + PROJECT + '/iosApps'
    apps, page = [], None
    while True:
        data = request(parent + ('?pageToken=' + page if page else ''))
        apps.extend(data.get('apps', []))
        page = data.get('nextPageToken')
        if not page:
            break
    found = [app for app in apps if app.get('bundleId') == BUNDLE]
    created = False
    if not found and args.apply:
        operation = request(parent, {'displayName': 'WOOW Assistant Bot iOS', 'bundleId': BUNDLE})
        for _ in range(30):
            if operation.get('done'):
                break
            time.sleep(2)
            operation = request(operation['name'])
        if not operation.get('done') or operation.get('error'):
            raise SystemExit('Firebase app creation did not complete; inspect before retrying.')
        found = [operation['response']]
        created = True
    if len(found) != 1:
        raise SystemExit('Dedicated iOS app missing or ambiguous; use --apply to create when missing.')
    app = found[0]
    if app['bundleId'] != BUNDLE or app.get('state') != 'ACTIVE':
        raise SystemExit('Firebase app identity/state mismatch.')
    receipt = {'project': PROJECT, 'bundleId': BUNDLE, 'appId': app['appId'], 'created': created,
               'apnsConfigured': None, 'deliveryVerified': False}
    if args.output:
        data = request(app['name'] + '/config')
        contents = base64.b64decode(data['configFileContents'], validate=True)
        config = plistlib.loads(contents)
        expected = {'PROJECT_ID': PROJECT, 'BUNDLE_ID': BUNDLE,
                    'GCM_SENDER_ID': NUMBER, 'GOOGLE_APP_ID': app['appId']}
        if any(config.get(k) != v for k, v in expected.items()):
            raise SystemExit('Downloaded Firebase client configuration identity mismatch.')
        args.output.parent.mkdir(parents=True, exist_ok=True)
        temporary = args.output.with_suffix('.plist.tmp')
        fd = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(fd, 'wb') as stream:
            stream.write(contents)
        temporary.replace(args.output)
        receipt['configSHA256'] = hashlib.sha256(contents).hexdigest()
    print(json.dumps(receipt, indent=2))


if __name__ == '__main__':
    main()
