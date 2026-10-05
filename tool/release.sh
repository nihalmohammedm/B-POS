#!/usr/bin/env bash
# Builds all three signed APKs and publishes them as a GitHub Release.
# Usage: tool/release.sh "optional release notes"
set -euo pipefail
cd "$(dirname "$0")/.."
[ -f android/key.properties ] || { echo "Missing android/key.properties (see key.properties.example)"; exit 1; }
VER=$(grep '^version:' pubspec.yaml | awk '{print $2}')
OUT=build/release; rm -rf "$OUT"; mkdir -p "$OUT"
for f in pos:main_pos captain:main_captain kitchen:main_kitchen; do
  flavor=${f%%:*}; target=${f##*:}
  flutter build apk --release --flavor "$flavor" -t "lib/$target.dart"
  cp "build/app/outputs/flutter-apk/app-$flavor-release.apk" "$OUT/bpos-$flavor.apk"
done
gh release create "v$VER" "$OUT"/bpos-*.apk --title "BPOS $VER" --notes "${1:-Update $VER}"
echo "Published v$VER"
