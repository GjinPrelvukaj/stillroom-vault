#!/bin/bash
# Builds build/Stillroom.app. Usage: Scripts/make-app.sh [debug|release]
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-debug}"
swift build -c "$CONFIG"

APP="build/Stillroom.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/$CONFIG/Stillroom" "$APP/Contents/MacOS/Stillroom"
# Every app build is checked for networking code; one that has any isn't made.
Scripts/check-offline.sh "$APP/Contents/MacOS/Stillroom"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>app.gjin.stillroom</string>
    <key>CFBundleName</key><string>Stillroom</string>
    <key>CFBundleDisplayName</key><string>Stillroom</string>
    <key>CFBundleExecutable</key><string>Stillroom</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>26.0</string>
    <key>NSHumanReadableCopyright</key><string>© 2026 Gjin Prelvukaj and Lis Shala</string>
    <key>NSCameraUsageDescription</key><string>Stillroom takes a photo of whoever types a wrong password, for your intruder log.</string>
    <key>NSServices</key>
    <array>
        <dict>
            <key>NSMenuItem</key><dict><key>default</key><string>Move to Stillroom</string></dict>
            <key>NSMessage</key><string>moveToStillroom</string>
            <key>NSPortName</key><string>Stillroom</string>
            <key>NSRequiredContext</key><dict/>
            <key>NSSendFileTypes</key><array><string>public.item</string></array>
        </dict>
    </array>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key><string>Anything</string>
            <key>CFBundleTypeRole</key><string>Viewer</string>
            <key>LSHandlerRank</key><string>None</string>
            <key>LSItemContentTypes</key><array><string>public.item</string><string>public.folder</string></array>
        </dict>
    </array>
</dict>
</plist>
PLIST
# The build day, so Settings can say when this copy is getting old without ever going online (Updates.swift).
/usr/libexec/PlistBuddy -c "Add :StillroomBuilt string $(date -u +%Y-%m-%d)" "$APP/Contents/Info.plist"

# A stable identity keeps the app the same app across rebuilds; ad-hoc when none is installed.
IDENTITY="${STILLROOM_SIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/ {print $2; exit}')}"
# Hardened runtime: no other program can inject code into Stillroom or attach a debugger to read its memory.
# The camera, for the intruder log's photo; the hardened runtime refuses it otherwise.
cat > "build/Stillroom.entitlements" <<'ENT'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>com.apple.security.device.camera</key><true/></dict></plist>
ENT
codesign --force --deep --options runtime --entitlements "build/Stillroom.entitlements" --sign "${IDENTITY:--}" "$APP"
echo "Built $APP (signed with: ${IDENTITY:-ad-hoc})"
