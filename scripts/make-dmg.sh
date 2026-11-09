#!/bin/zsh
# Builds a Release version of MinerGuru and packages it as a drag-to-Applications DMG.
# Usage: scripts/make-dmg.sh        → dist/MinerGuru-<version>.dmg
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="MinerGuru"
VOL_NAME="${APP_NAME}"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" MinerGuru/Info.plist)
BUILD_DIR="build/release"
APP_PATH="${BUILD_DIR}/${APP_NAME}.app"
STAGING="build/dmg-staging"
# Finder's window layout (.DS_Store) remembers where the writable image lay, so it lies outside the home folder.
RW_DIR="/private/tmp/MinerGuru-dmg"
RW_DMG="${RW_DIR}/${APP_NAME}-rw.dmg"
OUT_DIR="dist"
OUT_DMG="${OUT_DIR}/${APP_NAME}-${VERSION}.dmg"
# Personal traces: the user name sits in every build path, and other names must not appear either.
# The patterns are personal themselves, so they live outside the repository: one extended regex per line
# in MINERGURU_TRACES (default ~/.config/minerguru/traces). scripts/release.sh refuses to run without them.
TRACES_FILE="${MINERGURU_TRACES:-$HOME/.config/minerguru/traces}"
TRACES=""
[ -f "${TRACES_FILE}" ] && TRACES=$(grep -v -e '^#' -e '^[[:space:]]*$' "${TRACES_FILE}" | paste -sd '|' -)
[ -n "${TRACES}" ] || echo "⚠️  Keine Spurenmuster in ${TRACES_FILE}, die Spurenprüfung entfällt."

# Searches the raw bytes of every file, binaries and hidden files included.
# (`strings` skips the symbol table of a universal binary, where the debug map keeps the build paths.)
find_traces() {
  [ -n "${TRACES}" ] || return 0
  LC_ALL=C grep -r -a -l -i -E "${TRACES}" "$@" 2>/dev/null || true
}

echo "🔨 Release-Build (arm64 + x86_64)…"
rm -rf "${BUILD_DIR}"
xcodebuild \
  -project MinerGuru.xcodeproj -scheme "${APP_NAME}" -configuration Release \
  -derivedDataPath build/DerivedData \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
  CONFIGURATION_BUILD_DIR="${PWD}/${BUILD_DIR}" \
  DEPLOYMENT_POSTPROCESSING=YES STRIP_INSTALLED_PRODUCT=YES STRIP_STYLE=all COPY_PHASE_STRIP=YES \
  DEBUG_INFORMATION_FORMAT=dwarf-with-dsym \
  build 2>&1 | grep -E "error:|warning: unable|BUILD (SUCCEEDED|FAILED)" || true
[ -d "${APP_PATH}" ] || { echo "❌ Build fehlgeschlagen"; exit 1; }

echo "🔏 Signiere (ad-hoc, hardened runtime ohne Zertifikat nicht möglich)…"
# Inside out and without --deep: the widget extension keeps its own sandbox entitlements.
APPEX="${APP_PATH}/Contents/PlugIns/MinerGuruWidgets.appex"
[ -d "${APPEX}" ] || { echo "❌ Widget-Erweiterung fehlt im Build"; exit 1; }
# The entitlements file holds build settings ($(MINERGURU_BUNDLE_ID)); take the expanded ones Xcode signed with.
APPEX_ENTITLEMENTS="build/MinerGuruWidgets.signed.entitlements"
codesign -d --entitlements - --xml "${APPEX}" > "${APPEX_ENTITLEMENTS}"
grep -q "app.minerguru.MinerGuru/Widgets/" "${APPEX_ENTITLEMENTS}" || { echo "❌ Widget-Entitlements ohne Lesepfad"; exit 1; }
codesign --force --sign - --entitlements "${APPEX_ENTITLEMENTS}" "${APPEX}"
codesign --force --sign - --entitlements MinerGuru/MinerGuru.entitlements "${APP_PATH}"
codesign --verify --deep --strict "${APP_PATH}"
codesign -d --entitlements - "${APPEX}" 2>/dev/null | grep -q "app-sandbox" || { echo "❌ Widget-Erweiterung ohne Sandbox signiert"; exit 1; }

echo "🕵️  Prüfe auf persönliche Spuren…"
LEAKS=$(find_traces "${APP_PATH}")
if [ -n "${LEAKS}" ]; then
  echo "❌ Persönliche Daten im Build gefunden:"; echo "${LEAKS}" | head
  exit 1
fi

echo "🖼  Erzeuge DMG-Hintergrund…"
rm -rf "${STAGING}"; mkdir -p "${STAGING}/.background"
swift scripts/generate-dmg-background.swift "${STAGING}/.background/background.png" >/dev/null
cp -R "${APP_PATH}" "${STAGING}/"
ln -s /Applications "${STAGING}/Applications"

echo "💿 Erzeuge DMG…"
mkdir -p "${OUT_DIR}"
rm -rf "${RW_DIR}" "${OUT_DMG}"
mkdir -p "${RW_DIR}"
hdiutil detach "/Volumes/${VOL_NAME}" >/dev/null 2>&1 || true
hdiutil create -srcfolder "${STAGING}" -volname "${VOL_NAME}" -fs HFS+ -format UDRW -ov "${RW_DMG}" >/dev/null
DEVICE=$(hdiutil attach -readwrite -noverify -noautoopen "${RW_DMG}" | grep -E '^/dev/' | head -1 | awk '{print $1}')
sleep 2

echo "🎨 Gestalte Fenster (Finder)…"
osascript <<APPLESCRIPT || echo "⚠️  Finder-Layout konnte nicht gesetzt werden (Automation-Berechtigung?)"
tell application "Finder"
  tell disk "${VOL_NAME}"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 860, 520}
    set viewOptions to the icon view options of container window
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 112
    set text size of viewOptions to 13
    set background picture of viewOptions to file ".background:background.png"
    set position of item "${APP_NAME}.app" of container window to {165, 200}
    set position of item "Applications" of container window to {495, 200}
    update without registering applications
    delay 2
    close
  end tell
end tell
APPLESCRIPT

# Custom volume icon (copied after mounting; hdiutil drops it from -srcfolder)
if [ -f MinerGuru/AppIcon.icns ]; then
  cp MinerGuru/AppIcon.icns "/Volumes/${VOL_NAME}/.VolumeIcon.icns"
  SetFile -a C "/Volumes/${VOL_NAME}" 2>/dev/null || xattr -wx com.apple.FinderInfo "0000000000000000040000000000000000000000000000000000000000000000" "/Volumes/${VOL_NAME}"
fi

sync; sleep 1
chmod -Rf go-w "/Volumes/${VOL_NAME}" 2>/dev/null || true
hdiutil detach "${DEVICE}" >/dev/null || { sleep 3; hdiutil detach -force "${DEVICE}" >/dev/null; }

hdiutil convert "${RW_DMG}" -format UDZO -imagekey zlib-level=9 -o "${OUT_DMG}" >/dev/null
rm -rf "${RW_DIR}"

echo "🕵️  Prüfe das fertige DMG auf persönliche Spuren…"
CHECK_MOUNT=$(hdiutil attach -readonly -nobrowse -noautoopen "${OUT_DMG}" | grep -o '/Volumes/.*' | head -1)
LEAKS=$(find_traces "${CHECK_MOUNT}")
hdiutil detach "${CHECK_MOUNT}" >/dev/null || hdiutil detach -force "${CHECK_MOUNT}" >/dev/null
if [ -n "${LEAKS}" ]; then
  rm -f "${OUT_DMG}"
  echo "❌ Persönliche Daten im DMG gefunden, DMG gelöscht:"; echo "${LEAKS}" | head
  exit 1
fi

echo "✅ Fertig: ${OUT_DMG} ($(du -h "${OUT_DMG}" | cut -f1))"
