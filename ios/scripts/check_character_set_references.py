#!/usr/bin/env python3
"""No method reference to `contains`, and the compiler fault behind that rule.

Xcode 26.6's Swift, when optimizing (the Release configuration), mis-compiles a CharacterSet's `contains`
handed on as a function value. `unicodeScalars.contains(where: blocked.contains)` answered true for the
plain key "localkey" in build 292, so the model form refused every API key and model name, while the
same line had worked in build 291: the line did not change, the code around it did. Written as a closure,
`contains(where: { blocked.contains($0) })`, the same check is always right.

1. Scans Sources, scripts and Tests for `.contains` passed on without being called (`.contains)` or
   `.contains,`) and fails on each one. Set and Array references were right in the same test, but one
   rule is simpler to keep than a rule about which types are safe.
2. Compiles a small program with -O, as a Release build is, and fails when the closure spelling answers
   wrongly. It also reports whether the method reference still answers wrongly in the shapes that failed
   (a hint, not a proof: the fault depends on the code around it, so a right answer here does not show
   the compiler is repaired).
"""
import re
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FOLDERS = ["Sources", "scripts", "Tests"]
SKIPPED = ("Tests/Fixtures/",)
REFERENCE = re.compile(r"\.contains[),]")

PROGRAM = r"""
import Foundation
@inline(never) func blockedByClosure(_ text: String) -> Bool {
    let blocked = CharacterSet.whitespacesAndNewlines.union(.controlCharacters)
    return text.unicodeScalars.contains(where: { blocked.contains($0) })
}
@inline(never) func controlByClosure(_ text: String) -> Bool {
    text.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
}
@inline(never) func alphanumericByClosure(_ text: String) -> Bool {
    text.unicodeScalars.contains(where: { CharacterSet.alphanumerics.contains($0) })
}
@inline(never) func allowedByClosure(_ text: String) -> Bool {
    let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.-")
    return text.unicodeScalars.allSatisfy({ allowed.contains($0) })
}
@inline(never) func notBlockedByReference(_ text: String) -> Bool {
    let blocked = CharacterSet.whitespacesAndNewlines.union(.controlCharacters)
    return !text.unicodeScalars.contains(where: blocked.contains)
}
@inline(never) func notControlByReference(_ text: String) -> Bool {
    !text.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
}
@inline(never) func alphanumericByReference(_ text: String) -> Bool {
    text.unicodeScalars.contains(where: CharacterSet.alphanumerics.contains)
}
var wrong: [String] = []
func expect(_ name: String, _ got: Bool, _ want: Bool) { if got != want { wrong.append(name) } }
for text in ["localkey", "demomodel", "local-key_1.A"] {
    expect("closure blocked " + text, blockedByClosure(text), false)
    expect("closure control " + text, controlByClosure(text), false)
    expect("closure allowed " + text, allowedByClosure(text), true)
}
expect("closure blocked space", blockedByClosure("two words"), true)
expect("closure control bell", controlByClosure("a\u{7}b"), true)
expect("closure alphanumeric dashes", alphanumericByClosure("---"), false)
expect("closure alphanumeric letters", alphanumericByClosure("--a"), true)
print("closure:" + (wrong.isEmpty ? "ok" : wrong.joined(separator: "|")))
wrong = []
for text in ["localkey", "demomodel", "local-key_1.A"] {
    expect("reference notBlocked " + text, notBlockedByReference(text), true)
    expect("reference notControl " + text, notControlByReference(text), true)
}
expect("reference alphanumeric dashes", alphanumericByReference("---"), false)
print("reference:" + (wrong.isEmpty ? "ok" : wrong.joined(separator: "|")))
"""


def references():
    found = []
    for folder in FOLDERS:
        for path in sorted((ROOT / folder).rglob("*")):
            relative = path.relative_to(ROOT).as_posix()
            if not path.is_file() or path.suffix not in (".swift", ".sh", ".py") or any(part in relative for part in SKIPPED):
                continue
            if path.name in (Path(__file__).name, "test_" + Path(__file__).name[len("check_"):]):
                continue  # these two spell the bad forms out as test data
            for number, line in enumerate(path.read_text(encoding="utf-8", errors="replace").splitlines(), 1):
                if line.lstrip().startswith("//"):
                    continue
                if REFERENCE.search(line):
                    found.append(f"{relative}:{number}: {line.strip()[:150]}")
    return found


def compiled_answers():
    with tempfile.TemporaryDirectory(prefix="woow-charset-") as folder:
        source = Path(folder) / "main.swift"
        source.write_text(PROGRAM)
        binary = Path(folder) / "probe"
        subprocess.run(["swiftc", "-O", "-wmo", "-swift-version", "5", str(source), "-o", str(binary)],
                       check=True, capture_output=True, timeout=600)
        out = subprocess.run([str(binary)], check=True, capture_output=True, text=True, timeout=60).stdout
    return dict(line.split(":", 1) for line in out.strip().splitlines())


def main():
    failures = []
    for line in references():
        failures.append("a method reference to contains (write a closure): " + line)
    answers = compiled_answers()
    if answers["closure"] != "ok":
        failures.append("the closure spelling answered wrongly under -O: " + answers["closure"])
    if failures:
        print("\n".join("FAIL: " + failure for failure in failures))
        sys.exit(1)
    state = ("answers wrongly under -O in this probe, so the rule stands" if answers["reference"] != "ok" else
             "answered rightly in this probe, which proves little: the fault depends on the code around it, "
             "so lift the rule only after typing an API key into a Release build")
    print(f"PASS character set references: no method reference to contains; closure spelling right under -O; compiler method reference {state}")


if __name__ == "__main__":
    main()
