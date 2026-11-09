#!/bin/zsh
set -euo pipefail

APP_NAME="MinerGuru"
BUILD_DIR="build"
APP_BUNDLE="${BUILD_DIR}/${APP_NAME}.app"
CONTENTS_DIR="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

SDK_PATH=$(xcrun --sdk macosx --show-sdk-path)
TOOLCHAIN_PLUGINS="/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/host/plugins"
PLATFORM_PLUGINS="/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/usr/lib/swift/host/plugins"

echo "🔨 Compiling ${APP_NAME} for macOS (arm64)…"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

swiftc \
  -O \
  -module-cache-path /tmp/minerguru-module-cache \
  -plugin-path "${TOOLCHAIN_PLUGINS}" \
  -plugin-path "${PLATFORM_PLUGINS}" \
  -target arm64-apple-macosx14.0 \
  -sdk "${SDK_PATH}" \
  -parse-as-library \
  $(find MinerGuru -name "*.swift" | sort) \
  -o "${MACOS_DIR}/${APP_NAME}"

# Process Info.plist variables
sed \
  -e "s/\$(EXECUTABLE_NAME)/${APP_NAME}/g" \
  -e "s/\$(PRODUCT_BUNDLE_IDENTIFIER)/app.minerguru.${APP_NAME}/g" \
  -e "s/\$(MACOSX_DEPLOYMENT_TARGET)/14.0/g" \
  MinerGuru/Info.plist > "${CONTENTS_DIR}/Info.plist"

printf "APPL????" > "${CONTENTS_DIR}/PkgInfo"

# Translations (English source, German): writes de.lproj / en.lproj into Resources
xcrun xcstringstool compile MinerGuru/Localizable.xcstrings --output-directory "${RESOURCES_DIR}"

if [ -f "MinerGuru/AppIcon.icns" ]; then
  cp "MinerGuru/AppIcon.icns" "${RESOURCES_DIR}/AppIcon.icns"
fi

echo "🔏 Signing ${APP_BUNDLE} (ad hoc with entitlements)…"
codesign --force --deep --sign - --entitlements MinerGuru/MinerGuru.entitlements "${APP_BUNDLE}" 2>/dev/null || true

echo "✅ Done: ${APP_BUNDLE}"
