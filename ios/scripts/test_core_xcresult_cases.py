"""Synthetic invariant tests: these fixtures are not xcresulttool output."""
import copy
import unittest

from core_xctest_inventory import TARGETS
from core_xcresult_cases import CaseError, inspect_synthetic_tree


class SyntheticCaseTests(unittest.TestCase):
    def setUp(self):
        self.expected = [t + '/OrdinaryTests/testNormal' for t in TARGETS]
        self.mcp = ['AssistantMCPTests/MCPInboundCoreTests/testCase' + str(n) for n in range(5)]
        self.memory = ['AssistantMemoryTests/MemoryCoreTests/testMutation', 'AssistantMemoryTests/MemoryCoreTests/testSensitive']
        self.expected += self.mcp + self.memory
        self.tree = {'schema': 'synthetic-xcresult-v0', 'cases': [
            {'identity': name, 'attempts': [{'status': 'Passed', 'issues': []}]} for name in self.expected]}

    def rejected(self, tree=None, expected=None):
        with self.assertRaises(CaseError):
            inspect_synthetic_tree(self.tree if tree is None else tree, self.expected if expected is None else expected)

    def test_full_synthetic_data_is_never_native_verification(self):
        result = inspect_synthetic_tree(self.tree, self.expected)
        self.assertEqual(result, {'classification': 'synthetic-only', 'native_provenance_verified': False, 'case_count': len(self.expected)})

    def test_mcp_zero_four_five_and_missing_memory(self):
        for count in (0, 4, 5):
            tree = copy.deepcopy(self.tree)
            tree['cases'] = [c for c in tree['cases'] if c['identity'] not in self.mcp[count:]]
            if count == 5:
                self.assertFalse(inspect_synthetic_tree(tree, self.expected)['native_provenance_verified'])
            else: self.rejected(tree)
        for whole in (False, True):
            tree = copy.deepcopy(self.tree)
            removed = self.memory if whole else self.memory[:1]
            tree['cases'] = [c for c in tree['cases'] if c['identity'] not in removed]
            self.rejected(tree)

    def test_skips_failures_retries_and_issues_are_rejected(self):
        for status in ('Skipped', 'Failed', 'Expected Failure', 'Unknown', '', True):
            tree = copy.deepcopy(self.tree)
            tree['cases'][0]['attempts'][0]['status'] = status
            with self.subTest(status=status): self.rejected(tree)
        for attempts in ([], [{'status': 'Failed', 'issues': []}, {'status': 'Passed', 'issues': []}],
                         [{'status': 'Passed', 'issues': []}, {'status': 'Passed', 'issues': []}],
                         [{'status': 'Passed', 'issues': ['failure']}],
                         [{'status': 'Passed', 'issues': [] , 'retry': False}]):
            tree = copy.deepcopy(self.tree)
            tree['cases'][0]['attempts'] = attempts
            with self.subTest(attempts=attempts): self.rejected(tree)

    def test_duplicate_unexpected_malformed_and_ambiguous_identity_rejected(self):
        for mutation in ('duplicate', 'extra', 'malformed', 'missing_attempts', 'unknown_field'):
            tree = copy.deepcopy(self.tree)
            if mutation == 'duplicate': tree['cases'].append(copy.deepcopy(tree['cases'][0]))
            if mutation == 'extra': tree['cases'].append({'identity': 'AssistantDomainTests/OtherTests/testExtra', 'attempts': [{'status': 'Passed', 'issues': []}]})
            if mutation == 'malformed': tree['cases'][0]['identity'] = 'OrdinaryTests/testNormal'
            if mutation == 'missing_attempts': del tree['cases'][0]['attempts']
            if mutation == 'unknown_field': tree['cases'][0]['skipped'] = True
            with self.subTest(mutation=mutation): self.rejected(tree)
        self.rejected(expected=self.expected + self.expected[:1])
        self.rejected(expected=[x for x in self.expected if not x.startswith(TARGETS[0] + '/')])

    def test_native_or_unknown_shape_is_not_mistaken_for_synthetic(self):
        for tree in ({}, {'schema': 'xcresulttool', 'cases': self.tree['cases']},
                     {'schema': 'synthetic-xcresult-v0', 'cases': [], 'unknown': 1},
                     {'schema': 'synthetic-xcresult-v0', 'cases': None}):
            with self.subTest(tree=tree): self.rejected(tree)


if __name__ == '__main__': unittest.main()
