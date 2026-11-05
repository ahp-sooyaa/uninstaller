#!/bin/sh
# Builds Uninstaller and installs it to /Applications.
set -e
cd "$(dirname "$0")"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
BUILT=build/Build/Products/Release/Uninstaller.app

xcodegen generate --quiet
xcodebuild -project Uninstaller.xcodeproj -scheme Uninstaller -configuration Release \
  -derivedDataPath build CODE_SIGN_IDENTITY=- build -quiet

pkill -x Uninstaller || true
pkill -x FinderExtension || true
ditto "$BUILT" /Applications/Uninstaller.app
# ditto leaves the bundle's own mod date alone, and icon caches key on it.
touch /Applications/Uninstaller.app

# Only the installed copy should handle the URL scheme and provide the extension.
"$LSREGISTER" -u "$PWD/$BUILT"
"$LSREGISTER" -f /Applications/Uninstaller.app
pluginkit -a /Applications/Uninstaller.app/Contents/PlugIns/FinderExtension.appex
echo "Installed. Turn on Uninstaller under Finder extensions in System Settings if you haven't."
