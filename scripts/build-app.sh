#!/bin/zsh
# Builds ZoomStat.app (release) into ./build and signs it.
# Signs with the first "Apple Development"/"Developer ID" identity if present so the
# Accessibility grant survives rebuilds; falls back to ad-hoc signing.
set -euo pipefail
cd "${0:A:h}/.."

swift build -c release --product ZoomStat
BIN="$(swift build -c release --show-bin-path)/ZoomStat"

APP=build/ZoomStat.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/ZoomStat"
cp Resources/Info.plist "$APP/Contents/Info.plist"

IDENTITY="${ZOOMSTAT_SIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development|Developer ID Application/ {print $2; exit}')}"
if [[ -n "$IDENTITY" ]]; then
  codesign --force --options runtime --sign "$IDENTITY" "$APP"
else
  codesign --force --sign - "$APP"
fi
echo "Built $APP (signed: ${IDENTITY:-ad-hoc})"
