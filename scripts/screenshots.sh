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
    # awk stops at 45 lines itself: piping it into head under pipefail failed the job whenever head closed first.
    awk '/^Call graph:/{on=1; next} on && /^    [0-9]+ Thread_/{n++} on && n>=2{exit} on{print; if (++m >= 45) exit}' \
      "$diag/$name.sample.txt" > "$diag/$name.main-thread.txt" || true
    if ! grep -q "mach_msg" "$diag/$name.main-thread.txt"; then
      echo "::warning::$name: main thread is busy, not idle in its run loop"
      cat "$diag/$name.main-thread.txt"
    fi
  fi
}

# What the demo app last wrote about the screen in front (DemoProbe), in this simulator's container.
probe_file() {
  echo "$(xcrun simctl get_app_container "$udid" "$bundle_id" data)/tmp/taken-ui-state.txt"
}

shoot() {
  local name="$1" screen="$2" look="${3:-signal}"
  xcrun simctl terminate "$udid" "$bundle_id" >/dev/null 2>&1 || true
  rm -f "$(probe_file)"
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
# StandBy and CarPlay remove a widget's canvas and draw it on black: Blush switches to its dark-canvas text there.
shoot 26-widgets-standby-blush widgets-standby blush
shoot 26-widgets-standby-signal widgets-standby signal
# Locked mode in Settings (the nudge needs Pro), and the paywall when the App Store returned every plan but yearly.
shoot 27-settings-locked settings-locked
shoot 28-paywall-no-yearly paywall-no-yearly

# Voice to-dos (SPEC 3.10): the To-do tab as one list, Personal then Work, with demo tasks (a time today, tomorrow at
# 09:00, done today under Personal) in every look, and listening with the words on screen.
shoot 29-todo todo
shoot 30-todo-recording todo-recording
for look in blush phosphor ice; do
  shoot "31-todo-$look" todo "$look"
done
shoot 32-todo-recording-blush todo-recording blush
shoot 33-todo-empty todo-empty
# The item sheet a tap on an item's name opens (Finasteride, every other day), and voice to-dos away from the app: the
# Lock Screen mic, list and count, and the Control Center controls.
shoot 36-item item
shoot 37-widgets-todo widgets-todo
shoot 38-widgets-todo-blush widgets-todo blush

# A -screen state must land where it says, not only look right: the probe written by the launch just captured.
lands() {
  local name="$1" expect="$2" state line
  state="$(cat "$(probe_file)" 2>/dev/null || true)"
  echo "$name in front: $(echo "$state" | tr '\n' ' ')"
  for line in $expect; do
    if ! grep -qx "$line" <<<"$state"; then
      echo "::error::$name should leave $line in front, found: $(echo "$state" | tr '\n' ' ')"
      exit 1
    fi
  done
}

# The 1.1 feedback build (SPEC 3.3, 3.10): the To-do tab as one list with Work dragged on top (so notes go there), and
# the Add sheet in type mode with "tum" typed (Turmeric suggested), in every look. The chip grid shows under the
# field, Semaglutide and Tirzepatide among the chips: keep these out of UK store screenshots (REDESIGN.md, Open).
shoot 41-todo-work todo-work
lands 41-todo-work "tab=todo sheet=none todoOrder=work,personal todoInto=work"
shoot 43-add-search add-search
lands 43-add-search "sheet=add"
for look in blush phosphor ice; do
  shoot "42-todo-work-$look" todo-work "$look"
  shoot "44-add-search-$look" add-search "$look"
done
# Feedback build 2 (Tom 2026-10-20): three open on Personal and nothing on Work, the state where "3 open" bounced. Both
# headings show, Work reads "Nothing open", and the line under the title stays. Then a note at its last minute ("0:40
# left") and the typing sheet, each with its list chip on the list on top.
shoot 46-todo-work-empty todo-work-empty
lands 46-todo-work-empty "tab=todo sheet=none todoOrder=personal,work"
shoot 47-todo-cap todo-cap
lands 47-todo-cap "tab=todo sheet=none todo=listening todoInto=personal"
shoot 48-todo-type todo-type
lands 48-todo-type "tab=todo sheet=todo-type todoInto=personal"
# Links reach the right screen with the quick action's scene delegate in place: Taken opens its own link after launch
# (-open-url, demo only, as a widget tap does; simctl openurl stops at an "Open in Taken?" prompt). The demo app writes
# what is in front to tmp/taken-ui-state.txt (DemoProbe), and the check fails unless the link landed there:
# taken://pro over Today locked opens the paywall; taken://todo and taken://todo/record open the To-do tab, over Profile,
# and the record link leaves it listening (the demo shows the listening state: CI has no microphone).
link() {
  local name="$1" screen="$2" url="$3" expect="$4"
  xcrun simctl terminate "$udid" "$bundle_id" >/dev/null 2>&1 || true
  sleep 1
  local container
  container="$(xcrun simctl get_app_container "$udid" "$bundle_id" data)"
  rm -f "$container/tmp/taken-ui-state.txt"
  xcrun simctl launch "$udid" "$bundle_id" -demo -screen "$screen" -open-url "$url" >/dev/null
  sleep 9
  xcrun simctl io "$udid" screenshot --type=png "$out/$name.png" >/dev/null
  local state
  state="$(cat "$container/tmp/taken-ui-state.txt" 2>/dev/null || true)"
  echo "captured $out/$name.png after $url; in front: $(echo "$state" | tr '\n' ' ')"
  for line in $expect; do
    if ! grep -qx "$line" <<<"$state"; then
      echo "::error::$name: $url should leave $line in front, found: $(echo "$state" | tr '\n' ' ')"
      exit 1
    fi
  done
}
link 34-link-pro locked "taken://pro" "paywall=1"
link 35-link-todo settings "taken://todo" "tab=todo sheet=none"
link 39-link-record settings "taken://todo/record" "tab=todo sheet=none todo=listening"
if cmp -s "$out/35-link-todo.png" "$out/04-settings.png"; then
  echo "::error::35-link-todo is the Profile screen it started on: taken://todo did not open the To-do tab"
  exit 1
fi

# The paywall on a 6.3 inch iPhone as well, where its compact layout must still show every plan above the button.
if [ -n "$small" ] && [ "$small" != "$udid" ]; then
  xcrun simctl terminate "$udid" "$bundle_id" >/dev/null 2>&1 || true
  xcrun simctl shutdown "$udid" >/dev/null 2>&1 || true
  prepare "$small"
  udid="$small"
  xcrun simctl launch "$udid" "$bundle_id" -demo -screen today >/dev/null
  sleep 6
  shoot 12-paywall-6.3in paywall
  # Today on the smaller iPhone: the Not today group stays in view above Take all.
  shoot 40-today-6.3in today
  # Type mode on the smaller iPhone: the pinned field and the suggestion rows stay above the keyboard.
  shoot 45-add-search-6.3in add-search
  # The one To-do list on the smaller iPhone: both headings and the mic above the tab bar.
  shoot 49-todo-6.3in todo
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
