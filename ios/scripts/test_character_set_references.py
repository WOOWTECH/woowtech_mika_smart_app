import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts/check_character_set_references.py"


class CharacterSetReferenceTests(unittest.TestCase):
    def test_sources_pass_and_the_compiler_probe_runs(self):
        result = subprocess.run([sys.executable, str(SCRIPT)], cwd=ROOT, capture_output=True, text=True, timeout=900)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("PASS character set references", result.stdout)

    def test_a_method_reference_is_found_in_any_source_folder(self):
        # The scan reads the folders next to the script, so a copy of the script beside a mutant tree sees only that.
        for folder, name in [("Sources", "Mutant.swift"), ("scripts", "Mutant.swift")]:
            for line in ["let bad = text.unicodeScalars.contains(where: blocked.contains)",
                         "let bad = text.unicodeScalars.allSatisfy(CharacterSet.controlCharacters.contains)",
                         "let bad = names.filter(Set(allowed).contains)"]:
                with self.subTest(folder=folder, line=line), tempfile.TemporaryDirectory(prefix="woow-charset-test-") as temp:
                    tree = Path(temp)
                    (tree / "scripts").mkdir()
                    (tree / "scripts" / SCRIPT.name).write_text(SCRIPT.read_text())
                    (tree / folder).mkdir(exist_ok=True)
                    (tree / folder / name).write_text(line + "\n")
                    result = subprocess.run([sys.executable, str(tree / "scripts" / SCRIPT.name)], cwd=tree,
                                            capture_output=True, text=True, timeout=900)
                    self.assertNotEqual(result.returncode, 0, "the scan must catch: " + line)
                    self.assertIn("FAIL: a method reference to contains", result.stdout)

    def test_a_call_and_a_comment_are_not_references(self):
        for line in ["let ok = text.unicodeScalars.contains(where: { blocked.contains($0) })",
                     "let ok = names.contains { $0 == name }",
                     "// not this: names.filter(set.contains)"]:
            with self.subTest(line=line), tempfile.TemporaryDirectory(prefix="woow-charset-test-") as temp:
                tree = Path(temp)
                (tree / "scripts").mkdir()
                (tree / "scripts" / SCRIPT.name).write_text(SCRIPT.read_text())
                (tree / "Sources").mkdir()
                (tree / "Sources" / "Fine.swift").write_text(line + "\n")
                result = subprocess.run([sys.executable, str(tree / "scripts" / SCRIPT.name)], cwd=tree,
                                        capture_output=True, text=True, timeout=900)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
