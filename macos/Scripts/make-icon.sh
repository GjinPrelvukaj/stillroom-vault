#!/bin/bash
# Redraws Resources/AppIcon.icns from Scripts/make-icon.swift. Run after changing the drawing; the .icns is committed.
set -euo pipefail
cd "$(dirname "$0")/.."
WORK="$(mktemp -d)"; SET="$WORK/AppIcon.iconset"; mkdir -p "$SET" Resources
swift Scripts/make-icon.swift "$WORK/icon.png"
for size in 16 32 128 256 512; do
    sips -z $size $size "$WORK/icon.png" --out "$SET/icon_${size}x${size}.png" >/dev/null
    sips -z $((size * 2)) $((size * 2)) "$WORK/icon.png" --out "$SET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$SET" -o Resources/AppIcon.icns
cp "$WORK/icon.png" Resources/AppIcon.png
rm -rf "$WORK"
echo "Wrote Resources/AppIcon.icns"
