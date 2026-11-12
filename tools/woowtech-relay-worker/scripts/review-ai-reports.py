#!/usr/bin/env python3
"""Review the private AI report inbox; token stays in a local mode-0600 file."""
import argparse
import json
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

BASE = 'https://assistant-relay.woowtech.io'


def request(path, token, method='GET'):
    url = BASE + path
    req = urllib.request.Request(url, headers={
        'Authorization': 'Bearer ' + token,
        'Accept': 'application/json',
        'User-Agent': 'WoowTech-Report-Review/1.0',
    }, method=method)
    try:
        with urllib.request.urlopen(req, timeout=20) as response:
            return json.load(response)
    except urllib.error.HTTPError as error:
        raise RuntimeError('Report inbox returned HTTP %s' % error.code) from None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--token-file', type=Path, default=Path.home() / '.woow-report-admin' / 'secret')
    parser.add_argument('--delete', metavar='REPORT_ID', help='delete a reviewed report')
    parser.add_argument('--confirm', metavar='REPORT_ID', help='repeat the same ID to confirm deletion')
    args = parser.parse_args()
    try:
        stat = args.token_file.stat()
        if stat.st_mode & 0o077:
            raise RuntimeError('Token file must not be readable by group or others')
        token = args.token_file.read_text().strip()
        if len(token) < 32:
            raise RuntimeError('Token file is empty or invalid')
        if args.delete:
            if args.confirm != args.delete:
                raise RuntimeError('Deletion requires --confirm with the same report ID')
            if not all(c in '0123456789abcdef-' for c in args.delete.lower()) or len(args.delete) != 36:
                raise RuntimeError('Invalid report ID')
            result = request('/admin/ai-reports/' + args.delete, token, method='DELETE')
            print('Deleted report' if result.get('deleted') else 'Deletion not confirmed')
            return
        cursor = None
        while True:
            path = '/admin/ai-reports' + ('?cursor=' + urllib.parse.quote(cursor) if cursor else '')
            page = request(path, token)
            for report in page['reports']:
                # Output is intended only for the authorized reviewer terminal; do not redirect into public logs.
                print(json.dumps(report, ensure_ascii=False))
            cursor = page.get('next_cursor')
            if not cursor:
                break
    except (OSError, RuntimeError, ValueError) as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)


if __name__ == '__main__':
    main()
