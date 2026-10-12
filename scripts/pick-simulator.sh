#!/usr/bin/env bash
# Print the UDID of the first available simulator matching a preferred name, on the newest iOS 26 runtime.
# Usage: scripts/pick-simulator.sh "iPhone 17 Pro Max" "iPhone 16 Pro Max"
set -euo pipefail

xcrun simctl list devices available -j | python3 -c '
import json, sys

preferred = sys.argv[1:]
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
    if version[0] != 26:
        continue
    for entry in entries:
        if entry.get("isAvailable", True):
            candidates.append((entry["name"], version, entry["udid"]))

for name in preferred:
    matches = sorted((c for c in candidates if c[0] == name), key=lambda c: c[1], reverse=True)
    if matches:
        print(matches[0][2])
        sys.exit(0)

iphones = sorted((c for c in candidates if c[0].startswith("iPhone")), key=lambda c: c[1], reverse=True)
if iphones:
    print(iphones[0][2])
    sys.exit(0)
sys.exit("No iOS 26 iPhone simulator is available")
' "$@"
