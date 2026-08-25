#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")"

SDK="$(xcrun --sdk macosx --show-sdk-path)"
TARGET="arm64-apple-macos14"
BUILD=".build/swiftc"
APP="dist/GrokIP.app"

mkdir -p "$BUILD" "$APP/Contents/MacOS" "$APP/Contents/Resources/Fonts"

CORE=()
APP_SWIFT=()
for f in Sources/GrokIPCore/**/*.swift; do CORE+=("$f"); done
for f in Sources/GrokIP/**/*.swift; do APP_SWIFT+=("$f"); done

echo "==> Tests"
swiftc -parse-as-library -swift-version 6 -target "$TARGET" -sdk "$SDK" \
  -framework Foundation -framework SystemConfiguration \
  "${CORE[@]}" Tests/RunTests.swift \
  -o "$BUILD/grokip-tests"
"$BUILD/grokip-tests"

echo "==> Release build"
swiftc -parse-as-library -swift-version 6 -O -target "$TARGET" -sdk "$SDK" \
  -framework SwiftUI -framework AppKit -framework Foundation \
  -framework Network -framework SystemConfiguration -framework CoreText \
  -framework UniformTypeIdentifiers \
  "${CORE[@]}" "${APP_SWIFT[@]}" \
  -o "$APP/Contents/MacOS/GrokIP"

cp Info.plist "$APP/Contents/Info.plist"
cp Sources/GrokIPCore/Resources/nmap-mac-prefixes "$APP/Contents/Resources/"
cp -R Sources/GrokIP/Resources/Fonts/. "$APP/Contents/Resources/Fonts/"
if [[ -f AppIcon.icns ]]; then
  cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
fi
printf 'APPL????' > "$APP/Contents/PkgInfo"
chmod +x "$APP/Contents/MacOS/GrokIP"
codesign --force --deep --sign - "$APP"

# Friendly name for GitHub Releases / drag-into-Applications.
RELEASE_APP="dist/Grok IP Scanner.app"
rm -rf "$RELEASE_APP"
cp -R "$APP" "$RELEASE_APP"
ditto -c -k --keepParent "$RELEASE_APP" dist/Grok-IP-Scanner-macos.zip

echo "==> Built $APP"
echo "    open \"$RELEASE_APP\""
echo "    zip  dist/Grok-IP-Scanner-macos.zip"
