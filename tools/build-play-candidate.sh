#!/usr/bin/env bash
# Build and verify the Play upload bundle without reading or printing signing secrets.
# PLAY_FLAVOR picks the Play edition: woowtech (default, io.woowtech.assistant) or apporoplay (com.apporo.assistant.play).
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

play_flavor="${PLAY_FLAVOR:-woowtech}"
case "$play_flavor" in
    woowtech)
        : "${WOOWTECH_SIGNING_PROPERTIES:?Set WOOWTECH_SIGNING_PROPERTIES to the private upload signing properties file}"
        signing_properties="$WOOWTECH_SIGNING_PROPERTIES"
        gradle_variant=WoowtechRelease
        expected_package=io.woowtech.assistant
        ;;
    apporoplay)
        : "${APPORO_PLAY_SIGNING_PROPERTIES:?Set APPORO_PLAY_SIGNING_PROPERTIES to the private upload signing properties file}"
        signing_properties="$APPORO_PLAY_SIGNING_PROPERTIES"
        gradle_variant=ApporoplayRelease
        expected_package=com.apporo.assistant.play
        ;;
    *)
        echo "Unknown PLAY_FLAVOR: $play_flavor (expected woowtech or apporoplay)" >&2
        exit 1
        ;;
esac
: "${JAVA_HOME:?Set JAVA_HOME to the JDK 17 directory}"
: "${BUNDLETOOL_JAR:?Set BUNDLETOOL_JAR to a local bundletool all JAR}"

if [[ ! -r "$signing_properties" || ! -r "$BUNDLETOOL_JAR" ]]; then
    echo "Signing properties or bundletool are unavailable" >&2
    exit 1
fi

./gradlew ":app:bundle$gradle_variant" --quiet

bundle="app/build/outputs/bundle/${play_flavor}Release/app-${play_flavor}-release.aab"
verify_log="$(mktemp)"
trap 'rm -f "$verify_log"' EXIT

# jarsigner can return zero for an unsigned JAR, so require its positive result.
if ! "$JAVA_HOME/bin/jarsigner" -verify "$bundle" >"$verify_log" 2>&1 ||
   ! grep -qx 'jar verified\.' "$verify_log"; then
    echo "Release bundle is not signed and verified" >&2
    exit 1
fi

"$JAVA_HOME/bin/java" -jar "$BUNDLETOOL_JAR" validate --bundle="$bundle" >/dev/null
package_name="$("$JAVA_HOME/bin/java" -jar "$BUNDLETOOL_JAR" dump manifest --bundle="$bundle" --xpath=/manifest/@package)"
version_code="$("$JAVA_HOME/bin/java" -jar "$BUNDLETOOL_JAR" dump manifest --bundle="$bundle" --xpath=/manifest/@android:versionCode)"
version_name="$("$JAVA_HOME/bin/java" -jar "$BUNDLETOOL_JAR" dump manifest --bundle="$bundle" --xpath=/manifest/@android:versionName)"
if [[ "$package_name" != "$expected_package" ]]; then
    echo "Unexpected Play package: $package_name" >&2
    exit 1
fi
if ! "$JAVA_HOME/bin/java" -jar "$BUNDLETOOL_JAR" dump config --bundle="$bundle" | grep -F 'PAGE_ALIGNMENT_16K' >/dev/null; then
    echo "Bundle does not declare 16 KB native library alignment" >&2
    exit 1
fi
if unzip -Z1 "$bundle" | grep -Ei 'rootfs|proot|mikarun|mlkit|packages\.json' >/dev/null; then
    echo "Bundle contains a forbidden direct-download runtime component" >&2
    exit 1
fi

printf 'Verified Play bundle: %s\n' "$repo_root/$bundle"
printf 'Source commit: %s\n' "$(git rev-parse --short HEAD)"
printf 'Package: %s  Version: %s (%s)\n' "$package_name" "$version_name" "$version_code"
shasum -a 256 "$bundle"
