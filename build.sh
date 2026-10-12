#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")"

SDK="$(xcrun --sdk macosx --show-sdk-path)"
TARGET="arm64-apple-macos14"
BUILD=".build/swiftc"
# One bundle only: Local Network privacy gets confused by several copies of the
# same app (same executable UUID) lying around, so do not keep a second one.
APP="dist/Grok IP Scanner.app"
rm -rf "$APP" "dist/GrokIP.app"

mkdir -p "$BUILD" "$APP/Contents/MacOS" "$APP/Contents/Resources/Fonts"

# Newer SDKs implement SwiftUI property wrappers such as @State as macros. Xcode
# passes the SDK's macro plugin folders to the compiler; a bare swiftc does not.
PLUGINS=()
PLATFORM="$(xcrun --sdk macosx --show-sdk-platform-path 2>/dev/null || true)"
for dir in "$SDK/usr/lib/swift/host/plugins" "$PLATFORM/Developer/usr/lib/swift/host/plugins"; do
  if [[ -d "$dir" ]]; then
    PLUGINS+=(-plugin-path "$dir")
  fi
done

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
  "${PLUGINS[@]}" \
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

# macOS Local Network privacy (macOS 15+) remembers the app by its code signature.
# An ad-hoc signature is a new identity on every build, so the permission can
# silently stop applying and the scan loses MACs and vendors. Use a real
# identity when there is one: GROKIP_SIGN_IDENTITY, else the first
# "Apple Development" / "Developer ID Application" certificate in the keychain
# (a free Apple ID in Xcode › Settings › Accounts gives you an Apple Development one).
IDENTITY="${GROKIP_SIGN_IDENTITY:-}"
if [[ -z "$IDENTITY" ]]; then
  IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
    | awk -F'"' '/Apple Development|Developer ID Application/ { print $2; exit }')"
fi
if [[ -n "$IDENTITY" && "$IDENTITY" != "-" ]]; then
  echo "==> Signing with: $IDENTITY"
  codesign --force --deep --sign "$IDENTITY" "$APP"
else
  echo "==> Ad-hoc signing (no Apple code-signing identity found)"
  echo "    Local Network access may need re-approving after each rebuild; see README."
  codesign --force --deep --sign - "$APP"
fi

rm -f dist/Grok-IP-Scanner-macos.zip
ditto -c -k --keepParent "$APP" dist/Grok-IP-Scanner-macos.zip

echo "==> Built $APP"
echo "    open \"$APP\""
echo "    zip  dist/Grok-IP-Scanner-macos.zip"
