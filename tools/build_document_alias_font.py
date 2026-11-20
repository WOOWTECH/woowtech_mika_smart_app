#!/usr/bin/env python3
"""Rebuild the OFL document alias font using fonttools==4.60.2.

Use the pinned source URL in app/src/main/assets/fonts/README.txt.
No network access or Gradle dependency is needed.
"""
from pathlib import Path
import sys
import fontTools
from collections import defaultdict
from copy import deepcopy
import json,hashlib
from fontTools.ttLib import TTFont
from fontTools import subset
from fontTools.varLib.instancer import instantiateVariableFont
assert fontTools.__version__ == '4.60.2', 'Use fonttools==4.60.2 for reproducibility'
if len(sys.argv) != 3: raise SystemExit('Usage: build_document_alias_font.py SOURCE.ttf OUTPUT.ttf')
source, output = map(Path, sys.argv[1:])
assert hashlib.sha256(source.read_bytes()).hexdigest() == '864727d210d54f2537bbe23b3a839436c3992af72de9322af5270897246bd44f', 'Unexpected source font'
f=TTFont(source,recalcTimestamp=False)
byglyph=defaultdict(list)
for cp,g in f.getBestCmap().items():byglyph[g].append(cp)
aliases={g:cs for g,cs in byglyph.items() if len(cs)>1}
print('aliases',len(aliases),'codepoints',sum(map(len,aliases.values())),flush=True)
assert f.getBestCmap()[0x6587]==f.getBestCmap()[0x2f42]
options=subset.Options();options.layout_features=[];options.name_IDs=['*'];options.name_legacy=True;options.name_languages=['*']
s=subset.Subsetter(options=options);s.populate(unicodes=[cp for cs in aliases.values() for cp in cs]);s.subset(f)
f=instantiateVariableFont(f,{'wght':400},inplace=True)
# Each Unicode scalar gets a separate glyph ID, even when outlines are identical.
order=list(f.getGlyphOrder())
for original,cps in aliases.items():
 for cp in cps[1:]:
  name=f'pdfuni{cp:X}'
  f['glyf'][name]=deepcopy(f['glyf'][original]);f['hmtx'][name]=f['hmtx'][original]
  if 'vmtx' in f:f['vmtx'][name]=f['vmtx'][original]
  order.append(name)
  for table in f['cmap'].tables:
   if table.isUnicode() and cp in table.cmap:table.cmap[cp]=name
f.setGlyphOrder(order)
for tag in ['GSUB','GPOS','GDEF','DSIG']:
 if tag in f:del f[tag]
for name in f['name'].names:
 if name.nameID in [1,2,3,4,6,16,17,25]:
  value='Regular' if name.nameID in [2,17] else ('ApporoDocumentAliases-Regular' if name.nameID==6 else 'Apporo Document Aliases')
  name.string=value.encode(name.getEncoding())
out=output;f.save(out)
verified=TTFont(out);cm=verified.getBestCmap();assert len(set(cm.values()))==len(cm)
assert cm[0x6587]!=cm[0x2f42]
report={'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'font_sha256':hashlib.sha256(out.read_bytes()).hexdigest(),'bytes':out.stat().st_size,'scalars':len(cm),'glyphs':len(verified.getGlyphOrder()),'aliases':{g:[f'U+{cp:04X}' for cp in cps] for g,cps in aliases.items()}}
assert report['font_sha256'] == 'fa4fa5671d64fa5983c1c3bc2fe176adae8e892d4310f74af09498c504bd453c', 'Non-reproducible font output'
print(json.dumps(report, indent=2))
