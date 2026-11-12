#!/bin/zsh
# Installs Legroom in /Applications, the one copy meant for everyday use:
# a stable Dock icon, a single app in Spotlight, widgets and menu bar item served from it.
# Usage: tools/install.sh                 → builds Release and installs it
#        tools/install.sh --from <.app>   → installs a ready bundle (e.g. the one release.sh exports)
set -euo pipefail
cd "$(dirname "$0")/.."
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
DEST=/Applications/Legroom.app

if [[ "${1:-}" == "--from" ]]; then
  SRC=${2:?path to the .app}
else
  tools/build.sh Release
  SRC=build.noindex/Build/Products/Release/Legroom.app
fi
codesign --verify --deep --strict "$SRC"

echo "▸ quitting the running Legroom"
osascript -e 'tell application id "com.rafabitt.legroom" to quit' >/dev/null 2>&1 || true
for _ in 1 2 3 4 5 6; do pgrep -x Legroom >/dev/null || break; sleep 0.5; done
pkill -x Legroom 2>/dev/null || true
pkill -x LegroomWidget 2>/dev/null || true

echo "▸ copying to $DEST"
rm -rf "$DEST"
ditto "$SRC" "$DEST"
"$LSREGISTER" -f "$DEST"
open "$DEST"
echo "✓ installed: $(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$DEST/Contents/Info.plist") ($(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$DEST/Contents/Info.plist"))"
