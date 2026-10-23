#!/usr/bin/env bash
# App Review Guideline 2.5.19 (no hidden, dormant or undocumented features): an App Store build of Taken must not
# contain the owner-only Pro unlock (InternalBuild, Shared/Pro.swift), the taken://todo-eval sheet
# (Taken/Todo/TodoEval.swift) or the voice note log (Taken/Todo/VoiceNoteLog.swift, taken://todo-log). All three
# compile only with DEBUG or TAKEN_INTERNAL (project.internal.yml, the EAS "internal" profile), so a Release build
# generated from project.yml carries none of their markers, and neither Info.plist has the TakenInternalPro key.
#
# The markers are text an optimised Release build keeps when the code is compiled in (checked on the internal build
# 1.1.0 (9)): the plist key "TakenInternalPro" (app and widget), the eval's type names and one eval note. The voice
# note log's type names (16 and 17 bytes, the same kind of name as the eval's) are markers too; --internal requires
# VoiceNoteLogView, which proves the scan sees them before an App Store build is called clean of them. Swift keeps
# strings of 15 bytes or fewer inside the code, where strings(1) cannot see them, and drops literals only tests use
# ("taken://todo-eval" is gone from that build), so do not swap in a short or test-only string.
#
# An internal build must also be exported "TestFlight internal testing only" (.eas/build/build-ios-internal.yml), so
# App Store Connect can never put it in an App Store version or App Review. Xcode's export with that option writes
# TFInternalTestingOnly = true into the app's Info.plist (seen on the internal build 1.1.0 (14), not on (12) or (13));
# an App Store build must not have it.
#
# Usage: scripts/check-app-store-build.sh path/to/Taken.app            the App Store shape: no marker may be present
#        scripts/check-app-store-build.sh --internal path/to/Taken.app  the internal shape: the markers must be present
set -euo pipefail

expect=absent
if [ "${1:-}" = "--internal" ]; then
  expect=present
  shift
fi
app="${1:?usage: check-app-store-build.sh [--internal] path/to/Taken.app}"
appex="$app/PlugIns/TakenWidgets.appex"
markers='TakenInternalPro|TodoEvalView|TodoEvalRunner|TodoEvalRoute|VoiceNoteLogView|VoiceNoteLogStore|Restock Always pads and Native deodorant'
# Every build of both targets keeps the App Group ID (TakenStore.appGroupID): a scan that cannot see it read nothing,
# and the check fails rather than calling an unread binary clean.
control='group.com.tombaxter.taken'

command -v strings >/dev/null && test -x /usr/libexec/PlistBuddy \
  || { echo "::error::strings or PlistBuddy is not available"; exit 1; }

# The markers in one binary, space separated ("" when none). Fails when the binary cannot be read.
markers_in() {
  test -s "$1" || { echo "::error::$1 is missing" >&2; exit 1; }
  local text
  text="$(strings -a "$1")" || { echo "::error::strings failed on $1" >&2; exit 1; }
  grep -q -F "$control" <<<"$text" || { echo "::error::$1 has no $control: the scan read nothing" >&2; exit 1; }
  { grep -o -E "$markers" <<<"$text" || [ $? -eq 1 ]; } | sort -u | tr '\n' ' '
}
# "yes" when the Info.plist carries the TakenInternalPro key. Fails when the plist cannot be read.
plist_marked() {
  test -f "$1" || { echo "::error::$1 is missing" >&2; exit 1; }
  # Every real Info.plist names its bundle: one that does not is unreadable, not unmarked.
  plutil -extract CFBundleIdentifier raw -o - "$1" >/dev/null 2>&1 \
    || { echo "::error::$1 is not a readable Info.plist" >&2; exit 1; }
  if /usr/libexec/PlistBuddy -c 'Print :TakenInternalPro' "$1" >/dev/null 2>&1; then echo yes; else echo no; fi
}

app_hits="$(markers_in "$app/Taken")"
widget_hits="$(markers_in "$appex/TakenWidgets")"
app_plist="$(plist_marked "$app/Info.plist")"
widget_plist="$(plist_marked "$appex/Info.plist")"
# plutil prints its "no value" error on stdout, so a failed read is "unset", not its message.
internal_only="$(plutil -extract TFInternalTestingOnly raw -o - "$app/Info.plist" 2>/dev/null)" || internal_only=unset
report="Taken: ${app_hits:-none}; TakenWidgets: ${widget_hits:-none}; Info.plist marker: app $app_plist, widget $widget_plist; TFInternalTestingOnly: $internal_only"

if [ "$expect" = "absent" ]; then
  if [ -n "$app_hits$widget_hits" ] || [ "$app_plist" = yes ] || [ "$widget_plist" = yes ]; then
    echo "::error::App Store build contains internal-only code. $report"
    exit 1
  fi
  if [ "$internal_only" = true ]; then
    echo "::error::App Store build is exported TestFlight internal testing only, so it could never be submitted. $report"
    exit 1
  fi
  echo "App Store shape: no internal-only code or TakenInternalPro marker in Taken or TakenWidgets"
  exit 0
fi

# The internal build must show each kind of marker where it belongs, which also proves this check can see them.
case " $app_hits " in *" TakenInternalPro "*) ;; *) echo "::error::Taken lacks the Pro unlock. $report"; exit 1 ;; esac
case " $app_hits " in *" TodoEvalView "*) ;; *) echo "::error::Taken lacks the eval sheet. $report"; exit 1 ;; esac
case " $app_hits " in *" VoiceNoteLogView "*) ;; *) echo "::error::Taken lacks the voice note log. $report"; exit 1 ;; esac
case " $widget_hits " in *" TakenInternalPro "*) ;; *) echo "::error::TakenWidgets lacks the Pro unlock. $report"; exit 1 ;; esac
if [ "$app_plist" != yes ] || [ "$widget_plist" != yes ]; then
  echo "::error::An Info.plist lacks the TakenInternalPro marker. $report"
  exit 1
fi
if [ "$internal_only" != true ]; then
  echo "::error::Not exported TestFlight internal testing only: App Store Connect could put it in App Review. $report"
  exit 1
fi
echo "Internal shape: $report"
