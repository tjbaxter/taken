#!/usr/bin/env bash
# The App Store .ipa, checked before it is uploaded: .github/workflows/app-store-build.yml runs this between
# `eas build -e production --local` and `eas submit`. It unpacks the .ipa, prints one OK or FAIL line per check, and
# fails unless every check passes:
#   1. App Store shape: scripts/check-app-store-build.sh, so no internal-only code, no TakenInternalPro and no
#      TFInternalTestingOnly (App Review Guideline 2.5.19).
#   2. iPhone only: UIDeviceFamily is exactly [1] in Taken.app and TakenWidgets.appex. App Store Connect rejected a
#      universal build once (90474), and once a universal build is accepted, iPad support can never be dropped.
#   3. App Group: the signed entitlements of both (codesign --display --entitlements, as TN3125 shows) include
#      group.com.tombaxter.taken, the container the app, widgets, intents and notification actions share.
#   4. Version: CFBundleShortVersionString is project.yml's MARKETING_VERSION in both, with one CFBundleVersion.
#   5. Founding members: the build number is above FoundingMember.maxBuild (Shared/Pro.swift), as release.yml requires,
#      since a first download of a build at or below it keeps Pro for life.
#   6. Xcode: scripts/check-xcode.sh on both, so DTXcode and DTXcodeBuild are the Xcode in .xcode-version.
#   7. Provisioning: each embedded.mobileprovision, unwrapped with `security cms -D` (TN3125), is an App Store
#      distribution profile for that bundle's App ID: no ProvisionedDevices (development and ad hoc profiles list
#      devices), no ProvisionsAllDevices (In-House and Developer ID) and no get-task-allow (development).
# TN3125: https://developer.apple.com/documentation/technotes/tn3125-inside-code-signing-provisioning-profiles
#
# Usage: scripts/check-ipa.sh path/to/Taken.ipa
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
ipa="${1:?usage: check-ipa.sh path/to/Taken.ipa}"
team=F7YRP3B2U8
group=group.com.tombaxter.taken

test -s "$ipa" || { echo "::error::$ipa is missing or empty"; exit 1; }
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
unzip -q "$ipa" -d "$work/ipa" || { echo "::error::$ipa could not be unpacked"; exit 1; }
app="$work/ipa/Payload/Taken.app"
appex="$app/PlugIns/TakenWidgets.appex"
for bundle in "$app" "$appex"; do
  test -f "$bundle/Info.plist" || { echo "::error::$ipa has no ${bundle#"$work/ipa/"}"; exit 1; }
done

# A check function returns non-zero with $reason on failure, and may leave $detail for the OK line. It runs inside an
# if, where set -e does not apply, so each one tests every command itself.
reason=""
detail=""
checks=0
failures=0
check() {
  local label="$1"
  shift
  reason=""
  detail=""
  checks=$((checks + 1))
  if "$@"; then
    echo "OK    $label${detail:+: $detail}"
  else
    echo "FAIL  $label: ${reason:-see above}"
    failures=$((failures + 1))
  fi
}

# One Info.plist value as text, "" when the key is missing (plutil prints that error on stdout, so it is dropped).
plist_value() {
  local value
  value="$(plutil -extract "$2" raw -o - "$1/Info.plist" 2>/dev/null)" || value=""
  printf '%s' "$value"
}

app_store_shape() {
  "$root/scripts/check-app-store-build.sh" "$app" || { reason="scripts/check-app-store-build.sh refused it (above)"; return 1; }
  detail="no internal-only code, TakenInternalPro or TFInternalTestingOnly (Guideline 2.5.19)"
}

iphone_only() {
  local bundle families
  for bundle in "$app" "$appex"; do
    families="$(plutil -extract UIDeviceFamily json -o - "$bundle/Info.plist" 2>/dev/null | tr -d '[:space:]')" || families=""
    if [ "$families" != "[1]" ]; then
      reason="$(basename "$bundle") has UIDeviceFamily ${families:-(none)}, not [1]"
      return 1
    fi
  done
  detail="UIDeviceFamily [1] in Taken.app and TakenWidgets.appex"
}

app_group() {
  local bundle entitlements groups
  for bundle in "$app" "$appex"; do
    entitlements="$work/$(basename "$bundle")-entitlements.plist"
    if ! codesign --display --entitlements - --xml "$bundle" 2>/dev/null | plutil -convert xml1 -o "$entitlements" - >/dev/null 2>&1; then
      reason="$(basename "$bundle") has no signed entitlements that codesign can read"
      return 1
    fi
    groups="$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.application-groups' "$entitlements" 2>/dev/null)" || groups=""
    # PlistBuddy prints the array one indented ID per line.
    if ! tr -d '[:blank:]' <<<"$groups" | grep -Fxq "$group"; then
      reason="$(basename "$bundle") is not signed with the App Group $group"
      return 1
    fi
  done
  detail="$group in the signed entitlements of Taken.app and TakenWidgets.appex"
}

version() {
  local want app_short widget_short app_build widget_build
  want="$(sed -n 's/^[[:space:]]*MARKETING_VERSION:[[:space:]]*"\{0,1\}\([0-9.]*\)"\{0,1\}.*/\1/p' "$root/project.yml")"
  if [ -z "$want" ] || [[ "$want" == *$'\n'* ]] || ! grep -Eqx '[0-9]+(\.[0-9]+){1,2}' <<<"$want"; then
    reason="project.yml does not set one MARKETING_VERSION x.y.z"
    return 1
  fi
  app_short="$(plist_value "$app" CFBundleShortVersionString)"
  widget_short="$(plist_value "$appex" CFBundleShortVersionString)"
  app_build="$(plist_value "$app" CFBundleVersion)"
  widget_build="$(plist_value "$appex" CFBundleVersion)"
  if [ "$app_short" != "$want" ] || [ "$widget_short" != "$want" ]; then
    reason="Taken.app is ${app_short:-unversioned} and TakenWidgets.appex ${widget_short:-unversioned}; project.yml says $want"
    return 1
  fi
  if [ -z "$app_build" ] || [ "$app_build" != "$widget_build" ]; then
    reason="Taken.app is build ${app_build:-(none)} and TakenWidgets.appex build ${widget_build:-(none)}"
    return 1
  fi
  detail="$want ($app_build) in both, as in project.yml"
}

founding_cutoff() {
  local max build short
  max="$(sed -n 's/.*static let maxBuild = \([0-9][0-9]*\).*/\1/p' "$root/Shared/Pro.swift" | head -n 1)"
  build="$(plist_value "$app" CFBundleVersion)"
  short="$(plist_value "$app" CFBundleShortVersionString)"
  if [ -z "$max" ]; then
    reason="FoundingMember.maxBuild not found in Shared/Pro.swift"
    return 1
  fi
  if ! grep -Eqx '[0-9]+' <<<"$build"; then
    reason="build number '${build:-(none)}' is not a whole number"
    return 1
  fi
  case "$short" in
    1.0|1.0.*) detail="a 1.0.x build ($build): founding members are first downloads of builds 1 to $max"; return 0 ;;
  esac
  if [ "$build" -le "$max" ]; then
    reason="build $build is not above FoundingMember.maxBuild $max, so every new customer would keep Pro for life"
    return 1
  fi
  detail="build $build is above FoundingMember.maxBuild $max"
}

xcode() {
  local bundle
  for bundle in "$app" "$appex"; do
    "$root/scripts/check-xcode.sh" "$bundle" || { reason="scripts/check-xcode.sh refused $(basename "$bundle") (above)"; return 1; }
  done
  detail="Taken.app and TakenWidgets.appex were built by the Xcode in .xcode-version"
}

profiles() {
  local bundle bundle_id profile name app_identifier names=""
  for bundle in "$app" "$appex"; do
    bundle_id=com.tombaxter.taken
    if [ "$bundle" = "$appex" ]; then bundle_id=com.tombaxter.taken.widgets; fi
    if [ "$(plist_value "$bundle" CFBundleIdentifier)" != "$bundle_id" ]; then
      reason="$(basename "$bundle") is $(plist_value "$bundle" CFBundleIdentifier), not $bundle_id"
      return 1
    fi
    profile="$work/$(basename "$bundle")-profile.plist"
    if ! security cms -D -i "$bundle/embedded.mobileprovision" -o "$profile" >/dev/null 2>&1; then
      reason="$(basename "$bundle")/embedded.mobileprovision is missing or not a signed profile"
      return 1
    fi
    name="$(/usr/libexec/PlistBuddy -c 'Print :Name' "$profile" 2>/dev/null)" || name=""
    if [ -z "$name" ]; then
      reason="the profile in $(basename "$bundle") has no Name, so it was not read"
      return 1
    fi
    if /usr/libexec/PlistBuddy -c 'Print :ProvisionedDevices' "$profile" >/dev/null 2>&1; then
      reason="'$name' ($(basename "$bundle")) lists devices: a development or ad hoc profile"
      return 1
    fi
    if [ "$(/usr/libexec/PlistBuddy -c 'Print :ProvisionsAllDevices' "$profile" 2>/dev/null || true)" = true ]; then
      reason="'$name' ($(basename "$bundle")) provisions all devices: an In-House or Developer ID profile"
      return 1
    fi
    if [ "$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:get-task-allow' "$profile" 2>/dev/null || true)" = true ]; then
      reason="'$name' ($(basename "$bundle")) allows get-task-allow: a development profile"
      return 1
    fi
    app_identifier="$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:application-identifier' "$profile" 2>/dev/null)" || app_identifier=""
    if [ "$app_identifier" != "$team.$bundle_id" ]; then
      reason="'$name' ($(basename "$bundle")) is for ${app_identifier:-no App ID}, not $team.$bundle_id"
      return 1
    fi
    names="$names${names:+, }'$name' for $bundle_id"
  done
  detail="$names"
}

check "App Store shape" app_store_shape
check "iPhone only" iphone_only
check "App Group" app_group
check "Version" version
check "Founding member cutoff" founding_cutoff
check "Xcode" xcode
check "App Store distribution profiles" profiles

if [ "$failures" -gt 0 ]; then
  echo "::error::$failures of $checks checks failed: refusing to upload $(basename "$ipa")"
  exit 1
fi
echo "All $checks checks passed"
