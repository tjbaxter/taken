#!/usr/bin/env bash
# Select the newest installed Xcode 26.x (never a beta) and print its version.
set -euo pipefail

xcode="$(ls -d /Applications/Xcode_26*.app 2>/dev/null | grep -vi beta | sort -V | tail -n 1 || true)"
if [ -z "$xcode" ]; then
  echo "::error::No Xcode 26 found on this runner"
  ls -d /Applications/Xcode*.app || true
  exit 1
fi
sudo xcode-select -s "$xcode/Contents/Developer"
xcodebuild -version
