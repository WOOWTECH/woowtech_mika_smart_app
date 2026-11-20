Apporo Document Aliases Regular — modified Noto Sans TC, SIL OFL 1.1.
Copyright 2014-2021 Adobe (http://www.adobe.com/), with Reserved Font Name 'Source'.
See ApporoDocumentAliases-OFL.txt. The derivative family uses a different name.

Source: Google Fonts commit 3be1884c48c3e45b52ecc725676a08f87776373e
https://raw.githubusercontent.com/google/fonts/3be1884c48c3e45b52ecc725676a08f87776373e/ofl/notosanstc/NotoSansTC%5Bwght%5D.ttf
Source SHA-256: 864727d210d54f2537bbe23b3a839436c3992af72de9322af5270897246bd44f
Derived SHA-256: fa4fa5671d64fa5983c1c3bc2fe176adae8e892d4310f74af09498c504bd453c

Rebuild: python3 tools/build_document_alias_font.py SOURCE.ttf OUTPUT.ttf
Requires fonttools==4.60.2 only for rebuilding; not an app or Gradle dependency.

The 165380-byte static weight-400 TrueType font contains 867 Unicode scalars
from 427 shared-glyph groups. Each scalar gets a distinct glyph ID and original
outlines/metrics; Unicode cmap tables agree. GSUB/GPOS/GDEF are omitted to avoid
shaping aliases back into a shared ID. Other characters use Android sans-serif
fallback. This fixes observed CJK/radical alias corruption in PdfDocument's
reverse glyph-to-Unicode mapping without normalizing or rewriting source text.
Coverage outside this font is still platform-dependent, not a universal Unicode
guarantee. Regular/bold mixing, extraction and pagination require native tests.
