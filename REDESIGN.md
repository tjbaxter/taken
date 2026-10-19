# Taken 1.1 redesign + voice to-dos (Tom's feedback 2026-10-13)

Tom used 1.0 on his iPhone. Verbatim highlights:
- "it feels like a bit too much going on in one place. It feels a bit messy ... What's that little 0, 4, 10, 16, 22, 04? ... bracket 0, 2, stack, dash, dash, dash, dash, dash, 3 taken. It feels like there's too much. It's too mil-techy. There's too many little decals ... It's quite confusing. It needs to be a lot simpler."
- "I don't know how I feel about having to scroll down to look at the calendar ... it feels a bit beta."
- "I'm seeing nowhere to add another thing. I have to go into the settings gear icon to add another thing. That's not very intuitive. I think there should be a plus button somewhere around the stack."
- "how does it work when I've got things I take daily and then things I take alternate days? ... will Finasteride still be there [tomorrow]? Because it shouldn't be."
- "I want my account. I want Thomas Baxter. I want maybe a profile picture option ... customize it."
- Reminders / to-dos: "it needs to be AI based and pure voice note ... I can say ... today by 4 p.m. I need to do X, Y, and Z ... in a string of messy words ... the AI will decompose what I've said and assign it into tasks. And then I can tap to complete those tasks ... if I'm on the move, if I'm busy ... stream of consciousness as quickly and easy as possible. It should be, again, one tap, voice note, done ... one toggle to get there, one toggle to see it ... the AI should be doing all the heavy lifting for me."
- "You got it right with the taken one ... common pills pre-filled. It was tap, tap, tap. It was really nice." "Day starts at, I like that." "Haptics on, export CSV, cool." "I don't want to overbuild this." (Skincare: explicitly out of scope.)

## Decisions (owner: Claude, per Tom "You tell me")

### Navigation
- Native iOS bottom tab bar (system TabView, Liquid Glass on iOS 26), three tabs: **Today** (pills), **To-do** (voice to-dos), **History** (calendar and stats). The calendar leaves the Today screen.
- Profile avatar (photo or initials) top-right on every tab opens **Profile**: name, photo, streak summary, then all settings (Stack, Look, Reminder, Day starts at, Haptics, Pro, Data, About). The gear disappears.

### Simpler visual language (applies to all four looks)
- Remove the HUD decals: section numbers like [01]/[02], the 24-hour tick ruler, dashed rules, viewfinder corner brackets on panels, LIVE/LOCKED IN micro-labels, scanline sweep. Keep: dark premium canvas, one accent colour (amber in Signal), Geist for text, Geist Mono only for times and counts, generous spacing, large tap targets, the satisfying check animation and haptics.
- Today = large title "Today" with date, one calm progress line ("2 of 3 taken" + a slim bar), then the list. Rows: name, small frequency label, and on the right either an empty ring (pending) or an accent check with the time ("07:42"). A plain "Take all" button only when 2+ are pending. A clear "+" in the list header (next to the stack title) opens Add.
- Not-due items (alternate days) sit in a quiet "Not today" group with "Next: Thursday" so nobody wonders.
- All-done state: a simple, satisfying "All taken" moment (check, haptic), no locked-in HUD.

### Adding and editing items
- "+" on Today opens the Add sheet (chips stay exactly as loved). After picking chips, each selected item shows its own frequency control (Daily / Every other day / 2x / 3x / Days) so Finasteride can be every other day while D3 is daily, in the same flow.
- Tapping an item's name (or long-press) opens a small item sheet: frequency, time-of-day hint optional, rename, archive, delete. No trip to settings.

### Profile ("account")
- Profile = name + photo (PhotosPicker, cropped circle) + initials fallback, stored locally in the App Group store. No passwords, no sign-up wall. On first launch nothing is asked; Profile is optional and reachable from the avatar. (Cloud backup/sync via the user's own iCloud is a later step: it needs an iCloud container registered in the developer portal.)

### Voice to-dos (Pro feature)
- To-do tab: a big round mic button. One tap starts recording immediately (no extra screen), a live waveform and transcript show, tap again (or 1.5 s silence after speech, configurable later) to stop. The AI turns the ramble into tasks in about a second; tasks appear with a gentle animation. Tap a task's circle to complete it (strike + haptic); swipe to delete; tap to edit text/time. Completed tasks fold into a "Done today" section; yesterday's open tasks stay until done.
- Each task: title (short imperative), optional due time ("by 4 pm" -> 16:00 today), optional day (today/tomorrow/date), created-from-note id. Tasks with a due time sort first and can get a local notification at that time (only if Reminder notifications are allowed).
- Speech to text: on-device. iOS 26: SpeechAnalyzer/SpeechTranscriber; iOS 17-25: SFSpeechRecognizer with requiresOnDeviceRecognition when supported. Audio is never stored or uploaded.
- Turning text into tasks: on-device **Apple Foundation Models** (iOS 26, Apple Intelligence devices, Tom's iPhone qualifies) with guided generation into a @Generable task list; pass the current date/time and day-start so "by 4" and "tomorrow" resolve. If Foundation Models is unavailable (older phone or Apple Intelligence off), fall back to a single task containing the transcript, editable, with a one-line note that automatic sorting needs Apple Intelligence. (A Claude Haiku on Bedrock fallback for older phones is a later step; it needs a small backend and a consent screen under App Review 5.1.2.)
- Quick capture from anywhere: an App Intent "New voice to-do" that opens straight into recording, offered as a Control Center control, a Lock Screen widget, an Action Button option and a Home Screen quick action (long-press the icon). Siri phrase "Add to-dos in Taken".
- Privacy: transcription and task extraction happen on the iPhone; the privacy label stays "Data Not Collected". Add NSMicrophoneUsageDescription and NSSpeechRecognitionUsageDescription with plain wording.
- Pro: voice to-dos need Pro (paywall bullet "VOICE TO-DOS"); the first voice note works without Pro so people feel it.
- Two lists, Personal and Work (Tom 2026-10-19: "personal things and then business related to-dos ... toggle it"), one in view at a time under the To-do title, and a note lands in the list in view. Named Work rather than Business because Personal and Work are Apple's own default Focus names (https://support.apple.com/guide/watch/apd6640937c4/watchos) and Sunsama's contexts use #work and #personal (https://help.sunsama.com/docs/usage-guides/channels-and-contexts).

### Wake-up time (replaces "Day starts at"; Tom 2026-10-13: "this is confusing, fix this, people are allowed to change the day they wake up, don't say don't")
- The setting is "Wake-up time" (default 07:00, any time of day, mono time picker). One plain helper line: "Doses count for the day you wake up into."
- Code owns the day boundary: rollover = wake-up time minus 4 hours, clamped to 00:00 through 12:00 (wake 08:00 -> 04:00; wake 05:00 -> 01:00; wake 14:00 -> 10:00; wake 02:00 -> 00:00). Users never see or set the rollover. Migrate an existing dayStartHour setting to wake-up = dayStart + 4 h so nobody's history moves.
- Wake-up time also sets sensible defaults: backfill time on a past day = wake-up time + 1 h; the nudge default = wake-up time + 13 h if the user never chose one.
- Never tell the user not to pick a time; there is no wrong answer.
