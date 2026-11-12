#!/usr/bin/env python3
"""Fail-closed core XCTest evidence contract; does not perform native discovery."""
import argparse
import bisect
import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path

TARGETS = (
    "AssistantDomainTests", "AssistantModelsTests", "AssistantMCPTests",
    "AssistantMemoryTests", "AssistantSkillsTests", "AssistantPersistenceTests",
    "AssistantBrowserIntegrationTests",
)
IDENT = re.compile(r"[A-Za-z_][A-Za-z0-9_]*\Z")
CASE = re.compile(r"([A-Za-z_][A-Za-z0-9_]*)/(test[A-Za-z0-9_]+)\Z")
EVENT = re.compile(r"Test Case '-\[([A-Za-z_][A-Za-z0-9_]*)\.([A-Za-z_][A-Za-z0-9_]*) (test[A-Za-z0-9_]+)\]' (started\.|(?:passed|failed|skipped) \([^\n]*\)\.)")
# Audited non-XCTest bases/protocols found in the current project sources.
# New names require review and an explicit code change, never silent omission.
NON_TEST_BASES = frozenset({
    "Sendable", "URLProtocol", "NSObject", "TaskNotificationClient", "ChatModelClient",
    "LearningKeyStore", "SkillAuthoringStoring", "ModelCredentialStoring",
    "MultiSourceResearchExecuting", "StructuredStreamingChatModelClient", "ResearchSourceDiscovering",
})


class EvidenceError(ValueError):
    pass


def digest(data):
    return hashlib.sha256(data).hexdigest()


def file_digest(path):
    hasher = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            hasher.update(block)
    return hasher.hexdigest()


def canonical(data):
    return json.dumps(data, sort_keys=True, separators=(",", ":"), ensure_ascii=True).encode()


def read_json(path):
    def unique(pairs):
        result = {}
        for key, value in pairs:
            if key in result: raise EvidenceError("duplicate JSON key")
            result[key] = value
        return result
    return json.loads(path.read_text(), object_pairs_hook=unique)


def read_utf8_exact(path):
    """Decode without universal-newline conversion so hashes cover input bytes."""
    return path.read_bytes().decode("utf-8", errors="strict")


def target_blocks(text):
    """Read only the supported project.yml target/source subset; reject variants."""
    if re.search(r"(?m)^\s*(?:include|configFiles|preBuildScripts|postBuildScripts|postCompileScripts)\s*:", text):
        raise EvidenceError("external project configuration or build scripts require review")
    lines = text.splitlines()
    if lines.count("targets:") != 1:
        raise EvidenceError("project targets missing or ambiguous")
    lines = lines[lines.index("targets:") + 1:]
    blocks = {}
    current = None
    for line in lines:
        if line and not line[0].isspace() and not line.startswith("#"):
            break
        match = re.fullmatch(r"  ([A-Za-z_][A-Za-z0-9_]*):", line)
        if match:
            current = match.group(1)
            if current in blocks:
                raise EvidenceError("duplicate target")
            blocks[current] = []
        elif current is not None:
            blocks[current].append(line)
    unit = set()
    for name, body in blocks.items():
        types = [line for line in body if re.match(r"^    type\s*:", line)]
        if len(types) != 1 or not re.fullmatch(r"    type: [A-Za-z0-9_.-]+", types[0]):
            raise EvidenceError("unsupported or ambiguous target type")
        if types[0] == "    type: bundle.unit-test":
            unit.add(name)
    if unit != set(TARGETS):
        raise EvidenceError("unit-test target set changed")
    return blocks


def source_paths(body):
    found = [i for i, line in enumerate(body) if re.match(r"^    sources\s*:", line)]
    if len(found) != 1:
        raise EvidenceError("target sources missing or ambiguous")
    i = found[0]
    line = body[i]
    if line == "    sources:":
        values = []
        for row in body[i + 1:]:
            if not row.strip() or row.lstrip().startswith("#"):
                continue
            if not row.startswith("      "):
                break
            match = re.fullmatch(r"      - ([A-Za-z0-9_./-]+)", row)
            if not match:
                raise EvidenceError("unsupported source declaration")
            values.append(match.group(1))
    else:
        match = re.fullmatch(r"    sources: \[([A-Za-z0-9_./-]+)\]", line)
        if not match:
            raise EvidenceError("unsupported inline sources")
        values = [match.group(1)]
    if not values or len(values) != len(set(values)):
        raise EvidenceError("empty or duplicate sources")
    return values


def checked_path(root, relative):
    if not relative or relative.startswith("/") or any(p in ("", ".", "..") for p in relative.split("/")):
        raise EvidenceError("unsafe source path")
    path = root
    for part in relative.split("/"):
        path = path / part
        if path.is_symlink():
            raise EvidenceError("symlink source not supported")
    if not path.exists():
        raise EvidenceError("source path missing")
    return path


def mask_swift(source):
    """Mask strings/comments; reject regex literals and unterminated constructs.

    This is deliberately not a Swift parser. A reviewer must still inspect
    conditional compilation and any syntax outside the supported subset.
    """
    chars = list(source)
    n, i = len(source), 0

    def blank(start, end):
        for j in range(start, end):
            if chars[j] != "\n":
                chars[j] = " "

    while i < n:
        if source.startswith("//", i):
            end = source.find("\n", i)
            end = n if end < 0 else end
            blank(i, end); i = end; continue
        if source.startswith("/*", i):
            start, depth = i, 1
            i += 2
            while i < n and depth:
                if source.startswith("/*", i): depth += 1; i += 2
                elif source.startswith("*/", i): depth -= 1; i += 2
                else: i += 1
            if depth: raise EvidenceError("unterminated Swift comment")
            blank(start, i); continue
        start = i
        hashes = 0
        while i + hashes < n and source[i + hashes] == "#": hashes += 1
        q = i + hashes
        if q < n and source[q] == '"':
            triple = source.startswith('"""', q)
            quote = '"""' if triple else '"'
            ending = quote + "#" * hashes
            i = q + len(quote)
            while i < n:
                if source.startswith(ending, i):
                    # Swift escapes terminate a normal string only after an
                    # even number of immediately preceding escape sequences.
                    marker = "\\" + "#" * hashes
                    k, escapes = i, 0
                    while k >= len(marker) and source[k-len(marker):k] == marker:
                        k -= len(marker); escapes += 1
                    if escapes % 2 == 0:
                        i += len(ending); break
                i += 1
            else: raise EvidenceError("unterminated Swift string")
            blank(start, i); continue
        if hashes and q < n and source[q] == "/":
            raise EvidenceError("Swift regex literal requires explicit review")
        i = start + 1
    masked = "".join(chars)
    # Bare regex literals are ambiguous with division without a Swift parser.
    # Reject common literal positions; all other unusual syntax needs review.
    if re.search(r"(?:=|\(|\[|\breturn)\s*/(?![/*])", masked):
        raise EvidenceError("possible Swift regex literal requires review")
    return masked


def preprocessor_states(text):
    """Track lexical conditional regions without guessing their truth values."""
    points, states, stack = [], [], []
    for match in re.finditer(r"^[ \t]*#(if|elseif|else|endif)\b([^\n]*)", text, re.M):
        kind, expression = match.group(1), match.group(2).strip()
        if kind == "if":
            if not expression: raise EvidenceError("empty Swift compilation condition")
            stack.append("if " + expression)
        elif kind == "elseif":
            if not stack or not expression or stack[-1].startswith("else "):
                raise EvidenceError("invalid Swift elseif")
            stack[-1] = "elseif " + expression
        elif kind == "else":
            if not stack or expression or stack[-1].startswith("else "):
                raise EvidenceError("invalid Swift else")
            stack[-1] = "else " + stack[-1]
        else:
            if not stack or expression: raise EvidenceError("invalid Swift endif")
            stack.pop()
        points.append(match.end()); states.append(tuple(stack))
    if stack: raise EvidenceError("unbalanced Swift compilation conditions")
    return points, states


def declared_tests(root, snapshot):
    """Conservative direct XCTest declarations, before #if evaluation."""
    root = Path(root)
    output = {target: {} for target in TARGETS}
    for target, files in snapshot["targets"].items():
        classes = {}
        scanned = []
        for relative in files:
            if not relative.endswith(".swift"):
                continue
            text = mask_swift((root / relative).read_text())
            points, states = preprocessor_states(text)
            if re.search(r"@Test\b|@objc\s*\(|\bfunc\s+`|\b(?:class|extension)\s+\w+\s*<", text):
                raise EvidenceError("unsupported test syntax")
            declarations = list(re.finditer(r"\bclass\s+(\w+)(?:\s*:\s*([^\n{]+))?\s*\{", text))
            scanned.append((relative, text, declarations, points, states))
            for declaration in declarations:
                name, parents = declaration.groups()
                parent = parents.split(",")[0].strip() if parents else None
                if parent == "XCTestCase":
                    if name in classes:
                        raise EvidenceError("duplicate XCTest class")
                    classes[name] = (relative, declaration)
        for relative, text, declarations, points, states in scanned:
            for declaration in declarations:
                name, parents = declaration.groups()
                parent = parents.split(",")[0].strip() if parents else None
                if parent == "@unchecked Sendable": parent = "Sendable"
                if parent != "XCTestCase" and parent and (parent in classes or parent not in NON_TEST_BASES or name.endswith("Tests")):
                    raise EvidenceError("unknown or inherited class base requires review: " + relative)
            if any(re.search(r"\bextension\s+" + re.escape(name) + r"\b", text) for name in classes):
                raise EvidenceError("XCTest extensions require a supported inventory adapter")
            covered = set()
            for name, (file, declaration) in classes.items():
                if file != relative: continue
                depth, end = 1, declaration.end()
                while end < len(text) and depth:
                    if text[end] == "{": depth += 1
                    elif text[end] == "}": depth -= 1
                    end += 1
                if depth: raise EvidenceError("unbalanced XCTest class")
                level, position = 0, declaration.end()
                for method in re.finditer(r"\bfunc\s+(test\w+)\s*\(", text[declaration.end():end-1]):
                    start = declaration.end() + method.start()
                    for char in text[position:start]:
                        if char == "{": level += 1
                        elif char == "}": level -= 1
                    position = declaration.end() + method.end()
                    if level != 0 or not re.match(r"\s*\)", text[position:]):
                        raise EvidenceError("unsupported XCTest method declaration")
                    identity = name + "/" + method.group(1)
                    if identity in output[target]: raise EvidenceError("duplicate XCTest method")
                    condition_index = bisect.bisect_right(points, start) - 1
                    output[target][identity] = list(states[condition_index]) if condition_index >= 0 else []
                    covered.add(start)
            all_methods = {
                m.start() for m in re.finditer(r"\bfunc\s+test\w+\s*\(", text)
                if not re.search(r"\b(?:static|class)\s*$", text[text.rfind("\n", 0, m.start()) + 1:m.start()])
            }
            if all_methods != covered:
                raise EvidenceError("test method outside supported XCTest class: " + relative)
        if not output[target]: raise EvidenceError("target has no test declarations")
    return {target: dict(sorted(methods.items())) for target, methods in output.items()}


def source_snapshot(root):
    root = Path(root).resolve(strict=True)
    project = checked_path(root, "project.yml")
    project_bytes = project.read_bytes()
    blocks = target_blocks(project_bytes.decode("utf-8"))
    targets = {}
    for target in TARGETS:
        files = {}
        for source in source_paths(blocks[target]):
            path = checked_path(root, source)
            if path.is_file():
                candidates = [path]
            elif path.is_dir():
                # Reject symlinked directories and files, including non-Swift
                # inputs; do not silently omit a potentially compiled source.
                candidates = []
                for child in path.rglob("*"):
                    if child.is_symlink():
                        raise EvidenceError("symlink within source directory")
                    if child.is_file():
                        candidates.append(child)
            else:
                raise EvidenceError("unsupported source kind")
            if not candidates:
                raise EvidenceError("empty source declaration")
            for child in candidates:
                relative = child.relative_to(root).as_posix()
                if relative in files:
                    raise EvidenceError("overlapping source declarations")
                files[relative] = file_digest(child)
        targets[target] = dict(sorted(files.items()))
    base = {"project_sha256": digest(project_bytes), "targets": targets}
    return {**base, "sha256": digest(canonical(base))}


def new_template(root, profile):
    snapshot = source_snapshot(root)
    return {
        "schema": "core-xctest-inventory-v1", "state": "draft",
        "snapshot": snapshot, "profile": profile,
        "review": {"reviewer": "", "conditions": "", "inheritance": ""},
        "declarations": declared_tests(root, snapshot),
        "expected": {target: [] for target in TARGETS},
        "excluded": {target: {} for target in TARGETS},
    }


def validate_inventory(inventory, root):
    if not isinstance(inventory, dict) or inventory.get("schema") != "core-xctest-inventory-v1" or inventory.get("state") != "reviewed":
        raise EvidenceError("reviewed inventory required")
    if inventory.get("snapshot") != source_snapshot(root):
        raise EvidenceError("project or sources changed")
    declarations = declared_tests(root, inventory["snapshot"])
    if inventory.get("declarations") != declarations:
        raise EvidenceError("source declarations changed or incomplete")
    profile, review, expected = inventory.get("profile"), inventory.get("review"), inventory.get("expected")
    excluded = inventory.get("excluded")
    if not isinstance(profile, dict) or set(profile) != {"configuration", "platform", "conditions", "source_commit"}:
        raise EvidenceError("build profile required")
    if profile["configuration"] not in ("Debug", "Release") or profile["platform"] != "iphonesimulator":
        raise EvidenceError("unsupported build profile")
    if not isinstance(profile["source_commit"], str) or not re.fullmatch(r"[0-9a-f]{40}", profile["source_commit"]):
        raise EvidenceError("exact source commit required")
    try:
        head = subprocess.check_output(["git", "-C", str(root), "rev-parse", "HEAD"], text=True, stderr=subprocess.DEVNULL).strip()
    except (OSError, subprocess.SubprocessError) as error:
        raise EvidenceError("cannot verify checkout commit") from error
    if head != profile["source_commit"]:
        raise EvidenceError("checkout commit mismatch")
    if not isinstance(profile["conditions"], dict) or not profile["conditions"] or not all(
        isinstance(k, str) and IDENT.fullmatch(k) and type(v) is bool for k, v in profile["conditions"].items()
    ):
        raise EvidenceError("explicit compilation conditions required")
    if not isinstance(review, dict) or set(review) != {"reviewer", "conditions", "inheritance"} or not all(
        isinstance(review[k], str) and review[k].strip() for k in review
    ):
        raise EvidenceError("condition and inheritance review required")
    if not isinstance(expected, dict) or set(expected) != set(TARGETS) or not isinstance(excluded, dict) or set(excluded) != set(TARGETS):
        raise EvidenceError("expected targets incomplete")
    tests = set()
    for target in TARGETS:
        methods = expected[target]
        if not isinstance(methods, list) or not methods:
            raise EvidenceError("each target needs reviewed methods")
        omitted = excluded[target]
        if not isinstance(omitted, dict) or not all(isinstance(k, str) and isinstance(v, str) and v.strip() for k, v in omitted.items()):
            raise EvidenceError("explicit conditional exclusions required")
        if any(not declarations[target].get(method) for method in omitted):
            raise EvidenceError("unconditional test cannot be excluded")
        if set(methods) & set(omitted) or set(methods) | set(omitted) != set(declarations[target]):
            raise EvidenceError("every declaration must be included or explicitly excluded")
        for method in methods:
            if not isinstance(method, str) or not CASE.fullmatch(method):
                raise EvidenceError("unsupported test identity")
            full = target + "/" + method
            if full in tests:
                raise EvidenceError("duplicate expected method")
            tests.add(full)
    return tests


def verify(inventory, root, discovery, execution, summary, log, product):
    expected = validate_inventory(inventory, root)
    if not isinstance(discovery, dict) or discovery.get("schema") != "core-xctest-discovery-v1" or discovery.get("complete") is not True:
        raise EvidenceError("complete native discovery required")
    if discovery.get("snapshot_sha256") != inventory["snapshot"]["sha256"] or discovery.get("profile") != inventory["profile"]:
        raise EvidenceError("discovery source/profile mismatch")
    product = Path(product)
    if product.is_symlink() or not product.is_file():
        raise EvidenceError("product archive unavailable")
    if discovery.get("product_sha256") != file_digest(product):
        raise EvidenceError("product archive mismatch")
    if not isinstance(execution, dict) or execution.get("schema") != "core-xctest-execution-v1":
        raise EvidenceError("execution evidence context required")
    for key in ("snapshot_sha256", "product_sha256", "profile"):
        if execution.get(key) != discovery.get(key):
            raise EvidenceError("execution source/product/profile mismatch")
    if (execution.get("discovery_sha256") != digest(canonical(discovery))
            or execution.get("summary_sha256") != digest(canonical(summary))
            or execution.get("log_sha256") != digest(log.encode("utf-8"))):
        raise EvidenceError("execution evidence contents differ")
    if not all(isinstance(execution.get(k), str) and execution[k].strip() for k in ("run_id", "destination", "runtime")):
        raise EvidenceError("execution identity incomplete")
    discovered = discovery.get("tests")
    if not isinstance(discovered, list) or any(not isinstance(x, str) for x in discovered) or len(discovered) != len(set(discovered)) or set(discovered) != expected:
        raise EvidenceError("native discovery differs from reviewed inventory")
    if not isinstance(summary, dict):
        raise EvidenceError("invalid result summary")
    keys = ("totalTestCount", "passedTests", "failedTests", "skippedTests", "expectedFailures")
    if not all(type(summary.get(k)) is int and summary[k] >= 0 for k in keys):
        raise EvidenceError("invalid result counts")
    if (summary.get("result") != "Passed" or summary["totalTestCount"] != len(expected)
            or summary["passedTests"] != len(expected)
            or any(summary[k] for k in ("failedTests", "skippedTests", "expectedFailures"))):
        raise EvidenceError("incomplete, skipped or failed result")
    seen = {}
    for line in log.splitlines():
        if "Test Case" not in line:
            continue
        match = EVENT.search(line)
        if not match or line.count("Test Case") != 1 or line[match.end():].strip():
            raise EvidenceError("unrecognized test event")
        target, cls, method, outcome = match.groups()
        identity = target + "/" + cls + "/" + method
        seen.setdefault(identity, []).append("started" if outcome == "started." else outcome.split(" ")[0])
    if set(seen) != expected or any(events != ["started", "passed"] for events in seen.values()):
        raise EvidenceError("missing, repeated, unexpected or nonpassing test")
    return {"contract_verified": True, "native_provenance_verified": False,
            "test_count": len(expected), "target_count": len(TARGETS),
            "snapshot_sha256": inventory["snapshot"]["sha256"], "product_sha256": discovery["product_sha256"]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    template = sub.add_parser("template")
    template.add_argument("--root", type=Path, required=True)
    template.add_argument("--output", type=Path, required=True)
    check = sub.add_parser("verify")
    for name in ("root", "inventory", "discovery", "execution", "summary", "log", "product"):
        check.add_argument("--" + name, type=Path, required=True)
    args = parser.parse_args()
    try:
        if args.command == "template":
            head = subprocess.check_output(["git", "-C", str(args.root), "rev-parse", "HEAD"], text=True).strip()
            profile = {"configuration": "Debug", "platform": "iphonesimulator", "conditions": {"DEBUG": True},
                       "source_commit": head}
            args.output.write_text(json.dumps(new_template(args.root, profile), indent=2, sort_keys=True) + "\n")
            print("Draft only: review sources, conditions, inheritance and expected methods before verification")
        else:
            result = verify(read_json(args.inventory), args.root, read_json(args.discovery), read_json(args.execution), read_json(args.summary),
                            read_utf8_exact(args.log), args.product)
            print(json.dumps(result, sort_keys=True))
    except (EvidenceError, OSError, ValueError, TypeError, UnicodeError, subprocess.SubprocessError) as error:
        print("Core XCTest evidence rejected: " + str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
