#!/usr/bin/env bash
# Capture App Store screenshots from the simulator with demo data.
# Usage: scripts/screenshots.sh <simulator-udid> <path/to/Taken.app> <output-dir> [diagnostics-dir] [6.3-inch-udid]
set -euo pipefail

udid="$1"
app="$2"
out="$3"
diag="${4:-$out-diagnostics}"
small="${5:-}"
bundle_id="com.tombaxter.taken"

mkdir -p "$out" "$diag"

prepare() {
  local device="$1"
  xcrun simctl boot "$device" 2>/dev/null || true
  xcrun simctl bootstatus "$device" -b
  xcrun simctl ui "$device" appearance dark || true
  xcrun simctl status_bar "$device" override \
    --time "9:41" \
    --dataNetwork wifi --wifiMode active --wifiBars 3 \
    --cellularMode active --cellularBars 4 --operatorName "" \
    --batteryState discharging --batteryLevel 100
  xcrun simctl install "$device" "$app"
}

prepare "$udid"

# Warm launch so first-run work (font registration, caches) does not land in a screenshot.
xcrun simctl launch "$udid" "$bundle_id" -demo -screen today >/dev/null
sleep 6
xcrun simctl terminate "$udid" "$bundle_id" || true

# Where is the main thread right now? Saved for every shot, printed when the app looks stuck.
diagnose() {
  local name="$1" pid
  pid="$(pgrep -f "Taken.app/Taken" | head -n 1 || true)"
  if [ -z "$pid" ]; then
    echo "::warning::$name: Taken is not running after launch"
    return 0
  fi
  sample "$pid" 1 -mayDie -file "$diag/$name.sample.txt" >/dev/null 2>&1 || true
  if [ -f "$diag/$name.sample.txt" ]; then
    awk '/^Call graph:/{on=1; next} on && /^    [0-9]+ Thread_/{n++} on && n>=2{exit} on{print}' "$diag/$name.sample.txt" \
      | head -n 45 > "$diag/$name.main-thread.txt"
    if ! grep -q "mach_msg" "$diag/$name.main-thread.txt"; then
      echo "::warning::$name: main thread is busy, not idle in its run loop"
      cat "$diag/$name.main-thread.txt"
    fi
  fi
}

shoot() {
  local name="$1" screen="$2" look="${3:-signal}"
  xcrun simctl terminate "$udid" "$bundle_id" >/dev/null 2>&1 || true
  sleep 1
  xcrun simctl launch "$udid" "$bundle_id" -demo -screen "$screen" -theme "$look" >/dev/null
  sleep 6
  local attempt size
  for attempt in 1 2 3 4; do
    xcrun simctl io "$udid" screenshot --type=png "$out/$name.png" >/dev/null
    size=$(stat -f%z "$out/$name.png")
    # A frame with only the background compresses below ~100 KB; a real screen is well above it.
    if [ "$size" -gt 110000 ]; then break; fi
    echo "::warning::$name looks blank ($size bytes), attempt $attempt"
    diagnose "$name-blank-$attempt"
    if [ "$attempt" -eq 2 ]; then
      xcrun simctl terminate "$udid" "$bundle_id" >/dev/null 2>&1 || true
      sleep 1
      xcrun simctl launch "$udid" "$bundle_id" -demo -screen "$screen" -theme "$look" >/dev/null
    fi
    sleep 4
  done
  echo "captured $out/$name.png ($size bytes)"
  diagnose "$name"
}

shoot 01-today today
shoot 02-today-done today-done
shoot 03-add add
shoot 04-settings settings
shoot 05-day day
shoot 06-log log
shoot 07-widgets widgets
shoot 08-empty empty
# Taken Pro (PRO.md): the paywall (yearly selected, introductory week available) and TODAY locked without Pro.
# CI has no App Store account, so under -demo the paywall shows StoreKit-shaped plans instead of loading products.
shoot 09-paywall paywall
shoot 10-locked locked
shoot 11-widgets-locked widgets-locked

# The four looks (SPEC section 4), each chosen with -theme. Names end in the look, never in a state, so the store-shots
# matcher (tools/store-shots/generate.mjs) keeps finding the Signal captures above by their state.
shoot 13-look-signal look signal
for look in blush phosphor ice; do
  shoot "14-today-$look" today "$look"
  shoot "15-today-done-$look" today-done "$look"
  shoot "16-log-$look" log "$look"
  shoot "17-paywall-$look" paywall "$look"
  shoot "18-widgets-$look" widgets "$look"
  shoot "19-look-$look" look "$look"
done
# Blush is the light look: the sheets, system controls and locked states get a capture too.
shoot 20-settings-blush settings blush
shoot 21-add-blush add blush
shoot 22-day-blush day blush
shoot 23-locked-blush locked blush
shoot 24-empty-blush empty blush
shoot 25-widgets-locked-blush widgets-locked blush

# The paywall on a 6.3 inch iPhone as well, where its compact layout must still show every plan above the button.
if [ -n "$small" ] && [ "$small" != "$udid" ]; then
  xcrun simctl terminate "$udid" "$bundle_id" >/dev/null 2>&1 || true
  xcrun simctl shutdown "$udid" >/dev/null 2>&1 || true
  prepare "$small"
  udid="$small"
  xcrun simctl launch "$udid" "$bundle_id" -demo -screen today >/dev/null
  sleep 6
  shoot 12-paywall-6.3in paywall
fi

xcrun simctl terminate "$udid" "$bundle_id" >/dev/null 2>&1 || true
ls -la "$out"
crashes="$(ls ~/Library/Logs/DiagnosticReports 2>/dev/null | grep -i taken || true)"
if [ -n "$crashes" ]; then
  echo "::warning::Crash reports found"
  for report in $crashes; do
    cp ~/Library/Logs/DiagnosticReports/"$report" "$diag/" || true
    head -n 60 ~/Library/Logs/DiagnosticReports/"$report" || true
  done
fi
