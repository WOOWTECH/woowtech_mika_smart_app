"""Prepare GPL sources for unpublished main versions (and manual audit runs)."""
import os
from pathlib import Path
from publish import GitHub, version_from_sources

version, _ = version_from_sources(Path('app/build.gradle.kts').read_text(), Path('app/brand.gradle.kts').read_text())
event = os.environ['GITHUB_EVENT_NAME']
needed = event == 'workflow_dispatch'
if event == 'push' and os.environ['GITHUB_REF'] == 'refs/heads/main':
    release = GitHub().optional('/releases/tags/v' + version)
    needed = not release or release['draft']
with open(os.environ['GITHUB_OUTPUT'], 'a') as out:
    out.write('needed=' + str(needed).lower() + '\n')
print('version:', version, 'prepare sources:', needed)
