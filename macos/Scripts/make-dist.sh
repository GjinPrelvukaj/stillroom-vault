#!/bin/bash
# A Stillroom any Mac opens without warnings: signed with your Developer ID, notarized by Apple, and the ticket stapled
# on so it checks out even offline. Makes build/Stillroom.app and build/Stillroom.zip (the one to send).
#
# Needs, once: the notary login in the keychain
#   xcrun notarytool store-credentials vault-notary --apple-id YOUR_APPLE_ID --team-id WP56DL33UR
set -euo pipefail
cd "$(dirname "$0")/.."

ID="${STILLROOM_DIST_IDENTITY:-$(security find-identity -v -p codesigning | awk -F'"' '/Developer ID Application/ {print $2; exit}')}"
[ -n "$ID" ] || { echo "No Developer ID Application certificate in the keychain." >&2; exit 1; }

STILLROOM_SIGN_IDENTITY="$ID" Scripts/make-app.sh release
# Notarization wants a secure timestamp on the signature, so it's signed once more with one.
codesign --force --options runtime --timestamp --entitlements build/Stillroom.entitlements --sign "$ID" build/Stillroom.app
codesign --verify --strict --verbose=2 build/Stillroom.app

ditto -c -k --keepParent build/Stillroom.app build/Stillroom-upload.zip
xcrun notarytool submit build/Stillroom-upload.zip --keychain-profile "${STILLROOM_NOTARY_PROFILE:-vault-notary}" --wait
rm build/Stillroom-upload.zip
xcrun stapler staple build/Stillroom.app

ditto -c -k --keepParent build/Stillroom.app build/Stillroom.zip
spctl --assess --type execute --verbose=2 build/Stillroom.app
echo "Ready: build/Stillroom.app and build/Stillroom.zip (signed: $ID, notarized, stapled)"
# Published on the download page, so a buyer can check the zip is the one made here.
echo "SHA-256 of build/Stillroom.zip (set download.sha256 in website/src/config.ts when it goes up):"
shasum -a 256 build/Stillroom.zip | awk '{print "  " $1}'
