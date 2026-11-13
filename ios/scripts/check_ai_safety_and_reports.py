#!/usr/bin/env python3
"""Play's AI safety rules on every model request, and AI reply reports.

The rules: their text against the Play build (docs/evidence), and a source audit
that every model request site sends them. Reports: the Swift harness in Debug and
Release, through a scripted transport. No network, Keychain or App container.
"""
import argparse
import json
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
EVIDENCE = 'docs/evidence/play-964d7bec-ai-safety-reports.json'
REPORT_SOURCES = ['Sources/App/AIResponseReports.swift', 'Sources/App/AIResponseReportDelivery.swift',
                  'Sources/App/AIResponseReportService.swift']

# Each model request site and how it sends the rules. Play sends its identity
# prompt and the rules on every run and child run (TaskRun.kt); iOS runs are
# separate, so each one appends the identity line and the rules to its own
# instructions, or sends them alone when it has none.
COVERED = {
    # Ordinary chat: the skill tools offer when there is one, then the rules.
    'Sources/App/ChatSession.swift': [
        'let messages = [AISafetyRules.systemMessage(instructions: skillIndex.map { ChatSkillPrompts.entry(index: $0, plainChat: true) })] + input'],
    # The skill tools step of an ordinary chat.
    'Sources/AssistantSkills/ChatSkillTools.swift': [
        'let system = ModelMessage(role: "system", content: AISafetyRules.appended(to: ChatSkillPrompts.run(index: catalog().index())))'],
    # Ordinary chat with memory and profile tools (and the skill tools offer after them).
    'Sources/AssistantMemory/UserProfileChatFlow.swift': ['public static let instructions = AISafetyRules.appended(to: """'],
    'Sources/AssistantMCP/MCPConversationRunner.swift': ['system = AISafetyRules.appended(to: system)'],
    # Website research and route replay answers, and proposed browser actions.
    'Sources/AssistantBrowser/WebResearchRunner.swift': ['let system = AISafetyRules.appended(to: """'],
    'Sources/App/BrowserSession.swift': ['let system = AISafetyRules.appended(to: """'],
    'Sources/AssistantBrowser/BrowserInteractionPlanner.swift': ['private static let instructions = AISafetyRules.appended(to: """'],
    # Web tasks started from chat: every step of the task.
    'Sources/AssistantBrowser/ChatWebTaskRunner.swift': ['return AISafetyRules.appended(to: """'],
    # Background requests whose text the user sees: memories and skill drafts.
    'Sources/AssistantMemory/MemoryExtractor.swift': ['private static let instructions = AISafetyRules.appended(to: """'],
    'Sources/AssistantSkills/SkillLearningService.swift': ['private static let draftInstructions = AISafetyRules.appended(to: """'],
    # Model-written skills (no screen opens it now; kept in the module).
    'Sources/AssistantSkills/SkillToolSession.swift': ['private static let instructions = AISafetyRules.appended(to: """'],
}
# Instructions without the rules, and why.
EXEMPT = {
    'Sources/AssistantSkills/SkillLearningService.swift': {
        'private static let judgeInstructions = """': 'outcome judge: an internal yes/no assessment, never shown or acted on',
    },
}
# Requests that need no rules: the fixed connection test, whose reply only tells
# whether the service answered and is never shown.
EXEMPT_FILES = {'Sources/AssistantModels/ModelConnectionCheck.swift'}
# Clients that only pass a request on, and the test fixture.
PASS_THROUGH = {'Sources/App/LearningRunContext.swift', 'Sources/App/UITestModelFixture.swift'}
REQUEST = re.compile(r'\.(complete|stream)\(\s*messages:')
SYSTEM = re.compile(r'role: *"system"')
INSTRUCTIONS = re.compile(r'static let [A-Za-z]*[Ii]nstructions = (.*)$')


def swift_literal(source, name):
    match = re.search(r'public static let ' + name + r' = """\n    (.*?)\n    """', source, re.S)
    return match.group(1) if match else None


def rules_audit(root, overrides=None):
    """overrides maps a relative path to changed text, or None for a removed file (mutation tests)."""
    overrides = overrides or {}

    def read(relative):
        if relative in overrides:
            return overrides[relative] or ''
        return (root / relative).read_text() if (root / relative).exists() else ''

    evidence = json.loads((root / EVIDENCE).read_text())
    source = read('Sources/AssistantModels/AISafetyRules.swift')
    text = swift_literal(source, 'text')
    expected = evidence['safety_rules'].replace(evidence['safety_rules_edition'], 'App Store edition safety rules', 1)
    failures = []
    if evidence['source_commit'] != '964d7becff9a0daa228f24cc5c8e2664fde8b7d9':
        failures.append('evidence is not from Play 964d7bec')
    if text != expected:
        failures.append('AISafetyRules.text differs from the Play rules beyond the edition name')
    identity = re.search(r'public static let identity = "(.*)"', source)
    if not identity or not identity.group(1).startswith("You are woowtech agent (渥屋助理 in Traditional Chinese), the user's personal assistant"):
        failures.append("the identity line does not follow Play's with the app's names (woowtech agent, 渥屋助理)")
    if 'public static let prompt = identity + "\\n\\n" + text' not in source:
        failures.append('the safety prompt must be the identity line, then the rules')
    if 'instructions + "\\n\\n" + prompt' not in source:
        failures.append('appended(to:) must put the identity line and the rules after the instructions')
    if 'public static let message = ModelMessage(role: "system", content: prompt)' not in source:
        failures.append('a request without instructions must send the identity line and the rules alone')
    sites = {}
    paths = {str(path.relative_to(root)) for path in (root / 'Sources').rglob('*.swift')} | set(overrides)
    for relative in sorted(paths):
        if relative == 'Sources/AssistantModels/AISafetyRules.swift' or overrides.get(relative, '') is None:
            continue
        body = read(relative)
        if REQUEST.search(body) or SYSTEM.search(body):
            sites[relative] = body
    unexpected = sorted(set(sites) - set(COVERED) - PASS_THROUGH - EXEMPT_FILES)
    if unexpected:
        failures.append('model request sites not reviewed for the safety rules: ' + ', '.join(unexpected))
    for relative, patterns in COVERED.items():
        body = read(relative)
        for pattern in patterns:
            if body.count(pattern) != 1:
                failures.append(f'{relative}: expected once: {pattern}')
        for line in body.splitlines():
            match = INSTRUCTIONS.search(line.strip())
            if match and 'AISafetyRules.appended' not in line:
                declaration = line.strip()
                reason = EXEMPT.get(relative, {}).get(declaration)
                if reason is None and match.group(1) == '"""':
                    # Text spliced into other instructions or user messages is not a request of its own.
                    name = re.search(r'let ([A-Za-z]+)', declaration).group(1)
                    if re.search(r'content: *(Self\.)?' + name + r'\b', body):
                        failures.append(f'{relative}: {name} is sent as instructions without the rules')
    missing = sorted(relative for relative in set(COVERED) | EXEMPT_FILES if relative not in sites)
    if missing:
        failures.append('listed request sites no longer send requests (update the list): ' + ', '.join(missing))
    return {'rules_match_play': text == expected, 'covered_sites': len(COVERED), 'exempt': EXEMPT,
            'exempt_files': sorted(EXEMPT_FILES), 'pass_through': sorted(PASS_THROUGH)}, failures


def reports_harness(root, sources, scratch, configs=('Debug', 'Release')):
    lines = []
    for config, flags in [('Debug', ['-DDEBUG']), ('Release', [])]:
        if config not in configs:
            continue
        binary = Path(scratch) / ('ai-reports-' + config)
        subprocess.run(['swiftc', '-swift-version', '5', '-warnings-as-errors', '-parse-as-library', *flags, *map(str, sources),
                        str(root / 'scripts/CheckAIResponseReports.swift'), '-o', str(binary)],
                       cwd=root, check=True, timeout=600)
        result = subprocess.run([str(binary), scratch], cwd=root, capture_output=True, text=True, timeout=120)
        lines.append(result.stdout.strip())
        if result.returncode:
            raise SystemExit(result.stdout + result.stderr)
    return lines


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', action='append', type=Path, default=[],
                        help='replace one report source with a changed copy (mutation tests)')
    parser.add_argument('--rules-only', action='store_true')
    parser.add_argument('--config', choices=['Debug', 'Release'], help='build one configuration only')
    args = parser.parse_args()
    sources = [ROOT / s for s in REPORT_SOURCES]
    for changed in args.source:
        sources = [changed.resolve() if s.name == changed.name else s for s in sources]
    summary, failures = rules_audit(ROOT)
    for failure in failures:
        print('FAIL: ' + failure)
    if failures:
        raise SystemExit(1)
    print('PASS AI safety rules: Play 964d7bec text, ' + str(summary['covered_sites']) + ' request sites')
    if not args.rules_only:
        with tempfile.TemporaryDirectory(prefix='woow-ai-reports-') as scratch:
            for line in reports_harness(ROOT, sources, scratch, [args.config] if args.config else ('Debug', 'Release')):
                print(line)


if __name__ == '__main__':
    main()
