#!/bin/bash
# Assembles the SPM executable into a real .app bundle.
#
# The bundle is what makes LSUIElement, launch-at-login (SMAppService) and a stable bundle
# identifier work — none of which apply to the bare `swift build` binary.
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIGURATION="${CONFIGURATION:-release}"
APP_NAME="Synqit Notch"
BUNDLE_ID="com.synqit.notch"
VERSION="${VERSION:-0.1.0}"
BUILD_VERSION="${BUILD_VERSION:-1}"
# Ad-hoc by default. Set SIGN_IDENTITY="Developer ID Application: …" for a real signature.
SIGN_IDENTITY="${SIGN_IDENTITY:--}"

echo "▸ Building ($CONFIGURATION)…"
swift build -c "$CONFIGURATION"

BINARY="$(swift build -c "$CONFIGURATION" --show-bin-path)/SynqitNotch"
APP_DIR=".build/$APP_NAME.app"

echo "▸ Assembling ${APP_DIR}…"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BINARY" "$APP_DIR/Contents/MacOS/SynqitNotch"

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>SynqitNotch</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$BUILD_VERSION</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <!-- Agent app: no dock icon, no main window. It lives in the notch. -->
    <key>LSUIElement</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>Synqit</string>
    <!-- Production connects over wss://. This only permits the plaintext loopback socket the
         bundled mock server uses during development. -->
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsLocalNetworking</key>
        <true/>
    </dict>
</dict>
</plist>
PLIST

echo "▸ Signing (identity: $SIGN_IDENTITY)…"
codesign --force --sign "$SIGN_IDENTITY" --timestamp=none "$APP_DIR" >/dev/null 2>&1

echo "▸ Verifying…"
codesign --verify --deep --strict "$APP_DIR" && echo "  signature ok"
/usr/libexec/PlistBuddy -c "Print :LSUIElement" "$APP_DIR/Contents/Info.plist" >/dev/null \
    && echo "  LSUIElement set"

echo
echo "Built $APP_DIR"
echo "Run it:      open \"$APP_DIR\""
echo "Install it:  cp -R \"$APP_DIR\" /Applications/"
if [ "$SIGN_IDENTITY" = "-" ]; then
    echo
    echo "This is an ad-hoc signature. On another Mac, Gatekeeper will block first launch —"
    echo "right-click the app and choose Open, or run:"
    echo "  xattr -dr com.apple.quarantine \"/Applications/$APP_NAME.app\""
fi
