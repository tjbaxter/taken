#!/usr/bin/env bash
# Print the UDID of the first available simulator matching a preferred name, on the newest iOS runtime of the same major
# version as the Xcode in .xcode-version (Xcode 27.x ships the iOS 27 simulators).
# Usage: scripts/pick-simulator.sh "iPhone 18 Pro Max" "iPhone 17 Pro Max"
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
major="$(cut -d. -f1 < "$root/.xcode-version" | tr -d '[:space:]')"

xcrun simctl list devices available -j | python3 -c '
import json, sys

major = int(sys.argv[1])
preferred = sys.argv[2:]
devices = json.load(sys.stdin)["devices"]
candidates = []
for runtime, entries in devices.items():
    marker = "SimRuntime.iOS-"
    if marker not in runtime:
        continue
    try:
        version = tuple(int(part) for part in runtime.split(marker, 1)[1].split("-"))
    except ValueError:
        continue
    if version[0] != major:
        continue
    for entry in entries:
        if entry.get("isAvailable", True):
            candidates.append((entry["name"], version, entry["udid"]))

for name in preferred:
    matches = sorted((c for c in candidates if c[0] == name), key=lambda c: c[1], reverse=True)
    if matches:
        print(matches[0][2])
        sys.exit(0)

# Never fall back to iPhone Duo: its iOS 27.1 runtime is the newest, but it is a different display class.
iphones = sorted((c for c in candidates if c[0].startswith("iPhone") and "Duo" not in c[0]), key=lambda c: c[1], reverse=True)
if iphones:
    print(iphones[0][2])
    sys.exit(0)
sys.exit("No iOS %d iPhone simulator is available" % major)
' "$major" "$@"
