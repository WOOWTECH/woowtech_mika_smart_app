#!/bin/sh
# WOOWTECH fork: brand leak checks. Not part of upstream Mika; see docs-woowtech/FORK.md.
#
#   sh woowtech/tools/brand-check.sh sources      # shipped sources must not point at the upstream repo
#   sh woowtech/tools/brand-check.sh apk <file>   # a built woowtech APK: package, labels, locales, strings
#
# Allowed on purpose: Brand.kt's upstream defaults, the attribution on the licenses page (woow_lic_mika,
# "Copyright 2026 wangzan101") and in the about_author string ("Based on wangzan101/Mika" / "基於 wangzan101/Mika").
# Everything else fails.
set -eu
cd "$(dirname "$0")/../.."

fail=0
say() { printf '%s\n' "$*"; }
bad() { say "FAIL: $*"; fail=1; }

case "${1:-}" in
sources)
    hits=$(grep -rn -E 'github\.com/wangzan101/Mika|repos/wangzan101/Mika' \
        app/src/main/java core/src/main/kotlin core/src/main/resources app/src/main/assets app/src/woowtech 2>/dev/null \
        | grep -v -E '^core/src/main/kotlin/com/wangzan101/mika/core/brand/Brand\.kt:' \
        | grep -v -E '^app/src/woowtech/res/values[^/]*/strings_woowtech_licenses\.xml:[0-9]+:\s*<string name="woow_lic_mika">' \
        | grep -v -E '^app/src/main/java/com/wangzan101/mika/about/MikaLinks\.kt:[0-9]+:\s*// ' || true)
    [ -z "$hits" ] || bad "upstream repo address in shipped sources (route it through Brand):
$hits"
    # Informational: hard-coded "Mika" strings in app code. New ones after an upstream sync need a look.
    n=$(grep -rn --include='*.kt' -E '"[^"]*(^|[^A-Za-z0-9_/.@-])Mika([^A-Za-z0-9_/-]|$)[^"]*"' app/src/main/java | grep -v -E ':\s*(//|\*)' | wc -l | tr -d ' ')
    say "info: $n hard-coded \"Mika\" string lines left in app/src/main/java (model-facing or logs; see docs-woowtech/FORK.md)"
    # Every upstream licenses entry needs its woowtech translation (else it shows upstream's Simplified Chinese).
    untranslated=$(sed -n 's/^ *Entry("\([^"]*\)".*/\1/p' app/src/main/java/com/wangzan101/mika/ui/LicensesScreen.kt | while IFS= read -r name; do
        grep -qF "\"$name\" to Text(" app/src/woowtech/java/com/wangzan101/mika/woowtech/BrandLicenses.kt || say "$name"
    done)
    [ -z "$untranslated" ] || bad "licenses entries without a woowtech translation (add them to woowtech BrandLicenses.kt and strings_woowtech_licenses.xml):
$untranslated"
    ;;
apk)
    apk="${2:?usage: brand-check.sh apk <file.apk>}"
    [ -f "$apk" ] || { say "no such APK: $apk"; exit 2; }
    sdk="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}"
    aapt2=$(ls -d "$sdk"/build-tools/*/aapt2 2>/dev/null | sort -V | tail -n 1)
    [ -n "$aapt2" ] || { say "aapt2 not found under $sdk/build-tools"; exit 2; }
    badging=$("$aapt2" dump badging "$apk")
    say "$badging" | grep -q "^package: name='io.woowtech.agent'" || bad "package is not io.woowtech.agent"
    say "$badging" | grep -q "^application-label:'woowtech agent'" || bad "default label is not 'woowtech agent'"
    say "$badging" | grep -q "^application-label-[^:]*Hant[^:]*:'渥屋助理'" || bad "zh-Hant label is not '渥屋助理'"
    locales=$(say "$badging" | sed -n "s/^locales: //p" | tr -d "'" | tr ' ' '\n' | grep -v -E '^(--_--|en|zh-Hant|b\+zh\+Hant|zh-rHant)$' || true)
    [ -z "$locales" ] || bad "unexpected UI locales: $(say "$locales" | tr '\n' ' ')"
    say "$badging" | grep -E "^(package|application-label|locales)" | sed 's/^/  /'
    strings=$("$aapt2" dump strings "$apk")
    leaks=$(say "$strings" | grep -E '(^|[^A-Za-z0-9_/.@-])Mika([^A-Za-z0-9_/-]|$)|wangzan101' \
        | grep -v -E 'Based on wangzan101/Mika \(Apache-2\.0\)|基於 wangzan101/Mika（Apache-2\.0）|Copyright 2026 wangzan101' || true)
    [ -z "$leaks" ] || bad "resource strings still naming Mika or the upstream repo:
$leaks"
    ;;
*)
    say "usage: brand-check.sh sources | apk <file.apk>"; exit 2 ;;
esac

[ "$fail" -eq 0 ] && say "brand-check $1: OK"
exit "$fail"
