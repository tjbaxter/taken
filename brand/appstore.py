#!/usr/bin/env python3
"""Writes brand/appstore.md: the App Store Connect listing for Taken, with every
character count measured by code against Apple's limits. Edit the copy here,
then run:  python3 brand/appstore.py
"""
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))

NAME = "Taken: Pill & Supplement Log"
NAME_FALLBACK = "Taken: Supplement Tracker"
SUBTITLE = "Did I take it? Know for sure."

PROMO = (
    "Tap once when you take it. Open it later and see exactly when. "
    "No ads, no account, no typing. Your log never leaves your iPhone."
)

DESCRIPTION = """\
It's late, and you can't remember: did I take it today? Taken is the source of truth for your daily pills and supplements. Tap when you take it. Look later and know for sure, down to the minute.

ONE TAP
• Tap a pending item and it lights up with the time you took it.
• TAKE ALL logs your whole stack in a single tap.
• A stray tap never un-logs a dose, and Undo is right there if you need it.

KNOW FOR SURE
• Every dose keeps its exact time stamp: TAKEN 07:42, 9H AGO.
• Remember twice in one day? The answer is on screen the moment you open the app.
• Forgot to log? Set the real time, or fix an earlier day from the history grid.
• Day rollover at 04:00 by default, so a late-night dose counts for the day you were living. Change it to suit you.

LOG IT FROM ANYWHERE
• Interactive Home Screen widgets: log a dose or take all without opening the app.
• Lock Screen widgets show 2/3 before you unlock.
• A Take all control for Control Center.
• Siri: ask "Did I take my pills in Taken" and hear the answer with times. Say "Log my stack in Taken" to take everything.

A REMINDER THAT STAYS QUIET
• One optional nudge at the time you choose.
• It only fires if something is still pending. Already done? Silence.
• Take all straight from the notification.

YOUR RECORD
• Five weeks of days as a grid of lit ticks.
• Your streak and 30-day completion at a glance.
• Daily, 2x or 3x daily, alternate days, or the weekdays you pick.
• Export every dose to CSV whenever you want it.

NOTHING ELSE
• No ads. No account. No onboarding funnel.
• No typing needed: add your stack from quick-pick chips in a few taps.
• No tracking, no analytics, no third-party code. Taken never connects to the internet. Everything stays on your iPhone.

Taken is a personal log, not medical advice. Always follow the directions from your doctor or pharmacist."""

# 100 max, comma separated, no spaces, no word already in the name or subtitle
# (Apple indexes those already and combines words across fields).
KEYWORDS = [
    "reminder",    # pill reminder (largest query in the category)
    "tracker",     # pill / supplement / vitamin / medication tracker
    "medication",  # medication tracker, medication reminder
    "vitamin",     # vitamin tracker, vitamin reminder
    "meds",        # meds tracker
    "medicine",    # medicine reminder
    "habit",       # habit tracker searches from the daily-routine crowd
    "dose",        # dose tracker, dose log
    "daily",       # daily pill, daily vitamins
    "creatine",    # creatine tracker (gym and biohacker searches)
    "checklist",   # daily checklist
    "stack",       # supplement stack
    "alarm",       # pill alarm
]

WHATS_NEW = (
    "The first release of Taken. Tap to log, take all, exact times, widgets for the Home Screen and "
    "Lock Screen, a Control Center control and Siri. Your log stays on your iPhone."
)

REVIEW_NOTES = """\
No login, account or network connection is needed, and there are no in-app purchases. Taken stores everything on the device and makes no network requests.

How to try it:
1. On first launch tap ADD TO STACK, tap three chips (for example Vitamin D3, Fish Oil and Finasteride) and tap ADD (3). TODAY shows 0/3 and TAKE ALL (3).
2. Tap the Vitamin D3 row. It lights up with the current time, and a toast offers UNDO. Leave the other two pending for the steps below. Touch and hold any row for Undo last dose, Set time and Edit item.
3. Tap today's outlined cell in the history grid to see the day, log a dose at a chosen time or remove one.

Steps 4 to 8 each log what is still pending. If nothing is pending before one of them, touch and hold a taken row in the app and choose Undo last dose.
4. Home Screen: touch and hold the Home Screen, tap Edit, Add Widget, choose Taken, and add the small and the medium widget. Tap a pending row on the medium widget to log that item, or TAKE ALL on the small widget to log everything pending. The count changes on the widget and in the app.
5. Lock Screen: touch and hold the Lock Screen, tap Customize, Lock Screen, and add a Taken widget. It shows the count, for example 2/3.
6. Control Center (iOS 18 and later): open Control Center, tap +, Add a Control, choose Taken, Take all. Tapping it logs everything pending.
7. Siri: say "Did I take my pills in Taken" to hear what is taken and what is pending, or "Log my stack in Taken" to log everything pending. The same actions are in the Shortcuts app under Taken.
8. Reminder: tap the gear, turn on NUDGE under REMINDER (notification permission is requested at that moment), tap the time next to TIME, set it 2 minutes ahead and tap SET. With something still pending, the notification arrives at that time: touch and hold it and tap TAKE ALL to log everything pending without opening the app. With nothing pending, no notification is sent."""

SUPPORT_URL = "https://tjbaxter.github.io/taken/#support"
MARKETING_URL = "https://tjbaxter.github.io/taken/"
PRIVACY_URL = "https://tjbaxter.github.io/taken/privacy.html"

LIMITS = {
    "name": 30,
    "subtitle": 30,
    "promo": 170,
    "description": 4000,
    "keywords": 100,
    "whats_new": 4000,
    "review_notes": 4000,
}


def check_copy(label, text):
    banned = []
    if re.search(r"[–—]", text):
        banned.append("en/em dash")
    if re.search(r"(?i)\bfree\b", text):
        banned.append("the word free")
    if "!" in text:
        banned.append("exclamation mark")
    if banned:
        raise SystemExit(f"{label}: contains {', '.join(banned)}")


def main():
    keywords = ",".join(KEYWORDS)
    name_words = set(re.findall(r"[a-z]+", (NAME + " " + SUBTITLE).lower()))
    dupes = [k for k in KEYWORDS if k in name_words]
    assert not dupes, f"keywords repeat name/subtitle words: {dupes}"
    assert " " not in keywords

    fields = {
        "name": NAME,
        "subtitle": SUBTITLE,
        "promo": PROMO,
        "description": DESCRIPTION,
        "keywords": keywords,
        "whats_new": WHATS_NEW,
        "review_notes": REVIEW_NOTES,
    }
    counts = {}
    for key, text in fields.items():
        check_copy(key, text)
        counts[key] = len(text)
        assert counts[key] <= LIMITS[key], f"{key} is {counts[key]} chars, limit {LIMITS[key]}"
    assert len(NAME_FALLBACK) <= 30

    def c(key):
        return f"{counts[key]} / {LIMITS[key]} characters"

    md = f"""# Taken: App Store listing

Generated by `brand/appstore.py`, which measures every field with code against Apple's limits and fails on an em or en dash, the word "free" or an exclamation mark. Paste each block into App Store Connect as is.

## App information

| Field | Value |
| --- | --- |
| Name | `{NAME}` ({c("name")}) |
| Name fallback, if the name is unavailable | `{NAME_FALLBACK}` ({len(NAME_FALLBACK)} / 30 characters) |
| Subtitle | `{SUBTITLE}` ({c("subtitle")}) |
| Primary category | Health & Fitness |
| Secondary category | Lifestyle (optional) |
| Age rating | 4+ (answer None or No to every content question, including medical or treatment information: Taken is a log and gives no medical information) |
| Price | No charge. No in-app purchases. No ads. |
| App Privacy | Data Not Collected |
| Encryption | Uses no non-exempt encryption (ITSAppUsesNonExemptEncryption = NO) |
| Copyright | 2026 Thomas Baxter |
| Support URL | {SUPPORT_URL} |
| Marketing URL | {MARKETING_URL} |
| Privacy Policy URL | {PRIVACY_URL} |

## Promotional text ({c("promo")})

```
{PROMO}
```

## Description ({c("description")})

```
{DESCRIPTION}
```

## Keywords ({c("keywords")})

```
{keywords}
```

Comma separated with no spaces, and no word that already appears in the name or subtitle (Apple indexes those and combines words across fields, so `pill` + `reminder` matches "pill reminder", `supplement` + `tracker` matches "supplement tracker", `vitamin` + `tracker` matches "vitamin tracker").

| Keyword | Why |
| --- | --- |
""" + "".join(
        f"| `{k}` | {why} |\n" for k, why in KEYWORD_NOTES
    ) + f"""
## What's New in Version 1.0 ({c("whats_new")})

```
{WHATS_NEW}
```

## App Review notes ({c("review_notes")})

```
{REVIEW_NOTES}
```

Sign-in required: No. Contact details for App Review come from the account holder.

## Character counts

| Field | Count | Limit |
| --- | --- | --- |
""" + "".join(f"| {k} | {counts[k]} | {LIMITS[k]} |\n" for k in fields) + """
## Screenshots

Produced later in CI from simulator captures (6.9 inch iPhone, 1320 x 2868).
"""
    out = os.path.join(HERE, "appstore.md")
    with open(out, "w") as f:
        f.write(md)
    for k in fields:
        print(f"{k:13s} {counts[k]:5d} / {LIMITS[k]}")
    print("wrote", out)


KEYWORD_NOTES = [
    ("reminder", "Pairs with pill in the name: pill reminder is the largest query in the category"),
    ("tracker", "Pairs with pill, supplement, vitamin and medication for every tracker query"),
    ("medication", "Medication tracker and medication reminder, the next biggest family"),
    ("vitamin", "Vitamin tracker and vitamin reminder"),
    ("meds", "Meds tracker, the short form people type"),
    ("medicine", "Medicine reminder and medicine tracker"),
    ("habit", "Habit tracker searches from people who treat their stack as a daily habit"),
    ("dose", "Dose tracker, dose log"),
    ("daily", "Daily pill, daily vitamins, daily supplement"),
    ("creatine", "Creatine tracker, a growing gym and biohacker search"),
    ("checklist", "Daily checklist, the simplest mental model of the app"),
    ("stack", "Supplement stack, how biohackers name their routine"),
    ("alarm", "Pill alarm"),
]


if __name__ == "__main__":
    main()
