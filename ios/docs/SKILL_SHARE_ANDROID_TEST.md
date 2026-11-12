# Original iOS skill shares and Android import

This test candidate preserves the existing iOS `ShareLink` path through
`SkillsState.exportMarkdown` and `SkillDocument.shareable`. It changes no product
code. Local metadata is removed as before; the original skill body, headings,
links, and public front matter are not rewritten. Export does not promise that
every destination will accept a particular skill.

`ios/scripts/GenerateAndroidSkillShareFixtures.swift` imports and approves
synthetic skills in the real iOS skills module, then calls the same exporter as
`ShareLink`. `IOSSkillShareImportTest` feeds the resulting unedited files to the
actual Android `SkillImport.prepare` and checks the installed and shared content.
The dedicated workflow builds the Swift modules and Android core and requires
all seven JUnit cases to execute, rather than silently accepting skipped cases.
It generates synthetic data only. Its CI execution and actual iOS share sheet
remain separate validations. On 2026-11-12, the focused local run compiled
Android core and reported 7 tests, 0 skipped, 0 failures and 0 errors in its
JUnit XML.

On the tested source baseline, Android's validator requires its simplified
Chinese section prefixes. A traditional-Chinese-only or English-only skill is
still shareable without alteration, but Android returns `missing_section`. An
iOS document with an indented closing front-matter delimiter is also shared
unchanged; Android returns `invalid_name`. Those outcomes describe Android
import, not a reason to block sharing to other destinations.

The Android parser also currently counts required headings inside fenced blocks,
and accepts the exercised malformed fence info and HTML `<pre>` example. The
corresponding JUnit cases record the actual `Ready` result; they do not assert
that such content is semantically valid, nor do they modify the original body.
Android import yields a pending skill, not an automatically installed skill.

The comparisons against Android `de5be35` found no source differences in
`SkillImport.kt`, `SkillDrafter.kt`, or `FrontMatter.kt` at the iOS baseline
`a5374cf`. The tests run against the Android core in the candidate worktree;
other Android versions and destination applications may behave differently.
