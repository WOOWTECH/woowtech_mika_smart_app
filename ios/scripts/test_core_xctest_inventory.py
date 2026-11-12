"""Synthetic contract checks; never claim these are native XCTest evidence."""
import copy
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

import core_xctest_inventory as gate


MCP = [
    "testAndroidToolSchemasAndOriginalAnswerSteerArguments",
    "testMaximumListResponsePreservesAllItemsAndBothRepresentations",
    "testParseErrorWithoutIDMatchesAndroidAndCanEncodeJSONRPCNull",
    "testExpiredConnectionFreesCapacityAndPendingReview",
    "testStaleDiscardAndApprovalPreserveReplacementReview",
]


class CoreInventoryChecks(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="core-inventory-check-")
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        project = ["name: Fixture", "targets:"]
        for target in gate.TARGETS:
            folder = self.root / "Tests" / target
            folder.mkdir(parents=True)
            source = "class OrdinaryTests: XCTestCase { func testNormal() {} }\n"
            if target == "AssistantMCPTests":
                source += "class MCPInboundCoreTests: XCTestCase { " + " ".join(
                    "func " + name + "() {}" for name in MCP) + " }\n"
            if target == "AssistantMemoryTests":
                source += ("class MemoryCoreTests: XCTestCase { func testMutationsUndoAndSerialization() {} "
                           "func testSensitiveExclusion() {}\n#if OPTIONAL\nfunc testConditional() {}\n#endif\n}\n")
            (folder / "Fixture.swift").write_text(source)
            project += ["  " + target + ":", "    type: bundle.unit-test", "    sources:", "      - Tests/" + target]
            if target == "AssistantSkillsTests":
                (self.root / "scripts").mkdir(exist_ok=True)
                (self.root / "scripts/Hosted.swift").write_text("class HostedTests: XCTestCase { func testHosted() {} }\n")
                project += ["      - scripts/Hosted.swift"]
        project += ["schemes:", "  Fixture:"]
        (self.root / "project.yml").write_text("\n".join(project) + "\n")
        def git(*args):
            return subprocess.check_output(["git", "-C", str(self.root), *args], stderr=subprocess.DEVNULL, text=True).strip()
        git("init", "-q")
        git("add", "project.yml", "Tests", "scripts")
        git("-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid", "commit", "-qm", "fixture")
        self.profile = {"configuration": "Debug", "platform": "iphonesimulator", "conditions": {"DEBUG": True},
                        "source_commit": git("rev-parse", "HEAD")}
        self.inventory = gate.new_template(self.root, self.profile)
        self.inventory["state"] = "reviewed"
        self.inventory["review"] = {"reviewer": "fixture", "conditions": "fixture branches reviewed", "inheritance": "fixture classes reviewed"}
        self.inventory["expected"] = {target: list(methods) for target, methods in self.inventory["declarations"].items()}
        self.product = self.root / "products.zip"
        self.product.write_bytes(b"synthetic, not an xctestproducts archive")
        self.tests = sorted(target + "/" + case for target, cases in self.inventory["expected"].items() for case in cases)
        self.discovery = {"schema": "core-xctest-discovery-v1", "complete": True,
                          "snapshot_sha256": self.inventory["snapshot"]["sha256"], "profile": self.profile,
                          "product_sha256": gate.digest(self.product.read_bytes()), "tests": self.tests[:]}
        self.summary = {"result": "Passed", "totalTestCount": len(self.tests), "passedTests": len(self.tests),
                        "failedTests": 0, "skippedTests": 0, "expectedFailures": 0}
        self.log = self.log_for(self.tests)

    @staticmethod
    def log_for(tests):
        lines = []
        for test in tests:
            target, cls, method = test.split("/")
            prefix = "2026-01-01 Test Case '-[" + target + "." + cls + " " + method + "]' "
            lines += [prefix + "started.", prefix + "passed (0.1 seconds)."]
        return "\n".join(lines)

    def verify(self, inventory=None, discovery=None, execution=None, summary=None, log=None):
        discovery = self.discovery if discovery is None else discovery
        summary = self.summary if summary is None else summary
        log = self.log if log is None else log
        if execution is None:
            execution = {"schema": "core-xctest-execution-v1", "snapshot_sha256": discovery.get("snapshot_sha256"),
                         "product_sha256": discovery.get("product_sha256"), "profile": discovery.get("profile"),
                         "discovery_sha256": gate.digest(gate.canonical(discovery)),
                         "summary_sha256": gate.digest(gate.canonical(summary)), "log_sha256": gate.digest(log.encode()),
                         "run_id": "synthetic", "destination": "synthetic", "runtime": "synthetic"}
        return gate.verify(self.inventory if inventory is None else inventory, self.root,
                           discovery, execution, summary, log, self.product)

    def rejected(self, **changes):
        with self.assertRaises(gate.EvidenceError):
            self.verify(**changes)

    def test_source_bound_inventory_discovery_and_results_all_required(self):
        result = self.verify()
        self.assertEqual(result["test_count"], len(self.tests))
        self.assertTrue(result["contract_verified"])
        self.assertFalse(result["native_provenance_verified"])
        self.assertIn("scripts/Hosted.swift", self.inventory["snapshot"]["targets"]["AssistantSkillsTests"])
        draft = gate.new_template(self.root, self.profile)
        self.rejected(inventory=draft)
        unreviewed = copy.deepcopy(self.inventory); unreviewed["review"]["inheritance"] = ""
        self.rejected(inventory=unreviewed)

    def test_mcp_zero_four_five_and_memory_missing_cannot_pass(self):
        mcp = [x for x in self.tests if "/MCPInboundCoreTests/" in x]
        self.assertEqual(len(mcp), 5)
        for count in (0, 4, 5):
            kept = [x for x in self.tests if x not in mcp[count:]]
            discovery = {**self.discovery, "tests": kept}
            summary = {**self.summary, "totalTestCount": len(kept), "passedTests": len(kept)}
            if count == 5:
                self.assertTrue(self.verify(discovery=discovery, summary=summary, log=self.log_for(kept))["contract_verified"])
            else:
                self.rejected(discovery=discovery, summary=summary, log=self.log_for(kept))
        for whole in (False, True):
            kept = [x for x in self.tests if not ("/MemoryCoreTests/" in x and (whole or x.endswith("/testMutationsUndoAndSerialization")))]
            discovery = {**self.discovery, "tests": kept}
            summary = {**self.summary, "totalTestCount": len(kept), "passedTests": len(kept)}
            self.rejected(discovery=discovery, summary=summary, log=self.log_for(kept))

    def test_expected_and_discovery_cannot_both_omit_a_declared_method(self):
        inventory = copy.deepcopy(self.inventory)
        inventory["expected"]["AssistantMemoryTests"].remove("MemoryCoreTests/testMutationsUndoAndSerialization")
        kept = [x for x in self.tests if not x.endswith("/testMutationsUndoAndSerialization")]
        self.rejected(inventory=inventory, discovery={**self.discovery, "tests": kept},
                      summary={**self.summary, "totalTestCount": len(kept), "passedTests": len(kept)}, log=self.log_for(kept))
        # A reviewer cannot drop an unconditional declaration even with a reason.
        inventory["excluded"]["AssistantMemoryTests"]["MemoryCoreTests/testMutationsUndoAndSerialization"] = "not compiled in this fixture profile"
        self.rejected(inventory=inventory)
        # A reviewer can explicitly account for a conditional declaration; a
        # discovery record must still match that independently reviewed profile.
        inventory = copy.deepcopy(self.inventory)
        identity = "MemoryCoreTests/testConditional"
        inventory["expected"]["AssistantMemoryTests"].remove(identity)
        inventory["excluded"]["AssistantMemoryTests"][identity] = "OPTIONAL is false in this fixture profile"
        kept = [x for x in self.tests if not x.endswith("/testConditional")]
        self.assertTrue(self.verify(inventory=inventory, discovery={**self.discovery, "tests": kept},
                                    summary={**self.summary, "totalTestCount": len(kept), "passedTests": len(kept)},
                                    log=self.log_for(kept))["contract_verified"])
        inventory["excluded"]["AssistantMemoryTests"][identity] = ""
        self.rejected(inventory=inventory)

    def test_rejects_missing_duplicate_extra_or_nonpassing_events(self):
        lines = self.log.splitlines()
        for log in ("", "\n".join(lines[1:]), "\n".join(lines[:-1]), self.log + "\n" + "\n".join(lines[:2]),
                    "\n".join([lines[1], lines[0], *lines[2:]]), self.log + "\n" + lines[0],
                    self.log.replace("passed (", "failed (", 1), self.log.replace("passed (", "skipped (", 1),
                    self.log + "\nTest Case '-[Bad invalid]' passed (0.1 seconds)."):
            with self.subTest(log=log[:50]): self.rejected(log=log)
        for key in ("failedTests", "skippedTests", "expectedFailures"):
            self.rejected(summary={**self.summary, key: 1})
        self.rejected(summary={**self.summary, "passedTests": 0, "totalTestCount": 0})
        self.rejected(summary={**self.summary, "passedTests": True})

    def test_discovery_must_be_complete_source_profile_and_product_bound(self):
        for change in ({"complete": False}, {"tests": []}, {"tests": self.tests + self.tests[:1]},
                       {"snapshot_sha256": "0" * 64}, {"product_sha256": "0" * 64},
                       {"profile": {**self.profile, "configuration": "Release"}}):
            self.rejected(discovery={**self.discovery, **change})
        self.product.write_bytes(b"different")
        self.rejected()

    def test_execution_metadata_is_bound_and_never_claims_native_provenance(self):
        self.rejected(execution={})
        result = self.verify()
        self.assertTrue(result["contract_verified"])
        self.assertFalse(result["native_provenance_verified"])
        execution = {"schema": "core-xctest-execution-v1", "snapshot_sha256": self.discovery["snapshot_sha256"],
                     "product_sha256": self.discovery["product_sha256"], "profile": self.profile,
                     "discovery_sha256": gate.digest(gate.canonical(self.discovery)),
                     "summary_sha256": gate.digest(gate.canonical(self.summary)), "log_sha256": gate.digest(self.log.encode()),
                     "run_id": "synthetic", "destination": "synthetic", "runtime": "synthetic"}
        for field in ("snapshot_sha256", "product_sha256", "discovery_sha256", "summary_sha256", "log_sha256", "run_id", "destination", "runtime"):
            bad = {**execution, field: ""}
            with self.subTest(field=field): self.rejected(execution=bad)

    def test_project_sources_changes_symlinks_and_unknown_targets_fail_closed(self):
        (self.root / "scripts/Hosted.swift").write_text("// changed\n")
        self.rejected()
        old = (self.root / "project.yml").read_text()
        (self.root / "project.yml").write_text(old.replace("schemes:", "  OtherTests:\n    type: bundle.unit-test\n    sources: [Tests/Other]\nschemes:"))
        with self.assertRaises(gate.EvidenceError): gate.source_snapshot(self.root)
        (self.root / "project.yml").write_text(old)
        (self.root / "project.yml").write_text(old + "configFiles:\n  Debug: external.xcconfig\n")
        with self.assertRaises(gate.EvidenceError): gate.source_snapshot(self.root)
        (self.root / "project.yml").write_text(old)
        (self.root / "project.yml").write_text(old.replace("      - scripts/Hosted.swift", "      - path: scripts/Hosted.swift"))
        with self.assertRaises(gate.EvidenceError): gate.source_snapshot(self.root)
        (self.root / "project.yml").write_text(old.replace("    type: bundle.unit-test", '    type: "bundle.unit-test"', 1))
        with self.assertRaises(gate.EvidenceError): gate.source_snapshot(self.root)
        (self.root / "project.yml").write_text(old)
        (self.root / "Tests/AssistantDomainTests/link.swift").symlink_to(self.root / "scripts/Hosted.swift")
        with self.assertRaises(gate.EvidenceError): gate.source_snapshot(self.root)

    def test_inheritance_extensions_and_unsupported_test_shapes_fail_closed(self):
        source = self.root / "Tests/AssistantDomainTests/Fixture.swift"
        for text in ("class Derived: OrdinaryTests {}", "class Innocent: ExternalTestBase {}", "extension OrdinaryTests {}",
                     "class UnknownTests: ExternalBase {}", "class GenericTests<T>: XCTestCase {}",
                     "class NewTests: XCTestCase { func testWithArguments(_ x: Int) {} }"):
            with self.subTest(text=text):
                original = source.read_text()
                source.write_text(original + "\n" + text + "\n")
                with self.assertRaises(gate.EvidenceError): gate.new_template(self.root, self.profile)
                source.write_text(original)

    def test_swift_comments_strings_and_unterminated_constructs(self):
        source = self.root / "Tests/AssistantDomainTests/Fixture.swift"
        source.write_text(source.read_text() + '\n// class FakeTests: XCTestCase { func testFake() {} }\nlet x = "func testFake() {}"\n/* nested /* inner */ done */\n')
        draft = gate.new_template(self.root, self.profile)
        self.assertEqual(draft["declarations"]["AssistantDomainTests"], {"OrdinaryTests/testNormal": []})
        original = source.read_text()
        source.write_text(original + "\nlet pattern = /abc/\n")
        with self.assertRaises(gate.EvidenceError): gate.new_template(self.root, self.profile)
        source.write_text(original)
        source.write_text(source.read_text() + "\n/* unfinished")
        with self.assertRaises(gate.EvidenceError): gate.new_template(self.root, self.profile)

    def test_wrong_commit_and_duplicate_json_keys_are_rejected(self):
        inventory = copy.deepcopy(self.inventory)
        inventory["profile"]["source_commit"] = "0" * 40
        self.rejected(inventory=inventory)
        path = self.root / "duplicate.json"
        path.write_text('{"complete":true,"complete":false}')
        with self.assertRaises(gate.EvidenceError): gate.read_json(path)


if __name__ == "__main__":
    unittest.main()
