#!/usr/bin/env bash
# Select the Xcode in .xcode-version, the one EAS ships Taken with (eas.json's pinned image), and check it. A runner
# without that exact Xcode fails rather than testing with a different one.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
want="$(tr -d '[:space:]' < "$root/.xcode-version")"
xcode="/Applications/Xcode_${want}.app"
if [ ! -d "$xcode" ]; then
  echo "::error::Xcode $want (.xcode-version) is not installed on this runner"
  ls -d /Applications/Xcode*.app || true
  exit 1
fi
sudo xcode-select -s "$xcode/Contents/Developer"
"$root/scripts/check-xcode.sh"
