#!/usr/bin/env bash
# Checks a Taken release bundle (android/SPEC-ANDROID.md 3.3 and 15.4), one OK or FAIL line each, and exits 1 on any
# FAIL. One copy for both callers, so they cannot drift apart: android.yml checks the unsigned bundle of every push, and
# android-release.yml checks the signed bundle it hands to Google Play.
#
#   ci/check-bundle.sh BUNDLE.aab [--version-code N] [--signed-by SHA256] [--facts FILE]
#
#   --version-code N    the versionCode the bundle must carry (android-release.yml's)
#   --signed-by SHA256  the upload certificate's SHA-256 fingerprint: the bundle must be signed by exactly that one
#                       certificate. Without it the bundle is reported as unsigned or signed, and not judged.
#   --facts FILE        also writes what was read (version_code, version_name, bytes, signer_sha256) as key=value
#                       lines, for the release job's outputs and summary.
#
# Run from android/ after :app:bundleRelease. Needs a JDK (keytool, jarsigner), the SDK's build-tools (aapt2), readelf,
# unzip and python3, all on GitHub's ubuntu-24.04 image. Reads the bundle itself, not Gradle's intermediates: the
# manifest Play reads is the one inside the bundle.

# ok and fail below always succeed, so `test && ok ... || fail ...` reads as if-then-else throughout.
# shellcheck disable=SC2015
set -euo pipefail

aab=""
want_code=""
want_signer=""
facts=""
while [ $# -gt 0 ]; do
  case "$1" in
    --version-code) want_code="$2"; shift 2 ;;
    --signed-by) want_signer="$(tr '[:lower:]' '[:upper:]' <<<"$2")"; shift 2 ;;
    --facts) facts="$2"; shift 2 ;;
    -*) echo "unknown option $1" >&2; exit 2 ;;
    *) aab="$1"; shift ;;
  esac
done
[ -f "$aab" ] || { echo "FAIL no bundle at '$aab'"; exit 1; }

status=0
ok() { echo "OK   $*"; }
fail() { echo "FAIL $*"; status=1; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

bytes="$(stat -c %s "$aab")"
ok "bundle $(basename "$aab"): $bytes bytes, $(awk -v b="$bytes" 'BEGIN { printf "%.2f MB (%.2f MiB)", b / 1e6, b / 1048576 }')"

# --- The manifest inside the bundle ----------------------------------------------------------------------------------
# A bundle keeps its manifest and resources in aapt2's proto format. They are put back together as a proto APK and
# turned into a binary one with `aapt2 convert`, the documented way between the two formats
# (https://developer.android.com/tools/aapt2#convert), so `aapt2 dump badging` and `dump xmltree` can read them
# (https://developer.android.com/tools/aapt2#dump).
sdk="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
aapt2="$(find "$sdk/build-tools" -maxdepth 2 -name aapt2 -type f 2>/dev/null | sort -V | tail -n 1)"
[ -x "$aapt2" ] || { echo "FAIL aapt2 not found under ${sdk:-\$ANDROID_HOME}/build-tools"; exit 1; }
python3 -I - "$aab" "$work/proto.apk" <<'PY'
import sys, zipfile
src, dst = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(src) as bundle, zipfile.ZipFile(dst, "w", zipfile.ZIP_DEFLATED) as apk:
    for info in bundle.infolist():
        name = info.filename
        if name == "base/manifest/AndroidManifest.xml":
            apk.writestr("AndroidManifest.xml", bundle.read(name))
        elif name == "base/resources.pb" or name.startswith("base/res/"):
            apk.writestr(name[len("base/"):], bundle.read(name))
PY
"$aapt2" convert --output-format binary -o "$work/binary.apk" "$work/proto.apk"
badging="$("$aapt2" dump badging "$work/binary.apk" 2>/dev/null || true)"
"$aapt2" dump xmltree --file AndroidManifest.xml "$work/binary.apk" > "$work/manifest.txt"
manifest="$(cat "$work/manifest.txt")"
[ -n "$badging" ] || { echo "FAIL aapt2 could not read the bundle's manifest"; exit 1; }

package_line="$(grep -m 1 '^package:' <<<"$badging")"
package_field() { sed -n "s/.* $1='\([^']*\)'.*/\1/p" <<<"$package_line"; }
package="$(package_field name)"
version_code="$(package_field versionCode)"
version_name="$(package_field versionName)"
# Newer aapt2 prints minSdkVersion:'28', older sdkVersion:'28'.
min_sdk="$(sed -n -E "s/^(min)?[sS]dkVersion:'([0-9]*)'.*/\2/p" <<<"$badging" | head -n 1)"
target_sdk="$(sed -n "s/^targetSdkVersion:'\([0-9]*\)'.*/\1/p" <<<"$badging")"

[ "$package" = "com.tombaxter.taken" ] && ok "package com.tombaxter.taken" || fail "package is '$package', not com.tombaxter.taken"
[ "$target_sdk" = "36" ] && ok "targetSdk 36" || fail "targetSdk is '$target_sdk', not 36 (SPEC-ANDROID 3.2)"
[ "$min_sdk" = "28" ] && ok "minSdk 28" || fail "minSdk is '$min_sdk', not 28 (SPEC-ANDROID 3.2)"
if [ -n "$want_code" ]; then
  [ "$version_code" = "$want_code" ] && ok "versionCode $version_code" || fail "versionCode is '$version_code', not $want_code"
else
  ok "versionCode $version_code"
fi
[[ "$version_name" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] && ok "versionName $version_name" || fail "versionName '$version_name' is not major.minor.point"
grep -q '^application-debuggable' <<<"$badging" && fail "the bundle is debuggable" || ok "not debuggable"

# --- Permissions (SPEC-ANDROID 3.3) ----------------------------------------------------------------------------------
permissions="$(sed -n "s/^uses-permission: name='\([^']*\)'.*/\1/p" <<<"$badging" | sort -u)"
echo "Permissions in the bundle's manifest:"
while IFS= read -r p; do echo "       $p"; done <<<"${permissions:-(none)}"
# Where each came from, when Gradle's merger report is at hand (https://developer.android.com/build/manage-manifests).
report="app/build/outputs/logs/manifest-merger-release-report.txt"
if [ -f "$report" ]; then
  python3 -I - "$report" <<'PY'
import re, sys
lines = open(sys.argv[1], encoding="utf-8").read().splitlines()
for i, line in enumerate(lines):
    if line.startswith("uses-permission#") and "${" not in line:
        action = next((l for l in lines[i + 1:i + 4] if l.startswith(("ADDED from", "REMOVED from"))), "")
        found = re.search(r"\[([^\]]+)\]", action)
        verb = "removed by" if action.startswith("REMOVED") else "from"
        print(f"       {line[len('uses-permission#'):]}: {verb} {found.group(1) if found else 'Taken itself'}")
PY
fi
# INTERNET and ACCESS_NETWORK_STATE are declared by com.google.android.datatransport:transport-backend-cct, a compile
# dependency of the Play Billing Library 9.1.0 (its POM), reviewed and listed in SPEC-ANDROID 3.3. Taken's own code
# makes no network call.
allowed=(
  com.android.vending.BILLING
  android.permission.INTERNET
  android.permission.ACCESS_NETWORK_STATE
  android.permission.POST_NOTIFICATIONS
  android.permission.RECORD_AUDIO
  android.permission.RECEIVE_BOOT_COMPLETED
  android.permission.WAKE_LOCK
  android.permission.FOREGROUND_SERVICE
  com.tombaxter.taken.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION
)
forbidden=(
  com.google.android.gms.permission.AD_ID
  android.permission.SCHEDULE_EXACT_ALARM
  android.permission.USE_EXACT_ALARM
)
permissions_ok=1
for p in $permissions; do
  for f in "${forbidden[@]}"; do
    [ "$p" = "$f" ] && { fail "forbidden permission $p (SPEC-ANDROID 3.3)"; permissions_ok=0; continue 2; }
  done
  case " ${allowed[*]} " in
    *" $p "*) ;;
    *) fail "$p is not in SPEC-ANDROID 3.3's list"; permissions_ok=0 ;;
  esac
done
[ "$permissions_ok" = 1 ] && ok "permissions match SPEC-ANDROID 3.3, nothing forbidden"

# --- Google Play Billing (SPEC-ANDROID 9; NEXT 1) --------------------------------------------------------------------
# Play lets products be created only once a build "that includes the Google Play Billing Library" is on a track
# (https://developer.android.com/google/play/billing/getting-ready). Three marks of the library, from its own manifest
# and code: the BILLING permission, the version it writes into the manifest's meta-data, and the Play Store service its
# client binds to, a string R8 keeps only while Taken's BillingClient is really in the code.
dex="$work/classes.dex.txt"
unzip -p "$aab" 'base/dex/*.dex' > "$dex"
billing_version="$(python3 -I - "$work/manifest.txt" <<'PY'
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
for block in re.split(r"\n\s*E: ", text):
    if block.startswith("meta-data") and '"com.google.android.play.billingclient.version"' in block:
        value = re.search(r':value\([^)]*\)="([^"]*)"', block)
        print(value.group(1) if value else "")
PY
)"
grep -qx 'com.android.vending.BILLING' <<<"$permissions" && ok "Billing permission" || fail "no com.android.vending.BILLING permission"
[ -n "$billing_version" ] && ok "Play Billing Library $billing_version in the manifest" || fail "no Play Billing Library version in the manifest"
grep -a -q 'com.android.vending.billing.InAppBillingService.BIND' "$dex" \
  && ok "Billing client code in the dex" || fail "no Billing client code in the dex (R8 removed it, or it was never there)"

# --- 16 KB page sizes ------------------------------------------------------------------------------------------------
# Google's two checks (https://developer.android.com/guide/practices/page-sizes): every LOAD segment of every .so is
# aligned to 2**14 or more ("Check for 16 KB ELF alignment"; readelf reads any architecture's headers), and the bundle
# asks for 16 KB zip alignment of uncompressed libraries, which `bundletool dump config` shows as PAGE_ALIGNMENT_16K.
# The runner has no bundletool, so BundleConfig.pb is read directly by its published schema
# (https://github.com/google/bundletool/blob/master/src/main/proto/config.proto: BundleConfig.optimizations = 2,
# Optimizations.uncompress_native_libraries = 2, UncompressNativeLibraries.alignment = 2, 16K = 2, 64K = 3).
libs="$work/libs"
mkdir -p "$libs"
unzip -q -o "$aab" 'base/lib/*' -d "$libs" 2>/dev/null || true
count=0
elf_ok=1
while IFS= read -r so; do
  count=$((count + 1))
  aligns="$(readelf -lW "$so" | awk '$1 == "LOAD" { print $NF }')"
  [ -n "$aligns" ] || { fail "${so#"$libs"/}: readelf found no LOAD segments"; elf_ok=0; }
  for align in $aligns; do
    [ $((align)) -ge 16384 ] || { fail "${so#"$libs"/} has a LOAD segment aligned to $align"; elf_ok=0; }
  done
done < <(find "$libs" -name '*.so' | sort)
[ "$elf_ok" = 1 ] && ok "16 KB ELF alignment: $count native libraries, every LOAD segment aligned to 16 KB or more"
alignment="$(python3 -I - "$aab" <<'PY'
import sys, zipfile

def varint(buf, i):
    value = shift = 0
    while True:
        byte = buf[i]; i += 1
        value |= (byte & 0x7F) << shift; shift += 7
        if byte < 0x80:
            return value, i

def fields(buf):
    i = 0
    while i < len(buf):
        key, i = varint(buf, i)
        number, wire = key >> 3, key & 7
        if wire == 0:
            value, i = varint(buf, i)
        elif wire == 2:
            size, i = varint(buf, i); value = buf[i:i + size]; i += size
        elif wire == 1:
            value = buf[i:i + 8]; i += 8
        elif wire == 5:
            value = buf[i:i + 4]; i += 4
        else:
            raise ValueError(f"wire type {wire}")
        yield number, value

def child(buf, number):
    return next((v for n, v in fields(buf) if n == number), b"")

config = zipfile.ZipFile(sys.argv[1]).read("BundleConfig.pb")
libraries = child(child(config, 2), 2)
names = {0: "PAGE_ALIGNMENT_UNSPECIFIED", 1: "PAGE_ALIGNMENT_4K", 2: "PAGE_ALIGNMENT_16K", 3: "PAGE_ALIGNMENT_64K"}
print(names.get(child(libraries, 2) or 0, "unknown"))
PY
)"
case "$alignment" in
  PAGE_ALIGNMENT_16K | PAGE_ALIGNMENT_64K) ok "16 KB zip alignment: the bundle asks for $alignment" ;;
  *) fail "the bundle's config asks for $alignment, not PAGE_ALIGNMENT_16K" ;;
esac

# --- No debug or demo code (SPEC-ANDROID 4: src/debug never reaches a release) ----------------------------------------
debug_ok=1
for mark in DemoScreens WeightDemo today-nudge-offer today-weight-offer -demo-stack 'Alex Morgan'; do
  grep -a -q -e "$mark" "$dex" && { fail "debug or demo code in the release dex ('$mark')"; debug_ok=0; }
done
for activity in androidx.compose.ui.tooling.PreviewActivity androidx.activity.ComponentActivity; do
  grep -q "\"$activity\"" <<<"$manifest" && { fail "debug-only activity $activity in the manifest"; debug_ok=0; }
done
[ "$debug_ok" = 1 ] && ok "no debug or demo code"

# --- Signature -------------------------------------------------------------------------------------------------------
# A bundle carries a JAR signature by the upload key; Play checks it against the upload certificate it holds and re-signs
# with the app signing key (https://support.google.com/googleplay/android-developer/answer/9842756). jarsigner proves the
# signature is valid; keytool names the certificates behind it (https://docs.oracle.com/en/java/javase/21/docs/specs/man/keytool.html).
verify="$(jarsigner -verify "$aab" 2>&1 || true)"
fingerprints=""
if [ -n "$want_signer" ]; then
  grep -q '^jar verified\.' <<<"$verify" && ok "signature verified by jarsigner" || fail "jarsigner could not verify the signature"
  grep -q -i 'unsigned entries' <<<"$verify" && fail "the bundle has unsigned entries"
  certs="$(keytool -printcert -jarfile "$aab" 2>&1 || true)"
  signers="$(grep -c '^Signer #' <<<"$certs" || true)"
  fingerprints="$(sed -n 's/^[[:space:]]*SHA256:[[:space:]]*//p' <<<"$certs" | tr '[:lower:]' '[:upper:]')"
  cert_count="$(grep -c . <<<"$fingerprints" || true)"
  if [ "$signers" = 1 ] && [ "$cert_count" = 1 ] && [ "$fingerprints" = "$want_signer" ]; then
    ok "signed by exactly the upload certificate, SHA-256 $fingerprints"
  else
    fail "signers: $signers, certificates: $cert_count, SHA-256: ${fingerprints:-none}; want one, $want_signer"
  fi
else
  if grep -q '^jar is unsigned' <<<"$verify"; then ok "unsigned (only android-release.yml signs)"; else echo "NOTE signed, signer not checked here"; fi
fi

if [ -n "$facts" ]; then
  {
    echo "version_code=$version_code"
    echo "version_name=$version_name"
    echo "bytes=$bytes"
    echo "signer_sha256=${fingerprints:-}"
  } > "$facts"
fi

exit "$status"
