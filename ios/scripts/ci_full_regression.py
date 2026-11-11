#!/usr/bin/env python3
"""Plan and verify bounded, exact XCTest slices for the non-Live CI regression."""

import argparse
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import time

from release_ios17 import TEST_SCOPES, UI_SHARDS, test_completion, ui_inventory


IPHONES = (
    {"label": "ios18-compact", "xcode": "16.4", "runtime": "iOS-18-5", "device": "iPhone SE (3rd generation)"},
    {"label": "ios18-large", "xcode": "16.4", "runtime": "iOS-18-5", "device": "iPhone 16 Pro Max"},
    {"label": "ios26-current", "xcode": "26.2", "runtime": "iOS-26-2", "device": "iPhone 17"},
)
IPAD = {"label": "ios26-ipad", "xcode": "26.2", "runtime": "iOS-26-2", "device": "iPad (A16)"}
IPAD_ONLY = "WoowAssistantUITests/WoowAssistantUITests/testRealIPadReadOnlyNavigationAudit"
# A full run needs two portable Xcode builds and 22 test-only jobs. A selected
# manual iPhone needs one build and seven jobs. Every shard keeps its own result.
COHORTS = (
    ("ui-startup", "ui-pdf-capability"),
    ("ui-documents", "ui-download-pdf"),
    ("ui-workspace", "ui-browser"),
    ("ui-learning", "ui-language", "ui-notifications", "core"),
    ("ui-memory", "ui-profile"),
    ("ui-memory-tools", "ui-skills"),
    ("ui-mcp", "ui-archive"),
)
SLICE_SECONDS = 30 * 60
COHORT_SECONDS = 55 * 60
SELECTIONS = {"all": IPHONES, "current": IPHONES[2:],
              "compact": IPHONES[:1], "large": IPHONES[1:2]}


def source_sha(root):
    return subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=root, text=True).strip()


def selection_from_flags(current_only=False, compact_only=False, large_only=False):
    """Keep the preexisting workflow_dispatch precedence when flags overlap."""
    return ("current" if current_only else "compact" if compact_only else
            "large" if large_only else "all")


def make_plan(root, *, current_only=False, compact_only=False, large_only=False,
              fresh_simulator=True):
    if type(fresh_simulator) is not bool:
        raise ValueError("Simulator freshness must be a boolean")
    selection = selection_from_flags(current_only, compact_only, large_only)
    iphones = SELECTIONS[selection]
    catalog = ui_inventory(root)
    if len(UI_SHARDS) != 15 or set(catalog["shards"]) != set(UI_SHARDS):
        raise ValueError("The 15 owned UI shards changed; review the CI partition")
    cohort_scopes = [scope for group in COHORTS for scope in group]
    if len(cohort_scopes) != 16 or set(cohort_scopes) != set(UI_SHARDS) | {"core"}:
        raise ValueError("Every UI shard and core must have exactly one cohort owner")
    if IPAD_ONLY not in catalog["shards"]["ui-startup"]["tests"]:
        raise ValueError("The iPad-only method must be owned by ui-startup")
    sha = source_sha(root.parent)
    rows = []
    for device in iphones:
        for index, scopes in enumerate(COHORTS, start=1):
            slices = []
            for scope in scopes:
                methods = ([] if scope == "core" else
                           [method for method in catalog["shards"][scope]["tests"] if method != IPAD_ONLY])
                selectors = TEST_SCOPES["core"] if scope == "core" else methods
                slices.append({"scope": scope, "methods": methods,
                               "selectors": ["-only-testing:" + method for method in selectors]})
            rows.append({**device, "id": f"{device['label']}-cohort-{index:02d}",
                         "slices": slices, "selection": selection,
                         "fresh_simulator": fresh_simulator, "source_sha": sha,
                         "inventory_sha256": catalog["inventory_sha256"]})
    if selection == "all":
        rows.append({**IPAD, "id": "ios26-ipad-ui-startup-audit",
                     "slices": [{"scope": "ui-startup", "methods": [IPAD_ONLY],
                                 "selectors": ["-only-testing:" + IPAD_ONLY]}],
                     "selection": selection, "fresh_simulator": fresh_simulator,
                     "source_sha": sha, "inventory_sha256": catalog["inventory_sha256"]})
    return {"version": 1, "source_sha": sha, "inventory_sha256": catalog["inventory_sha256"],
            "selection": selection, "fresh_simulator": fresh_simulator,
            "iphone_labels": [device["label"] for device in iphones], "rows": rows}


def verify_plan(plan, catalog):
    rows = plan["rows"]
    selection = plan["selection"]
    if selection not in SELECTIONS or type(plan["fresh_simulator"]) is not bool:
        raise ValueError("Invalid selected device or simulator mode")
    iphones = SELECTIONS[selection]
    expected_jobs = len(iphones) * len(COHORTS) + (selection == "all")
    if (plan["version"] != 1 or plan["inventory_sha256"] != catalog["inventory_sha256"]
            or len(rows) != expected_jobs
            or len(rows) != len({row["id"] for row in rows})
            or plan["iphone_labels"] != [device["label"] for device in iphones]):
        raise ValueError("Selected device cohort jobs do not match the plan")
    expected = {method for shard in catalog["shards"].values() for method in shard["tests"]}
    if expected & set(catalog["live_tests_excluded"]):
        raise ValueError("Live cases cannot enter the non-Live plan")
    for device in iphones:
        label = device["label"]
        own_rows = [row for row in rows if row["label"] == label]
        if (len(own_rows) != len(COHORTS)
                or {row["id"] for row in own_rows} !=
                {f"{label}-cohort-{i:02d}" for i in range(1, len(COHORTS) + 1)}):
            raise ValueError("Device cohort identity or count changed")
        ui = [method for row in own_rows for sl in row["slices"] if sl["scope"] != "core"
              for method in sl["methods"]]
        if len(ui) != len(expected) - 1 or set(ui) != expected - {IPAD_ONLY}:
            raise ValueError("Each iPhone must execute every eligible UI method exactly once")
        if [sl["scope"] for row in own_rows for sl in row["slices"]].count("core") != 1:
            raise ValueError("Each iPhone must execute core exactly once")
        for index, row in enumerate(own_rows, start=1):
            if [sl["scope"] for sl in row["slices"]] != list(COHORTS[index - 1]):
                raise ValueError("Cohort shard ownership changed")
    ipad = [row for row in rows if row["label"] == IPAD["label"]]
    if selection == "all":
        if (len(ipad) != 1 or ipad[0]["id"] != "ios26-ipad-ui-startup-audit"
                or len(ipad[0]["slices"]) != 1 or ipad[0]["slices"][0]["methods"] != [IPAD_ONLY]):
            raise ValueError("The iPad audit must execute once on an iPad")
    elif ipad:
        raise ValueError("Selected manual iPhone plan cannot include an iPad")
    for row in rows:
        if row["source_sha"] != plan["source_sha"] or row["inventory_sha256"] != plan["inventory_sha256"]:
            raise ValueError("Slice source or inventory identity changed")
        if row["selection"] != selection or row["fresh_simulator"] is not plan["fresh_simulator"]:
            raise ValueError("Row selection or simulator mode differs from the plan")
        device = next((x for x in (*IPHONES, IPAD) if x["label"] == row["label"]), None)
        if device is None or any(row[key] != device[key] for key in ("xcode", "runtime", "device")):
            raise ValueError("Unexpected simulator identity")
        for sl in row["slices"]:
            scope = sl["scope"]
            expected_methods = [] if scope == "core" else ([IPAD_ONLY] if row["label"] == IPAD["label"]
                else [x for x in catalog["shards"][scope]["tests"] if x != IPAD_ONLY])
            selectors = TEST_SCOPES["core"] if scope == "core" else expected_methods
            if sl["methods"] != expected_methods or sl["selectors"] != ["-only-testing:" + x for x in selectors]:
                raise ValueError("Shard methods or selectors differ from inventory")


def materialize(root, row, output):
    selection = row["selection"]
    if selection not in SELECTIONS or type(row["fresh_simulator"]) is not bool:
        raise ValueError("Invalid row selection or simulator mode")
    plan = make_plan(root, current_only=selection == "current",
                     compact_only=selection == "compact", large_only=selection == "large",
                     fresh_simulator=row["fresh_simulator"])
    expected = next((item for item in plan["rows"] if item["id"] == row["id"]), None)
    if expected is None or row != expected:
        raise ValueError("Runner row differs from the planned source, inventory, or selectors")
    output.mkdir(parents=True, exist_ok=True)
    (output / "full-row.json").write_text(json.dumps(row, indent=2) + "\n")


def finish(row, sl, summary_path, log_path, exit_code):
    receipt = {"id": row["id"] + ":" + sl["scope"], "source_sha": row["source_sha"],
               "inventory_sha256": row["inventory_sha256"], "expected_methods": sl["methods"],
               "exit_code": exit_code, "verified": False, "reason": "summary_or_log_unavailable"}
    if not summary_path.is_file() or not log_path.is_file():
        return receipt
    try:
        summary = json.loads(summary_path.read_text())
        completion = test_completion(summary, log_path, sl["methods"], sl["scope"] != "core")
    except (OSError, ValueError, TypeError, KeyError):
        receipt["reason"] = "invalid_test_summary_or_log"
        return receipt
    receipt.update(completion)
    receipt["verified"] = bool(receipt["verified"] and exit_code == 0)
    if sl["scope"] == "core":
        log = log_path.read_text(errors="replace")
        suite_pattern = re.compile(r"Test Suite '([A-Za-z0-9]+Tests)\.xctest' passed at ")
        suites = suite_pattern.findall(log)
        expected = TEST_SCOPES["core"]
        receipt["core_suites_passed"] = suites
        receipt["verified"] = bool(receipt["verified"] and sorted(suites) == sorted(expected))
    receipt["reason"] = "complete" if receipt["verified"] else "incomplete_or_failed_test_selection"
    return receipt


def test_command(products, simulator_id, result, sl):
    return ["xcodebuild", "test-without-building", "-testProductsPath", str(products),
            "-destination", "platform=iOS Simulator,id=" + simulator_id,
            "-resultBundlePath", str(result), "-parallel-testing-enabled", "NO",
            "-test-timeouts-enabled", "YES", "-default-test-execution-time-allowance", "240",
            "-maximum-test-execution-time-allowance", "420" if sl["scope"] == "ui-workspace" else "300",
            *sl["selectors"], "CODE_SIGN_IDENTITY=-", "CODE_SIGNING_ALLOWED=YES"]


def product_directory(products):
    apps = list(products.rglob("WoowAssistant.app")) if products.is_dir() else []
    if len(apps) != 1 or not apps[0].is_dir() or apps[0].is_symlink():
        raise ValueError("Portable test bundle must contain one real WoowAssistant.app")
    return apps[0].parent


def bounded_process(command, log_path, seconds):
    """One attempt; kill the process group on timeout, retaining its partial log."""
    start = time.monotonic()
    with log_path.open("wb") as log:
        process = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT,
                                   start_new_session=True)
        while True:
            remaining = seconds - (time.monotonic() - start)
            if remaining <= 0:
                try:
                    os.killpg(process.pid, signal.SIGTERM)
                except ProcessLookupError:
                    pass
                try:
                    process.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    try:
                        os.killpg(process.pid, signal.SIGKILL)
                    except ProcessLookupError:
                        pass
                    process.wait()
                return None
            try:
                return process.wait(timeout=min(60, remaining))
            except subprocess.TimeoutExpired:
                print("CI shard still running after %d seconds" % int(time.monotonic() - start), flush=True)


def execute(row, products, simulator_id, output):
    output.mkdir(parents=True, exist_ok=True)
    deadline = time.monotonic() + COHORT_SECONDS
    receipts = []
    for sl in row["slices"]:
        scope = sl["scope"]
        folder = output / scope
        folder.mkdir()
        result = folder / "Tests.xcresult"
        log = folder / "ios-tests.log"
        summary = folder / "test-summary.json"
        remaining = deadline - time.monotonic()
        exit_code = None
        if remaining > 0:
            exit_code = bounded_process(test_command(products, simulator_id, result, sl), log,
                                        min(SLICE_SECONDS, remaining))
            if result.is_dir():
                with (folder / "summary-export.log").open("wb") as export_log:
                    try:
                        with summary.open("wb") as report:
                            subprocess.run(["xcrun", "xcresulttool", "get", "test-results", "summary",
                                            "--path", str(result)], stdout=report, stderr=export_log,
                                           check=False, timeout=90)
                    except subprocess.TimeoutExpired:
                        export_log.write(b"xcresult summary export timed out\n")
                # Keep the complete xcresult; exported diagnostics make failures
                # reviewable without another native run.
                if scope == "ui-documents" or exit_code != 0:
                    try:
                        with (folder / "diagnostics-export.log").open("wb") as export_log:
                            subprocess.run(["xcrun", "xcresulttool", "export", "diagnostics",
                                            "--path", str(result), "--output-path", str(folder / "diagnostics")],
                                           stdout=export_log, stderr=subprocess.STDOUT, timeout=120)
                    except subprocess.TimeoutExpired:
                        (folder / "diagnostics-export.log").write_text("diagnostics export timed out\n")
        receipt = finish(row, sl, summary, log, exit_code)
        if remaining <= 0:
            receipt["reason"] = "cohort_budget_exhausted"
        elif exit_code is None:
            receipt["reason"] = "shard_timeout"
        (folder / "full-receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
        receipts.append(receipt)
        print(json.dumps({"id": receipt["id"], "verified": receipt["verified"],
                          "reason": receipt["reason"]}), flush=True)
    return receipts


def aggregate(plan, receipts_dir):
    rows = {row["id"] + ":" + sl["scope"]: (row, sl)
            for row in plan["rows"] for sl in row["slices"]}
    files = sorted(receipts_dir.rglob("full-receipt.json"))
    observed = {}
    duplicates = []
    invalid = []
    for path in files:
        try:
            receipt = json.loads(path.read_text())
            row, sl = rows[receipt["id"]]
            valid = (receipt["source_sha"] == row["source_sha"]
                     and receipt["inventory_sha256"] == row["inventory_sha256"]
                     and receipt["expected_methods"] == sl["methods"]
                     and receipt["exit_code"] == 0 and receipt["verified"] is True)
            if not valid:
                invalid.append(receipt["id"])
            if receipt["id"] in observed:
                duplicates.append(receipt["id"])
            observed[receipt["id"]] = path
        except (OSError, ValueError, TypeError, KeyError):
            invalid.append(str(path.name))
    missing = sorted(rows.keys() - observed.keys())
    extra = sorted(observed.keys() - rows.keys())
    return {"verified": not (missing or extra or duplicates or invalid),
            "selection": plan["selection"], "fresh_simulator": plan["fresh_simulator"],
            "iphone_labels": plan["iphone_labels"],
            "planned_slices": len(rows), "received_slices": len(files),
            "missing": missing, "extra": extra, "duplicates": sorted(duplicates), "invalid": sorted(invalid)}


def require_full(plan):
    if plan["selection"] != "all" or plan["fresh_simulator"] is not True:
        raise ValueError("PR and push require all three iPhones, iPad, and fresh simulators")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    plan_cmd = sub.add_parser("plan")
    plan_cmd.add_argument("--output", type=Path, required=True)
    plan_cmd.add_argument("--github-output", type=Path)
    plan_cmd.add_argument("--current-only", action="store_true")
    plan_cmd.add_argument("--compact-only", action="store_true")
    plan_cmd.add_argument("--large-only", action="store_true")
    plan_cmd.add_argument("--existing-simulator", action="store_true")
    materialize_cmd = sub.add_parser("materialize")
    materialize_cmd.add_argument("--row", required=True)
    materialize_cmd.add_argument("--output", type=Path, required=True)
    products_cmd = sub.add_parser("product-directory")
    products_cmd.add_argument("--bundle", type=Path, required=True)
    execute_cmd = sub.add_parser("execute")
    execute_cmd.add_argument("--row", type=Path, required=True)
    execute_cmd.add_argument("--products", type=Path, required=True)
    execute_cmd.add_argument("--simulator-id", required=True)
    execute_cmd.add_argument("--output", type=Path, required=True)
    finish_cmd = sub.add_parser("finish")
    finish_cmd.add_argument("--row", type=Path, required=True)
    finish_cmd.add_argument("--scope", required=True)
    finish_cmd.add_argument("--summary", type=Path, required=True)
    finish_cmd.add_argument("--log", type=Path, required=True)
    finish_cmd.add_argument("--exit-code", type=int, required=True)
    finish_cmd.add_argument("--output", type=Path, required=True)
    aggregate_cmd = sub.add_parser("aggregate")
    aggregate_cmd.add_argument("--plan", type=Path, required=True)
    aggregate_cmd.add_argument("--receipts", type=Path, required=True)
    aggregate_cmd.add_argument("--output", type=Path, required=True)
    aggregate_cmd.add_argument("--require-full", action="store_true")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    if args.command == "plan":
        plan = make_plan(root, current_only=args.current_only, compact_only=args.compact_only,
                         large_only=args.large_only, fresh_simulator=not args.existing_simulator)
        verify_plan(plan, ui_inventory(root))
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(plan, indent=2) + "\n")
        if args.github_output:
            with args.github_output.open("a") as stream:
                stream.write("matrix=" + json.dumps({"include": plan["rows"]}, separators=(",", ":")) + "\n")
                stream.write("build_matrix=" + json.dumps({"xcode": sorted({row["xcode"]
                    for row in plan["rows"]})}, separators=(",", ":")) + "\n")
        print(json.dumps({"selection": plan["selection"], "fresh_simulator": plan["fresh_simulator"],
                          "jobs": len(plan["rows"]),
                          "slices": sum(len(row["slices"]) for row in plan["rows"]),
                          "iphones": plan["iphone_labels"],
                          "inventory_sha256": plan["inventory_sha256"]}))
    elif args.command == "materialize":
        materialize(root, json.loads(args.row), args.output)
    elif args.command == "product-directory":
        print(product_directory(args.bundle))
    elif args.command == "execute":
        row = json.loads(args.row.read_text())
        materialize(root, row, args.output)
        if not args.products.is_dir():
            raise ValueError("Portable test products are unavailable")
        if not re.fullmatch(r"[0-9A-Fa-f]{8}(?:-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}", args.simulator_id):
            raise ValueError("Invalid simulator UUID")
        receipts = execute(row, args.products, args.simulator_id, args.output)
        if not all(receipt["verified"] for receipt in receipts):
            return 1
    elif args.command == "finish":
        row = json.loads(args.row.read_text())
        sl = next((item for item in row["slices"] if item["scope"] == args.scope), None)
        if sl is None:
            raise ValueError("Unknown row scope")
        receipt = finish(row, sl, args.summary, args.log, args.exit_code)
        args.output.write_text(json.dumps(receipt, indent=2) + "\n")
        print(json.dumps({"id": receipt["id"], "verified": receipt["verified"], "reason": receipt["reason"]}))
        if not receipt["verified"]:
            return 1
    else:
        plan = json.loads(args.plan.read_text())
        verify_plan(plan, ui_inventory(root))
        if plan["source_sha"] != source_sha(root.parent):
            raise ValueError("Aggregate source does not match its checkout")
        if args.require_full:
            require_full(plan)
        report = aggregate(plan, args.receipts)
        args.output.write_text(json.dumps(report, indent=2) + "\n")
        print(json.dumps(report))
        if not report["verified"]:
            return 1
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError, TypeError, KeyError) as error:
        print("Full regression plan or evidence is invalid: " + type(error).__name__, file=sys.stderr)
        sys.exit(1)
