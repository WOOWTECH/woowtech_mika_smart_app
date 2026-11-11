"""Check dispatch gates before any release secret can reach a runner."""

import ast
from pathlib import Path
import re
import unittest

import sync_monorepo_workflows as sync


IOS = Path(__file__).resolve().parents[1]
TEMPLATE = IOS / ".github/workflows/release-ios.yml"
GENERATED = IOS.parent / ".github/workflows/ios-release.yml"
SIGNED = {"signing-preflight", "signed-export", "signed-device-artifact", "signed-testflight"}
SIGNED_SECRET_STEP_COUNTS = {"signing-preflight": 1, "signed-export": 1,
                             "signed-device-artifact": 2, "signed-testflight": 3}
OTHER = {"transporter-check", "ios17-hosted", "ios17-self-hosted"}
MODES = SIGNED | OTHER | {"unsigned-device", "unexpected-mode"}
REFS = {"refs/heads/main", "refs/heads/feature", "refs/tags/v1"}


def jobs(source):
    body = source.split("\njobs:\n", 1)[1]
    headers = list(re.finditer(r"(?m)^  ([a-z][a-z0-9-]*):\s*$", body))
    return {match.group(1): body[match.end():headers[index + 1].start() if index + 1 < len(headers) else len(body)]
            for index, match in enumerate(headers)}


def steps(job):
    headers = list(re.finditer(r"(?m)^      - (?:name|uses): ", job))
    return [job[match.start():headers[index + 1].start() if index + 1 < len(headers) else len(job)]
            for index, match in enumerate(headers)]


def condition(block, indent):
    match = re.search(rf"(?m)^{re.escape(' ' * indent)}if: (.+)$", block)
    if match is None:
        return None
    value = match.group(1).strip()
    if value != ">-":
        return value
    parts = []
    for line in block[match.end():].splitlines():
        if line.strip() and len(line) - len(line.lstrip()) <= indent:
            break
        if line.strip():
            parts.append(line.strip())
    return " ".join(parts)


def enabled(expression, mode, ref):
    """Evaluate only the operators used by these release guards."""
    assert expression is not None
    tree = ast.parse(expression.replace("||", " or ").replace("&&", " and "), mode="eval")

    def evaluate(node):
        if isinstance(node, ast.Expression):
            return evaluate(node.body)
        if isinstance(node, ast.BoolOp):
            values = [evaluate(value) for value in node.values]
            if isinstance(node.op, ast.And):
                return all(values)
            if isinstance(node.op, ast.Or):
                return any(values)
        if isinstance(node, ast.Compare) and len(node.ops) == len(node.comparators) == 1:
            left, right = evaluate(node.left), evaluate(node.comparators[0])
            if isinstance(node.ops[0], ast.Eq):
                return left == right
            if isinstance(node.ops[0], ast.NotEq):
                return left != right
        if isinstance(node, ast.Attribute) and isinstance(node.value, ast.Name):
            values = {("inputs", "mode"): mode, ("github", "ref"): ref}
            return values[(node.value.id, node.attr)]
        if isinstance(node, ast.Constant) and isinstance(node.value, str):
            return node.value
        raise AssertionError(f"Unsupported release condition node: {type(node).__name__}")

    return evaluate(tree)


class ReleaseWorkflowGuardTests(unittest.TestCase):
    def test_modes_and_branch_truth_table(self):
        for path in self.workflow_paths():
            source = path.read_text(encoding="utf-8")
            options = re.search(r"(?m)^        options: \[([^]]+)\]$", source)
            self.assertIsNotNone(options, path)
            self.assertEqual(set(options.group(1).split(", ")), MODES - {"unexpected-mode"})
            blocks = jobs(source)
            self.assertEqual(set(blocks), {"device-build", "transporter-validation", "ios17-validation"})
            guard = condition(blocks["device-build"], 4)
            for mode in MODES:
                for ref in REFS:
                    with self.subTest(path=path.name, mode=mode, ref=ref):
                        self.assertEqual(enabled(guard, mode, ref),
                                         mode == "unsigned-device" or (mode in SIGNED and ref == "refs/heads/main"))

    def test_every_secret_step_is_signed_main_only(self):
        for path in self.workflow_paths():
            blocks = jobs(path.read_text(encoding="utf-8"))
            secret_steps = []
            for name, block in blocks.items():
                parsed = steps(block)
                self.assertEqual(block.count("${{ secrets."),
                                 sum(step.count("${{ secrets.") for step in parsed), path)
                for step in parsed:
                    if "${{ secrets." in step:
                        self.assertEqual(name, "device-build")
                        self.assertIsNotNone(condition(step, 8))
                        secret_steps.append(step)
            self.assertEqual(len(secret_steps), 5, path)
            job_guard = condition(blocks["device-build"], 4)
            for mode in MODES:
                for ref in REFS:
                    executed = [step for step in secret_steps
                                if enabled(job_guard, mode, ref) and enabled(condition(step, 8), mode, ref)]
                    with self.subTest(path=path.name, mode=mode, ref=ref):
                        expected = SIGNED_SECRET_STEP_COUNTS.get(mode, 0) if ref == "refs/heads/main" else 0
                        self.assertEqual(len(executed), expected)
                        if mode == "signed-testflight" and ref == "refs/heads/main":
                            self.assertTrue(any("secrets.ASC_" in step for step in executed))
                        else:
                            self.assertFalse(any("secrets.ASC_" in step for step in executed))
            self.assertTrue(any("secrets.ASC_" in step for step in secret_steps))
            self.assertTrue(any("secrets.IOS_SIGNING_" in step for step in secret_steps))

    def test_monorepo_root_is_generator_output(self):
        if (IOS.parent / "gradlew").is_file():
            self.assertTrue(GENERATED.is_file())
            self.assertEqual(GENERATED.read_text(encoding="utf-8"), sync.render("release-ios.yml"))

    @staticmethod
    def workflow_paths():
        return [TEMPLATE] + ([GENERATED] if GENERATED.is_file() else [])


if __name__ == "__main__":
    unittest.main()
