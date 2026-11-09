#!/bin/zsh
# Builds MinerGuru and prepares the files for a GitHub release. Maintainer only: it needs the local trace patterns.
# Usage: scripts/release.sh        → dist/MinerGuru-<version>.dmg + dist/upload/mac/{MinerGuru.dmg,SHA256SUMS.txt}
#
# Afterwards: create the release "v<version>" in the public repository and upload both files from dist/upload/mac.
# The upload name carries no version, so the website's releases/latest/download link keeps working.
# To build a DMG for yourself, scripts/make-dmg.sh is enough.
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="MinerGuru"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" MinerGuru/Info.plist)
DMG="dist/${APP_NAME}-${VERSION}.dmg"
UPLOAD_DIR="dist/upload/mac"

# A release never ships without the check for personal traces (patterns outside the repository, see make-dmg.sh).
TRACES_FILE="${MINERGURU_TRACES:-$HOME/.config/minerguru/traces}"
grep -q -v -e '^#' -e '^[[:space:]]*$' "${TRACES_FILE}" 2>/dev/null || { echo "❌ No trace patterns in ${TRACES_FILE}, no release."; exit 1; }

# Builds, signs ad-hoc, checks for personal traces and packages the DMG
scripts/make-dmg.sh

rm -rf "${UPLOAD_DIR}"
mkdir -p "${UPLOAD_DIR}"
cp "${DMG}" "${UPLOAD_DIR}/${APP_NAME}.dmg"
(cd "${UPLOAD_DIR}" && shasum -a 256 "${APP_NAME}.dmg" > SHA256SUMS.txt)

echo "✅ Upload files for release v${VERSION}:"
ls -lh "${UPLOAD_DIR}"
cat "${UPLOAD_DIR}/SHA256SUMS.txt"
