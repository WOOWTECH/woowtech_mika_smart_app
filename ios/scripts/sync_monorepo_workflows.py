#!/usr/bin/env python3
"""Generate root GitHub workflows from the preserved iOS workflow templates."""

import argparse
from pathlib import Path
import sys

IOS = Path(__file__).resolve().parents[1]
ROOT = IOS.parent
TEMPLATES = IOS / ".github/workflows"
DESTINATION = ROOT / ".github/workflows"
NAMES = {
    "ios.yml": "ios-app.yml",
    "core-native-diagnostic.yml": "ios-core-native-diagnostic.yml",
    "release-ios.yml": "ios-release.yml",
    "live-model.yml": "ios-live-model.yml",
    "live-mcp.yml": "ios-live-mcp.yml",
    "skill-worker-container.yml": "ios-skill-worker-container.yml",
    "android-ui-reference.yml": "ios-android-ui-reference.yml",
}
HEADER = "# Generated from ios/.github/workflows; run ios/scripts/sync_monorepo_workflows.py.\n"


def render(name):
    source = (TEMPLATES / name).read_text(encoding="utf-8")
    run_defaults = "defaults:\n  run:\n    shell: bash\n"
    if run_defaults in source:
        source = source.replace(run_defaults, run_defaults + "    working-directory: ios\n", 1)
    else:
        assert "\njobs:\n" in source
        source = source.replace("\njobs:\n", "\ndefaults:\n  run:\n    shell: bash\n    working-directory: ios\n\njobs:\n", 1)
    if name == "ios.yml":
        before = "  pull_request:\n  push:\n    branches: [main]\n"
        after = ("  pull_request:\n    paths: ['ios/**', '.github/workflows/ios-*.yml']\n"
                 "  push:\n    branches: [main]\n"
                 "    paths: ['ios/**', '.github/workflows/ios-*.yml']\n")
        assert before in source
        source = source.replace(before, after, 1)
    if name == "android-ui-reference.yml":
        before = ('          git clone --depth 1 https://github.com/WOOWTECH/woowtech_mika_smart_app.git "$RUNNER_TEMP/woow-android-reference"\n'
                  '          python3 scripts/check_android_ui_reference.py --android-repo "$RUNNER_TEMP/woow-android-reference"')
        after = '          python3 scripts/check_android_ui_reference.py --android-repo "$GITHUB_WORKSPACE"'
        assert before in source
        source = source.replace(before, after, 1)
        source = source.replace('"$RUNNER_TEMP/woow-android-reference"', '"$GITHUB_WORKSPACE"')
    # upload-artifact resolves paths from the checkout root, not defaults.run.
    lines = source.splitlines(keepends=True)
    in_paths = False
    for index, line in enumerate(lines):
        if line == "          path: |\n":
            in_paths = True
            continue
        if in_paths and not line.startswith("            "):
            in_paths = False
        if in_paths and line.startswith("            build/"):
            lines[index] = line.replace("            build/", "            ios/build/", 1)
        elif line.startswith("          path: build/"):
            lines[index] = line.replace("          path: build/", "          path: ios/build/", 1)
    return HEADER + "".join(lines)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    if not DESTINATION.is_dir():
        parser.error("Expected the Android monorepo with .github/workflows")
    mismatches = []
    for template, output in NAMES.items():
        path = DESTINATION / output
        content = render(template)
        if args.check:
            if not path.is_file() or path.read_text(encoding="utf-8") != content:
                mismatches.append(str(path.relative_to(ROOT)))
        else:
            path.write_text(content, encoding="utf-8")
    if mismatches:
        print("Generated workflows need synchronization: " + ", ".join(mismatches), file=sys.stderr)
        return 1
    print(("Checked " if args.check else "Generated ") + str(len(NAMES)) + " iOS workflows")
    return 0


if __name__ == "__main__":
    sys.exit(main())
