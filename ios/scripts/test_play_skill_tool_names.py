"""Play's known tool names on iOS: the Swift list matches the Play 964d7bec evidence,
and skill import, edit and restore accept them (PlaySkillToolNames, LearningStore)."""
import json
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class PlaySkillToolNamesTests(unittest.TestCase):
    def test_swift_list_matches_play_evidence(self):
        evidence = json.loads((ROOT / "docs/evidence/play-964d7bec-tool-names.json").read_text(encoding="utf-8"))
        self.assertEqual(evidence["source_commit"], "964d7becff9a0daa228f24cc5c8e2664fde8b7d9")
        swift = (ROOT / "Sources/AssistantSkills/PlaySkillToolNames.swift").read_text(encoding="utf-8")
        body = swift.split("public static let known: Set<String> = [", 1)[1].split("]", 1)[0]
        self.assertEqual(set(re.findall(r'"([a-z][a-z0-9_]*)"', body)), set(evidence["names"]))
        for name in ("web_navigate", "web_read_page", "skill_save", "memory_save", "do_steps"):
            self.assertIn(name, evidence["names"])

    def test_import_edit_and_restore_use_the_broad_names(self):
        store = (ROOT / "Sources/App/LearningStore.swift").read_text(encoding="utf-8")
        self.assertIn("static let skillToolNames: Set<String> = PlaySkillToolNames.known", store)
        self.assertIn(".union(ChatWebCommand.toolNames)", store)
        view = (ROOT / "Sources/App/MemoryDataView.swift").read_text(encoding="utf-8")
        self.assertIn("private let toolNames = LearningStore.skillToolNames", view)
        self.assertNotIn("private let toolNames = BrowserSession.toolNames", view)


if __name__ == "__main__":
    unittest.main()
