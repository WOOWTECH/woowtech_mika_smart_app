#!/usr/bin/env python3
"""Synthetic-only core result invariant engine, not an xcresulttool decoder.

No native format is accepted until actual tool output and attempt semantics are
independently established. This module never emits a native verification.
"""
import re

from core_xctest_inventory import TARGETS


class CaseError(ValueError):
    pass


IDENTITY = re.compile(r'([A-Za-z_][A-Za-z0-9_]*)/([A-Za-z_][A-Za-z0-9_]*)/(test[A-Za-z0-9_]+)\Z')


def validate_expected(expected):
    if not isinstance(expected, list) or not expected or any(not isinstance(x, str) or not IDENTITY.fullmatch(x) for x in expected):
        raise CaseError('expected identities unavailable or unsupported')
    if len(set(expected)) != len(expected):
        raise CaseError('duplicate expected identity')
    if {x.split('/')[0] for x in expected} != set(TARGETS):
        raise CaseError('expected target set incomplete')
    return set(expected)


def inspect_synthetic_tree(tree, expected):
    """Check invented case/attempt shape; outputs a synthetic diagnostic only.

    `expected` must be independently supplied: do not derive it from the result
    tree. This example shape has not been observed in native xcresulttool output.
    """
    needed = validate_expected(expected)
    if not isinstance(tree, dict) or set(tree) != {'schema', 'cases'} or tree['schema'] != 'synthetic-xcresult-v0':
        raise CaseError('unrecognized result schema; native xcresult not supported')
    cases = tree['cases']
    if not isinstance(cases, list):
        raise CaseError('case list unavailable')
    seen = set()
    for case in cases:
        if not isinstance(case, dict) or set(case) != {'identity', 'attempts'}:
            raise CaseError('unknown case shape')
        identity = case['identity']
        if not isinstance(identity, str) or not IDENTITY.fullmatch(identity):
            raise CaseError('invalid case identity')
        if identity not in needed or identity in seen:
            raise CaseError('unexpected or duplicate case')
        seen.add(identity)
        attempts = case['attempts']
        if not isinstance(attempts, list) or len(attempts) != 1:
            raise CaseError('missing or repeated attempt')
        attempt = attempts[0]
        if not isinstance(attempt, dict) or set(attempt) != {'status', 'issues'}:
            raise CaseError('unknown attempt shape')
        if attempt['status'] != 'Passed' or attempt['issues'] != []:
            raise CaseError('nonpassing attempt or issue')
    if seen != needed:
        raise CaseError('missing expected cases')
    return {'classification': 'synthetic-only', 'native_provenance_verified': False, 'case_count': len(seen)}
