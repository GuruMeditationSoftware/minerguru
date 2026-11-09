#!/bin/zsh
# Starts the simulated miners and a separate MinerGuru build that lists all of them.
#
# The app is built with its own bundle id (app.minerguru.MinerGuru.mock), so its settings and miner list
# are kept apart from the real MinerGuru. Optional filters select variants like mock_miner.py:
#
#   MockMiners/run-app-with-mocks.sh                 # all variants
#   MockMiners/run-app-with-mocks.sh hex nerdqx      # only matching variants
#
# Stop the miners with Ctrl+C (the app keeps running and shows them offline).
set -euo pipefail
cd "$(dirname "$0")/.."

BUNDLE_ID="app.minerguru.MinerGuru.mock"
BUILD_DIR="build/mock"

echo "🔨 Baue MinerGuru (Mock) …"
xcodebuild -project MinerGuru.xcodeproj -scheme MinerGuru -configuration Debug \
  MINERGURU_BUNDLE_ID="$BUNDLE_ID" MINERGURU_URL_SCHEME=minerguru-mock CONFIGURATION_BUILD_DIR="$PWD/$BUILD_DIR" build -quiet

echo "📋 Trage Mock-Miner in die Miner-Liste der Mock-App ein …"
osascript -e "tell application id \"$BUNDLE_ID\" to quit" 2>/dev/null || true
python3 - "$BUNDLE_ID" "$@" <<'EOF'
import json, subprocess, sys, uuid
from pathlib import Path
bundle_id, filters = sys.argv[1], [f.lower() for f in sys.argv[2:]]
files = sorted(Path("MockMiners/variants").glob("*.json"))
miners = [
    {"id": str(uuid.uuid4()).upper(), "ipAddress": f"127.0.0.1:{48001 + i}", "customName": path.stem, "addedAt": 0}
    for i, path in enumerate(files)
    if not filters or any(word in path.stem.lower() for word in filters)
]
data = json.dumps(miners).encode().hex()
subprocess.run(["defaults", "write", bundle_id, "MinerGuru.SavedMiners.v1", "-data", data], check=True)
subprocess.run(["defaults", "write", bundle_id, "MinerGuru.AutoScanOnEmptyLaunch.v1", "-bool", "false"], check=True)
print(f"   {len(miners)} Miner eingetragen")
EOF

open "$BUILD_DIR/MinerGuru.app"
exec python3 MockMiners/mock_miner.py "$@"
