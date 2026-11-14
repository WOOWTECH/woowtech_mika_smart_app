from copy import deepcopy
from pathlib import Path
import tempfile
import unittest

import release_ios17 as ios17
from release_ios import ReleaseError


ROOT = Path(__file__).resolve().parents[1]


class DocumentFocusedScopesTests(unittest.TestCase):
    def test_actual_repository_methods_form_the_chat_attachment_scope(self):
        catalog = ios17.ui_inventory(ROOT)
        expected = set(catalog["shards"]["ui-documents"]["tests"])
        groups = ios17.validate_document_scopes(catalog)
        self.assertEqual(set(groups), {"documents-chat"})
        self.assertEqual(set(groups["documents-chat"]), expected)
        self.assertEqual(len(expected), 3)
        self.assertIn("WoowAssistantUITests/ChatAttachmentUITests/testTrayShowsPhotoAndFileRemovesOneAndSendsAttachmentAlone",
                      expected)
        self.assertEqual(catalog["document_focused_scopes"], groups)
        self.assertEqual(ios17.UI_SHARDS["ui-documents"], ["ChatAttachmentUITests"])
        for scope, methods in groups.items():
            self.assertNotIn(scope, ios17.UI_SHARDS)
            self.assertEqual(ios17.selected_ui_tests(catalog, scope), methods)
            self.assertEqual(set(ios17.TEST_SCOPES[scope]), set(methods))

    def test_wrong_duplicate_class_selector_extra_and_empty_scopes_fail_closed(self):
        catalog = ios17.ui_inventory(ROOT)
        correct = ios17.validate_document_scopes(catalog)
        wrong_method = deepcopy(correct)
        wrong_method["documents-chat"][0] = "WoowAssistantUITests/ChatAttachmentUITests/testNotInSource"
        duplicated = deepcopy(correct)
        duplicated["documents-chat"][0] = duplicated["documents-chat"][1]
        broad = {"documents-chat": ["WoowAssistantUITests/ChatAttachmentUITests"]}
        for invalid in (wrong_method, duplicated, broad, {**correct, "documents-extra": []},
                        {"documents-chat": []}, {}):
            with self.subTest(invalid=invalid), self.assertRaises(ReleaseError):
                ios17.validate_document_scopes(catalog, invalid)

    def test_new_renamed_or_removed_actual_source_method_fails_inventory(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            target = root / "Tests/WoowAssistantUITests"
            target.mkdir(parents=True)
            for name in ios17.UI_SHARDS["ui-documents"]:
                (target / (name + ".swift")).write_text(
                    (ROOT / "Tests/WoowAssistantUITests" / (name + ".swift")).read_text())
            for name in ios17.LIVE_UI_CLASSES:
                (target / (name + ".swift")).write_text(
                    "final class " + name + ": XCTestCase { func testSyntheticLive() {} }")
            mapping = {"ui-documents": ios17.UI_SHARDS["ui-documents"]}
            ios17.ui_inventory(root, mapping)
            path = target / "ChatAttachmentUITests.swift"
            original = path.read_text()
            declaration = "final class ChatAttachmentUITests: XCTestCase {"
            self.assertEqual(original.count(declaration), 1)
            name = "testPhotoReachesModelOnlyAfterSeesImagesIsOn"
            mutations = [original.replace(declaration, declaration + "\nfunc testNewAttachmentFlow() {}\n"),
                         original.replace(name, "testRenamedPhotoReachesModel"),
                         original.replace(name, "scenarioPhotoReachesModel")]
            for source in mutations:
                with self.subTest(mutation=mutations.index(source)):
                    path.write_text(source)
                    with self.assertRaisesRegex(ReleaseError, "聯集必須精確等於"):
                        ios17.ui_inventory(root, mapping)

    def test_equal_count_other_methods_cannot_pass_the_completion_gate(self):
        catalog = ios17.ui_inventory(ROOT)
        expected = catalog["document_focused_scopes"]["documents-chat"]
        startup = catalog["shards"]["ui-startup"]["tests"]
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "tests.log"
            summary = {"result": "Passed", "totalTestCount": len(expected), "passedTests": len(expected),
                       "failedTests": 0, "skippedTests": 0, "expectedFailures": 0}
            wrong_method_same_count = [startup[0], *expected[1:]]
            for selected, accepted in ((expected, True), (wrong_method_same_count, False)):
                path.write_text("".join("Test Case '-[WoowAssistantUITests.%s %s]' passed (1.0 seconds).\n" %
                                        tuple(name.split("/")[1:]) for name in selected))
                result = ios17.test_completion(summary, path, expected, True)
                self.assertEqual(result["verified"], accepted)


if __name__ == "__main__":
    unittest.main()
