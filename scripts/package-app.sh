#!/usr/bin/env bash
set -euo pipefail

APP_NAME="SelectionTranslator"
BUNDLE_ID="${BUNDLE_ID:-dev.fan.SelectionTranslator}"
VERSION="${VERSION:-0.1.0}"
BUILD="${BUILD:-1}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"

cd "$ROOT_DIR"

if ! xcrun --sdk macosx --show-sdk-path >/dev/null 2>&1; then
    cat >&2 <<'EOF'
error: active Xcode/Command Line Tools installation is not usable.

Fix it by installing a matching full Xcode, then run:

  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
  xcodebuild -runFirstLaunch
  swift --version

After that, run this script again.
EOF
    exit 1
fi

export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$ROOT_DIR/.build/clang-module-cache}"
SWIFT_BUILD_ARGS=(
    -c release
    --disable-sandbox
    --cache-path "$ROOT_DIR/.build/swiftpm-cache"
    --config-path "$ROOT_DIR/.build/swiftpm-config"
    --security-path "$ROOT_DIR/.build/swiftpm-security"
)

swift build "${SWIFT_BUILD_ARGS[@]}"
BIN_DIR="$(swift build "${SWIFT_BUILD_ARGS[@]}" --show-bin-path)"
BIN_PATH="$BIN_DIR/$APP_NAME"

if [[ ! -x "$BIN_PATH" ]]; then
    echo "error: release executable not found at $BIN_PATH" >&2
    exit 1
fi

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

cp "$BIN_PATH" "$APP_DIR/Contents/MacOS/$APP_NAME"
chmod +x "$APP_DIR/Contents/MacOS/$APP_NAME"

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleDisplayName</key>
    <string>Selection Translator</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
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
    <string>$BUILD</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP_DIR" >/dev/null

echo "Created $APP_DIR"
echo "Run it with: open \"$APP_DIR\""
