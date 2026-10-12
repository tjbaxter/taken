#!/usr/bin/env bash
# Capture App Store screenshots from the simulator with demo data.
# Usage: scripts/screenshots.sh <simulator-udid> <path/to/Taken.app> <output-dir> [diagnostics-dir]
set -euo pipefail

udid="$1"
app="$2"
out="$3"
diag="${4:-$out-diagnostics}"
bundle_id="com.tombaxter.taken"

mkdir -p "$out" "$diag"
xcrun simctl boot "$udid" 2>/dev/null || true
xcrun simctl bootstatus "$udid" -b
xcrun simctl ui "$udid" appearance dark || true
xcrun simctl status_bar "$udid" override \
  --time "9:41" \
  --dataNetwork wifi --wifiMode active --wifiBars 3 \
  --cellularMode active --cellularBars 4 --operatorName "" \
  --batteryState discharging --batteryLevel 100
xcrun simctl install "$udid" "$app"

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
  local name="$1" screen="$2"
  xcrun simctl terminate "$udid" "$bundle_id" >/dev/null 2>&1 || true
  sleep 1
  xcrun simctl launch "$udid" "$bundle_id" -demo -screen "$screen" >/dev/null
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
      xcrun simctl launch "$udid" "$bundle_id" -demo -screen "$screen" >/dev/null
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
