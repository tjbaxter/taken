#!/usr/bin/env bash
# One Xcode builds Taken everywhere: the version in .xcode-version. GitHub CI and release.yml select it
# (scripts/select-xcode.sh) and EAS gets it from the image pinned in eas.json (build.production.ios.image), so the Xcode
# that ships an App Store or TestFlight build is the Xcode CI tested. This check fails the build when any of them differ,
# instead of building with whatever Xcode happens to be there.
#
# Usage: scripts/check-xcode.sh                    the active Xcode and eas.json's image must match .xcode-version
#        scripts/check-xcode.sh path/to/Taken.app  and the built app's DTXcode and DTXcodeBuild must match the active Xcode
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
want="$(tr -d '[:space:]' < "$root/.xcode-version")"
if [ -z "$want" ]; then
  echo "::error::.xcode-version is empty"
  exit 1
fi

version="$(xcodebuild -version)"
have="$(sed -n 's/^Xcode //p' <<<"$version" | head -1)"
build="$(sed -n 's/^Build version //p' <<<"$version" | head -1)"
echo "Active Xcode: $have ($build) at $(xcode-select -p); .xcode-version: $want"
if [ "$have" != "$want" ]; then
  echo "::error::Xcode $have ($build) is active but .xcode-version says $want: refusing to build"
  exit 1
fi

# EAS image names end in the Xcode they carry (macos-tahoe-26.5-xcode-26.6), so a bump of .xcode-version without the
# image, or of the image without .xcode-version, fails here on both CI and EAS.
image="$(plutil -extract build.production.ios.image raw -o - "$root/eas.json")"
echo "eas.json production iOS image: $image"
case "$image" in
  *-xcode-"$want") ;;
  *)
    echo "::error::eas.json build.production.ios.image is '$image', not an image with Xcode $want"
    exit 1
    ;;
esac

app="${1:-}"
if [ -n "$app" ]; then
  # Info.plist records the Xcode that built the app: DTXcode is the version as digits (26.6 -> 2660, 26.6.1 -> 2661).
  IFS=. read -r major minor patch <<<"$want"
  want_dt="${major}${minor:-0}${patch:-0}"
  dt="$(/usr/libexec/PlistBuddy -c 'Print :DTXcode' "$app/Info.plist")"
  dt_build="$(/usr/libexec/PlistBuddy -c 'Print :DTXcodeBuild' "$app/Info.plist")"
  sdk="$(/usr/libexec/PlistBuddy -c 'Print :DTSDKName' "$app/Info.plist")"
  echo "$(basename "$app"): DTXcode $dt, DTXcodeBuild $dt_build, DTSDKName $sdk"
  if [ "$dt" != "$want_dt" ] || [ "$dt_build" != "$build" ]; then
    echo "::error::$(basename "$app") was built by Xcode $dt ($dt_build), expected $want_dt ($build)"
    exit 1
  fi
fi
