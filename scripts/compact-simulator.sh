#!/usr/bin/env bash
# Print the UDID of a 6.1 inch iPhone simulator on the newest iOS 26 runtime, creating one if the runner has none, so
# CI can check that the paywall fits the smallest current iPhone without scrolling (SPEC 3.9).
# Usage: scripts/compact-simulator.sh
set -euo pipefail

# 6.1 inch iPhones, 393 x 852 pt (Dynamic Island) or 390 x 844 pt (notch); iPhone 16 is the tighter of the two.
names=("iPhone 16" "iPhone 16e" "iPhone 17e" "iPhone 15")
types=("iPhone-16" "iPhone-16e" "iPhone-17e" "iPhone-15")

found="$(xcrun simctl list devices available -j | python3 -c '
import json, sys

wanted = sys.argv[1:]
devices = json.load(sys.stdin)["devices"]
best = {}
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
        name = entry["name"]
        if entry.get("isAvailable", True) and name in wanted:
            if name not in best or best[name][0] < version:
                best[name] = (version, entry["udid"])
for name in wanted:
    if name in best:
        print(best[name][1])
        break
' "${names[@]}")"

if [ -n "$found" ]; then
  echo "$found"
  exit 0
fi

runtime="$(xcrun simctl list runtimes available -j | python3 -c '
import json, sys

runtimes = [r for r in json.load(sys.stdin)["runtimes"] if r.get("platform", "iOS") == "iOS"
            and r["version"].split(".")[0] == "26" and r.get("isAvailable", True)]
runtimes.sort(key=lambda r: tuple(int(p) for p in r["version"].split(".")), reverse=True)
print(runtimes[0]["identifier"] if runtimes else "")
')"
if [ -z "$runtime" ]; then
  echo "No iOS 26 runtime to create a 6.1 inch iPhone on" >&2
  exit 1
fi
for type in "${types[@]}"; do
  if udid="$(xcrun simctl create "Taken 6.1in" "com.apple.CoreSimulator.SimDeviceType.$type" "$runtime" 2>/dev/null)"; then
    echo "$udid"
    exit 0
  fi
done
echo "No 6.1 inch iPhone simulator could be found or created" >&2
exit 1
