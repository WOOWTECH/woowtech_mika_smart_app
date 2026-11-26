#!/usr/bin/env python3
"""Convert the assistant's Firebase client JSON to external Gradle properties.
No credentials are printed. Output must remain outside this repository.
"""
import argparse
import json
import os
from pathlib import Path

PACKAGE = 'io.woowtech.agent'

def convert(document):
    project = document.get('project_info', {})
    clients = [c for c in document.get('client', [])
               if c.get('client_info', {}).get('android_client_info', {}).get('package_name') == PACKAGE]
    if len(clients) != 1:
        raise ValueError('Exactly one io.woowtech.agent client is required; other products cannot be used')
    client = clients[0]
    keys = client.get('api_key', [])
    if len(keys) != 1:
        raise ValueError('Exactly one client API key is required')
    result = {'applicationId': PACKAGE,
              'google_app_id': client.get('client_info', {}).get('mobilesdk_app_id'),
              'google_api_key': keys[0].get('current_key'),
              'gcm_defaultSenderId': project.get('project_number'),
              'project_id': project.get('project_id')}
    if any(not isinstance(v, str) or not v or any(c in v for c in '\r\n\\') for v in result.values()):
        raise ValueError('Invalid or missing Firebase client configuration')
    if not result['google_app_id'].startswith('1:' + result['gcm_defaultSenderId'] + ':android:'):
        raise ValueError('App ID does not match sender/project number')
    return ''.join(k+'='+v+'\n' for k,v in result.items())

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('google_services_json', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[2]
    output = args.output.resolve()
    if output.is_relative_to(repo):
        parser.error('Output must be outside the repository')
    text = convert(json.loads(args.google_services_json.read_text()))
    # Never overwrite an existing config silently.
    fd = os.open(output, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, 'w') as stream:
        stream.write(text)
    print('Validated assistant Firebase client configuration saved; set WOOWTECHBOT_FIREBASE_PROPERTIES to its path.')

if __name__ == '__main__':
    main()
