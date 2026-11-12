#!/bin/zsh
# Distribution build of Legroom outside the App Store:
#   archive (Release, Developer ID, Hardened Runtime) → export → DMG → notarization → staple.
#
# One-time prerequisites:
#   1. A "Developer ID Application" certificate (Xcode › Settings › Accounts › Manage Certificates › + ).
#   2. Notarization credentials stored in the Keychain:
#        xcrun notarytool store-credentials legroom-notary \
#          --apple-id YOUR_APPLE_ID --team-id YOUR_TEAM_ID --password APP_SPECIFIC_PASSWORD
#      (app-specific password at appleid.apple.com › Sign-In and Security › App-Specific Passwords)
#
# Usage: tools/release.sh             → notarized dist/Legroom-<version>.dmg
#        tools/release.sh --no-notary → archive + export + DMG only (to test the pipeline)
#        then: tools/install.sh --from dist/export.noindex/Legroom.app → installs in /Applications
#
# Updates: the notarized DMG is signed for Sparkle (EdDSA key in the login Keychain,
# account "legroom", created with Sparkle's generate_keys) and added to appcast.xml.
# Publishing = GitHub Release v<version> with the DMG + pushing appcast.xml.
set -euo pipefail
cd "$(dirname "$0")/.."

PROFILE=${NOTARY_PROFILE:-legroom-notary}
NOTARIZE=1
[[ "${1:-}" == "--no-notary" ]] && NOTARIZE=0

if ! security find-identity -v -p codesigning | grep -q "Developer ID Application"; then
  echo "✗ No 'Developer ID Application' certificate in the Keychain. Create one in Xcode › Settings › Accounts › Manage Certificates." >&2
  exit 1
fi

xcodegen generate >/dev/null   # Info.plist (and the version) comes from project.yml
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Lupa/Info.plist)
BUILD=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Lupa/Info.plist)
DIST=dist
ARCHIVE=$DIST/Legroom.xcarchive
EXPORT=$DIST/export.noindex   # .noindex: keeps the exported app out of Spotlight
DMG=$DIST/Legroom-$VERSION.dmg
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
mkdir -p "$DIST"
rm -rf "$ARCHIVE" "$EXPORT" "$DIST/export" "$DMG"   # DMGs of other versions are kept

echo "▸ archive $VERSION ($BUILD)"
xcodebuild -project Legroom.xcodeproj -scheme Legroom -configuration Release \
  -archivePath "$ARCHIVE" archive -quiet

echo "▸ export (Developer ID)"
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$EXPORT" \
  -exportOptionsPlist tools/ExportOptions.plist -quiet
APP="$EXPORT/Legroom.app"

echo "▸ verifying signature"
codesign --verify --deep --strict --verbose=2 "$APP"
codesign -d --entitlements :- "$APP" 2>/dev/null | head -20 || true

echo "▸ DMG"
STAGE=$DIST/stage.noindex; rm -rf "$STAGE"; mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Legroom" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
codesign --sign "Developer ID Application" --timestamp "$DMG"

if [[ $NOTARIZE == 1 ]]; then
  echo "▸ notarization (may take a few minutes)"
  xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
  echo "▸ staple"
  xcrun stapler staple "$DMG"
  xcrun stapler validate "$DMG"
  echo "▸ Gatekeeper"
  spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG" || true
  echo "▸ appcast (Sparkle update feed)"
  NOTES=dist/notes-$VERSION.html
  if [[ -f $NOTES ]]; then tools/appcast.py "$DMG" "$VERSION" "$BUILD" --notes "$NOTES"
  else tools/appcast.py "$DMG" "$VERSION" "$BUILD"; fi
fi

rm -rf "$STAGE"
# Only the /Applications copy should be visible to the system (tools/install.sh).
for stray in "$PWD/$EXPORT/Legroom.app" "$PWD/$STAGE/Legroom.app"; do "$LSREGISTER" -u "$stray" >/dev/null 2>&1 || true; done
find ~/Library/Developer/Xcode/DerivedData -path "*ArchiveIntermediates/Legroom/*" -name "Legroom.app" -maxdepth 8 \
  -exec "$LSREGISTER" -u {} \; >/dev/null 2>&1 || true
echo "✓ $DMG"
echo "  to use it on this Mac: tools/install.sh --from $EXPORT/Legroom.app"
if [[ $NOTARIZE == 1 ]]; then
  echo "  to ship it: gh release create v$VERSION $DMG, then commit and push appcast.xml"
fi
