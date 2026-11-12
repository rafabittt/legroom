#!/bin/zsh
# Development build into build.noindex/, kept out of Spotlight and Launch Services
# so the system only sees the Legroom installed in /Applications.
# Usage: tools/build.sh [Debug|Release]
# Without the maintainer's certificates, sign ad hoc: LEGROOM_ADHOC=1 tools/build.sh
# (the app works; the widget can't read the shared App Group and shows less).
set -euo pipefail
cd "$(dirname "$0")/.."
CONFIG=${1:-Debug}
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
SIGNING=()
[[ "${LEGROOM_ADHOC:-0}" == 1 ]] && SIGNING=(CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= OTHER_CODE_SIGN_FLAGS=)

xcodegen generate >/dev/null
xcodebuild -project Legroom.xcodeproj -scheme Legroom -configuration "$CONFIG" \
  -derivedDataPath build.noindex build -quiet "${SIGNING[@]}"
APP="$PWD/build.noindex/Build/Products/$CONFIG/Legroom.app"
# xcodebuild registers the app on every build; without this it becomes one more
# "Legroom" in Spotlight and competes with the installed copy for widgets.
"$LSREGISTER" -u "$APP" >/dev/null 2>&1 || true
echo "✓ $APP"
