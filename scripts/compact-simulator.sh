#!/usr/bin/env bash
# Print the UDID of a 6.1 inch iPhone simulator on the newest iOS 26 runtime, so CI can check that the paywall fits
# the smallest current iPhone without scrolling (SPEC 3.9). The iPhone 16 (393 x 852 pt with the Dynamic Island) is the
# tightest 6.1 inch sheet, 4 pt shorter than the iPhone 16e's (390 x 844 pt, notch): it is used, created if the runner
# has none, and the other 6.1 inch iPhones are the fallback.
# Usage: scripts/compact-simulator.sh
set -euo pipefail

existing() {
  xcrun simctl list devices available -j | python3 -c '
import json, sys

wanted = sys.argv[1]
devices = json.load(sys.stdin)["devices"]
best = None
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
        if entry.get("isAvailable", True) and entry["name"] in (wanted, "Taken " + wanted):
            if best is None or best[0] < version:
                best = (version, entry["udid"])
print(best[1] if best else "")
' "$1"
}

runtime="$(xcrun simctl list runtimes available -j | python3 -c '
import json, sys

runtimes = [r for r in json.load(sys.stdin)["runtimes"] if r.get("platform", "iOS") == "iOS"
            and r["version"].split(".")[0] == "26" and r.get("isAvailable", True)]
runtimes.sort(key=lambda r: tuple(int(p) for p in r["version"].split(".")), reverse=True)
print(runtimes[0]["identifier"] if runtimes else "")
')"

for pair in "iPhone 16:iPhone-16" "iPhone 16e:iPhone-16e" "iPhone 17e:iPhone-17e" "iPhone 15:iPhone-15"; do
  name="${pair%%:*}"
  type="${pair##*:}"
  udid="$(existing "$name")"
  if [ -z "$udid" ] && [ -n "$runtime" ]; then
    udid="$(xcrun simctl create "Taken $name" "com.apple.CoreSimulator.SimDeviceType.$type" "$runtime" 2>/dev/null || true)"
  fi
  if [ -n "$udid" ]; then
    echo "$name: $udid" >&2
    echo "$udid"
    exit 0
  fi
done
echo "No 6.1 inch iPhone simulator could be found or created" >&2
exit 1
