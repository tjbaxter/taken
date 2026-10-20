#!/usr/bin/env bash
# The two EAS iOS configs must not drift apart. .eas/build/build-ios.yml builds the App Store (profile "production");
# .eas/build/build-ios-internal.yml builds the owner's TestFlight builds (profile "internal") and exports them
# "TestFlight internal testing only", so App Store Connect can never put one in an App Store version or App Review.
# The internal file is the production file plus the blocks between "# >>> internal only" and "# <<< internal only"
# (and its own header and name), so a check added to one file and not the other fails here.
#
# Usage: scripts/check-eas-configs.sh   (from the repository root)
set -euo pipefail

prod=.eas/build/build-ios.yml
internal=.eas/build/build-ios-internal.yml

fail() { echo "::error::$1"; exit 1; }

for profile_config in production:build-ios.yml internal:build-ios-internal.yml; do
  profile="${profile_config%%:*}"
  want="${profile_config#*:}"
  got="$(plutil -extract "build.$profile.ios.config" raw -o - eas.json 2>/dev/null || true)"
  [ "$got" = "$want" ] || fail "eas.json profile $profile builds with '${got:-nothing}', expected $want"
done

grep -q -E '^ +testFlightInternalTestingOnly: true,$' "$internal" || fail "$internal does not export testFlightInternalTestingOnly"
! grep -q 'testFlightInternalTestingOnly' "$prod" || fail "$prod must export App Store builds, not internal-only ones"
! grep -q -E '# (>>>|<<<) internal only' "$prod" || fail "$prod has internal-only blocks"

# Everything from "build:" on, without the name line and without the internal-only blocks.
shared() {
  awk -v file="$1" '
    /# >>> internal only/ { if (skip) { print "unclosed internal-only block in " file > "/dev/stderr"; exit 2 } skip = 1; next }
    /# <<< internal only/ { if (!skip) { print "stray internal-only end in " file > "/dev/stderr"; exit 2 } skip = 0; next }
    skip { next }
    /^build:/ { started = 1 }
    !started { next }
    /^  name: / && !named { named = 1; next }
    { print }
    END { if (skip) { print "unclosed internal-only block in " file > "/dev/stderr"; exit 2 } }
  ' "$1"
}

prod_shared="$(shared "$prod")"
internal_shared="$(shared "$internal")"
if ! diff -u <(printf '%s\n' "$prod_shared") <(printf '%s\n' "$internal_shared"); then
  fail "$internal differs from $prod outside its internal-only blocks: make the same change in both"
fi
echo "EAS configs: production builds with build-ios.yml, internal with build-ios-internal.yml (internal-only export), and the shared steps match"
