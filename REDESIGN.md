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
- Two lists, Personal and Work (Tom 2026-10-19: "personal things and then business related to-dos ... toggle it"), one in view at a time under the To-do title, and a note lands in the list in view. Named Work rather than Business because Personal and Work are Apple's own default Focus names (https://support.apple.com/guide/watch/apd6640937c4/watchos) and Sunsama's contexts use #work and #personal (https://help.sunsama.com/docs/usage-guides/channels-and-contexts). (Replaced 2026-10-20 by one list with a heading for each, "1.1 feedback build 2" below, and that 2026-10-21 by one list with no lists, "1.1 feedback build 3".)

### Wake-up time (replaces "Day starts at"; Tom 2026-10-13: "this is confusing, fix this, people are allowed to change the day they wake up, don't say don't")
- The setting is "Wake-up time" (default 07:00, any time of day, mono time picker). One plain helper line: "Doses count for the day you wake up into."
- Code owns the day boundary: rollover = wake-up time minus 4 hours, clamped to 00:00 through 12:00 (wake 08:00 -> 04:00; wake 05:00 -> 01:00; wake 14:00 -> 10:00; wake 02:00 -> 00:00). Users never see or set the rollover. Migrate an existing dayStartHour setting to wake-up = dayStart + 4 h so nobody's history moves.
- Wake-up time also sets sensible defaults: backfill time on a past day = wake-up time + 1 h; the nudge default = wake-up time + 13 h if the user never chose one.
- Never tell the user not to pick a time; there is no wrong answer.

## 1.1 feedback build (Tom's feedback 2026-10-19)

Tom used the 1.1 TestFlight build. Verbatim highlights:
- "the quality of taking a to-do needs to be improved massively ... let me just examine this text and actually extract what are the actual to-dos done, and then let me give it an appropriate name as well. But yeah, I guess they're nice and short because we don't want paragraphs on the to-do list"
- "today I wanted to order new toothbrushes, right, from a company called Reach. So I said, order Reach toothbrushes on Amazon ... it split the request up into two separate things, even though it was one voice note."
- "I want a section where it's like personal things and then business related to-dos. I don't want to be mixing to-dos in with each other. So if maybe I could like toggle it"
- "when I click custom, it's so ugly. It like spawns a cursor, but the add button is cutting off half of the text box ... that whole animation needs to be a lot more premium and intentional."
- "do people even know how to spell turmeric ... spawn a drop down menu of suggestions so people don't have to type the whole word and like spell it correctly ... like when you enter an address"
- "maybe we add a few peptides ... remember to take your peptides on the right day ... we don't want to make it dominant peptides and alienate people"
- "a female ... and male logos ... quick toggle ... the main thing is we don't want to overwhelm"
- "connect your personal agent ... Claude can see, oh, I see you've taken your pills today"
- "it does transcribe some things wrong for me" ... "If you want to use Apple, I'm happy to do that."
- "make sure people can't, like, rinse us ... put a sensible limit" (everything runs on the iPhone, so there is no per-use cost and nothing to limit).

### Decisions (owner: Claude; each rests on the sources named, and anything marked own choice has none)

Voice notes: one action is one to-do (SPEC 3.10)
- The cause was in the code: the instructions said "Make one task for each separate thing" and "Split lists like X, Y and Z", titles had to start with a verb, nothing tied a task to the words it came from, and only exact duplicates were dropped. The fix stays on the iPhone and follows Apple's documented practice for the on-device model: short instructions, three simple examples (Apple: 2 to 15; WWDC25 248: fewer than five), a grounding field (`spoken`) generated before the title because properties are generated in the order they are declared, and code that owns what is saved (`TodoGrounding`, rules G1 to G6). Extractions are kept only where they line up with the source text and never overlap, as Google's LangExtract does.
  - https://developer.apple.com/tutorials/data/documentation/foundationmodels/generating-swift-data-structures-with-guided-generation.json
  - https://developer.apple.com/tutorials/data/documentation/foundationmodels/prompting-an-on-device-foundation-model.json
  - https://developer.apple.com/tutorials/data/documentation/foundationmodels/generating-content-and-performing-tasks-with-foundation-models.json
  - https://developer.apple.com/tutorials/data/documentation/foundationmodels/generationguide/maximumcount(_:).json
  - https://developer.apple.com/videos/play/wwdc2025/248/
  - https://developers.googleblog.com/en/introducing-langextract-a-gemini-powered-information-extraction-library/
- `spoken` is at most 12 words: the iPhone writes about 30 tokens a second (https://machinelearning.apple.com/research/introducing-apple-foundation-models) and a note falls back to one to-do after 15 s. Code still places a shortened span.
- A full stop or question mark is only a weak separator: whether SpeechTranscriber punctuates is undocumented (DictationTranscriber has an explicit punctuation option), so "Order." may arrive as its own sentence. CI proves "Order. Reach toothbrushes on Amazon." and "Order Reach toothbrushes. On Amazon." both give "Order Reach toothbrushes on Amazon". Own choice.
- Day, time and number words never join two to-dos (G2), because the prompt tells the model to apply "today by 4" to every task in a list; CI proves three tasks sharing "today by 4 pm" stay three. Own choice.
- The recogniser is told the names to expect (the stack first, then the chips and the most widely taken catalog names, at most 100 phrases, Apple: "Limit the total number of phrases to no more than 100", https://developer.apple.com/documentation/speech/sfspeechrecognitionrequest/contextualstrings). Apple's accepted forum answer (https://developer.apple.com/forums/thread/811083) says SpeechTranscriber does not read contextual strings yet and DictationTranscriber does, so on iOS 26 this may change nothing today; it costs at most 0.3 s and never blocks listening. Switching to DictationTranscriber stays deferred.
- The eval is a link (`taken://todo-eval`), not a launch argument, because CI cannot run Apple's model and a TestFlight app takes no launch arguments. It is compiled only into Debug and the EAS "internal" profile's builds (`TAKEN_INTERNAL`, from `project.internal.yml`), and answers only in a build carrying the `TakenInternalPro` marker. Note 6 is "Restock Always pads and Native deodorant"; note 11 says "by Thursday" (due 2026-10-22), since "before Thursday" could mean Wednesday.

Keep as one (SPEC 3.10)
- One tap after the save instead of a review step before it: Apple's HIG asks for generated results that are easy to refine or revert (https://developer.apple.com/design/human-interface-guidelines/generative-ai), and Doist's lesson from Ramble is that easy correction beats perfect first-time accuracy (https://www.producttalk.org/building-todoist-ramble-how-doist-turned-voice-braindumps-into-real-time-task-capture/). Ramble, Stuff and Reminders preview before saving (https://www.todoist.com/help/articles/dictate-to-add-tasks-with-ramble-P1Raq7vVF), which would break "one tap, voice note, done".
- It lasts 10 s, or until the list changes, the mic is tapped or the tab is left, and is also an accessibility custom action on each task of that note while it is live, because a timed line alone is easy to miss with VoiceOver or Switch Control. Own choice.

Personal and Work (SPEC 3.10)
- One list in view at a time, and a note lands in the list in view: Superlist creates voice tasks "directly in the selected list" (https://help.superlist.com/en/articles/224824-create-tasks-and-notes-with-your-voice-talk), Ramble applies the project in view, Sunsama's contexts filter to one (https://help.sunsama.com/docs/usage-guides/channels-and-contexts), and a segmented control suits closely related views with noun labels (https://developer.apple.com/design/human-interface-guidelines/segmented-controls). The names are in the Voice to-dos section above. (Replaced 2026-10-20: one list, notes go to the list on top, "1.1 feedback build 2" below; replaced again 2026-10-21: no lists, "1.1 feedback build 3".)
- The Lock Screen to-do widget follows the list in view and is reloaded whenever it changes; it stays a StaticConfiguration so no placed widget breaks. Own choice. (Replaced 2026-10-20: both lists in the app's order, below; 2026-10-21: the one list, build 3.)

Add sheet: type mode and type-ahead (SPEC 3.3)
- The field is pinned under the header, where neither the keyboard nor the Add bar can cover it, as Apple Health puts a name field at the top with matches under it (https://support.apple.com/en-gb/HT213351). Baymard: keep sticky elements out of the space between a field and the keyboard, and show 4 to 8 suggestions on mobile (https://baymard.com/blog/autocomplete-design). The posted workaround of scrolling after the keyboard appears races it (https://forums.swift.org/t/swiftui-how-to-implement-natural-textfields-keyboard-avoidance-in-scrollview/67616).
- No matchedGeometryEffect across the ScrollView edge (no source shows it behaving there); the field slides in with opacity and a move from the top. Focus is set on appear, because `defaultFocus` is evaluated only when the window first appears or a focus binding moves focus (https://developer.apple.com/documentation/swiftui/view/defaultfocus(_:_:priority:)).
- Typo tolerance follows the engines' documented defaults: 1 typo from 4 letters and 2 from 8, a first-letter typo ranked as two (https://www.algolia.com/doc/guides/managing-results/optimize-search-results/typo-tolerance/in-depth/configuring-typo-tolerance), and a swap of two letters counts as one (https://meilisearch.com/docs/resources/internals/typo_tolerance). Apple's search-field guidance is to suggest as people type (https://developer.apple.com/design/human-interface-guidelines/search-fields).
- The list ships in the binary and was checked offline against RxNorm (public domain, https://www.nlm.nih.gov/research/umls/rxnorm/docs/prescribe.html) and the NIH Dietary Supplement Label Database (https://dsld.od.nih.gov/); names are not copyrightable (https://www.copyright.gov/help/faq/faq-protect.html).

New chips and Weekly (SPEC 3.3)
- Semaglutide and Tirzepatide are approved prescription medicines and dosed weekly on a regularly scheduled day (https://medical.lilly.com/us/products/answers/what-should-a-patient-do-if-they-miss-a-dose-of-zepbound-tirzepatide-209169). The leading GLP-1 tracker lists both and leaves retatrutide out (https://apps.apple.com/us/app/-/id6499510249), and the FDA says retatrutide and cagrilintide cannot be compounded and warns sellers labelling them "for research purposes" (https://www.fda.gov/drugs/drug-alerts-and-statements/fdas-concerns-unapproved-glp-1-drugs-used-weight-loss). Apple Health offers weekly schedules (https://support.apple.com/guide/iphone/track-your-medications-iph811670c81/ios).
- Semaglutide starts on Weekly and switches to Daily in one tap, because the same tracker names daily oral doses.
- Oral Semaglutide is its own non-chip entry on Daily, with Rybelsus and the Wegovy pill as its aliases, because both tablets are taken once a day (Rybelsus label, https://www.accessdata.fda.gov/drugsatfda_docs/label/2025/213051s024%2Cs028s029lbl.pdf; Wegovy pill, https://www.healio.com/news/endocrinology/20260213/fda-approves-wegovy-pill-the-first-oral-glp1-to-treat-obesity). Before, typing Rybelsus started a daily pill on Weekly. Typing Wegovy shows both the injection (Semaglutide, Weekly) and the pill, so the person picks which. Own choice: the entry name "Oral Semaglutide".
- Birth Control is a daily pill many women take: NCHS Data Brief 539 reports pill use at 16.8% among US women aged 20 to 29, as their contraceptive method (https://www.cdc.gov/nchs/products/databriefs/db539.htm). It balances Finasteride and keeps the grid neutral. (The plan called it "the most-used daily pill", which the data brief does not say.)
- Weekly saves as a one-day Days set, so the file format does not change; missed-day, streak and nudge logic is unchanged tonight.

Agents through Shortcuts (SPEC 3.7)
- App Intents that return values are the on-device route shipping apps use: Things' Find Items and Get Item (https://www.macstories.net/reviews/things-3-17-overhauls-the-apps-shortcuts-actions/), Claude's "Ask Claude" action (https://support.claude.com/en/articles/10263469-use-claude-app-intents-shortcuts-and-widgets-on-ios), and iOS 26 "Use Model" taking app entities (https://developer.apple.com/videos/play/wwdc2025/260/). `ReturnsValue` is iOS 16 (https://developer.apple.com/documentation/appintents/returnsvalue) and `EnumerableEntityQuery` iOS 17 (https://developer.apple.com/documentation/appintents/enumerableentityquery). Data processed only on the device is not collected (https://developer.apple.com/app-store/app-privacy-details/), so the label stays Data Not Collected.

Contracts and store copy
- Apple allows one app version submission under review per platform at a time (https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/overview-of-submitting-for-review), so 1.1 goes in only after 1.0 leaves review, and its What's New lists only what merged.
- docs/ (the public support site) is unchanged tonight: 1.1 is not in the App Store and publishing public copy needs Tom's yes. The proposed copy is below.

### Where this differs from what Tom said (one line each)
- Transcription and sorting: Apple's on-device model with a grounded prompt and code checks, not a cloud model, because Apple's guidance is on-device first and a cloud model would break "Nothing you say is sent anywhere".
- Business to-dos: the list is named Work, because Personal and Work are Apple's own default Focus names and Sunsama uses #work and #personal. (Replaced 2026-10-21: no lists, build 3.)
- Female and male toggle: none, because Apple's HIG says to avoid unnecessary references to specific genders, including in glyphs, and that colours carry culture-specific meanings (https://developer.apple.com/design/human-interface-guidelines/inclusion); Birth Control and type-ahead cover it instead.
- Peptides: only Semaglutide and Tirzepatide, because retatrutide is unapproved, cannot be compounded and the leading tracker omits it; the pitch is a weekly dose on the right day, not "peptides".
- An API key for Claude: none, because a key needs a public server of Taken's own and ChatGPT's Apps SDK takes OAuth 2.1 only (https://developers.openai.com/apps-sdk/build/auth); Shortcuts actions on the phone work with Ask Claude and Ask ChatGPT today.
- Over-the-air updates: not possible, because Taken is native Swift, so every change is an App Store build through review, and Android does not exist yet.
- A usage limit: none, because nothing runs on a server of ours, so there is no per-use cost to protect.

### Not built tonight
- Opt-in "Smarter sorting" on Private Cloud Compute (retires a written promise; needs Xcode 27, an entitlement and Tom's call), third-party cloud models (break zero network calls and Data Not Collected), two-pass extraction and custom adapters (only if the eval misses), a review-before-save preview, DictationTranscriber, a per-task list chosen by speech, a configurable or Focus-filtered widget, an All view, the gender toggle, a goal row, research peptides, brand names as chips or metadata, Every N days, iOS 27 App Schemas, a hosted key or MCP server, Apple Health export, Spotlight indexing, accounts and social features.

### Open: needs Tom's iPhone or Tom's call
- Run `taken://todo-eval` from Safari on the internal build; the bar is 11 of 12. If notes fail, compare the model's lines with the saved ones. The new instructions run longer than Apple's "one to three paragraphs", so A/B a shorter version if the eval misses. (Now 15 cases, bar 14 of 15: "1.1 feedback build 2" below.)
- Time a 2-minute ramble against the 15 s sorting limit (`spoken` adds output tokens).
- Check whether SpeechTranscriber finalises punctuated segments ("Order."), and whether names transcribe better at all on iOS 26.
- The custom field on a 6.1 inch iPhone at default and large text, and on an iPhone SE: the slide-in, the keyboard and the rows.
- App Review 2.5.19 ("no hidden, dormant, or undocumented features"): DONE 2026-10-20. The eval and the internal Pro unlock compile only under `#if DEBUG || TAKEN_INTERNAL`; only the EAS "internal" profile generates from `project.internal.yml` (the build step refuses when `TAKEN_INTERNAL_PRO` and the profile disagree, and checks the generated project), and `scripts/check-app-store-build.sh` checks every Release binary in CI, release.yml and EAS before upload. Internal builds are unsubmittable since 2026-10-20 (tjbaxter/taken#2): the `internal` profile builds with `.eas/build/build-ios-internal.yml`, which exports "TestFlight internal testing only" (`testFlightInternalTestingOnly`), so App Store Connect marks each one Internal (`buildAudienceType` INTERNAL_ONLY, status Testing, internal groups only) and never offers it for an App Store version or App Review; `scripts/check-app-store-build.sh --internal` refuses an internal IPA whose app Info.plist lacks the `TFInternalTestingOnly` mark that export writes. Verified on 1.1.0 (15) in group Tom. The older internal builds 1.1.0 (8) and (9) predate this and are still "Ready to Submit" (APP_STORE_ELIGIBLE): expire them once Tom has (15) installed, and never attach them. The 1.1 build to submit is an EAS `production` build (its log says "Generating from project.yml" and "App Store shape"). Sources: https://developer.apple.com/documentation/xcode/distributing-your-app-for-beta-testing-and-releases (TestFlight internal testing only), https://developer.apple.com/help/app-store-connect/test-a-beta-version/add-internal-testers, https://developer.apple.com/documentation/appstoreconnectapi/buildaudiencetype, https://docs.expo.dev/custom-builds/schema/ (generate_gymfile_from_template template), https://developer.apple.com/app-store/review/guidelines/ (2.5.19), https://developer.apple.com/documentation/xcode/build-settings-reference#Active-Compilation-Conditions, https://github.com/yonaskolb/XcodeGen/blob/2.46.0/Docs/ProjectSpec.md#include, https://docs.expo.dev/eas/environment-variables/usage/ (EAS_BUILD_PROFILE).
- A late weekly dose: DONE 2026-10-21 in the 1.1 retention build below (a weekly dose counts for its week, with no nudge, window or countdown after its day).
- Age rating: 13+ since the 1.1 retention build below (it replaces "stays 4+"). Store metadata and screenshots are per storefront and global, settled in that build's "Store screenshots for the 1.1 submission": every localization other than English (U.S.), and the primary language that storefronts without their own localization show, uses the neutral set, with no drug names, "GLP-1", "jab", "pen" or weight language; English (U.S.) alone may show a "Semaglutide · Weekly · Thu" row and name generic medicines. The neutral set uses the type-ahead capture (`43-add-search`, "mag") in place of the chip grid, which shows Semaglutide and Tirzepatide, so frame 03 ("Your stack in four taps", `tools/store-shots/frames.mjs`) is never built from the `03-add` chip grid for it. Brand names go nowhere.
- Tom's questions: may a voice note's words ever leave the iPhone (Private Cloud Compute, opt-in, iOS 27)? Will Taken ever run its own server? After TestFlight, does he want a quiet goal row (Hair, Cycle, Pregnancy, Gym, Sleep)? The recommendation for each is not now.

### Proposed support-site copy (superseded)
Superseded by "Publish with 1.1" in the 1.1 retention build below, which is the one text to publish: its privacy sections 04 and 08 replace the drafts that stood here (the 04 line "They stay on your iPhone." and a shorter 08 line), and the "Use Taken with your AI" recipe section moved to that build's "Later" list, since no recipe gallery ships in 1.1. What is left here and not covered there:

docs/index.html, the Ask Siri card could add: Say "What's on my to-do list in Taken" to hear your open to-dos.

docs/privacy.html, section 03, the to-dos line could read (build 3: no list): your to-dos: the words of each one, when it is due if you said, and when you finished it (never the audio of a voice note), and the date of your first voice note.

## 1.1 feedback build 2 (Tom's feedback 2026-10-20)

Tom uses the internal build daily. His voice note, verbatim:
- "For the to-do list, I don't like how work is split from personal, in the sense that I wanted it all under one tab. And it's like, maybe I can drag work up or drag personal below for whichever one I want on top. But I want it to be scrollable. I don't want it to be a toggle left and right where if I go on work, all my personals are hidden. And if I go on personal, all my works are hidden."
- "I'd rather like a subheading personal than all the things under that, than a subheading work than all the things under that. And then if I want work on top, I can drag work up and personal will pop down below it, or vice versa."
- "Also, when I switch from personal to work, because I've got three open right now on my account, and I've got nothing on work, the three disappears and does like a glitchy bounce"
- "I think it'd be really helpful if you could see [the transcription]"
- "I should have personal selected, and it should go in personal, or I should have work selected and it should go in work"
- "I was going to say I should send messages to my LinkedIn ICPs, and it kind of split it up for some reason"
- "I did a huge voice note and it seemed to just get cut off. Is there a limit to the voice note or something? ... sometimes I want a monologue for a minute or 2 minutes about everything I need to do ... People should at least be able to talk for at least 5 minutes a day ... that all needs to be fixed."

What the code showed: the note stopped at Tom's first pause after "LinkedIn ICPs" (`TodoModel.silenceToStop` was 1.5 s once words had come, and 2 minutes the longest note), and came back as one Work task, "LinkedIn ICP", due at a 17:18 nobody said: the model left `spoken` empty, "icp" did not match "icps", so the task was never placed and passed through with the model's due. The bounce: the line under the title was nil whenever the list in view was empty, so switching to an empty Work list dropped that line while the switch slid.

### Decisions (owner: Claude, with the lead's decisions D1 to D8; each rests on the sources named, and anything marked own choice has none)

One list (SPEC 3.10; replaced 2026-10-21 by one list with no lists, "1.1 feedback build 3" below: the headings, dragging a heading, its menu and VoiceOver action, each list's own Done today and "Nothing open" are gone)
- One scrolling list with a heading for each list replaces the Personal | Work switch, as Apple Reminders (https://support.apple.com/en-gb/guide/iphone/iph82596cb20/ios), Things headings (https://culturedcode.com/things/support/articles/2803577/), Todoist sections (https://todoist.com/help/articles/introduction-to-sections, https://todoist.com/help/articles/205847912) and TickTick (https://blog.ticktick.com/2020/09/03/recent-updates-in-ticktick/) group tasks; HIG lists and tables (https://developer.apple.com/design/human-interface-guidelines/lists-and-tables). A segmented control is for switching between views (https://developer.apple.com/design/human-interface-guidelines/segmented-controls), which Tom no longer wants. The switch's code is gone with it (`select`, the list in view, its empty and listening lines).
- The bounce: the line under the title now counts both lists and never drops out while anything is listed, and nothing on the tab reads a list in view. No animation was tuned. (From the code.)
- Moving a list (D1): touch and hold its heading and drop it on the other list; the two swap. Apple DTS: to move sections use `draggable` and `dropDestination`, not `onMove` (https://developer.apple.com/forums/thread/780117). No `onMove` and no task drags, so the onMove reports that a no-op move does not snap back (https://developer.apple.com/forums/thread/768948) and that a long press while scrolling starts moves (https://www.hackingwithswift.com/forums/swiftui/scroll-and-drag-unwanted-interaction/23877) cannot change a task's list. The drag carries a Codable value as DTS's sample does, not D1's plain String, because a String dragged inside one List is reported never to arrive (https://developer.apple.com/forums/thread/730367). Only the other list's heading lights in `signalWash` while a heading is over it, and a drop on its own list goes back (HIG drag and drop, https://developer.apple.com/design/human-interface-guidelines/drag-and-drop). Noting which list is dragged when SwiftUI reads the payload is own choice: no source documents when it does, and if it is read late the failure is safe (no highlight).
- The other ways the HIG asks for (same page: "Offer alternative ways to accomplish drag-and-drop actions"): a context menu on each heading and the same VoiceOver custom action. Each menu has one item, the move that changes something ("Move Personal to bottom" on top, "Move Work to top" below): own choice, as a second, no-op item would confuse.
- Tasks inside a list keep their automatic order (due first) and are not dragged; they still move between lists by the leading swipe or the edit sheet. This avoids the drag-versus-sort clash Reminders users report (https://discussions.apple.com/thread/256207966).
- Done today (D7): each list shows its own done-today tasks at its bottom, struck through with their time, with no label (no label is own choice). A list with nothing open or done today reads "Nothing open" (own choice: the old "say what needs doing for work" line assumed the mic records into the list in view). A list with only done-today tasks shows them without the line.
- The order animates with `.snappy(0.3)` (none with Reduce Motion), the soft haptic (https://developer.apple.com/design/human-interface-guidelines/playing-haptics) and a VoiceOver announcement, which is held back while a note is starting or heard because the microphone would hear it. The values are own choice. Moving a list is allowed while a note is sorted, since it changes no task and the note's list is fixed (own choice).
- The Lock Screen widget and Shortcuts follow the one list (D3): both lists in the app's order with one count, and "Add to-do" with no list goes to the list on top. One list in the app means one order everywhere. This reverses 1.1's "the Lock Screen never mixes Personal and Work". `TodoEntry` no longer carries a list.

Where a note goes (D2; SPEC 3.10; replaced 2026-10-21: every note goes onto the one list, and the chip and `lastArea`'s role are gone, build 3)
- New notes, typed notes, quick captures and "Add to-do" with no list go to the list on top, which is the first heading on the tab, so the destination is in sight before the mic is tapped. A chip on the Listening card and the type sheet ("Into Personal") sends this note only to the other list, as Todoist Ramble lets you change the project before confirming (https://www.todoist.com/help/articles/dictate-to-add-tasks-with-ramble-P1Raq7vVF) and Superlist files voice tasks in the list chosen (https://help.superlist.com/en/articles/224824-create-tasks-and-notes-with-your-voice-talk). It is not sticky: the plan's sticky `lastArea` could again send a note to Work from last time before Tom saw it. `lastArea` stays in the file for compatibility only. No spoken routing ("for work" would also catch "Work on the deck").
- The chip sits under the words, not on the first line, which is too narrow for the time and waveform (own choice). The type sheet forgets an unused choice when it opens and closes (own choice).
- A saved note scrolls the list to its first task, and a tapped due-time notification scrolls to its task and washes it (https://developer.apple.com/documentation/swiftui/scrollviewreader), instead of switching lists.

Talking for 5 minutes (D4)
- A tap finishes a note, as Ramble, Superlist Talk and Voice Memos end on a tap (https://support.apple.com/guide/iphone/make-a-recording-iph4d2a39a3b/ios). 30 s of quiet stops it, words or not, as Apple's dictation stops after 30 s of silence (https://support.apple.com/guide/iphone/dictate-text-iph2c0651d2/ios). 5:00 is the cap: Tom asked for "at least 5 minutes", so 5:00 is the floor of his request (Wispr Flow's 5-minute cap is Android only, https://docs.wisprflow.ai/articles/2312866822-dictation-session-time-limits-on-android). From 4:00 one soft tap and a countdown (replaced in build 3 by one static "1 minute left"); at 5:00 "Stopped at 5 minutes. Tap the mic to keep going." Notes are unlimited, since nothing runs on a server of ours.
- The screen stays on only while a note is starting or heard. Apple's doc tells recording apps to let the screen sleep (https://developer.apple.com/documentation/uikit/uiapplication/isidletimerdisabled), but locking the phone ends listening because speech recognition does not run in the background (Apple DTS, https://developer.apple.com/forums/thread/53784), so Auto-Lock would cut a monologue short.
- The card shows only the last 240 characters of the words, so a 5-minute note never lays out a page of text on every result (D4).
- Every word kept on iOS 17 to 25: on-device SFSpeechRecognizer can start over after a pause and report only the new words (Apple staff, https://developer.apple.com/forums/thread/765609; https://developer.apple.com/forums/thread/762952). A start-over is told from the text, never from partial results' timestamps, which Apple says are not accurate (https://developer.apple.com/forums/thread/785389). D4's rule was "a result 3 or more words shorter that does not continue the previous text"; the build compares each result no longer than the longest text since the last start-over with that text (a longer one is a revision, since iOS 18.1 and later rewrite the opening of one growing result, and D4 too counts only shorter results), because the literal rule loses "Buy milk." when a short phrase is followed by a pause and a start-over, and keeps both texts when a start-over cannot be ruled out at the stop (a duplicated phrase is possible, a lost one is not). Both are own choices built on D4's text rule. A task that ends by itself is followed by a new one with the same settings (rare: WWDC19 256 lists no on-device audio limit, https://devstreaming-cdn.apple.com/videos/wwdc/2019/256p7m9z4yst71ai/256/256_advances_in_speech_recognition.pdf?dl=1).
- iOS 26: each finalized result's range is kept as a timed phrase for the log (https://developer.apple.com/tutorials/data/documentation/speech/speechtranscriber/result.md, https://developer.apple.com/videos/play/wwdc2025/277/), and the finished words are read under the transcript's lock, never from the event stream, which keeps only the newest 64 events.

Sorting a long note in parts (D4; SPEC 3.10)
- One on-device session holds 4,096 tokens with its instructions, schema and answer (TN3193, https://developer.apple.com/tutorials/data/documentation/technotes/tn3193-managing-the-on-device-foundation-model-s-context-window.md), and the phone writes about 30 tokens a second (https://machinelearning.apple.com/research/introducing-apple-foundation-models), so a note of more than about seven tasks used to miss the 15 s limit and fall back to one 400-character task. Apple's documented answer is to split the input, each piece in a new session (https://developer.apple.com/tutorials/data/documentation/foundationmodels/managing-the-context-window.md); sorting while the person talks follows Ramble (https://www.todoist.com/help/todoist/product-updates/capture-tasks-at-the-speed-of-thought-ramble-beta-nov-19-2025-r6701hY0t, https://www.producttalk.org/building-todoist-ramble-how-doist-turned-voice-braindumps-into-real-time-task-capture/).
- Parts are cut from text only, at sentence ends after 40 words, forced at 80, never before a connector or right after a day header; no pause cuts, since whether SpeechTranscriber's ranges leave out silence is undocumented. On SpeechAnalyzer the parts are sorted while the person talks (`sortsWhileListening = true`, one switch to flip if the device check shows lag), on SFSpeechRecognizer and for typed notes at the stop. The deadlines are D4's. `exceededContextWindowSize` halves a part once (https://developer.apple.com/tutorials/data/documentation/foundationmodels/languagemodelsession/generationerror/exceededcontextwindowsize(_:).md). Non-streaming, as Apple advises off screen (https://developer.apple.com/tutorials/data/documentation/foundationmodels/languagemodelsession/streamresponse(to:generating:includeschemainprompt:options:).md).
- A part the model cannot sort, and a note on an iPhone without Apple Intelligence, is saved as said, one line per sentence, in its place, never as one long to-do and never losing a word. Own choices: a failed part's lines in its place, sorted tasks capped at 80 but lines never, and a filler-only piece merged into the next line.
- The note is saved as lines the moment the words are known and hidden while sorted, so a kill mid-sort keeps every word; the sorted tasks replace the lines only while every line is untouched. Keep as one is offered only for a note of one part.

Titles keep the action, and no due nobody said (D5; SPEC 3.10)
- The grounding rules exist so code, not the small model, owns what is saved (WWDC25 286, https://developer.apple.com/videos/play/wwdc2025/286/). A trailing s or es is ignored when placing a title, and a kept title takes the spelling said, so "LinkedIn ICP" places on "LinkedIn ICPs". An empty `spoken` places by half its title's words; a live task that still cannot be placed is dropped.
- G5 keeps the action: "I should send messages to my LinkedIn ICPs" saves "Send messages to my LinkedIn ICPs". The copula and adjacency limits on that rule are own choices ("the main thing is send the deck" would otherwise be rebuilt badly, and "finally book the dentist" would take "finally" for the action).
- G7: a due stands only where a day or time was said for that task (build 3 tells a day from a clock time), from D5's narrow list ("now", "later", "next", "first", "may" and "march" never count; weekday short forms only before a time or after "on", "by" and the like; numbers only beside a time word), so "Buy 6 eggs" never keeps 06:00 and "I should now send ..." never keeps the prompt's own time. The neighbour words for numbers are own choice.
- The prompt asks for "the verb and what it is done to" with one example that is not Tom's words.

The eval and the voice note log
- `taken://todo-eval` gains the LinkedIn case and a 2-minute and a 5-minute ramble that pass only if every part takes 15 s or less; the bar is 14 of 15. CI cannot run Apple's model, so the proof is a run on Tom's iPhone.
- Voice note log (D6), internal builds only: iOS cannot read an app's logs from earlier runs (https://developer.apple.com/documentation/oslog/oslogstore, https://developer.apple.com/forums/thread/691093), so it is Taken's own file, on the phone (App Privacy stays Data Not Collected, https://developer.apple.com/app-store/app-privacy-details/), compiled out of App Store builds (Guideline 2.5.19, https://developer.apple.com/app-store/review/guidelines/), excluded from backup (https://developer.apple.com/documentation/foundation/optimizing-your-app-s-data-for-icloud-backup), protected as todos.json is (https://developer.apple.com/documentation/uikit/encrypting-your-app-s-files), copied with a 10-minute expiry (https://developer.apple.com/documentation/uikit/uipasteboard/optionskey/expirationdate) or shared (https://developer.apple.com/documentation/swiftui/sharelink). Shaped like WordPress's build-configuration gate (https://github.com/wordpress-mobile/WordPress-iOS/blob/46a956711674a813c85a27fbd1ee024db7b2606c/Modules/Sources/BuildSettingsKit/BuildConfiguration.swift) and Pulse's size and age limits (https://github.com/kean/Pulse/blob/d766560531096d17ebd8c62f2dccbd58d99819eb/Sources/Pulse/LoggerStore/LoggerStore+Configuration.swift). It recorded the list each note went to and whether the chip changed it (D6; gone in build 3). Counting prompt tokens after the save, so counting never slows the sorting it measures, is own choice.

Delivery (D8)
- `internal-testflight.yml` runs `eas build --local` on GitHub's macos-26 runner with the Node and fastlane of the EAS image the cloud builds use, `macos-tahoe-26.5-xcode-26.6` (Node 22.23.1 and fastlane 2.236.1, https://docs.expo.dev/build-reference/infrastructure/), pinned by `actions/setup-node` and `gem install` and checked before the build, not the runner's own (Node 24, Fastlane, CocoaPods, Xcode 26.6: https://github.com/actions/runner-images/blob/main/images/macos/macos-26-arm64-Readme.md; free on public repositories, https://docs.github.com/en/billing/concepts/product-billing/github-actions) and `eas submit`, because the pestline-ai account has used its month's iOS builds and Expo's billing FAQ names local builds as the way to keep building (https://docs.expo.dev/billing/faq/, https://docs.expo.dev/build-reference/local-builds/). Read in eas-cli's own source at v24.11.0: a profile with a config file runs as a custom build, the local path never sends a build request to EAS (https://github.com/expo/eas-cli/blob/v24.11.0/packages/eas-cli/src/build/build.ts, https://github.com/expo/eas-cli/blob/v24.11.0/packages/eas-cli/src/build/ios/prepareJob.ts), and the job with its credentials reaches the local plugin in an environment variable, not on the command line (https://github.com/expo/eas-cli/blob/v24.11.0/packages/eas-cli/src/build/local.ts). Pinned to 24.11.0, published 2026-10-05 and the newest release at least two weeks old (npm), not the plan's 25.2.0 (three days old). The token is an Expo robot token (https://docs.expo.dev/accounts/programmatic-access/). Not run.

### Where this differs from what Tom said (one line each)
- "Drag work up and personal will pop down": you touch and hold the Work heading and drop it on the Personal list, and the two swap; the heading's menu and VoiceOver do the same. (Replaced 2026-10-21: no lists, build 3.)
- "All under one tab": both lists are on one scrolling list, but each task still belongs to one list, and tasks inside a list still order themselves (due first), so they are not dragged.
- "Does like a glitchy bounce": the cause was the count line vanishing for an empty list in view, not the animation; one list removes it, and no animation was changed.
- "I should have personal selected": one list has no selected list, so a note goes to the list on top and a chip on the Listening card and the type sheet sends that one note to the other list. (Replaced 2026-10-21: no lists, build 3.)
- "It kind of split it up": the note was not split; it stopped at the first 1.5 s pause after "LinkedIn ICPs" and came back as one task, so the fixes are the stop rule and the title rules, not the routing.
- "Is there a limit to the voice note?": yes, 2 minutes, but the 1.5 s silence rule cut him off first; both changed (30 s of quiet, 5 minutes).
- "At least 5 minutes a day": 5 minutes per note, with unlimited notes and no daily total, because nothing runs on a server of ours.
- "Helpful if you could see [the transcription]": the voice note log keeps it on his phone in internal builds only, and Claude sees a record only when he copies it, so the app stays Data Not Collected.

### Open: needs Tom's iPhone or Tom's call
Nothing here has run on a device yet. CI proves the build, the unit tests and the screenshots on the simulator only.
- Run `taken://todo-eval` on the internal build: the bar is 14 of 15, with every part of cases 14 and 15 at 15 s or less.
- Talk for 5 minutes with pauses, then open Profile > Internal > Voice note log and Copy it to Claude: seconds per part, transcript lag while parts are sorted, start-overs, and every word saved. If sorting while talking lags the words, set `NoteSorter.sortsWhileListening` to false in the next build. Check heat and battery too (no source gives on-device load figures).
- A short note's time after the stop against the model's first-call latency: the last part of a note gets the rest of the note's time (20 s for a note of one part), not D4's 4 s + 0.15 s a word, because nothing waits behind it and a 9-word note would otherwise get 5.35 s where 1.1 gave every note 15 s.
- (Build 2 only; gone in build 3 with the lists, as are the next five about headings, the swipe, the chip and both lists on the widget.) Drag the Work heading onto Personal and back, on iOS 26 and on the iOS 17 simulator: forum threads 730367 and 733419 (https://developer.apple.com/forums/thread/733419) report that a drop inside one List never arrives, while DTS's sample does exactly that. If it never lands, the heading's menu and VoiceOver still move the list.
- A long press on a heading opens its menu and moving the finger starts the drag; check that both work, and that a long press while scrolling does not start one by accident.
- The `signalWash` highlight shows only on the other list while dragging, and the drag preview reads well in every look.
- Moving a task with the swipe, and finishing one, now re-sort one List: check the row does not flicker (an iOS 26 report: https://developer.apple.com/forums/thread/817786).
- The Lock Screen widget showing both lists' first titles under "To-do · N". A note's lines saved as said while it is sorted do not reload the widget, so it goes straight to the sorted tasks; Get to-dos, which reads the file, can still see the lines for those seconds.
- Toggle the Listening chip mid-note with VoiceOver on: VoiceOver may read the chip's new label, and with no echo cancellation on the input the microphone may hear it into the note.
- Lock the phone mid-note and check it saves; with Low Power Mode on (Auto-Lock 30 s, https://support.apple.com/en-us/101604), check the screen stays on through a 5-minute note.
- SFSpeechRecognizer start-overs on iOS 17 and 18 (the log's Resets section).
- On iOS 26 without the SpeechTranscriber model on the phone yet, a note is cut only at the stop and gets at most 60 s after it, so much of a 5-minute note may be saved as lines.
- `VoiceNoteLogView` and `VoiceNoteLogStore` must be seen by `check-app-store-build.sh --internal` in the first internal build (it fails closed if not).
- Tom's one step for the internal TestFlight workflow: an Expo robot token for the `EXPO_TOKEN` repository secret, moved by `secret-move.sh` and never shown. `eas submit` needs the App Store Connect API key stored on EAS (check with `eas credentials` first), and the profile guard's `EAS_BUILD_PROFILE` is set by the local build plugin (https://github.com/expo/eas-cli/blob/v24.11.0/packages/local-build-plugin/src/build.ts), read in source, not yet run.

## 1.1 feedback build 3 (Tom's feedback 2026-10-21)

Tom used internal 1.1.0 (20). His voice note, verbatim but for the expletives, left out as "..." (this repository is public):
- "So the transcription is much, much better, and it's much cleaner in terms of like getting my intentions correct, which is good. But one thing I don't like, actually, and I think I'm kind of going back on that, I think it's become a bit too complicated to record a voice note."
- "I prefer the original UI design where it was just like the text box and I could speak. Also, I don't like the little volume bars next to the timer. It kind of puts pressure on me. And it also moves at like 1 FPS. It's really low frame rate, and it just looks kind of ... So get rid of that. Have whatever was the original one, have that."
- "And I think, yes, again, it's decision fatigue. Having going into work or personal takes all the ... point away of I need to like click voice, speak, end it. ... So I think actually let's get rid of work and personal. Get rid of both of those. I guess it can be done manually if someone wants to create their own folder and organize their to-do list."
- "But I think voice note mode, it should just literally go into one ... table. And then if they want to drag it into work, they can. But I think for default, I think default have... just one table, original to-do list as before."
- "one thing that's broken is if I drag work up and try and slide it up, it doesn't replace personal. Or if I hold on personal and drag it down, it just shoots back up to the top. There's no way to put work on top. But again, I don't think we're going to have this work personal split."
- "Because some things like apply to job applications. Is that personal or is that work? It's kind of in the middle. And I think just ... having to give a human that decision gives decision fatigue and actually makes it a worse product. So I think just having one list as we originally did is best, and simplifying the recording UI. You've made it too complicated. Back to the original one was better."
- "I love how much improved the transcription and recording messages. Are we using state-of-the-art transcription, by the way?"
- On the countdown, later the same day: "No, don't count them down ... the 1 minute left only comes in after".

His screenshot also showed one note at 09:21 ("... I need to take my vitamin D tablets Need to clean the apartment get my life in order give ... the gym and be a calorie deficit") saved as six tasks all due "09:21", the moment he spoke, though he said no clock time.

### Decisions (owner: Claude, with the lead's brief; each rests on the sources named, and anything marked own choice has none)

One list, no lists (SPEC 3.10; replaces build 2's "One list" and "Where a note goes" and the 1.1 feedback build's "Personal and Work")
- The To-do tab is the pre-feedback layout again: "To-do" with "3 open, 2 done today", the open tasks due first (`TodoOrdering`), then "Done today", and "Tap the mic and say what you need to do" when there is nothing. No headings, no dragging, no menus, no leading swipe, no List picker, no chip. Keep as one, the Delete swipe, editing, completion, due labels, two-line titles and the scroll to a saved note's task stay.
- Every voice note, typed note, quick capture and Shortcuts "Add to-do" goes onto the one list, as a capture with no list named lands in Things' Inbox (https://culturedcode.com/things/guide/), Todoist's Inbox (https://todoist.com/help/articles/use-the-inbox-in-todoist-HwHvYErS) and Reminders' default list (https://support.apple.com/guide/iphone/make-a-reminder-list-iph88463e18/ios). Choosing a list was a step between "click voice, speak, end it", and some tasks ("apply to job applications") are both.
- The drag Tom found broken goes with the lists, so it is not fixed.
- Data kept, not shown: `area` on each task, `lastArea` and `areaOrder` stay in todos.json exactly as builds 9 to 20 decode and encode them, so those builds read the same file and nothing is lost; nothing reads them, and every new task is Personal. Tom's tasks on Work ("LinkedIn ICP") show on the one list. A test reads a file a list build wrote and writes it back unchanged.
- The Lock Screen widget is the one list again ("To-do · N", the first open titles due first, "N to-dos" inline), and Get to-dos and Add to-do lose their List parameter (`TodoListOption` is gone; Show, the returned values, the unlock on a locked iPhone and the Pro gate stay).
- The voice note log drops the list and the chip from each record; a record a list build wrote still loads. The eval had no lists.

The original recording card (SPEC 3.10)
- The Listening card is 1.1's again: the signal dot, "Listening" or "Sorting into to-dos" in `fgMuted`, and the words in Geist 19, 4 lines, head truncation. The waveform, the running time and the chip are gone. The last 240 characters only, so a 5-minute note stays smooth, is kept from build 2.
- From 4:00 a static "1 minute left" fades in once where the waveform was (Geist 13, `fgSubtle`), with the one soft tap; it never counts down and nothing shows before 4:00 (Tom: "don't count them down"). The 5-minute cap, a tap to finish and the 30 s quiet stop stay.
- The ring around the stop button still breathes with the voice, as in 1.1. Its level is now read by the button alone, so the voice's level never redraws the list and the words (it used to redraw the whole tab several times a second). Own choice; that this was the cause of the 1 FPS look is a guess no source confirms.

No clock time nobody said (G7, SPEC 3.10)
- The cause: G7 let a due stand when any day or time was said for the task, and the model, given "Now: ... 09:21" in the prompt, wrote 09:21 with a time for each task; a "today" in the same run-on sentence was enough to keep it.
- The rule: a clock time stays only when a time was said for that task (its own words, the day and time words its sentence opens with before the first task, the header before it, or the part's carried phrase; never another task's words, so "Call mum at 8 tonight, take my tablets" times only mum, run-on or not): a number beside at, by, around, before, until, till, from or past, before am, pm or o'clock, or after quarter to; a written time ("9:30"); "half three"; an hour before a part of the day ("8 tonight"); noon, midday or midnight; or "in N minutes/hours", "in an hour", "in half an hour", as Duckling's English rules read them (https://github.com/facebook/duckling/blob/main/Duckling/Time/EN/Rules.hs, https://github.com/facebook/duckling/blob/main/Duckling/Duration/EN/Rules.hs). A day word alone (today, tonight, tomorrow, a weekday, a date) keeps the day with no time. Nothing said, no due. A time within 2 minutes of the prompt's "Now" with no time said in the task's own words always goes, for an answer no word places too. This is how date parsers separate a day from a time: chrono marks an hour as certain only when it was written (`isCertain`, https://github.com/wanasit/chrono), and Duckling gives "tomorrow" a day grain and "tomorrow at 3pm" an hour grain (https://github.com/facebook/duckling, https://docs.rs/duckling). Counting "midday" with noon, a digit date ("the 23rd") as a day, and no time after a currency sign ("£9.50") are own choices.
- Unit tested with Tom's note (no task keeps a clock time; a day only where "today" was said for it), "Call mum at 8 tonight" (20:00), "Gym at 6" (18:00), "Tomorrow call the dentist" (tomorrow, no time), "in 20 minutes take my tablets" (now plus 20 minutes), "Call mum at 8 tonight, take my vitamin D tablets, clean the apartment" with the rest answered at 09:21 (only mum keeps a time, as a comma list and as one run-on), the eval's case 9 at 09:21 (the MOT due tomorrow with no time), and "tomorrow 9:30", "at half three", "8 tonight" and "in an hour" (each keeps its time).

Transcription (Tom's question)
- Taken already uses Apple's newest on-device speech model on iOS 26, SpeechAnalyzer with SpeechTranscriber (https://developer.apple.com/videos/play/wwdc2025/277/), and on-device SFSpeechRecognizer on iOS 17 to 25, with the stack's names as vocabulary. A cloud model would send his voice off the phone and end "Nothing you say is sent anywhere" and Data Not Collected, so it is not proposed here.

### Where this differs from what Tom said (one line each)
- "If they want to drag it into work, they can": there is no Work to drag into; lists or folders made by hand come only if he asks.
- "Have whatever was the original one": the original card, but with "1 minute left" from 4:00, because a 5-minute cap that stops with no warning would cut a monologue off mid-sentence.

### Later
- Manual lists or folders, only if Tom asks.

### Open: needs Tom's iPhone
- The one list on his phone shows his Work tasks with the rest, and an internal build from before this one still reads the file after it.
- A note past 4:00 shows "1 minute left" once, with no countdown.
- A note like his 09:21 one saves no clock time.

## 1.1 retention build (Tom's question, 2026-10-21)

Tom, verbatim: "What do you think people would enjoy the most? What do you think would be the highest expected value? What do you think would keep people renewing the app? What do you think would make our customers most enjoy the app? Base it off that." And: "we're not a UK shop, mate. We're a global app on the App Store. Don't tie us to the UK."

The standing rules held: minimal and clean, "tap, tap, tap, done", no choice added to the capture path, no ads, and the streak, History, the Lock Screen widget and the nightly reminder he likes kept as they are. Taken's pricing already matches the evidence (a hard paywall with a trial converts at 10.7% against 2.1% for freemium, https://www.revenuecat.com/state-of-subscription-apps), so renewal is lost after the paywall: the one feature with clinical evidence, the reminder, was off and buried in Profile, and a late weekly dose broke the streak. Median Health & Fitness first renewal is 25% for annual plans (https://www.revenuecat.com/blog/growth/average-subscription-renewal-rates-by-app-category), and month 1 holds 35% of annual cancellations (https://www.revenuecat.com/sosa-2026-insights-part-2).

### Decisions (owner: Claude, with the lead's brief and research; each rests on the sources named, and anything marked own choice has none)

A weekly dose counts for its week (SPEC 3.3, R1 to R5)
- A dose logged up to 6 days after its due day counts for that day at its real time, so the streak, the grid and the 30-day % come out right; while that week is open it counts neither way, and the next due day closes it (missed, if still empty). A dose 1 to 3 days early counts for the next due day once this week is logged, so Taken never nudges "1 pending: SEM" after the shot (own choice: 3 days, the smallest window covering "a day or two early"). In those 3 days Today's Not today row is today's quiet ring again, so the early dose is one tap, as before this build; on the 3 days after the due day the lit ring stays and a tap only shows its time (own choice: which row shows when, from R1 b and "tap, tap, tap, done"). On the due day the early dose reads "Tue 08:12" on its row and in "Last Tue 08:12", and VoiceOver and Siri name Tuesday. Extra doses stay on their day. The nudge stays on the due day only, and Take all, widgets, the control and the nudge never log a weekly item off its day.
- No countdown, no "still time", no "late": how late a dose may be taken differs by medicine (Ozempic within 5 days, https://www.novo-pi.com/ozempic.pdf; Wegovy only if the next dose is more than 2 days away, https://www.novo-pi.com/wegovy.pdf; Zepbound within 4 days, https://pi.lilly.com/us/zepbound-uspi.pdf), so a later prompt would be dosing advice (Guideline 1.4, https://developer.apple.com/app-store/review/guidelines/). The item sheet gets one fixed line: "Missed a dose? Follow your medicine's leaflet, or ask your pharmacist or doctor."
- Why: a broken streak lowers later use, more when people blame themselves, less when it can be repaired (https://www.colorado.edu/business/faculty-research/2023/04/19/or-track-how-broken-streaks-affect-consumer-decisions); an easier streak raised Duolingo's day-14 retention 3.3% (https://blog.duolingo.com/improving-the-streak); weekly slack got 55% back on track the day after a miss against 37% for a hard goal (https://anderson-review.ucla.edu/emergency-reserves/); Streaks keeps a skipped day's streak (https://streaks.app/help/task_edit_history/).

The evening nudge, offered once (renewal lever 1)
- After the stack is added, while the nudge is off, Today shows one quiet row, "Nudge me at 20:00 if anything's left" (the person's own nudge time), with Turn on and Not now. iOS asks for permission only on Turn on. Either answer is kept in taken.json's settings and the row never returns, not even after Erase all data (own choice, as the look is kept). Profile's Nudge toggle, on or off, is an answer too, so someone who had the nudge on and turns it off is never offered it again. The default stays off.
- Why: text reminders doubled the odds of taking medication across 16 randomised trials, 2,742 patients (OR 2.11, https://research.bond.edu.au/en/publications/mobile-telephone-text-messaging-for-medication-adherence-in-chron/); Apple says to ask "after the person schedules a first task" (https://developer.apple.com/documentation/usernotifications/asking-permission-to-use-notifications); Airship's vendor figure, via RevenueCat, is about 3x retention with relevant pushes in the first 90 days (https://www.revenuecat.com/blog/growth/first-renewal-churn.md); Apple's Medications feature, the fallback, already reminds (https://support.apple.com/en-us/105064). For women on the pill a trial of daily texts did not cut missed pills (https://www.contemporaryobgyn.net/view/would-daily-text-message-reminders-improve-oral-contraceptive-adherence), so it is an offer, not a default.

The widget invite, once (lever 3)
- The first day that reaches All taken, under it: "Log from your Lock Screen: add the Taken widget". A tap opens a short sheet with the person's own Lock Screen widget and Apple's three steps (https://support.apple.com/en-us/118610); a tap or the close ends it for good, and it never shows after that first day. It never shows to someone whose Lock Screen already has the Taken widget (Tom has one): Taken asks WidgetKit for the configured widgets each time it comes to the front (https://developer.apple.com/documentation/widgetkit/widgetcenter/getcurrentconfigurations(_:)), and the stack widget in a Lock Screen family counts as answered. `WidgetGallery` is a demo-only design check, so the sheet is new.
- Why: Duolingo's widget users retained "far better", and a prompt after a lesson made installs "skyrocket" (correlational, https://blog.duolingo.com/widget-feature). Until now the only mention was a paywall bullet.

The trial reminder (lever 4)
- Put on hold by Tom ("No, don't send trial reminders, mate."), then built later that day with the promise on the paywall, after the research he asked for: see "Trial promise and reminder (2026-10-21)" below.

The honest repair (lever 5)
- When yesterday is partial or missed and something was logged in the week before it, Today shows "Forgot to log yesterday? Fill it in", which opens yesterday's day sheet. It goes once yesterday is complete or today ends, and its close, the same 44 pt one the widget invite has, hides it for that day, so someone who really missed a dose (or one dose of a 3x daily item) is never left with a line pushing them to record it. Apple's TipKit lets people close a tip (https://developer.apple.com/documentation/tipkit/tips/invalidationreason/tipclosed), and Material's banner offers actions "to address (or dismiss the banner)" (https://github.com/material-components/material-components-web/blob/8d5b84fb260506c69fa93246aee538db89db8fc3/packages/mdc-banner/README.md). No freeze, no paid save, no "streak broken" message. Own choice: the 7 days before yesterday as the window.
- Why: repair weakens the drop after a break (the Colorado study above); Silverman advises apps not to dwell on broken streaks (https://udel.edu/udaily/2024/march/power-of-streaks-motivation-jackie-silverman); one missed day had little effect on forming a habit (https://bps.org.uk/research-digest/how-form-habit); paid streak repair is on the deceptive.design Hall of Shame (https://www.deceptive.design/articles/when-a-user-uses-duolingo-on-a-series-of-consecutive-days-this-is-called-a-streak-if-users-miss-a-day-they-can-pay-to-repair-it).

One row at a time (own choice): the nudge offer, then the repair, then the widget invite, none while locked, where the Taken Pro bar sits. `-demo` never shows one unless `-screen today-nudge-offer`, `today-repair` or `today-widget-invite` asks; `-screen widget-help` opens the sheet. CI captures all four (50 to 53).

Did I take it? on a locked iPhone
- `CheckStackIntent.authenticationPolicy` is `.requiresAuthentication`, like Get to-dos, so Siri asks for Face ID or the passcode before saying names like Birth Control. Apple's default lets an intent run "including when the device is locked" (https://developer.apple.com/documentation/appintents/appintent/authenticationpolicy). Discretion matters most to the people on birth control and hair-loss medicine.

Age rating 13+
- Medical or Treatment Information: Infrequent; Health or Wellness Topics: Yes; None to everything else (SPEC 5, `store/SUBMISSION-1.1.md`). Apple's definition includes "medication guidance" (https://developer.apple.com/help/app-store-connect/reference/app-information/age-ratings-values-and-definitions/); Taken lists prescription medicines, starts semaglutide and tirzepatide on Weekly and now carries the leaflet line, and Guideline 2.3.6 warns a mis-rated app can draw a regulator's inquiry. Every customer group is adult; Shotsy is 13+ (https://apps.apple.com/us/app/-/id6499510249). No evidence was found that 13+ changes adult search or conversion (own reading). Screenshots must still suit 4+ (Guideline 2.3.8).

### Where this differs from what Tom said (one line each)
- "Don't tie us to the UK": the store plan is per storefront and global. Most countries ban promoting prescription medicines to the public, and the US and New Zealand are the exceptions (https://theconversation.com/most-high-income-countries-ban-direct-advertising-of-prescription-drugs-why-does-nz-still-allow-it-231688), so only English (U.S.) may name a generic medicine and every other storefront gets the neutral set.

### Store screenshots for the 1.1 submission (the plan; not built in this build)
- English (U.S.): one Today screenshot whose mixed stack includes a "Semaglutide · Weekly · Thu" row. The description may say "a weekly shot such as semaglutide or tirzepatide". Generic names only.
- Every other localization, and the primary language that storefronts without their own localization show: a neutral set with a "Weekly shot" row and no prescription-only medicine at all. So Finasteride leaves the demo stack for it, and the Add sheet's chip grid (Finasteride, Metformin, Semaglutide, Tirzepatide) gives way to the type-ahead capture ("mag", `43-add-search`). If the primary language is English (U.S.), check whether another English can be primary with the neutral set and give English (U.S.) its own (https://developer.apple.com/help/app-store-connect/reference/app-information/app-store-localizations, https://developer.apple.com/help/app-store-connect/manage-app-information/localize-app-information).
- Brand names (Ozempic, Wegovy, Mounjaro, Zepbound) go nowhere in any storefront: not the name, subtitle, keywords, screenshots or description (Guideline 2.3.7; trademarks in keywords are a common rejection, https://developer.apple.com/app-store/search/). No jab, GLP-1, weight-loss words or pen images. Keywords stay as they are.
- To build then: a DemoData variant (launch argument `-demo-stack us` or `neutral`), with `scripts/screenshots.sh` writing each set to its own folder under `store/appstore/iphone-6.9/`.

### Publish with 1.1 (support and privacy text; docs/ is the public site and is not edited in this build)
Built on branch `release/1.1-site` (pull request #12, merged the day 1.1 goes live), with the Weight tab's lines too: weigh-ins, the goal and the height in 03, the weight CSV in 09, and what Erase all data deletes and keeps in 11.
docs/privacy.html, with a new effective date:
- 03, the settings line becomes: "your settings: reminder on or off and its time, the trial reminder on or off, your wake-up time, haptics, the look you chose, and whether you answered Today's one-time offers (and the day you closed its line about yesterday, if you did);"
- 04, after "Speech and task sorting happen on your iPhone.": "To hear names right, Taken gives Apple's on-device speech recognition up to 100 names, from your stack and its list of common supplements, as spelling hints. They are never stored or sent." Replace "The audio is never stored and never sent anywhere, and neither are the words." with "The audio is never stored and never sent anywhere, and Taken never sends the words. A shortcut you build can (section 08)."
- 03, the status file line becomes: "a small Taken Pro status file: whether Pro is active as Apple's App Store last reported it (the plan, the plan it renews to, and when it renews or ends), the plan prices the App Store last gave, when you first logged a dose, whether the Taken Pro offer and the notification question after a trial starts have been shown, and when the reminder before a trial ends was set to arrive."
- 07 becomes: "If you turn on the nudge, Taken schedules local notifications on your iPhone. They are created and delivered by iOS on your device. No push service and no server is involved. Once notifications are allowed, a to-do with a time also gets a local notification at that time, and during a Taken Pro trial one reminder arrives at least 3 days before it ends (while notifications are off, Today shows it instead). Taken asks for notification permission only when you turn the nudge on, in your profile or from the one-time offer on Today, or once right after a trial starts. You can turn the nudge and the trial reminder off at any time in your profile, or every notification from Taken in iOS Settings."
- 08, add: "Did I take it? and Get to-dos hand their answer to the shortcut that runs them. If your shortcut passes it to Use Model (On-Device, Private Cloud Compute or ChatGPT as an extension) or to another app, that service's terms apply; Taken itself sends nothing. On a locked iPhone, Did I take it? and Get to-dos ask for Face ID or your passcode before Siri answers. Take all from a locked iPhone replies with the names it logged." (https://support.apple.com/guide/shortcuts/tpg3vrvwmclv)
- 11, the Erase all data sentence becomes: "...to delete your stack, your log, your to-dos, your profile and your settings; the look you chose, whether you already answered Today's one-time offers (the nudge offer and the widget invite), the Taken Pro status file and the date of your first voice note, described above, stay." Erase keeps those two answers as yes or no only, never a date from the log (`StackState.eraseAll`, Guideline 5.1.1(i)).
- 12: "Taken is rated 13+ and collects no data from anyone, including children under 13 or the minimum age that applies in your country." in place of "suitable for all ages".
- The App Privacy label stays Data Not Collected (https://developer.apple.com/app-store/app-privacy-details/).

docs/index.html, Support, three more answers:
- "How do I get the evening nudge?" "Tap Turn on when Today offers it, or open your profile and turn on Nudge under Reminder. iOS asks for notifications then. Taken nudges you once, at the time you choose, only if something is still pending."
- "I took my weekly shot late." "Log it from its ring under Not today. It counts for its week, at the time you logged it, and your streak holds. For what to do about a missed dose, follow your medicine's leaflet, or ask your pharmacist or doctor." (the same words as the item sheet's line, `Fmt.missedDoseNote`)
- "How do I cancel or change my plan?" "In Taken, open your profile, then Taken Pro and Manage subscription. Or follow Apple's steps at https://support.apple.com/en-us/118428." (Plain cancel steps follow RevenueCat's warning about hiding the charge.)
- The Siri answer gains: "Shortcuts can pass the answer to Did I take it? on to another app or model."
- "How do I add the widget or the control?": the Lock Screen part becomes "touch and hold the Lock Screen, tap Customize, then Lock Screen, then Add Widgets, and choose Taken" (https://support.apple.com/en-us/118610).

### Later
- A Skipped button for a weekly dose (it needs a new kind of record in taken.json).
- History leading with the 30-day % when the streak is under 2, a follow-up nudge, a trial on the monthly plan, the Shortcuts recipe gallery: each worth considering, none built (opinion).
- The recipe section drafted in the 1.1 feedback build ("Proposed support-site copy"), for docs/index.html after "Log it from wherever your hand already is", once Tom says yes (no Anthropic or OpenAI logos, never presented as an integration): "**Use Taken with your AI.** Taken's Shortcuts actions hand your day to the assistant you already use, on your iPhone. Ask what is left: in Shortcuts, add "Taken: Did I take it?" and "Taken: Get to-dos", then "Ask Claude" or "Ask ChatGPT" with the prompt "Here is my day: [results]. Tell me what's left." Turn a thought into a to-do: add "Use Model" (On-Device), then "Taken: Add to-do". Taken never sends your log anywhere. A shortcut you build can. What it sends, and to whom, is up to you."

### Open: needs Tom's iPhone or Tom's call
- On a fresh install, add a stack: the nudge row appears once; Turn on asks for notifications once; after either button it never comes back.
- Log everything one day: the widget invite shows under All taken, opens the sheet, and never shows again after its close or the next day. With the Taken widget already on the Lock Screen (Tom's iPhone), it never shows at all.
- Weekly shot logged on its day, then on the Monday before the next one: the Not today ring is empty and one tap logs it, the row then reads "Weekly · Counts for Thursday", and on Thursday "Tue 08:12" with "Last Tue 08:12".
- Yesterday partial: the repair line's close hides it until tomorrow.
- A weekly shot logged the day after its day: the row reads "Fri 08:12" with "Weekly · Next: Thursday", and the streak holds.
- In App Store Connect, at submission: the 13+ answers above, and the storefront screenshot sets.

## Trial promise and reminder (2026-10-21)

Tom, verbatim: "No, don't send trial reminders, mate. Refunds get handled automatically through Apple. I don't know, actually. In terms of reminders, do deep research and just find what converts best for mobile apps, what sort of strategy."

Tom first said no trial reminders; the research shows the paywall promise converts and the reminder is neutral, so both ship.

His standing rule is to follow documented practice where it differs from what he said: here he asked for the research himself, and it points one way. The research note is the scratchpad's reminder-research.md for this session, with its verifier checks; the sources below are the ones it rests on.

### What converts (every test is one company's, and none gives a sample size except ShareFile's 90% confidence)
- The promise on the paywall is what converts. Blinkist put "we remind you on day 5" on its 7-day trial screen: "23% increase in conversion" (UX Planet, 2021-01-19, https://uxplanet.org/how-solving-our-biggest-customer-complaint-at-blinkist-led-to-a-23-increase-in-conversion-b60ad514134b), and its designer gives the 23% and 55% fewer complaints on RevenueCat's Sub Club (2022-11-09, https://subclub.com/episode/how-ethical-design-led-to-23-growth-jaycee-day-github). The 6% to 74% opt-in figure is only in secondary write-ups (https://growth.design/case-studies/trial-paywall-challenge, https://marketingexamples.com/landing-page/blinkist).
- ShareFile offered a reminder 3 days before the end: +16.4% registrations, and 62% paid against 53% (MarketingSherpa, 2007, B2B on the web, https://marketingsherpa.com/article/case-study/simple-email-cancellation-reminder-lifts).
- Slopes copied the promise: +4% trial starts and far fewer day-0 cancels, but trial-to-paid fell 7.8% among those who asked for the reminder, refunds unchanged, over a 2-week test (Curtis Herbert, 2021-04-05, https://blog.curtisherbert.com/slopes-diaries-39-risky-business/). A ski app is used at the resort, not at home on day 5; that Taken, used daily, will behave more like Blinkist is a judgement, not a finding.
- Clearful: a trial-timeline paywall raised trial starts 54% with no drop in paid conversion (2022-08-09), and its reminder 2 days before the end did not lower trial-to-paid (https://jeffreybunn.substack.com/p/firebase-revenuecat-free-trial-notifications).
- RevenueCat, 115,000+ apps: 64% of 7-day trial cancellations happen on day 0 to 1, and "fear of forgetting to cancel" is a named cause (https://www.revenuecat.com/blog/growth/7-day-trial-subscription-app); 39.8% on day 0 alone (https://www.revenuecat.com/state-of-subscription-apps). Health & Fitness trial-to-paid median 37.7%.
- So the reminder itself is roughly neutral (Clearful no change, Slopes down among requesters) and the promise is the lever. One reminder only: Slopes' drop came after just one, Apple's HIG warns against several notifications about the same thing (https://developer.apple.com/design/human-interface-guidelines/managing-notifications), and Phiture raised Headspace's push opt-ins by giving trial users the reminder as the reason (https://phiture.com/success-stories/headspace-inapps/).

### Utah
- Utah H.B. 174, in force 2025-01-01: "a person who provides an individual a trial period offer" must give a notice "at least three days before the day on which" the trial expires, with the expiry date, the price and how to cancel, for a trial of any length (https://le.utah.gov/~2024/bills/hbillenr/HB0174.pdf; Kelley Drye, https://www.kelleydrye.com/viewpoints/blogs/ad-law-access/auto-renewal-laws-2025-round-up; ZwillGen, https://www.zwillgen.com/auto-renewal/evolving-state-law-patchwork-imposes-new-obligations-on-subscription-businesses/). So the reminder comes at least 72 hours before the end and says the date, the price and "Cancel at least 24 hours before in Settings > your name > Subscriptions" (Apple's steps, "In Settings, tap your name." "Tap Subscriptions.", and its "cancel it at least 24 hours before the trial ends", https://support.apple.com/en-us/118428). Neither firm says whether the duty reaches an App Store sale, where Apple sells as the developer's agent, or whether a local push counts: a question for counsel, not settled here. Not legal advice.
- The same Utah section asks for a notice 30 to 60 days before a renewal onto a term over 45 days, so the yearly plan's renewal is a question for counsel too, as are the UK's draft rules for 2027 (a reminder on a durable medium, which a local push is not). Neither is built.

### Built
- The promise: under the Yearly card, while the introductory offer applies, "Today: full Pro", "Day 4: we remind you", "Day 7: $19.99 a year starts", from StoreKit's trial length, price and period. The paywall still fits a 6.1 inch iPhone without scrolling, measured in CI (`55-paywall-6.1in`). With notifications already off for Taken it shows no reminder step, and at larger text sizes the steps stack instead of cutting the price off.
- The ask: right after a trial starts, only while iOS has not asked yet, one short sheet with both reasons, "Get the evening nudge and a heads-up 3 days before your trial ends.", and one button, Continue, which brings iOS's prompt. Apple says to ask in context (https://developer.apple.com/documentation/usernotifications/asking-permission-to-use-notifications), to title a pre-prompt button like Continue, never Allow, to "Include only one button and make it clear that it opens the system alert", and not to offer a way "to leave the screen or window without viewing the system alert, like offering an option to close or cancel" (https://developer.apple.com/design/human-interface-guidelines/privacy); App Review rejected a pre-prompt with Continue and Not Now under 5.1.1(iv) (https://developer.apple.com/forums/thread/817672). So there is no Not now and no swipe away; iOS's alert carries the no. It waits until nothing else holds the screen: a locked "+" opens the Add sheet after the trial starts and the ask comes once that sheet closes; a mic tap starts the recording and the ask comes once it is done; over a sheet the paywall was over, it shows on that sheet while it is up, and on Today once it has closed. It is used up only once it is on screen. Never provisional: it delivers quietly, and the reminder must be seen. Allowed turns the evening nudge on at its time, so Today's nudge offer counts as answered (`54-trial-ask`).
- The reminder: one local notification on the day the paywall promised (day 4 of 7), at least 72 hours before StoreKit's end of the trial, at the nudge time or 10:00, or at the 72-hour moment itself when that time is later in the day: "Your Taken trial ends Sunday 1 Nov. Unless cancelled, it then renews at $19.99 a year. 12 doses logged so far. Cancel at least 24 hours before in Settings > your name > Subscriptions." The price is the plan that renews: a trialist who switches to monthly in Settings renews as monthly at the trial's end (same level, different duration: https://developer.apple.com/app-store/subscriptions/), and StoreKit's `autoRenewPreference` names it. "Unless cancelled" stays true when the trial was cancelled in Settings and Taken, where StoreKit runs, has not come to the front since; it is withdrawn the next time it does. No sales copy, no discount, never Time Sensitive (Apple's HIG: never for marketing, https://developer.apple.com/design/human-interface-guidelines/managing-notifications), only with permission, and at most one: once it has gone out it never comes again for that trial, even cleared from Notification Center or after a later nudge time (`trialReminder` in `pro.json`). Withdrawn when the trial converts, a billing issue starts, Pro is lifetime or founding, or the Trial reminder switch is off. Profile > Reminder has that switch while a trial is on (Apple's HIG: "you must also provide an in-app settings screen that lets people change their choice", https://developer.apple.com/design/human-interface-guidelines/managing-notifications). While notifications are not allowed for Taken, Today shows the same words from the reminder's moment until the trial ends, and a tap opens Manage subscription, so "we remind you" holds without notifications. This restores ead80f2's scheduling and withdrawal code (reverted in a535959) with the timing, the price, the date and the cancel line changed.
- Refunds: Apple handles them, as Tom said (https://support.apple.com/en-us/118223), and Taken already drops Pro on a refunded transaction. Each refund still costs the developer the price, and Taken cannot contest one without a server. No public controlled test shows reminders change App Store refunds (Slopes saw none), so they are not the reason either way.

### Own choices (no source)
- 10:00 when the nudge is off.
- Exactly 72 hours counts as "at least 72 hours"; no extra buffer. On day 4 the reminder comes at the nudge time or 10:00, or at the 72-hour moment (the time of day the trial began) when that time is later in the day. Only when that moment is before the person's wake-up time does it move to the evening before (day 3), so it never comes in the night: earlier than the promise, never later. The wake-up time as the end of the night is also own choice.
- The price left out of the reminder ("Unless cancelled, it then renews."), never guessed, when StoreKit has not given one yet (it is cached in `pro.json` whenever the plans load).
- Either answer to iOS's prompt answers Today's nudge offer as well, so there is never a second notification ask.
- A voice to-do request closes the ask and holds it back for 3 seconds, so the recording it asked for starts first; the ask comes once that recording is done.
- Today's line in place of the reminder while notifications are off, its place ahead of the other rows, and no close on it (it lasts at most 3 days and goes with the Trial reminder switch).
- The ask's title, "Your trial has started.", and the timeline's look: three steps left to right, each with a small dot, the first lit, and no rules between them (they read as dashes).

### Where this differs from what Tom said (one line)
- "Don't send trial reminders": one is sent, because he asked what converts and the documented practice is to promise one on the paywall and keep it.
- The brief asked for a quiet Not now on the ask: there is none, because Apple's HIG gives a screen before a permission alert one button and no way out without the system alert.
- The brief's cancel line was "Manage in Settings > Subscriptions.": it is "Cancel at least 24 hours before in Settings > your name > Subscriptions.", because Apple's steps go through your name and Apple asks for cancelling a trial at least 24 hours before it ends.

### Open: needs Tom's iPhone or Tom's call
- In the sandbox (an introductory week lasts minutes there), buy the trial: the ask shows once after the paywall closes, has only Continue and cannot be swiped away; Continue brings iOS's prompt; the nudge is on afterwards. From a locked "+" on Today: the Add sheet opens first and the ask comes when it closes. The reminder itself cannot be seen in the sandbox; the unit tests cover its schedule.
- The in-app switch for the trial reminder is built (Profile > Reminder > Trial reminder, while a trial is on). Check its wording on device.
- After 4 weeks: compare App Store Connect's introductory offer conversion, cancellations and refunds with the 4 weeks before (not a randomised test). Health & Fitness median trial-to-paid is 37.7% (RevenueCat 2026).
- Counsel: Utah's trial notice and renewal notice on App Store sales, and the UK's 2027 draft rules.

## App Store build on GitHub, 2026-10-21

The open item: the 1.1 App Store path is an EAS or GitHub production build with the IPA check, never an internal build. The pestline-ai account's EAS cloud iOS builds are used up until 1 Nov, so the App Store build is made on GitHub's runner, as the internal builds have been since 1.1.0 (20).

### Built
- `.github/workflows/app-store-build.yml`, run by hand from main only: the gate, `eas build -p ios -e production --local` (generated from `project.yml`, `.eas/build/build-ios.yml` unchanged), `scripts/check-ipa.sh`, then `eas submit -p ios -e production --path <ipa> --non-interactive --wait`. The 1.1 App Store build comes only from this workflow, or from an EAS cloud `production` build after 1 Nov. Internal builds stay unsubmittable: they are exported TestFlight internal testing only (since 2026-10-20), and the production profile refuses `TAKEN_INTERNAL_PRO`.
- `scripts/check-ipa.sh` prints one OK or FAIL line per check and refuses the upload unless every one passes: the App Store shape (`check-app-store-build.sh`), iPhone only (`UIDeviceFamily` exactly `[1]` in Taken.app and TakenWidgets.appex), the App Group `group.com.tombaxter.taken` in both signed entitlements (`codesign --display --entitlements`), the `project.yml` version in both with one build number, a build number above `FoundingMember.maxBuild` (as release.yml requires), the Xcode in `.xcode-version` (`check-xcode.sh` on both), and App Store distribution profiles (unwrapped with `security cms -D`: no `ProvisionedDevices`, no `ProvisionsAllDevices`, no `get-task-allow`, each for its own App ID). Tried on this Mac against fake ad hoc signed IPAs: a good one passes, and each of 18 broken ones fails on the one check it breaks and no other.
- The IPA goes to EAS Submit and App Store Connect only, never to a workflow artifact, since anyone signed in to GitHub can download a public repository's artifacts. Bluesky's public workflow hands its IPA between jobs as an artifact and Folo's keeps it as one for 90 days; this one builds, checks and submits in one job and keeps none.
- `.github/actions/ship-setup`, a composite action, holds what both shipping workflows share: the gate, Xcode, Node 22.23.1, fastlane 2.236.1 and the Xcode project, so they cannot drift apart. The gate ignores both workflow files and the action, which ci.yml neither builds nor tests, so a change to them needs no new CI run.
- Both workflows wait in one queue (`app-store-connect-upload` with `queue: max`, so nothing waiting is cancelled). eas-cli reads the newest build number on EAS and then writes the next one, for the bundle ID both profiles build, so two builds at once could take the same number, and App Store Connect identifies a build by it.
- After an App Store build uploads, App Store Connect gives it to the internal group "Tom" too (automatic distribution), and TestFlight's automatic updates install the newest build. So run internal-testflight.yml once more afterwards to keep Tom's iPhone on the newest internal build; the run's summary says so.

Sources: local builds and the eas.json fields they ignore (https://docs.expo.dev/build-reference/local-builds/), the remote build number (https://docs.expo.dev/build-reference/app-versions/, and in eas-cli's source at v24.11.0, https://github.com/expo/eas-cli/blob/v24.11.0/packages/eas-cli/src/build/ios/version.ts and https://github.com/expo/eas-cli/blob/v24.11.0/packages/eas-cli/src/build/ios/build.ts), the image's Node, fastlane and Xcode (https://docs.expo.dev/build-reference/infrastructure/), `eas submit --path` (https://docs.expo.dev/eas/cli/, https://docs.expo.dev/submit/ios/), profiles and entitlements (TN3125, https://developer.apple.com/documentation/technotes/tn3125-inside-code-signing-provisioning-profiles), `UIDeviceFamily` (https://developer.apple.com/library/archive/documentation/General/Reference/InfoPlistKeyReference/Articles/iPhoneOSKeys.html, https://developer.apple.com/documentation/xcode/build-settings-reference), App Groups (https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.application-groups), automatic distribution (https://developer.apple.com/help/app-store-connect/test-a-beta-version/add-internal-testers), TestFlight's automatic updates (https://testflight.apple.com/), the build string (https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds), composite actions (https://docs.github.com/en/actions/sharing-automations/avoiding-duplication), concurrency and `queue: max` (https://docs.github.com/en/actions/writing-workflows/choosing-what-your-workflow-does/control-the-concurrency-of-workflows-and-jobs, https://github.blog/changelog/2026-05-07-github-actions-concurrency-groups-now-allow-larger-queues), artifacts (https://docs.github.com/en/enterprise-server@3.16/actions/how-tos/manage-workflow-runs/download-workflow-artifacts, https://docs.github.com/en/rest/actions/artifacts), and public workflows that ship `eas build --local` production builds (https://github.com/bluesky-social/social-app/blob/df8ce385efaa734370ddfdbce186861bc7d40fd2/.github/workflows/build-submit-ios.yml, https://github.com/RSSNext/Folo/blob/84692b51f18349b05554a0a6f6ed73e575d2ed79/.github/workflows/build-ios.yml, https://www.amarjanica.com/submit-expo-ios-app-to-apple-appstore/).

### Own choices (no source)
- From main only, as a step in the workflow: GitHub's control for this, an environment's deployment branches (https://docs.github.com/en/actions/reference/workflows-and-actions/deployments-and-environments), is a repository setting, and this change makes none.
- The founding member cutoff and the widgets' version and build in the IPA check: release.yml already checks the first, and the second costs nothing.
- The wording of the check lines and the name of the queue.

### Open
- Not run yet. The first App Store build is the first run of `scripts/check-ipa.sh` on a signed IPA; a check that fails stops the upload, and the build number it took is skipped.
- actionlint 1.7.12 does not know `queue` yet (https://github.com/rhysd/actionlint/issues/657); GitHub accepts it (Elastic's public release workflow runs with it).
- Tom's call: instead of a second internal build after each App Store build, turn off automatic distribution for "Tom" and add each internal build with `eas submit --groups Tom` (eas-cli 24.11.0 has `--groups`). That changes App Store Connect, so it is not done here.

## App Store pack for 1.1 (2026-10-22)

Tom, 2026-10-21: "complete all tasks end to end" and "we're not a UK shop, mate. We're a global app on the App Store. Don't tie us to the UK." 2026-10-22: "can you continue on taken where we left off?" The plan was "Store screenshots for the 1.1 submission" above; this builds it, with the listing, the review notes and the checklist, so 1.1 can be submitted the moment 1.0 leaves review.

### Built
- `-demo-stack us|neutral` (`Shared/DemoData.swift`, `DemoStack`) seeds the two store sets on a Thursday, the weekly row's day. us, for English (U.S.): the stack CI has always captured plus Semaglutide, "Weekly · Thu", taken 07:45. neutral, for every other localization: a "Weekly shot" row and no Finasteride. Every other capture keeps its stack, day and history (`DemoDataTests`). The argument is read only in Debug builds, which CI's screenshot job runs; a Release build always seeds the standard stack, so no App Store build carries it (Guideline 2.5.19).
- `scripts/screenshots.sh` writes each set to `screenshots/store/<us|neutral>/` (today, today-done, add or add-search, day, log) and proves through the demo probe that each launch took its stack (`stack=`, `day=`). `store-shots.yml` frames both sets at 6.9" (1320 x 2868) and 6.3" (1206 x 2622) and refreshes the in-app purchase review screenshot; the renders are in `store/appstore/iphone-6.9/<set>/`, `store/appstore/iphone-6.3/<set>/` and `store/iap/paywall.png`.
- The listing per set in `store/metadata/en-US/` and `store/metadata/neutral/`, with fastlane deliver's file names (https://docs.fastlane.tools/actions/deliver/), the App Review notes in `store/metadata/review_information/`, the in-app purchases in `store/iap/products.json`, and every App Store Connect field in order in `store/SUBMISSION-1.1.md`. `scripts/check-store-metadata.py` checks them in CI ("Store metadata"). `brand/appstore.py` and `brand/appstore.md` are gone: `store/` is the one listing.

### Decisions (each rests on the sources named; anything marked own choice has none)
- The rules followed, from the App Review Guidelines (last updated October 16, 2026, https://developer.apple.com/app-store/review/guidelines/): 2.3.7, "Metadata such as app names, subtitles, screenshots, and previews should not include prices, terms, or descriptions that are not specific to the metadata type"; 2.3.8, screenshots "adhere to a 4+ age rating even if your app is rated higher"; 2.3.14, creative assets "should not include inappropriate content, references to other apps with an intent to mislead, unverifiable product claims, or specific or discounted pricing information"; 2.5.19, "Don't include any hidden, dormant, or undocumented features in your app"; 2.3.1(a), new features "must be described with specificity in the Notes for Review section"; 2.3.12, What's New must "clearly describe new features and product changes"; 1.4.1, apps "should remind users to check with a doctor". Apple's asset best practices add "Don't include specific pricing, discounts, website URLs, copyright symbols" and "Avoid claims that can't be verified" (https://developer.apple.com/app-store/asset-best-practices/). Every caption and every listing field is checked against these in CI.
- Which storefront sees what: English (U.K.) is the default or an additional language in every storefront but the United States, Canada and Japan; English (U.S.) is listed only for the United States (default) and Japan (additional) (https://developer.apple.com/help/app-store-connect/reference/app-information/app-store-localizations). So the neutral set goes to English (U.K.), English (Australia) and English (Canada), and the U.S. set to English (U.S.).
- The primary language: where no localization matches, "your metadata displays in the primary language", and a language can become primary only after it was added to a previous version and App Review approved it and its own screenshots (https://developer.apple.com/help/app-store-connect/manage-app-information/localize-app-information). If 1.0's primary language is English (U.S.), English (U.S.) therefore shows the neutral set in 1.1, English (U.K.) is added with its own uploaded screenshots, and the U.S. set follows in the next version once English (U.K.) is primary. The checklist branches on what App Store Connect shows.
- Sizes: App Store Connect requires "at least one screenshot for iPhone with Dynamic Island (medium display)", 1206 x 2622 or 1179 x 2556, and accepts 1320 x 2868 for the large display (https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications), so both sizes ship.
- No price in the neutral set: storefronts outside the United States charge in their own currency, and 2.3.1 forbids "promoting a false price". English (U.S.) keeps PRO.md's price block, which Apple's subscription page backs ("your app and App Store metadata must include links to your Terms of Use and Privacy Policy", https://developer.apple.com/app-store/subscriptions/).
- Limits, all checked in CI: name and subtitle 30 characters (https://developer.apple.com/help/app-store-connect/reference/app-information/app-information); promotional text 170, description and What's New 4000 characters, keywords 100 bytes with each keyword more than two characters, review notes 4000 bytes (https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information); in-app purchase display name 2 to 30 and description 45 characters, review notes 4000 (https://developer.apple.com/help/app-store-connect/reference/in-app-purchases-and-subscriptions/in-app-purchase-information). Keywords repeat no word of the name, subtitle or category and no plural of one (https://developer.apple.com/app-store/search/); they stay as they were.
- The first subscription and non-consumable go to review with the version and the subscription group (https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-in-app-purchase), and one app version can be under review per platform at a time (https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/overview-of-submitting-for-review).
- The listing's shape follows the top US Health & Fitness and medication listings in October 2026: Shotsy (https://apps.apple.com/us/app/id6499510249), Medisafe (https://apps.apple.com/us/app/id573916946), MyTherapy (https://apps.apple.com/us/app/id662170995), Streaks (https://apps.apple.com/us/app/id963034692) and Habitify (https://apps.apple.com/us/app/id1111447047) open with one plain promise, list features under capital headings, end with a health line and the Terms of Use and Privacy Policy links, and use promotional text for what is new. Shotsy, the leading weekly-shot tracker, names brands and "weight loss"; Taken does neither, in any storefront (2.3.7 and the plan above). Habitify sells App Intents and Siri to AI assistants the way Taken's Shortcuts line does.
- Every claim in the description, What's New, the review notes and the in-app purchase text was checked against the code on main (file and line), and What's New lists only what main has.

### Own choices (no source)
- The neutral text avoids every word English spells two ways (color or colour, canceled or cancelled), so one text serves English (U.K.), (Australia), (Canada), and English (U.S.) while it is primary.
- The neutral type-ahead types "mag" (the earlier commit's reason: with "tum" the chip grid's medicine rows stay in view above the keyboard).
- Version release by hand, so `docs/`' "Publish with 1.1" text goes live with the release.
- The in-app purchase display names and descriptions ("Taken Pro Yearly", "One-tap logging, widgets, Siri, voice to-dos").

### Where this differs from the plan above (one line each)
- "English (U.S.) alone may show a Semaglutide row": only once English (U.S.) is not the primary language, because Apple shows the primary language wherever no localization matches.
- English (U.S.) is also an additional language in Japan, so the U.S. set can reach Japanese storefront visitors; a Japanese localization holding the neutral set would stop that, and no Apple page says whether English text there is acceptable, so it is Tom's call.

### Review fixes and the Weight tab in 1.1 (2026-10-23)
Tom, 2026-10-22, on the Weight tab planned for 1.2: "Stop making more versions. Just publish it to the App Store. I want to see it." Apple reviews one version per platform at a time (https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/overview-of-submitting-for-review), so the Weight tab (pull request #11) ships in 1.1, the update submitted once 1.0 leaves review. This replaces the Weight tab record's "1.1 stays as built: build 23" and "Do not swap out build 23".
- What's New, every set: "New: an optional Weight tab. Log a weigh-in in a few taps and watch a smoothed trend form. Turn it on in Profile." What's New must list new features (Guideline 2.3.12) and is set per localization; the line is the Weight tab record's, word for word, its one exception to the no-weight-words rule.
- Review notes, step 12: where the switch is (Profile, Weight), the one-time offer on Today and the stacks it goes to (Semaglutide, Tirzepatide, Oral Semaglutide: `WeightOffer.medicineCodes`), weights.json on the iPhone, the CSV rows, the Pro rule, and the goal sentence from "Goal and moments" (care rule 11), word for word. Guideline 2.3.1(a): new features "must be described with specificity in the Notes for Review section". To fit 4000 bytes, the 1.1 summary is one paragraph and the sandbox steps are shorter.
- The English (U.S.) description line the Weight tab record allows is left out: the description has 4 characters to spare and the line needs 66, and English (U.S.) shows outside the United States (below).
- One listing for every storefront. Japan lists Japanese and English (US) (https://developer.apple.com/help/app-store-connect/reference/app-information/app-store-localizations), and Apple names no order between the storefront's language, the device's language and the primary language (same page), so a Japanese localization would not reliably keep English (U.S.) out of Japan. So English (U.S.) follows the neutral rules: no medicine name, since Japan bans promoting prescription medicines like the countries above, and no price, since a dollar price is false in a yen storefront (Guideline 2.3.1(a), "promoting a false price"). The App Store product page lists each in-app purchase in the visitor's currency and the paywall shows StoreKit's price. In 1.1 the en-US copy is the neutral copy, every localization takes the neutral screenshots, no localization is added and the Primary Language stays. This replaces "English (U.S.) keeps PRO.md's price block", the U.S. set's Semaglutide row and the plan to make English (U.K.) primary.
- `scripts/check-store-metadata.py`: weight words match as stems ("weigh" finds weighing and weigh-in), allowed only in What's New's line and the review notes; the medicine list is built from Shared/Catalog.swift (the medicines list and the medicine chips, with their other names), not 8 names; no medicine and no price in either set.
- `-demo`, `-screen`, `-theme` and `-open-url` are read only in Debug builds (`AppModel.fromLaunchArguments`, `TodoModel.fromLaunchArguments`, `TodoQuickAction.openDemoLinkIfAsked`), as `-demo-stack` already was, so a Release build carries no screenshot mode (Guideline 2.5.19). Only scripts/screenshots.sh passes them, to the Debug simulator build.
- The build: app-store-build.yml from main after pull requests #10 and #11 merge, with the Weight tab's `#if DEBUG || TAKEN_INTERNAL` gate, the `WeightTabRootView` marker and its presence check removed together; never build 23.
- The Paid Apps Agreement must be Active before the in-app purchases can be submitted (https://developer.apple.com/help/app-store-connect/manage-agreements/sign-and-update-agreements): a checklist step now.
- The release-day site text (privacy policy with weigh-ins, the goal and 13+; the 1.1 support answers) is pull request #12 (branch `release/1.1-site`), merged the day 1.1 goes live.
- Not done: a To-do frame in the store screenshots. The extras policy (on the Weight tab branch, 2026-10-22) sells Taken as the pill and supplement log with voice to-dos as a quiet extra, and the promotional text, What's New and the description already lead with voice to-dos.

### Open: Tom's call or App Store Connect
- Follow `store/SUBMISSION-1.1.md`: the Paid Apps Agreement, the new build from main after pull requests #10 and #11, one listing for every localization.

## Weight tab, 2026-10-22 (decision; built on feat/weight-tab for internal builds; ships in 1.2)

Update, 2026-10-23: it ships in 1.1, not 1.2. See "Weight tab in 1.1, 2026-10-23" at the end of this file.

Tom asked whether Taken should get a minimal weight log: weigh in, type the number, watch a graph form, the one thing he uses MyNetDiary for. His sketch: a fourth tab, on by default, with a corner button and a pop-up to remove it ("don't need to weigh yourself? remove"). Researched as of 22 Oct 2026 against Apple's docs and guidelines, shipping apps and the self-weighing research, then reviewed by a critic whose ten points were each checked against the sources (bottom of this section).

### Verdict
Add it as an optional Weight tab: off by default, offered once to stacks with a GLP-1 medicine, switched on in Profile, hidden from its own corner menu with Undo. Not in 1.1. Built on a branch now so Tom has it in his internal TestFlight builds; ships in 1.2 after 1.1 is approved.

### Why
Tom is the first user: he weighs in every day and opens MyNetDiary for nothing else, which today means a calorie dashboard, two scrolls, two cards, Log weigh-in, Save and a tap to open the chart. In Taken it becomes three taps and the digits, with the chart already on screen. Weight next to a dose log is normal in this category: Medisafe and MyTherapy offer weight as a tracker; the leading GLP-1 trackers chart weight with doses on it (Shotsy overlays dose changes on its weight chart, GlucoPal marks doses on it); and Taken already lists Semaglutide and Tirzepatide. Tom's real worry is diluting a pill app. His fix, a tab on by default with a way to remove it, is what Signal did with Stories and what Telegram has done with its Calls tab since April 2025, so the biggest tab precedents are on his side. Off by default is still the recommendation, as a judgement between two documented patterns: medication apps make weight something you add (Medisafe), fewer than 5% of the Word users Spool surveyed had changed any setting, whatever is on the first screen reads as important (NN/g), and Taken is rated 13+ with young women as the next audience, the groups in which frequent self-weighing goes with worse outcomes (Neumark-Sztainer 2006, Pacanowski 2015). Capture is one number. The chart is a smoothed trend with weekly dose ticks and no goals or red and green. Weigh-ins follow the same Pro rule as doses, at today's prices. It is about the size of the 1.1 retention work (2,000 to 3,000 lines with tests). No data shows a weight tab lifts conversion or renewal: it is a retention bet on the people who weigh in.

### What Tom does in MyNetDiary today (his 7 screenshots)
- The Dashboard opens on the apple-shaped Calorie Budget, My Daily Advice ("Not Losing Weight?") and an AI Coach card ("Weight Plan review needed"). He scrolls past to "Weigh In 88.4 kg, Last weigh-in: Oct 21" and a "My Weight Goal & Plan: New target date is needed" card.
- The Weight page: "Last weigh-in 88.35 kg yesterday", a green "Log weigh-in", Trending Weight 88.1 kg "Based on 14-day trends", 10-Day Low 87.85 kg, a Progress bar from 97.8 kg to an 87 kg goal, and an orange Go Premium.
- The New Entry sheet: an empty Weight field, Date "today", Add Photo, Save, the decimal pad.
- The chart: W, 30D, 90D, Y, ALL; dots, a smoothed line, a dashed goal line, "5% lost" and "10.6% lost" stars, an orange forecast line; Weight Changes 7-Day up 0.5 kg in red, 30-Day down 1.2 kg and 90-Day down 3.9 kg in green.
- What he values: the last number, one big Log button, and the line that updates itself. He went from 97.8 kg in March to 88.35 kg, about 0.3 kg a week.

### Spec

#### Placement
- An optional fourth tab, last: Today, To-do, History, Weight. Label "Weight" (HIG tab bars: "Use single words whenever possible"), SF Symbol scalemass. Today stays the launch tab and the dose path does not change. Weight never appears on Today (apart from the one-time offer), in widgets, the Control Center control, Siri, notifications, the streak or History. Last, so switching it never moves the three tabs people know (own choice).
- Code: `case weight` in `AppTab` (Taken/AppModel.swift). In RootView's TabView (Taken/Views/TodayView.swift): `if model.weight.showsTab { WeightTabRootView().tabItem { Label("Weight", systemImage: "scalemass") }.tag(AppTab.weight) }`. A plain `if` behind a user flag is Apple DTS's advice (forums thread 770633) and the only route on iOS 17: `Tab`, `hidden(_:)` and `TabViewCustomization` are iOS 18+, and Apple's tab customization works only in the iPad sidebar-adaptable style ("This modifier has no effect on other platforms"). `AppModel.tab(forScreen:)` and DemoProbe learn "weight".
- Layout (replaced by "Weight tab page: entry first" below; kept as the record of v1), top to bottom: (1) TabHeader "Weight", subtitle "Last weigh-in yesterday, 07:42" or "No weigh-ins yet", with a More button left of the Profile avatar. (2) A card with the trend in Geist Mono ("Trend 88.1 kg", caption "smooths daily swings"), "Last 88.35 kg" beside it, and a full-width "Log weigh-in" button. (3) The chart card. (4) An "All weigh-ins" row that opens a sheet: tap a row to edit its value, date or time; swipe to delete, with an Undo toast.
- Empty state (replaced by "Weight tab page: entry first": the caret, the unit and "No weigh-ins yet"; HIG: "If a section is empty, explain why its content is unavailable"): "Log your first weigh-in. Your trend starts here."

#### Default state
- Off for every install, new or updated, stored as `showsTab: Bool?` in weights.json (nil means off). An explicit choice is kept if the default ever changes, as Telegram did in January 2020 ("so the tab won't disappear for existing users after we change default").
- This is a judgement between two documented patterns, not a rule. On by default with a switch to hide it: Signal Stories (2022, Settings, Stories, Turn off stories) and Telegram's Calls tab since April 2025 (commit 4a97994b; it also retired its after-call offer in May 2026, commit 3e6363ab). Off by default and added by the person: Medisafe's health trackers (Manage, Health Trackers, +) and Telegram from 2017 to April 2025, apart from January to May 2020. Telegram itself changed its mind three times.
- Off wins for Taken because of its category (medication apps), HIG Settings ("default settings that give the best experience to the largest number of people") and Tab bars ("generally easier to navigate among fewer tabs"), Spool (fewer than 5% of the Word users surveyed had changed any setting, so on by default gives nearly every non-weigher a Weight tab for good), NN/g (whatever appears on the initial display tells users it is important, which is the dilution Tom fears), the 13+ rating and the self-weighing evidence (Designing for care below), and REDESIGN.md's store screenshots, which then still show the real default app.
- Two ways in. (1) Profile gets a "Weight" section with one switch, "Weight tab", footnote "Log your weight and see a smoothed trend. Kept on this iPhone." Tom turns this on. (2) One quiet row on Today, once ever: a new `TodayPrompt.weightOffer`, picked in `TodayPrompts.pick` (Shared/Retention.swift) after the trial notice, the nudge offer, the repair and the widget invite, only when the stack has an active SEM, TRZ or OSM item, today is All taken, Pro or the first session is active (the existing "none while locked" rule), the tab is off and the offer was never answered. Copy in the widget invite's style: "Log your weight here too: add a Weight tab", buttons "Not now" and "Add tab". Either answer is final. "Add tab" turns the tab on without switching to it. This is Telegram's 2017 to 2025 offer and the repo's own one-time rows; the GLP-1 trigger is my choice, because the category evidence is strongest there.
- No onboarding question (HIG Onboarding: "Postpone nonessential setup flows or customization steps").

#### Hiding and showing
- A 44 pt More button (ellipsis.circle) in the Weight tab's header, left of the Profile avatar; TabHeader gains an optional accessory. HIG Settings asks for showing and hiding options "in the screens they affect", and HIG pull-down buttons offers a More button for "items that don't need prominent positions in the main interface".
- Its menu: "Kilograms" and "Pounds" with a checkmark on the current one (HIG Menus: checkmarks show the attribute in effect), a divider, then "Hide Weight Tab" (HIG Menus: verb labels, title-style capitalization, the Show Map and Hide Map pattern). Three items, the minimum HIG pull-down buttons suggests.
- "Hide Weight Tab" is not styled destructive and asks nothing, because nothing is deleted (HIG Alerts: "Avoid displaying alerts for common, undoable actions, even when they're destructive"; NN/g: "Do not use confirmation dialogs for routine actions", offer undo). On tap: first `model.tab = .today` (Apple's `hidden(_:)` doc: "make sure to update the TabView's selection appropriately, since that tab could be selected"), then `showsTab = false` with animation, then Taken's toast "Weight tab hidden. Profile brings it back." with UNDO (new `UndoStep.showWeightTab`).
- The way back is Profile, Weight, Weight tab, where Signal and Telegram put theirs. Hiding never deletes weigh-ins; only Erase all data does. Taken never hides the tab by itself, and a locked user keeps it, read-only (HIG: "Don't disable or hide tab bar buttons, even when their content is unavailable").

#### Logging a weigh-in
- Weight tab, Log weigh-in, type the number, Save: three taps and the digits, with the chart already on screen.
- (Replaced by "Weight tab page: entry first": the big number on the page is the field, with a Weigh in bar on the decimal pad; there is no sheet.) The sheet is a new `SheetRoute.weighIn`, presented from RootView like every other sheet, at a short detent: one field already focused on the decimal pad (`@FocusState`), the unit label, the time as plain text ("Now"), and Save above the keyboard.
- Save stays disabled until the number parses in the current locale (88,35 works in de_DE) and falls between 20 and 350 kg (44 to 770 lb; own bounds). The placeholder shows the last weigh-in in grey, visible but not savable by accident (own choice; MyNetDiary's field is empty).
- No date, photo, note, goal or unit question on the capture path (Tom's rule; MyNetDiary's sheet adds Date and Add Photo).
- Save closes the sheet, plays the soft haptic if haptics are on, updates the dot and the trend, and shows "Weighed in 88.35 kg" with UNDO.
- `WeighIn` stores `id`, `kg`, `weighedAt` and `utcOffset`, like `Dose`; its day comes from Taken's DayClock, so "today" means what it means for doses. A wrong number or a past weigh-in is fixed in All weigh-ins.

#### Chart and trend
- Swift Charts (iOS 16+, new to the repo, allowed by SPEC.md section 2). Weigh-ins are small PointMarks in fgSubtle. The trend is a LineMark in the look's signal colour through the daily trend values with `.interpolationMethod(.monotone)` ("a cubic spline that preserves monotonicity of the data"), so the curve never swings past the values it joins.
- `WeightTrend` is a pure function in Shared/WeightData.swift, unit tested like DayMath: (1) one value per day, the day's lowest weigh-in (Happy Scale's rule, per the iPhoneJD review); (2) days between weigh-ins filled by linear interpolation (MacroFactor: 151 on Monday and 150 on Wednesday give 150.5 on Tuesday); (3) The Hacker's Diet trend: today's trend is yesterday's trend plus a tenth of (today's weight minus yesterday's trend), starting from the first weigh-in (Fourmilab's pencil-and-paper steps, smoothing constant 0.9); (4) no line or forecast past the last weigh-in.
- That trend lags about 9 to 10 days: Fourmilab calls 0.9 "roughly equivalent to a 20 day simple moving average in terms of lagging the trend" and aligns it with "a Shift of about 10". At 1 kg a week it sits about 1.3 kg above the scale; at Tom's recent 0.3 kg a week, about 0.4 kg. If Tom's side-by-side check against MyNetDiary's "14-day trends" shows it trailing too much, switch once to a 7-day EMA (alpha 0.25, lag about 3 days), as Weigh Easy ships. Never a user setting.
- Weekly dose ticks: for items on a Weekly schedule (how Taken starts Semaglutide and Tirzepatide), a small unlabelled tick on the chart's baseline on each day a dose was logged, with "Ticks: weekly doses" under the chart only when there are ticks. The pattern is the category's (Shotsy "overlays each dosage change onto a user's weight-loss chart"; GlucoPal 2.5.0: "See treatment changes and dose markers right on your weight chart"). Weekly-only and no drug name on the chart are my choices.
- Ranges W, 30D, 90D, Y and All in a segmented control (MyNetDiary's set), default All, last choice remembered in weights.json. v1 filters rather than scrolls (`chartScrollableAxes` and `chartXVisibleDomain` exist on iOS 17 for later). The y axis fits the visible data with padding and does not start at zero.
- Under the chart: the 7-, 30- and 90-day change in the trend, each as an arrow and a number, each shown once that much history exists (own choice: the trend, not raw weigh-ins, so water swings do not drive it).
- Left out of v1: goal line, percent-lost milestones, forecast, BMI, red and green.
- Accessibility: Swift Charts gives every chart a default Audio Graph and an element per mark (HIG Charts); Taken adds a title and a one-line summary ("Trend 88.1 kilograms, down 1.2 over 30 days").

#### Units
- Each `WeighIn` stores kilograms as a Double (UnitMass's base unit). v1 offers kilograms and pounds.
- The default comes from `UnitMass(forLocale: .current, usage: .personWeight)` (iOS 16+): pounds where it says pounds, kilograms everywhere else. Checked on this Mac: en_US and es_US give lb; en_GB gives st; en_IE, en_AU, en_CA, de_DE, fr_FR, ja_JP and en_IN give kg. So an en_GB iPhone like Tom's opens in kilograms, matching his MyNetDiary.
- Stones wait until a UK user asks (they need st and lb in two fields): my scope choice, in line with "Don't tie us to the UK".
- The person's pick lives in weights.json (`unit: WeightUnit?`, nil means use the locale) and is changed in the More menu.
- Precision is set by hand: in the same check Foundation's personWeight style rounded to whole units ("88 kg", "195 lb"), which would hide a 0.3 kg change. Show kg as typed with up to two decimals and lb with one. Parse with the locale's number format.
- If Apple Health arrives in phase 2, use `HKHealthStore.preferredUnits(for:)` unless the person chose a unit in Taken (Apple: present HealthKit data in the preferred units).

#### Storage, backups and Apple Health
- None in 1.2. Weigh-ins live only in a new weights.json in the App Group container, written by a `WeightStore` copied from TodoStore: NSFileCoordinator, atomic writes, completeFileProtectionUntilFirstUserAuthentication, an unreadable file set aside, a Darwin notification. Not in taken.json or StackSettings, which have hand-written decoding; a separate file also means builds without the feature ignore it.
- Device backups include it like the rest of Taken (privacy.html section 10; Apple: iCloud Backup includes your app's data). Export: Profile, Data, "Export weight CSV" (taken-weight.csv: date, time, kg).
- No HealthKit entitlement, usage strings or listing text. The privacy label stays Data Not Collected (Apple: "Data that is processed only on device is not collected").
- Phase 2, only if Tom or reviews ask (smart scales, old weigh-ins): an opt-in "Sync with Apple Health" item in the More menu (HIG HealthKit: ask "when people log their weight", not at launch; Happy Scale's Health link is opt-in). It reads and writes HKQuantityTypeIdentifier.bodyMass, imports past samples, writes each Taken weigh-in, re-reads with an anchored query on foreground, keeps Taken's own copy (Health is unreadable while the phone is locked) and dedupes by sample UUID. It needs the HealthKit capability on the App ID and new provisioning profiles, set up once outside the build workflows, which skip capability sync (`EXPO_NO_CAPABILITY_SYNC=1`) and freeze credentials; NSHealthShareUsageDescription and NSHealthUpdateUsageDescription; a description line naming Apple Health (Guideline 2.5.1); a privacy policy section; and "Apple Health", never "HealthKit", in the UI (HIG).
- No iCloud or CloudKit sync of weigh-ins: Guideline 5.1.3(ii) says apps "may not store personal health information in iCloud" (Shotsy syncs through iCloud anyway; recheck before ever revisiting).

#### Widgets, Siri and links
- Nothing new in 1.2. The widgets, the control, Siri and the nudge stay about doses and to-dos. A widget cannot take a typed weight: interactive widgets support only buttons and toggles, which are inactive on a locked device, and widgets do not resolve parameters (WidgetKit docs).
- New links exist only for CI: `taken://weight` (the tab, or Today when the tab is off) and the demo screens `-screen weight`, `weight-log`, `weight-empty` and `today-weight-offer`, checked by scripts/screenshots.sh and DemoProbe (`tab=weight`, `sheet=weigh-in`).
- Later, if wanted: an App Shortcut "Log weight in Taken" whose intent asks Siri, Shortcuts or the Action button for the number (Taken uses 5 of 10 App Shortcuts). Set its unit explicitly: a developer forum report says the locale-adjusted mass parameter defaulted to kg.

#### Taken Pro
- Weigh-ins follow the rule doses and voice to-dos follow (PRO.md): `WeightGate.access(firstWeighInAt:status:settled:legacyLog:now:)` calls `ProGate.access(..., hasLogged: firstWeighInAt != nil)`, as TodoGate does. The first weigh-in ever needs no Pro. After it, without active Pro, Log weigh-in, edit and backdate open the paywall through `model.requirePro` (internal builds already unlock Pro). `firstWeighInAt` survives Erase all data, like firstNoteAt.
- The chart, trend, All weigh-ins and the CSV always stay open (PRO.md: "we never hold someone's record hostage"), and the tab stays when locked. Weight never triggers the automatic paywall, which still follows only the first dose. The paywall keeps its four bullets (CI measures the 6.1 inch fit).
- Prices stay: $19.99 a year with the 7-day trial, $3.99 a month, $49.99 lifetime. No add-on, no rise. Weight-only apps sell for about $1.99 a month or $11.99 to $17.99 a year (Happy Scale, Libra), and MyNetDiary and Happy Scale give the chart away, so weight cannot carry a price of its own; it makes Pro better value instead (Tom would pay 99p a month for each; the yearly plan already works out at about $1.67 a month). GLP-1 trackers charge $35 to $60 a year but keep weight logging open because they are freemium (GlucoPal is "free to download and use"; Pro adds forecasts and PDF reports). Taken is a hard-paywall app (RevenueCat 2026: 10.7% download-to-paid against 2.1% for freemium), so it gates logging the same way everywhere. Gating weight like this is my own choice. Revisit price only with renewal data after 1.2.

#### Designing for care
- Adolescents: in Project EAT (2,516 adolescents over 5 years) frequent self-weighing predicted later binge eating and unhealthy weight control in girls, and the authors say prevention "should avoid messages likely to lead to frequent self-weighing" (Neumark-Sztainer et al. 2006). A study of 356 girls concluded "Adolescents should not be encouraged to engage in frequent self-weighing" (Friend et al. 2012).
- Young adults: over 10 years (1,868 people), more self-weighing went with lower body satisfaction and self-esteem and more weight concern and depression in young women; it "may not be an innocuous behavior for young people, particularly women" (Pacanowski et al. 2015).
- Adults with overweight in weight-loss programmes: daily weighing did not cause adverse psychological outcomes (Steinberg et al. 2014, RCT, N=91) and was not linked to more disordered eating (LaRose et al. 2014, n=178). So the tab suits adults who choose it, which GLP-1 users mostly are, and the defaults keep it away from everyone else.
- The app harms the research points to are goals, streak guilt, guilt-inducing notifications and good or bad labels (National Center for Health Research summary of Honary 2019 and Linardon and Messer 2019). My choices from that: no reminders about weighing; no weight streak, and weigh-ins never touch the dose streak, the History grid or the 30-day %; one neutral colour for gains and losses (an arrow and a number), never MyNetDiary's red for a gain and green for a loss; no goal weight, milestones, BMI, forecast, "Not losing weight?" prompts or praise for loss in v1 (a Happy Scale reviewer said its post-goal message "encourages disordered habits"); the trend as the headline number, so one heavy morning does not dominate. Copy uses Weight, Trend and weigh-in, never lose, ideal or goal. CI demo data is a flat-to-gently-falling line.

#### Store, privacy and positioning
- 1.1 stays as built: build 23, its screenshots and its listing do not change, and no weight code reaches main until 1.1 is approved. Taken stays "Did I take it? Know for sure."
- In 1.2 weight is a quiet extra: not in the name, subtitle, keywords or screenshots. The default app still has three tabs, so the 1.1 screenshot sets still show the real default (Guideline 2.3).
- What's New must list new features (Guideline 2.3.12) and is set per localization (App Store Connect: "This property can be localized"), so every localization gets one neutral line, translated: "New: an optional Weight tab. Log a weigh-in in a few taps and watch a smoothed trend form. Turn it on in Profile." No medicine, no "loss", no results. This is one written exception to REDESIGN.md's neutral-set rule for the 1.1 store screenshots (no "weight language" outside English (U.S.)): that rule exists because most countries ban promoting prescription medicines, and a feature name with no medicine in it promotes none. Outside What's New, non-U.S. descriptions, keywords and screenshots stay free of weight words.
- Notes for Review (Guideline 2.3.1(a)): where the switch is, the GLP-1 offer, on-device storage, and one sentence for the goal (Goal and moments, care rule 11): "An optional weight goal is in the Weight tab's More menu; it cannot be set below BMI 18.5, the sheet says goals are for adults, and nothing about it is prompted or sent." The English (U.S.) description may add: "Optional weight log with a smoothed trend, kept on your iPhone."
- Never show a drug name and a weight chart in the same screenshot, ad or custom product page (FTC net impression; ASA, July 2025, on implied weight-loss prescription medicines; Meta and TikTok require 18+ targeting for weight claims). With dose ticks, a real chart from a GLP-1 stack is exactly that pairing, so marketing never uses one. No "lose weight" or results claims (Guideline 2.3.7). "Taken is a personal log, not medical advice" stays (Guideline 1.4.1).
- Age rating stays 13+ (Health or Wellness Topics is already Yes). The privacy label stays Data Not Collected.
- docs/privacy.html: weigh-ins in sections 03 (what the app stores), 09 (CSV) and 11 (Erase, listing the tab setting, unit, offer answer and first weigh-in date as kept). Section 12 still says Taken "is suitable for all ages", which is wrong from 1.1's 13+: it belongs in the 1.1 store pack, and the 1.2 edit fixes it if it is still there.
- The Erase message becomes: "This removes your stack, every logged dose, all your to-dos, your weigh-ins and your profile from this iPhone. It cannot be undone."
- Later and optional: an English (U.S.) custom product page on weight-tracker keywords that shows the Weight tab with no medicine names (Apple allows up to 70, with keyword assignment).

#### Version, branch and files
- 1.2, after 1.1 is approved. Build now on a feature branch cut from main (for example feat/weight-tab), with every new type inside `#if DEBUG || TAKEN_INTERNAL`, the repo's existing setup for Guideline 2.5.19 ("Don't include any hidden, dormant, or undocumented features").
- Tom's builds: run ci.yml on the branch by hand (it has workflow_dispatch), then internal-testflight.yml on the branch. The ship-setup gate accepts any branch's green run that covers the code, and the internal workflow has no branch check. App Store builds come only from main (app-store-build.yml's "From main only" step), so nothing on the branch can reach 1.1, including the shared-code edits that cannot sit inside an `#if` (TabHeader, TodayPrompts.pick, RootView, ProfileView, DemoData, DemoProbe).
- App Store Connect gives every upload to Tom's internal group, so after any App Store build, run internal-testflight.yml from the branch again (the workflow header already says to re-run it). Rebase the branch on main as 1.0 and 1.1 fixes land.
- Merge after 1.1 is approved, keeping the `#if` gate, so any 1.1.x fix build from main stays clean until the 1.2 build.
- Marker: the tab's root view is a real type named `WeightTabRootView` (17 bytes; the script notes Swift keeps strings of 15 bytes or fewer where strings(1) cannot see them). Add it to the markers in scripts/check-app-store-build.sh and add an `--internal` presence check beside TodoEvalView and VoiceNoteLogView, so the scan proves it can see the name before an App Store build is called clean. For the 1.2 build, remove the `#if`, the marker and the presence check together.
- Do not swap out build 23: a new 1.1 build would restart the 1.1 store pack, screenshots and review notes. Weigh-ins Tom logs on internal builds stay in weights.json, which builds without the feature ignore and 1.2 reads.
- New files: Shared/WeightData.swift (WeighIn, WeightState, WeightTrend, WeightGate, WeightUnit, CSV), Shared/WeightStore.swift, Taken/Weight/WeightTabRootView.swift, WeighInSheet.swift, WeightChart.swift, WeighInList.swift, TakenTests/WeightTests.swift, TakenTests/WeightStoreTests.swift.
- Edited: Taken/AppModel.swift, Taken/Views/TodayView.swift, Taken/Profile/Profile.swift (TabHeader accessory), Taken/Views/ProfileView.swift, Shared/Retention.swift, Taken/Views/TodayPromptRow.swift, Shared/DemoData.swift, Taken/DemoProbe.swift, scripts/screenshots.sh, scripts/check-app-store-build.sh, docs/privacy.html, brand/appstore.py, SPEC.md, REDESIGN.md.
- Untouched: entitlements, both PrivacyInfo.xcprivacy files, Info.plist, project.yml, widgets, intents, StoreKit products, the age rating.
- Tests: trend math (lowest of the day, interpolation, the 0.9 trend, changes), unit parsing and formatting per locale, store round trip and concurrent writers, the gate, Erase, CSV, the offer rules, dose-tick selection, and tab visibility persistence with selection reset.
- Size: about 2,000 to 3,000 lines with tests (own estimate from the repo: the to-do store with its tests is 650 lines, the voice note log with its tests 781, the three 1.1 Today rows with tests 639, and the 1.1 retention PR #7 added 3,222 Swift lines).

### Where this differs from Tom's idea
- Default state. Tom: on for everyone, with a way to remove it. That is what Signal did with Stories and what Telegram has done with Calls since April 2025, so the biggest tab precedents are on his side. Recommended: off by default, offered once to GLP-1 stacks, plus a Profile switch, because Taken's own category (Medisafe) makes weight something you add, almost nobody changes a default (Spool), the first screen says what the app is (NN/g), HIG asks for defaults that suit the most people and fewer tabs, and Taken is 13+ with young women next. A judgement between two documented patterns; Telegram itself has switched three times.
- Removal. Tom: a corner button with a pop-up. Kept the corner button; it opens a small menu whose last item, "Hide Weight Tab", acts at once with an Undo toast and no confirmation, and Profile brings the tab back (HIG Alerts, HIG pull-down buttons, NN/g). Hiding deletes nothing.
- Wording. "Hide", not "Remove", so people know their weigh-ins stay; a verb in title case (HIG Menus).
- The corner. Every tab's top-right corner already holds the Profile avatar, so the More button sits beside it.
- The chart. MyNetDiary's has a goal line, percent-lost stars, a forecast and red and green change rows. v1 keeps the part Tom loves, the self-updating smoothed line, adds weekly dose ticks (what GLP-1 trackers do), and leaves the rest out, because goals and good or bad labels are where the eating-disorder research points.
- Who it is for. Tom reasons from people who take fitness pills. The evidence of demand is strongest for GLP-1 users, so the offer targets them; no data shows a weight tab makes a general supplement user stickier or likelier to pay (RevenueCat's 2026 report has none), so that part is a bet.
- Money. Tom's 99p for each suggests weight could carry its own price. It does not get one: weight-only apps get about $1.99 a month, and MyNetDiary and Happy Scale give the chart away. Weight goes into the existing Pro rule at today's prices.
- Timing. Not in 1.1. Built on a branch now for Tom's internal TestFlight builds; ships in 1.2.

### Own choices (no source found)
- Fourth tab after History; the scalemass symbol.
- Off by default rather than on, between two documented patterns.
- The Today offer's trigger (SEM, TRZ, OSM; an All-taken day; after the existing rows), its copy and buttons; "Add tab" does not switch tabs.
- The More menu's contents; the toast "Weight tab hidden. Profile brings it back."
- Kilograms and pounds only in v1; locales that prefer stones open in kilograms.
- The grey last-weigh-in placeholder, no date field in the sheet, bounds of 20 to 350 kg.
- The trend as the headline; changes computed from the trend and shown only once that much history exists.
- Dose ticks only for Weekly items and with no drug name on the chart.
- Chart default All, remembered range, filtering rather than scrolling.
- No goal line, milestones, forecast or BMI; one neutral colour; copy without lose, ideal or goal; no reminders; weigh-ins outside the streak, History grid and 30-day %.
- First weigh-in without Pro, then Pro, by analogy with TodoGate; no automatic paywall and no paywall bullet for weight.
- weights.json as its own file; the tab setting, unit, offer answer and first weigh-in date survive Erase, like the look and the nudge answer; a weigh-in's day from DayClock.
- Apple Health as an on-demand phase 2 from the Weight tab's menu.
- The branch, merge and gate sequence; the separate taken-weight.csv.
- The 7-day EMA fallback only after Tom's side-by-side check.
- The What's New exception to the neutral-set rule.
- The 2,000 to 3,000 line estimate.

### Risks
- Few people will find it: off by default and offered only to GLP-1 stacks. Taken collects no analytics, so the only signals are reviews, support mail and Tom's own use. If discovery proves too low, flipping the default for new installs is small, and explicit choices are kept.
- Scope creep toward MyNetDiary: goals, BMI, photos, calories, body fat. Each needs its own decision.
- Even opt-in, a weight chart can hurt some people; neutral design and no prompts reduce that, they do not remove it.
- Taken's trend will not match MyNetDiary's: the 0.9 trend runs about 9 to 10 days behind, about 1.3 kg above the scale at 1 kg a week and about 0.4 kg at Tom's pace. Check on his real data in the internal build before 1.2.
- UK users who think in stones get kg or lb only in v1.
- Weigh-ins live only on the iPhone and in device backups; without backups they go with the phone, as doses do today. CSV helps; Apple Health write in phase 2 would add a durable copy.
- The branch drifts from main, and each App Store upload moves Tom's phone off the weight build until internal-testflight.yml runs again from the branch.
- App Review: Notes for Review and What's New must describe it (2.3.1(a), 2.3.12), and internal-only code must stay out of App Store binaries until 1.2 (2.5.19), which the marker and its presence check prove.
- Marketing: any ad or screenshot pairing Semaglutide or Tirzepatide with a falling chart reads as a weight-loss claim (FTC, ASA) and needs 18+ targeting on Meta and TikTok.
- HIG coverage on iPhone: tab customization guidance sits in HIG's iPadOS section and the general rule is not to hide tabs, so a person-chosen tab on iPhone rests on shipping practice (Signal, Telegram), not explicit HIG text.
- Paywall friction for someone whose first action is a weigh-in: no data on how that converts.
- Phase 2 HealthKit adds a capability, new profiles outside the frozen-credential workflows, listing text and a privacy section.
- No evidence it lifts conversion or renewal; the case rests on correlational self-weighing and engagement studies and on Tom's own habit.
- Engineering time: 2,000 to 3,000 lines plus CI landings, competing with 1.0 and 1.1 review fixes.

### Critic review (each point checked against its source)
- Applied, Telegram precedent: commit 4a97994b (14 Apr 2025) made CallListSettings return true when nothing is stored, ApplicationContext.swift builds the tab bar from that, commit 3e6363ab (28 May 2026) commented out the after-call offer, and Telegram's 30 Apr 2025 post says "you may need to enable it via Settings > Recent Calls". History checked too: off in 2017, on in January 2020 (30e4543b9c), off in May 2020 (ad3147dbbf, "Don't show Calls tab by default"), on since April 2025. The record now says the tab precedents are on Tom's side and labels off by default as a judgement, resting on Medisafe, HIG, Spool, NN/g, the self-weighing studies and the store rule.
- Applied, dose markers: GlucoPal 2.5.0 and GLP-1 Digest on Shotsy confirmed; Glapp's listing only says "Monitor your weight loss progress at every dosage" and "detailed breakdowns by dosage", so the Glapp claim is narrowed. The chart gets weekly dose ticks.
- Applied, size: TodoStore 82 plus tests 568, VoiceNoteLog 610 plus tests 171, the Today rows 105, 267 and tests 267, PR #7 3,222 Swift lines. Estimate raised to 2,000 to 3,000; scope trimmed (kg and lb only; Swift Charts' built-in Audio Graph instead of a custom one).
- Applied, branch: "From main only" in app-store-build.yml, no branch check in internal-testflight.yml, any branch's green run accepted by ship-setup, workflow_dispatch on ci.yml.
- Applied, What's New: localizable per App Store Connect, required by 2.3.12, so a neutral line goes in every localization with a written exception to the neutral-set rule.
- Applied, citations: PMC4046275 is LaRose et al. 2014; Steinberg et al. 2014 is PMC4157390; Pacanowski et al. 2015 (PMC4644499) added; the adult no-harm claim is narrowed to adults with overweight in weight-loss programmes.
- Applied, marker: `WeightTabRootView` is the real type, with both the absent check and an `--internal` presence check.
- Applied, trend wording: lag about 9 to 10 days; no claim that MyNetDiary's spline overshoots; Weight Widgets says "7-day moving average", so only Weigh Easy is cited for an exponential 7-day trend.
- Applied, Erase message keeps "It cannot be undone."
- Applied with earlier timing, privacy.html section 12: it is wrong from 1.1's 13+, so it belongs in the 1.1 pack; the 1.2 edit is the backstop.
- Rejected in part: that current shipping practice simply matches Tom's idea. In Taken's own category Medisafe makes weight a tracker you add, and Telegram itself ran off by default for most of 2017 to 2025, so documented practice is split, not one-sided.

### Built on feat/weight-tab (internal builds only until 1.1 is approved)
- Every weight-only type sits inside `#if DEBUG || TAKEN_INTERNAL`: Shared/WeightData.swift, Shared/WeightStore.swift and Taken/Weight (WeightTabRootView, WeighInSheet, WeightChart, WeighInList, WeightModel). The shared edits (AppTab, SheetRoute, UndoStep, TodayPrompt, RootView, TabHeader, ProfileView, TodayPromptRow, DemoData, DemoProbe) add their weight cases inside the same `#if`, so a Release build from project.yml compiles exactly 1.1. XcodeGen picks the new files up from the `Taken` and `Shared` source folders; project.yml is unchanged.
- `WeightTabRootView` is a marker in scripts/check-app-store-build.sh, with an `--internal` presence check beside TodoEvalView and VoiceNoteLogView. ci.yml's Release build runs the check on every run.
- The offer's rule is an overload of `TodayPrompts.pick` with a `weightOffer` argument, so 1.1's `pick` is untouched. Following the extras policy below, it also waits for a later day than the first dose and than the widget invite's day, so it never shows in the first session or on the invite's day.
- Added beyond the spec: Profile, Data, "Import weight CSV" (below), behind the weigh-in Pro rule because it backdates in bulk; `WeightModel` holds weights.json for the app model.
- Screenshots (scripts/screenshots.sh): the list in "Weight tab page: entry first", section 14, with the goal's 70 to 75. No file name ends in a store frame's state, because tools/store-shots matches any file ending in "-<state>". Every other capture checks `weight=0`, so the 1.1 screenshots still show three tabs.
- Not in this branch: docs/privacy.html (sections 03, 09, 11 and 12; section 03 also names the optional weight goal and the height kept with it) and brand/appstore.py (What's New, Notes for Review with the goal sentence above, the English (U.S.) description line). docs/ is the public site and appstore.py holds 1.1's store text, and neither may change before 1.1 is approved. Both belong to the 1.2 store pack, with the What's New line above.

### Importing history (CSV)
- Shipping weight apps bring old weigh-ins in by CSV or through Apple Health. Weigh In lists "Import and export CSV files" and shipped a "New CSV importer" in 2.2.0; ScaleTrack lists "Import from CSV"; Libra fixed "importing from .csv files" in 4.6.3. Happy Scale imports only from Apple Health, taking the lowest entry of a day.
- MyNetDiary does not document its export's columns. Its FAQ says data export is on the website (Analysis, Data Export or Multi-Day Reports, saved as PDF or Excel), that reports from the website's Analysis page need Premium, and that the app's own reports are PDFs. Its professional guide says reports can be "exported to Excel (CSV format)". It also writes weight to Apple Health when its Health sync is on (off by default).
- So Taken reads any CSV by its headers rather than one app's layout: a date column and a weight column, the unit from the header or the cells and otherwise the person's own unit (which the result line names), an optional time column, commas, semicolons or tabs, a decimal point or comma, and day or month first worked out from the whole column. A row in a minute already logged is skipped, so importing twice adds nothing, and unreadable rows are counted.
- Not yet checked against a real MyNetDiary file: Tom's export is the test. If his MyNetDiary account is not Premium the website export may be closed to him, and Apple Health (phase 2 above) is the other documented route.

### Sources
- Apple HIG: https://developer.apple.com/design/human-interface-guidelines/tab-bars (change log 8 Jun 2026), https://developer.apple.com/design/human-interface-guidelines/settings, https://developer.apple.com/design/human-interface-guidelines/pull-down-buttons, https://developer.apple.com/design/human-interface-guidelines/alerts, https://developer.apple.com/design/human-interface-guidelines/menus, https://developer.apple.com/design/human-interface-guidelines/onboarding, https://developer.apple.com/design/human-interface-guidelines/healthkit, https://developer.apple.com/design/human-interface-guidelines/charts
- SwiftUI, Charts and Foundation: https://developer.apple.com/documentation/swiftui/tabviewcustomization, https://developer.apple.com/documentation/swiftui/tabcontent/customizationbehavior(_:for:), https://developer.apple.com/documentation/swiftui/tabcontent/hidden(_:), https://developer.apple.com/forums/thread/770633, https://developer.apple.com/documentation/charts/interpolationmethod/monotone, https://developer.apple.com/documentation/swiftui/view/chartscrollableaxes(_:), https://developer.apple.com/documentation/swiftui/view/chartxvisibledomain(length:), https://developer.apple.com/documentation/foundation/unitmass/init(forlocale:usage:), https://developer.apple.com/documentation/foundation/measurementformatunitusage/personweight
- HealthKit, widgets, intents: https://developer.apple.com/documentation/healthkit/hkhealthstore/preferredunits(for:completion:), https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/bodymass, https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities, https://developer.apple.com/forums/thread/771723, https://docs.expo.dev/build-reference/ios-capabilities/
- App Store: https://developer.apple.com/app-store/review/guidelines/ (Last Updated October 16, 2026: 1.4.1, 2.3, 2.3.1(a), 2.3.7, 2.3.12, 2.5.1, 2.5.19, 5.1.3), https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information, https://developer.apple.com/app-store/app-privacy-details/, https://developer.apple.com/documentation/foundation/optimizing-your-app-s-data-for-icloud-backup, https://developer.apple.com/app-store/custom-product-pages/
- Telegram: https://telegram.org/blog/calls (30 Mar 2017), https://telegram.org/blog/group-calls-made-easy (30 Apr 2025), https://github.com/TelegramMessenger/Telegram-iOS/commit/30e4543b9c4e2d6512604193265a305c24c1c6d1, https://github.com/TelegramMessenger/Telegram-iOS/commit/ad3147dbbfb90e48cdf29e2fe6335fb9ed59bbc8, https://github.com/TelegramMessenger/Telegram-iOS/commit/4a97994bffaa2240114dfd1360db07421e8268e0, https://github.com/TelegramMessenger/Telegram-iOS/commit/3e6363abf9c25af916dd75c574bc317eccecf978, https://github.com/TelegramMessenger/Telegram-iOS/blob/master/submodules/TelegramUIPreferences/Sources/CallListSettings.swift, https://github.com/TelegramMessenger/Telegram-iOS/blob/master/submodules/TelegramUI/Sources/ApplicationContext.swift, https://github.com/TelegramMessenger/Telegram-iOS/blob/master/submodules/TelegramCallsUI/Sources/CallController.swift
- Signal: https://signal.org/blog/introducing-stories/, https://www.xda-developers.com/signal-stories-rolls-out-to-all-users
- Defaults and confirmation: https://archive.uie.com/brainsparks/2011/09/14/do-users-change-their-settings/, https://www.nngroup.com/articles/progressive-disclosure/, https://www.nngroup.com/articles/confirmation-dialog/
- Medication and GLP-1 apps: https://help-center.medisafe.com/en/articles/8098222-how-to-add-a-health-tracker, https://apps.apple.com/us/app/medisafe-medication-management/id573916946, https://apps.apple.com/us/app/mytherapy-medication-reminder/id662170995, https://apps.apple.com/us/app/shotsy-glp-1-tracker/id6499510249, https://www.glp1digest.com/p/how-shotsy-grew-to-350000-monthly, https://www.revenuecat.com/blog/growth/aja-beckett-shotsy-launched-podcast-2025, https://apps.apple.com/app/id6670317407 (GlucoPal), https://apps.apple.com/app/id6756984097 (Glapp)
- Weight apps: https://apps.apple.com/us/app/happy-scale/id532430574, https://www.iphonejd.com/?p=5491, https://syntopikon.substack.com/p/an-interview-with-russ-shanahan, https://apps.apple.com/us/app/libra-weight-manager/id1644353761, https://apps.apple.com/us/app/mynetdiary-calorie-counter/id287529757, https://www.mynetdiary.com/iphelp_weight2.html, https://apps.apple.com/app/id6759265406 (Weigh Easy), https://apps.apple.com/app/id6761092594 (Weight Widgets)
- Trend: https://www.fourmilab.ch/hackdiet/e4/signalnoise.html, https://www.fourmilab.ch/hackdiet/e4/pencilpaper.html, https://help.macrofactorapp.com/dashboard/weight_trend/
- Self-weighing research: https://pubmed.ncbi.nlm.nih.gov/17116510/ (Neumark-Sztainer et al. 2006, J Adolesc Health 39(6):811-818), https://pubmed.ncbi.nlm.nih.gov/22717180/ (Friend et al. 2012, J Acad Nutr Diet 112:99-103), https://pmc.ncbi.nlm.nih.gov/articles/PMC4644499/ (Pacanowski et al. 2015), https://pmc.ncbi.nlm.nih.gov/articles/PMC4157390/ (Steinberg et al. 2014), https://pmc.ncbi.nlm.nih.gov/articles/PMC4046275/ (LaRose et al. 2014), https://www.center4research.org/fitness-tracking-apps-eating-disorders/
- Money: https://www.revenuecat.com/state-of-subscription-apps/
- Marketing: https://www.ftc.gov/business-guidance/resources/health-products-compliance-guidance, https://www.asa.org.uk/news/how-we-re-trimming-down-problem-ads-for-weight-loss-prescription-only-medicines.html, https://transparency.meta.com/policies/ad-standards/restricted-goods-services/health-wellness, https://ads.tiktok.com/resources/help/article/tiktok-ads-policy-weight-management
- Repo, origin/main 164a893: Taken/AppModel.swift (AppTab, SheetRoute, tab(forScreen:), requirePro, toasts, eraseAll), Taken/Views/TodayView.swift (RootView), Taken/Profile/Profile.swift, Taken/Views/ProfileView.swift (eraseMessage), Shared/Pro.swift (ProGate, InternalBuild), Shared/TodoData.swift (TodoGate), Shared/Retention.swift (TodayPrompts.pick), Shared/StackLogic.swift (eraseAll, CSVExport), Shared/Model.swift (Item, Dose, Frequency), Shared/Catalog.swift (SEM, TRZ, OSM), scripts/check-app-store-build.sh, .github/workflows/ci.yml, .github/workflows/app-store-build.yml, .github/workflows/internal-testflight.yml, .github/actions/ship-setup/action.yml, PRO.md, SPEC.md (sections 2 and 5), REDESIGN.md (lines 102, 124, 303 to 308, 393), docs/privacy.html (sections 03 to 12)
- Local check on this Mac (Foundation): UnitMass(forLocale:usage: .personWeight) gives lb for en_US and es_US, st for en_GB, kg for en_IE, en_AU, en_CA, de_DE, fr_FR, ja_JP and en_IN; personWeight formatting rounds 88.35 kg to "88 kg", "195 lb" and "13 st, 13 lb"
- Tom's MyNetDiary screenshots 1.webp to 7.webp, 22 Oct 2026
- Import: https://www.mynetdiary.com/faq.do ("Data export", "How do I download my log?", "How to email reports directly from the app", Apple Health), http://files.mynetdiary.com/MyNetDiaryHealthcareProfessionalGuide.pdf, https://happyscale.com/support, https://apps.apple.com/us/app/weigh-in-weight-tracker/id1082115351, https://apps.apple.com/app/id6782255261 (ScaleTrack), https://apps.apple.com/us/app/libra-weight-manager/id1644353761

### Goal and moments, 2026-10-22 (design for the Weight tab above; built on feat/weight-tab, internal builds only)

Tom asked for a weight goal to work towards, to see himself "getting closer to the line", and for the important points to be marked "so it's not super generic", while the page stays "enter weight, done" and the chart stays one chart at the right size, without MyNetDiary's awkward zoom. He was just as clear that MyNetDiary is what he uses, not a design to copy: he said its gold stars look like emojis. Three concepts came from three research passes (the behaviour-change and eating-disorder evidence; how careful apps and Apple show progress; Taken's own tokens and Swift Charts on iOS 17). A judge scored them. This is the winner, Lit Points, with the judge's grafts applied and the mistakes all three shared fixed. It replaces v1's "Left out of v1: goal line, percent-lost milestones" for the goal and its moments only. Forecast, BMI on screen, and red and green stay out.

#### Verdict
An optional goal, set only from the Weight tab's More menu. It adds three things to the page and nothing to the weigh-in:
1. One quiet solid line on the chart at the goal, labelled with its number.
2. One line under the trend that says how close you are: "1.1 kg to 87.0".
3. At most three lit points on your own trend line: where the trend first sat 5% and 10% below where you started, and where it reached the goal.

When a weigh-in you have just saved crosses one of those points, you get one plain sentence for that visit. Reaching the goal also plays the success haptic Taken already plays for All taken. There are no stars, badges, praise, target dates, pace, forecast, expand button or second chart. It ships with the tab in 1.2, inside the same `#if DEBUG || TAKEN_INTERNAL` gate.

#### Why each element earns its place
- **A goal.** Goal setting, self-monitoring and feedback are the components that predict effect in weight-loss trials (Samdal et al. 2017, 48 RCTs). The harms documented in apps come from the form a goal takes: prompted goals, guilt over missed targets, praise for use, and unsafe or ever-lower targets (Honary et al. 2019; National Alliance for Eating Disorders 2026; Frontiers in Computer Science 2023). So the goal is never prompted, has no deadline, has a floor, and earns no praise.
- **The closing-in line.** Effort rises as people near a goal, and it follows the share of the distance left (Kivetz, Urminsky and Zheng 2006). Pointing attention at the smaller part motivates most: what is done early on, what is left near the end (Koo and Fishbach 2012). The middle is where motivation dips (Bonezzi, Brendl and De Angelis 2011). One figure whose wording changes at halfway does all of that. It replaces MyNetDiary's progress bar, percentage and three change rows.
- **5% and 10%.** The guideline for adults with overweight or obesity recommends "sustained weight loss of 5 percent to 10 percent" and says even 3% gives clinically meaningful falls in triglycerides and blood glucose (ACC/AHA 2013). CDC: "even modest weight loss can help improve your blood pressure, cholesterol, and blood sugar levels", with a 5% example. The thresholds are the same for everyone, so a mark there states a fact about health. It is not generic praise.
- **A lit point, not a star.** Positive feedback that informs raises motivation (d = 0.33 for free-choice behaviour), while expected rewards undermine it (Deci, Koestner and Ryan 1999). Regulators cited Robinhood's confetti as gamification, and Robinhood removed it (CNBC 2021). Taken already has a mark for "this happened": lit (Theme.swift: "Lit = taken"; the paywall timeline's lit 8 pt dot; the lit dose disc). On iOS a star reads as a rating or a favourite. Choosing the lit point is my judgement, built on those sources.
- **A solid line, not a dashed one.** 1.1 removed dashed rules (REDESIGN.md line 19), and a reference line stays distinct from the grid when it carries its own label (leancrew 2025, on Apple Stocks against Google's chart).

#### The page, top to bottom (goal set, Signal look, Tom's numbers; replaced by "Weight tab page: entry first" below)
Changes from the v1 layout are marked NEW.
1. **TabHeader** "Weight", as v1. NEW subtitle: "Last 88.35 kg · yesterday, 07:42" in Geist 15, fgSubtle. It stays a plain String, so TabHeader does not change. The last weigh-in's value moves up from the card, so "Last" appears once and the card's third line gets the card's full width. Day words are as v1: "today", "yesterday", a weekday within the past week, then "14 Oct", and "14 Oct 2025" from another year. The More button and the avatar are as v1.
2. **Headline card** (Card, padding 16), now one column:
   - "Trend", Geist Medium 14, fgSubtle (v1).
   - The trend value in Geist Mono Medium 40, fg, `.contentTransition(.numericText())`, with "kg" in Geist Medium 18, fgMuted (v1).
   - NEW, **the slot**, 2 pt below the value. It is one line at the default text size (lineLimit 2).
     - No goal: v1's caption "smooths daily swings", now Geist 15, fgSubtle.
     - Goal set: the closing-in line.
     - For one visit after a crossing: the moment sentence.

     The slot is always there, so the card never changes height. v1's right-hand "Last" column is removed.
   - PrimaryButton "Log weigh-in", 16 pt below (v1).
3. **Chart card** (Card, padding 16, VStack spacing 14):
   - WeightRangePicker: W, 30D, 90D, Y, All (v1).
   - NEW: the change line for the selected range. It replaces v1's row of 7, 30 and 90 day changes and its divider.
   - The chart (below), with the plot at 196 pt.
   - "Ticks: weekly doses", only when there are ticks (v1).
4. **"All weigh-ins"** row (v1).

On screen with Tom's goal set:
- Numbers: 88.35 and 07:42 in the subtitle, 88.1 for the trend, 1.1 and 87.0 in the slot, −9.7 in the change line, the axis labels (87.0 among them) and one "−5%" label.
- Controls: More, the avatar, Log weigh-in, the range control, the chart (scrub) and All weigh-ins. These are v1's six. The goal adds no control to the page.

**Fit.** This is my estimate from the screenshots of CI run 39680393222, to be proved by the probe under CI. On the iPhone 16 (393 x 852 pt) at the default text size:
- Content starts about 158 pt down, and the floating tab bar begins about 768 pt down.
- The headline card is about 192 pt, then a 16 pt gap, then the chart card at about 365 pt.
- So the chart card ends near 731 pt, above the tab bar. All weigh-ins is a short scroll below.

The branch's current page (two-column card plus three change rows) is about 35 pt taller.

#### The goal
**Where it is set.** Only from the More menu, which becomes:
- "Kilograms" and "Pounds" with a checkmark (v1)
- a divider
- "Set Goal…", or "Change Goal…" once a goal exists, then "Clear Goal" (only when a goal exists)
- a divider
- "Hide Weight Tab" (v1)

HIG Menus asks for an ellipsis when an item needs more input, and allows one item whose label changes with state. "Set Goal…" stays dimmed until the first weigh-in exists (HIG Menus: "Show people when a menu item is unavailable"). Taken never asks for a goal anywhere else: not in onboarding, the Today offer, the empty state, the weigh-in sheet, Profile or a notification.

**The Goal sheet.** A new `SheetRoute.weightGoal` (id "weight-goal"), presented from RootView like the other sheets and sized to its content like WeighInSheet. From top to bottom:
- SheetHeader "Goal", with Close.
- The goal field, exactly like WeighInSheet's:
  - Geist Mono Medium 44 in a bgRaised box with card radius and a 1 pt `line` border that turns signalEdge while focused.
  - The unit beside it in Geist Medium 22, fgMuted.
  - Decimal pad, focused on appear with the same 80 ms task.
  - At most one decimal: `WeightFormat.sanitize` gains `maxDecimals`, 2 by default and 1 here.
  - Placeholder: the current trend, in fgFaint. Change Goal… opens with the goal filled in.
- **"Start" row.**
  - The label in Geist 15, fgMuted.
  - The start value in Geist Mono Medium 15, fg ("97.8 kg").
  - A compact, date-only `DatePicker` showing the start day, limited to the days from the first to the last weigh-in.
- **"Height" row.**
  - The label in Geist 15, fgMuted.
  - A button reading "Set" in Geist SemiBold 15, signalInk, until a height is chosen. After that it shows the height in Geist Mono Medium 15, fg, with `chevron.up.chevron.down` at 11 pt, fgSubtle. This is the MonoTimeButton pattern.
  - The button opens a small wheel sheet built like TimeWheelSheet:
    - SheetHeader "Height".
    - One wheel in centimetres (100 to 230), or two wheels for feet (3 to 7) and inches (0 to 11).
    - PrimaryButton "Set 183 cm" or "Set 6 ft 0 in".
    - The wheel starts at the stored height, or else at 170 cm or 5 ft 7 in. Nothing is kept until Set.
  - The unit follows `UnitLength(forLocale: .current, usage: .personHeight)` (iOS 16): feet gives feet and inches, anything else gives centimetres. Checked on this Mac: en_GB, en_US, en_CA and en_IN give feet; en_IE, en_AU, de_DE and ja_JP give centimetres; fr_FR gives metres, shown as centimetres.
  - Height is stored in centimetres.
- Footnote, Geist 13, fgSubtle: "Shows as a line on your chart, measured on your trend, not single weigh-ins. No dates, no pace, no reminders. Goals are for adults."
- Footnote, Geist 13, fgSubtle: "Height is used only to keep goals in a healthy range. Kept on this iPhone."
- When the goal is below the floor: one line above Save in Geist 15, fgMuted, never red: "Too low for your height. Taken keeps goals in a healthy range." It names no number.
- PrimaryButton "Save". It is enabled when all of these hold:
  - the goal parses in the locale;
  - it is inside the unit's bounds (20 to 350 kg, 44 to 770 lb, as v1);
  - a height is set;
  - the floor does not block it.

  Save stores the goal (with the height, if new), closes the sheet, plays the soft haptic if haptics are on, and announces "Goal set, 87.0 kilograms." There is no toast.

There is no target date, rate, plan, forecast or start-weight field. The weigh-in sheet does not change at all (Tom's rule).

**The floor.** The lowest goal is 18.5 x (height in metres) squared, that is BMI 18.5.
- Honary et al. 2019 propose blocking goals below BMI 18.5 and saying why.
- Lifesum's shipped block reads "Goal weight too low. Please change your goal." and gives no number.
- Beat welcomed the NHS weight app removing access for people with a low BMI instead of only telling them it was unsuitable.

The message names no number because the number would hand an at-risk person the lowest target to aim for. The floor applies to goals in the lower and near directions. A goal above the start, gaining towards a healthier weight, is never blocked. That is my judgement: the floor exists to stop unsafe loss, not recovery.

**Adults.** Adult BMI categories do not apply through age 19; CDC uses BMI-for-age percentiles for 2 through 19. Taken is rated 13+ and knows no ages, so the sheet says "Goals are for adults.", the kind of guidance Beat welcomed in the NHS app ("this product is only suitable for adults"). There is no age question: the double opt-in, the floor and that line are the mitigation (own judgement).

**Start.** The start S is the trend on the start day, computed when the goal is saved and then stored.
- **Default:** the first weigh-in day. MyNetDiary does the same: "MyNetDiary considers your first weigh-in date to be your start date".
- **Exception:** if the goal lies between the lowest and the highest trend since the first weigh-in, the trend has already been at that weight. The start is then the last weigh-in day instead. This is my own rule. It stops a long imported history from turning a regain into a finished goal.
- **Moving it:** the person can move the start in the Start row, as Happy Scale's start date does while keeping earlier entries. MyNetDiary's only way to change it is Start Over, which deletes earlier weigh-ins.
- **In the sheet:** Set Goal… recomputes the default start as the goal is typed, until the Start row is touched. Change Goal… keeps the stored start if the value is unchanged. If the value changes, it recomputes the default unless the start was picked by hand (`startPicked`).
- **After edits:** a start day that falls outside the weigh-ins after edits or deletes is clamped to the first or the last weigh-in day.
- **For Tom:** import MyNetDiary's export first (Profile, Data, Import weight CSV on the branch). Then his first weigh-in is March's 97.8 kg, the goal 87.0 is below every trend since, and the start is 97.8.

**Direction: inferred, never asked.** From S and the goal G:
- lower, if G is more than 0.68 kg below S;
- higher, if G is more than 0.68 kg above S;
- otherwise near.

0.68 kg is MacroFactor's maintenance tolerance (1.5 lb either way, judged on the trend weight). Allowing lower, higher and near follows Happy Scale and MacroFactor. Inferring the direction instead of offering a picker is my choice, so that the sheet stays one number.

**Reached.**
- Lower goal: reached on the first weigh-in day after the start on which the trend is at or below G + 0.05 kg.
- Higher goal: reached when the trend is at or above G - 0.05 kg.
- The 0.05 kg tolerance is my own, so "0.0 kg to 87.0" never shows.
- A near goal starts out held.

After that, the goal holds. There is no finish screen and no "set a new goal" prompt:
- v1's care section records a Happy Scale reviewer saying its post-goal message "encourages disordered habits".
- Honary describes apps that push ever-lower targets.
- A year after semaglutide stopped, people had regained two-thirds of their loss (Wilding et al. 2022), so holding is the long game.

**Clear and change.**
- Clear Goal acts at once:
  - the toast "Goal cleared" with UNDO (a new `UndoStep.restoreWeightGoal(WeightGoal)`);
  - the soft haptic;
  - VoiceOver: "Goal cleared."
- It shows no alert, because nothing is deleted (HIG Alerts; NN/g on confirmation dialogs, as v1's Hide Weight Tab).
- Changing or clearing a goal deletes no weigh-in and never asks for a reason.
- Hide Weight Tab keeps the goal. Erase all data removes the goal and the height along with the weigh-ins.

**Taken Pro.** Set, change and clear are open in every Pro state, like the unit and the range: a goal is a way of viewing the record, and the record is never held hostage (PRO.md). Logging stays gated as in v1, so a locked user gets no new moments. Own choice.

#### The slot: closing in, in one line
Everything is computed on the trend; T is the trend on the last weigh-in day. Numbers (with their units) are in Geist Mono Medium 15, fg; words are in Geist 15, fgMuted.

| State | When | Shows |
|---|---|---|
| No goal | | "smooths daily swings" (fgSubtle) |
| Not moving yet | less than 0.1 covered in the chosen unit, or the trend is on the far side of the start | "Goal 87.0" |
| Closer | less than half the distance covered | "4.2 kg closer to 87.0" (covered, rounded down to 0.1) |
| To go | half or more covered, not yet reached | "1.1 kg to 87.0" (left, rounded up to 0.1) |
| Holding | reached, or a near goal, with the trend within 0.68 kg of G | "Holding near 87.0" |
| From | reached, or a near goal, with the trend more than 0.68 kg away | "0.9 kg from 87.0" (never above, below, over or under) |
| Moment | one visit, after a crossing on the weigh-in just saved | "Trend is now 10% below where you started." or "Trend reached 87.0." (all in fg) |

How the numbers are worked out:
- Covered is S - T for a lower goal and T - S for a higher one. Half is half of the distance from S to G.
- Tom: S 97.8, T 88.1, G 87.0. He has covered 9.7 of 10.8 kg, which is past half, so the slot reads "1.1 kg to 87.0".
- Numbers are converted to the chosen unit before rounding.

At the default text size every state fits one line on a 375 pt iPhone. Measured with the repo's Geist files, the longest, the 10% sentence, is 299 pt in a 303 pt slot (321 pt on a 393 pt iPhone).

#### Moments
**Which.** There are at most three, and none without a goal.
1. The trend 5% below the start.
2. The trend 10% below the start.

   Both percent points follow three rules:
   - They exist only for a lower goal.
   - The threshold must lie between the start and the goal, more than 0.05 kg from the goal. So nothing ever marks going past your own goal.
   - The start must be at BMI 25 or more, using the height from the sheet. The 5% and 10% figures come from the guideline for adults with overweight or obesity (ACC/AHA 2013; CDC). Below BMI 25 they have no clinical basis, and marking loss there would mark it in exactly the people v1's care section protects. Tom keeps them unless he is taller than about 1.98 m.
3. The goal reached, in either direction.

Not marked:
- Halfway. The slot's change of wording is the acknowledgement.
- 15% and 20%. They are a trial responder ladder (STEP 1), not guideline thresholds; past 10% the person's own goal is the mark.
- "Lowest since", personal bests, weekly praise, streaks and speed.

A near goal gets no points. A higher goal gets only the goal point.

**When a point counts.** On the first weigh-in day, on or after the start, on which the trend is at or past the threshold.
- Only real weigh-in days count, never a day the trend filled in between weigh-ins (v1 fills gaps with straight lines). So a point never carries a date Tom did not weigh in.
- Once a point exists it stays, even if the trend rises again, because the first such day stays the first.
- Points are a pure function of the weigh-ins, the goal, its start and the height. Nothing is stored. Editing or deleting weigh-ins, or changing the goal, recomputes them, and a changed goal shows its own points only.
- A point is never shown as upcoming, pending, missed or lost. NICE TA875 uses less than 5% after 6 months as the point to consider stopping semaglutide, so "not yet 5%" would read as a verdict of non-response.

**The mark.** A lit point on the trend line on that day:
- An 8 pt circle in `signal` with `theme.glow(0.35)` at radius 4.
- Behind it, a 12 pt circle in `bgRaised`, the card's colour, which cuts the line so the point sits in it like a bead.
- The tokens carry it into every look (amber, rose, green, ice). Blush's glowStrength of 0.35 softens it further.
- It is drawn in `chartOverlay` (see the chart), above the line, and is never hit-testable.
- Dose ticks stay on the baseline, so the two never meet.

**Its label.** The chart carries at most one label: on the newest point in view, if that point is 5% or 10%.
- Text: "−5%" or "−10%", using the U+2212 minus that Geist Mono has, in Geist Mono Medium 11, fgMuted.
- Position: 8 pt right of and 12 pt above the point's centre, flipped to the left or below if it would leave the plot.
- The goal point is never labelled, because the goal's own axis label names it. Once the goal is reached, no point carries a label.
- Older points name themselves when scrubbed and to VoiceOver.

**The one-time acknowledgement.** It happens only when a weigh-in saved from Log weigh-in creates a point that did not exist just before the save and is dated that weigh-in's day. Backdated weigh-ins, edits, imports, a goal set or changed, and a moved start all make points appear silently.
- **Toast:** stays v1's "Weighed in 88.35 kg" with UNDO.
- **Sentence:** for that visit the slot shows "Trend is now 5% below where you started.", "Trend is now 10% below where you started." or "Trend reached 87.0.".
  - If two points arrive together after a gap, the goal outranks 10% and 10% outranks 5%.
  - The closing-in line returns when the Weight tab disappears, the app leaves the foreground, UNDO is tapped or the next weigh-in is saved.
  - Today's All taken already works this way: ProgressSummary swaps the progress line for the moment.
- **Animation:** the new point draws in 0.35 s after Save, once the sheet is down, with the All taken spring: scale 0.55 to 1 with `.spring(response: 0.38, dampingFraction: 0.55)`, and the glow easing from `glow(0.7)` at radius 8 to `glow(0.35)` at radius 4. Under Reduce Motion it fades in with `.easeOut(duration: 0.18)`, as ItemRow's ring does.
- **Haptics:** a 5% or 10% point keeps the ordinary soft save haptic. Reaching the goal plays `Haptics.success` instead, at the same 0.35 s; it is the haptic All taken plays. HIG Playing haptics: use system patterns for their documented meaning, consistently, not too often, and optionally. HIG Feedback: "match the significance of the information to the way it's delivered". Taken's Haptics switch applies.
- **VoiceOver:** one announcement 0.5 s after Save, for example "Weighed in, 88.35 kilograms. Trend is now 10 percent below where you started." For the goal it ends "Trend reached your goal, 87.0 kilograms."
- **UNDO:** undoing that weigh-in removes the point and the sentence. Saving the same number again acknowledges it again, so a typo cannot use up a moment.

**What never happens:**
- stars, emoji, badges, a badge shelf, trophies, confetti or sound;
- a sheet or full-screen moment;
- "Great job", "Keep it up" or "lost";
- a list of what comes next, or a hollow or grey future point;
- a notification, or anything in the widgets, History, the streak or Today;
- any mark, copy or colour change when weight goes up;
- red or green;
- a prompt to set a lower goal.

#### The chart
**Size.** One chart, inline, at the full card width.
- The plot is fixed at 196 pt with `chartPlotStyle { $0.frame(height: 196) }`, which replaces the branch's outer 220 pt frame. That way the points per kilogram are known.
- There is no expand button, no full-screen view, no pinch and no scroll. Ranges set `chartXScale` and filter, as in v1.
- WWDC22 session 110342: an interactive chart is "the width of your view, but not full-height", and a small chart sets up "the expectation that additional detail is just a tap away", which is MyNetDiary's zoom.

**Y domain.** v1's fitted, padded domain, which never starts at zero (HIG Charts, dynamic range). With a goal:
- The goal joins the domain only if the padded span with it is at most twice the padded span without it. So the data always keeps at least half the plot's height. Own rule.
- On All, Tom's goal sits inside the domain, and the narrowing gap between the end of the line and the goal line is the "closing in" picture. Nothing is added to it.
- On W or 30D, far from the goal, the goal stays out and its label is pinned to the edge (below). Nothing ever squashes the line to fit a far goal.

**Goal line.**
- `RuleMark(y:)`: 1 pt, solid, `fgFaint`.
- Drawn after the dose ticks and before the weigh-in dots and the trend.
- Accessibility label "Goal", value "87.0 kilograms".
- Not dashed (REDESIGN.md line 19); no "Goal Weight" text, no flag, no green.

**The goal's label.**
- Its value sits on the trailing axis in Geist Mono Medium 11, `fgMuted`, one step brighter than the other axis labels in fgSubtle. It comes from a second `AxisMarks(position: .trailing, values: [goal])` with a custom `AxisValueLabel` and no grid line.
- The regular y ticks become explicit values from a new pure function, `WeightAxis.ticks`. It picks the smallest step of 0.5, 1, 2, 5, 10 or 20 that gives four or fewer ticks inside the domain, and shows one decimal only for 0.5.
- Any tick within 12 pt of the goal loses its label and its grid line. So the goal's label never overprints, and no grid line runs right next to the goal line.
- v1's faint grid lines stay. HIG Charts: people who can inspect points need fewer grid lines and light labels, but too few grid lines make values hard to estimate.

**Goal off the plot.**
- The label sits 8 pt inside the top or the bottom of the trailing axis.
- It shows SF Symbol `arrow.up` or `arrow.down` at 8 pt semibold, plus the value, both in fgMuted.
- Ticks within 12 pt of it lose their label.
- It is hidden from VoiceOver; the summary carries it.

**Points.**
- Drawn in `.chartOverlay { proxy in GeometryReader { geo in ... } }`.
- Each sits at `proxy.position(for: (x: noon of its day, y: its trend))`, offset by `geo[proxy.plotFrame!].origin` (`plotFrame` is iOS 17), with `.allowsHitTesting(false)`.
- The overlay avoids relying on view state inside `.symbol { }`, whose lifetime across range changes Apple does not document.

**Scrub.** New for the chart, with or without a goal.
- `chartXSelection(value:)` (iOS 17) on the whole plot, snapped to the nearest day that has a trend.
- At that day, a 1 pt `lineStrong` `RuleMark(x:)` and a popover from `.annotation(position: .top, spacing: 0, overflowResolution: .init(x: .fit(to: .chart), y: .disabled))`, as in WWDC23 session 10037.
- Popover style: `bgInset` fill, 1 pt `lineStrong` border, corner radius `theme.radius.card / 2`, padding 8 by 6.
- Popover lines:
  - the date ("3 Aug"), Geist 12, fgSubtle;
  - "Trend" in Geist 12, fgMuted, with its value in Geist Mono Medium 15, fg;
  - "Weigh-in" and its value in Geist Mono Medium 13, fgMuted, when there was one that day;
  - on a point's day, its fact in Geist 12, signalInk: "5% below where you started", "10% below where you started" or "Reached 87.0".
- Scrubbing adds detail only. The slot, the change line and the newest label carry what matters (HIG Charts: "don't require interaction to reveal critical information").
- If the selection gesture stops the page scrolling when a drag starts on the chart, start the selection with a long press through `chartGesture` (iOS 17) instead. Untested.

**Hierarchy.** The trend (signal, 2.5 pt) and the points are the only saturated marks. The goal line, the dots, the ticks and the grid recede (HIG Charts: the data most prominent).

#### The change line
One line under the range control. It replaces v1's three columns: Apple Stocks shows the change for the selected range above the chart, and HIG Charts says to summarise the main message.
- **Spans:** W reads "over 7 days", 30D "over 30 days", 90D "over 90 days" and Y "over the year". Each is the trend's change over that span, ending on the last weigh-in day (v1's `WeightTrend.change(days:)` with 7, 30, 90 and 365).
- **Since:** when the trend is shorter than the range, and always on All, it reads "since 4 Mar" ("since 4 Mar 2025" from another year), measured from the first trend day in view.
- **Format:** the signed number and its unit in Geist Mono Medium 15, fg, with U+2212 for down and "+" for up ("−1.2 kg"), then " over 30 days" in Geist 15, fgMuted. There is one neutral colour both ways, no arrow, and no word like lost or gained.
- **Edge cases:** a change that rounds to 0.0 reads "No change over 30 days". The line is hidden when fewer than two trend days are in view. It animates with numericText when the range changes.
- **VoiceOver:** "Down 1.2 kilograms over 30 days", "Up 0.5 kilograms since 4 March", "No change over 30 days".

#### Every new or changed string
- Menu: "Set Goal…", "Change Goal…", "Clear Goal" (U+2026 ellipsis).
- Goal sheet:
  - "Goal", "Start", "Height", "Set", "Save"
  - the footnotes and the too-low line quoted above
  - "Set 183 cm" and "Set 6 ft 0 in"
- Slot:
  - "smooths daily swings", "Goal 87.0"
  - "4.2 kg closer to 87.0", "1.1 kg to 87.0"
  - "Holding near 87.0", "0.9 kg from 87.0"
  - "Trend is now 5% below where you started.", "Trend is now 10% below where you started.", "Trend reached 87.0."
- Change line: "−1.2 kg over 7 days", "over 30 days", "over 90 days", "over the year", "since 4 Mar", "No change over 30 days", "No change since 4 Mar".
- Subtitle: "Last 88.35 kg · today, 07:42" (and the yesterday, weekday and date forms).
- Chart: "−5%", "−10%"; popover "Trend", "Weigh-in", "5% below where you started", "10% below where you started", "Reached 87.0".
- Toast: "Goal cleared" with UNDO.
- VoiceOver:
  - "Goal set, 87.0 kilograms."
  - "Goal cleared."
  - "4.2 kilograms closer to your goal, 87.0", "1.1 kilograms to your goal, 87.0", "Holding near your goal, 87.0", "0.9 kilograms from your goal, 87.0", "Goal, 87.0 kilograms"
  - a point: "5 percent below where you started", with the value "3 August, trend 92.9 kilograms"
  - "Trend reached your goal"
  - the moment announcements above
- Erase message, ProfileView: "This removes your stack, every logged dose, all your to-dos, your weigh-ins, your weight goal and your profile from this iPhone. It cannot be undone."

Copy rules for all of them: never lose, lost, loss, ideal, great, should, missed, behind or off track, and no "!". The new strings live in a new `WeightGoalCopy`, with its own test: the same em and en dash, "free" and "!" checks as v1, plus those words matched as whole words, because "closer" contains "lose". `WeightCopy` keeps v1's test, which bans "goal" in the core copy, so the word appears only in the goal's own menu items, sheet, "Goal 87.0" state and VoiceOver. "Goal" is Tom's word and plain English. v1's ban existed because v1 had no goal.

#### Storage and code (all inside `#if DEBUG || TAKEN_INTERNAL`; names from the branch's WIP commit 957d125)
**New file `Shared/WeightGoal.swift`.** All pure, and unit tested like DayMath.

Types:
- `struct WeightGoal: Codable, Hashable, Sendable { var kg: Double; var startDay: DayKey; var startPicked: Bool }`. `kg` and `startDay` are required; `startPicked` defaults to false. A goal that cannot be read decodes as none.
- `enum GoalDirection { case lower, higher, near }`.
- `struct WeightMoment: Identifiable, Hashable, Sendable`, with `enum Kind { case percent(Int), goal }`, `kind`, `day: DayKey`, `trendKg: Double` and the ids "pct5", "pct10" and "goal".
- `enum GoalReadout: Equatable { case goalOnly, closer(Double), toGo(Double), holding, from(Double) }`, in kilograms.

`enum WeightGoals`:
- Constants: `holdBandKg = 0.68`, `reachToleranceKg = 0.05`, `floorBMI = 18.5`, `percentPointsMinBMI = 25`, `percents = [5, 10]`.
- Functions:
  - `floorKg(heightCm:)`
  - `defaultStartDay(goalKg:trend:)`
  - `start(of:trend:)`, which applies the clamp
  - `direction(startKg:goalKg:)`
  - `floorBlocks(goalKg:startKg:heightCm:)`
  - `moments(goal:trend:weighInDays:heightCm:)`
  - `readout(goal:trend:moments:)`
  - `fresh(before:after:savedDay:)`, which returns the highest-ranked new point dated `savedDay`, or nil.

Also in this file:
- `enum WeightAxis`: `ticks(lower:upper:)`, and `clear(_:of:lower:upper:plotHeight:gap:)`, which drops ticks within 12 pt.
- `WeightWindow.make` gains `goalKg: Double?` and returns `goalInDomain`. The domain rule above lives there.
- `enum WeightChangeLine { static func make(range:trend:window:) -> (kg: Double, span: Span)? }`, with `Span` as `.days(Int)`, `.year` or `.since(DayKey)`.
- `enum WeightGoalCopy`.

**Edited files.**
- `WeightState` (`Shared/WeightData.swift`): add `goal: WeightGoal?` and `heightCm: Double?`, both decoded with `try?` so older files still read. `eraseAll()` clears both and keeps the tab setting, unit, offer answer and first weigh-in date, as v1. Also `WeightCopy.lastLine` takes the new subtitle format, and `WeightCopy.chartSummary` takes the selected range's change.
- `WeightModel`:
  - `var justReached: WeightMoment?`, in memory only;
  - `setGoal(_:heightCm:)`, `clearGoal() -> WeightGoal?`, `restoreGoal(_:)`;
  - a `moments(clock:)` helper.
- `AppModel`:
  - In the `WeightModel.swift` extension: `openWeightGoal()`, `saveWeightGoal(kg:startDay:startPicked:heightCm:)` and `clearWeightGoal()`. `saveWeighIn` computes the points before and after `weight.log`, sets `justReached` from `WeightGoals.fresh`, picks the haptic and posts the combined announcement. `undoWeight` handles `.restoreWeightGoal` and clears `justReached` on `.removeWeighIn`. `weightPicture(range:)` also returns the points, the domain and the change line.
  - In `AppModel.swift`: `SheetRoute.weightGoal` and `UndoStep.restoreWeightGoal`, inside the gate.
- `RootView` (`TodayView.swift`): `case .weightGoal: WeightGoalSheet()`.
- New file `Taken/Weight/WeightGoalSheet.swift`: `WeightGoalSheet` and `HeightWheelSheet`.
- `WeightTabRootView`:
  - the subtitle, the one-column card with the slot, and the change line;
  - the menu items;
  - `justReached` cleared on `.onDisappear` and when `scenePhase` leaves `.active`.
- `WeightChart`: the goal line, the axes, the overlay points, the scrub and accessibility. Update its header comment, which still says "No goal line ... milestones".
- `ProfileView`: the Erase message.
- `docs/privacy.html` section 03, in the 1.2 edit: weights.json also holds an optional weight goal and, with it, your height. The label stays Data Not Collected; on-device processing is not collection.

**Size.** About 900 to 1,300 lines with tests (own estimate).

#### Edge cases
- **No goal.** v1's page with the new subtitle, the change line and the scrub. No goal line, no points; the slot shows the caption.
- **No weigh-ins.**
  - "Set Goal…" is dimmed.
  - If every weigh-in is deleted while a goal exists: the empty card shows, "Change Goal…" is dimmed, "Clear Goal" still works, and the goal waits for the next weigh-in. Its start is then clamped to that day.
- **Very few weigh-ins.** "Goal 87.0" until the trend has moved 0.1 towards the goal. On a one-week window the goal is usually pinned to the edge.
- **Goal reached.** The holding states; the goal point stays; no label; no prompt.
- **Goal changed.** Points recompute silently and the start follows the rules above.
- **Gain goal.** The same slot wording and line. The only point is reaching it. The floor never blocks it.
- **Maintain (near) goal.** "Holding near 87.0" or "0.9 kg from 87.0" from the first day. No points.
- **Trend on the far side of the start.** "Goal 87.0", with no number in red and no words.
- **Unit switch.** Goals are stored in kilograms and heights in centimetres. Everything on screen converts, the ticks recompute in the unit, and the percent labels do not change.
- **Pro locked.** Goal actions stay open. There are no new points without logging. Everything already drawn stays.
- **Import.** Points appear silently. A long history is handled by the start rule.
- **Two crossings on one save.** Both points appear, and only the higher-ranked one springs and speaks.
- **Larger text.** The slot wraps to two lines and the card grows. The fit claim is for the default size.
- **Height edited in the sheet.** The floor and the BMI 25 check use the new height. Nothing is stored until Save.

#### Accessibility
- **Chart summary** (v1's "Weight chart." label): "Trend 88.1 kilograms. 1.1 kilograms to your goal, 87.0. Down 9.7 kilograms since 4 March. Marked: 5 percent below where you started, 3 August." The goal and marked clauses come from WeightGoalCopy and are appended in WeightChart, so WeightCopy's own test is untouched.
- **Elements:** each point and the goal line are elements with a label and value. The goal's axis label and the pinned label are hidden from VoiceOver (HIG Charts: "Hide visible text labels for axes and ticks from assistive technologies").
- **Headline card:** one element, for example "Trend 88.1 kilograms. 1.1 kilograms to your goal, 87.0."
- **Moments:** spoken as values, never as animation alone (HIG Charts: help people notice important changes). The Audio Graph comes from Swift Charts, as in v1.
- **Reduce Motion:** points fade in instead of springing.
- **Haptics:** Taken's switch applies.

#### Care rules this adds to "Designing for care"
1. The goal is a second opt-in, reachable only from the More menu. It is never prompted, never on the capture path and never in onboarding (Alliance 2026; Honary 2019).
2. No target date, pace, rate, ETA or forecast, ever. Nothing can be "behind".
3. A BMI 18.5 floor for lower and near goals, from a height asked only in the goal sheet. The message gives no number (Honary 2019; Lifesum; Beat).
4. "Goals are for adults." in the sheet (CDC; Beat).
5. Percent points only from a start at BMI 25 or more, only between the start and the goal, and only 5% and 10% (ACC/AHA 2013).
6. Points are information, not reward: a factual sentence, the haptic Taken already has, and a lit point. No praise words, no badges (Deci, Koestner and Ryan 1999; CNBC 2021).
7. Points count on the trend, on real weigh-in days. They are permanent, and they are never shown as pending (NICE TA875).
8. A gain away from the goal gets a number only (MacroFactor's listing: no warnings, red numbers or shaming).
9. A reached goal holds, and nothing ever suggests a lower one.
10. Clearing or changing a goal deletes nothing, asks nothing, and can be undone.
11. Goals and points never appear in App Store screenshots, What's New or marketing, and never next to a drug name. What's New keeps v1's line, because the goal is part of the new tab. Notes for Review gain one sentence: "An optional weight goal is in the Weight tab's More menu; it cannot be set below BMI 18.5, the sheet says goals are for adults, and nothing about it is prompted or sent."

#### What trend-only points cost (read before Tom's first test)
- v1's 0.9 trend lags about 9 to 10 days and sits about 0.4 kg above the scale at Tom's 0.3 kg a week (Chart and trend, above). So a point lands roughly one to two weeks after the scale first shows that number.
- On Tom's numbers today, 10% below 97.8 is 88.02 and the trend reads 88.1. So Taken shows one point (−5%), where MyNetDiary's chart already shows a "10.6% lost" star. The 10% point arrives when the trend gets there.
- This is deliberate: one dehydrated morning cannot light a point and then take it back. It is not a bug.
- If his side-by-side check moves the trend to v1's 7-day fallback (alpha 0.25, a lag of about 3 days), the points follow on their own.

#### CI, demo screens and tests
**Demo data.** `DemoData.goalWeighIns(now:)` uses the branch's SeededRandom pattern:
- The first weigh-in is exactly 97.8 kg, 231 days before the demo day.
- About six mornings in seven have a weigh-in, falling about 0.3 kg a week with a fixed swing of up to 0.45 kg.
- The last trend lies between 88.05 and 88.3.
- The goal is 87.0 and the height 180 cm (start BMI 30.2).
- A test pins the result: exactly one point (pct5), and the slot reads "to go" between 1.1 and 1.3.

**Screens.**

| Screen | What it shows |
|---|---|
| `weight-goal` | the default demo state above |
| `weight-goal-moment` | one more weigh-in on the demo day that takes the trend below 88.02, with `justReached` set to the 10% point |
| `weight-goal-reached` | six more weeks down to about 86.8: three points, "Holding near 87.0", no label |
| `weight-goal-sheet` | Change Goal…, with 87.0, the start and 180 cm |
| `weight-goal-low` | 55.0 typed, showing the too-low line |

**Shots** in scripts/screenshots.sh, after the branch's 60 to 69:
- 70-weight-goal, plus Blush, Phosphor and Ice
- 71-weight-goal-moment
- 72-weight-goal-reached
- 73-weight-goal-sheet, plus Blush
- 74-weight-goal-low
- on the 6.1 inch simulator, 75-weight-goal-6.1in, with the fit check

DemoProbe adds `goal=0|1` and `points=N` (points in view) to taken-ui-state.txt. Example: `lands 70-weight-goal "tab=weight sheet=none weight=1 goal=1 points=1"`. Every other weight screen checks `goal=0`.

**Fit probe.** `DemoProbe.recordWeightFit(chartBottom:visibleBottom:)` writes tmp/taken-weight-fit.txt (`chart=`, `visible=`, `fits=`). A new `weight_fits` in scripts/screenshots.sh, beside `paywall_fits`, fails CI on the 6.1 inch run when the chart card's bottom is below the top of the tab bar. The bottom is measured against the ScrollView's visible frame minus its bottom safe-area inset. The App Store build check needs no new marker: `WeightTabRootView` already proves the tab is absent.

**Tests**, in a new `TakenTests/WeightGoalTests.swift` plus `WeightTests.swift` updates:
1. Default start: the first weigh-in when the goal is outside the trend's range; the last weigh-in day when inside; clamping after deletes.
2. Direction: the edges of the 0.68 kg band.
3. Floor: 18.5 x h squared, feet and inches to centimetres; it blocks lower and near goals below the floor and never higher ones.
4. Points:
   - thresholds at S x 0.95 and S x 0.90, on weigh-in days only (a crossing inside a gap lands on the next weigh-in day);
   - still there after the trend rises;
   - only between the start and the goal, and not within 0.05 kg of it;
   - start BMI 24.9 gives only the goal point, 25.0 gives all three;
   - near goals give none, higher goals only the goal point;
   - the 0.05 kg reach tolerance.
5. Readout:
   - "Goal 87.0" while less than 0.1 is covered and on the far side of the start;
   - closer rounds down, to go rounds up, and the flip is at exactly half;
   - holding within 0.68 kg, from beyond it;
   - in kilograms and in pounds.
6. Fresh:
   - a crossing save returns its point;
   - a second weigh-in the same day returns none;
   - two at once return the higher rank;
   - a point dated before the saved day returns none;
   - UNDO then the same number returns it again.
7. Domain: the twice-the-span rule in both directions, and the pinned edge.
8. Axis: steps, four ticks or fewer, labels within 12 pt dropped.
9. Change line: over N days, since a date, hidden, no change, and the U+2212 and "+" signs.
10. Copy: WeightGoalCopy rules; WeightCopy still bans "goal"; the new lastLine format.
11. Storage: round trip; a lossy file; Erase clears the goal and the height and keeps the tab and the unit.
12. Clear then UNDO restores the same goal, start included.
13. Sheet logic: Change Goal… with the same value keeps the start; a new value recomputes it unless `startPicked`.
14. The demo screens show 1, 2 and 3 points.

#### Where this differs (one line each)
- From Tom's words:
  - Stars become a lit point on his own line plus one plain sentence, because a star reads as a rating or emoji and rewards undermine motivation.
  - The green dotted line becomes one solid quiet line with its number, because 1.1 removed dashed rules.
  - "Lost 5%" becomes "5% below where you started", because the copy never says lost.
  - Progress and weight changes become two single lines: the slot and the change line.
  - The zoom becomes no zoom: no expand, no full-screen chart, and a far goal never squashes the line.
- From the judged concept:
  - The start can be moved, as Happy Scale's start date allows; MyNetDiary's only way deletes weigh-ins.
  - Points use real weigh-in days only.
  - Percent points need a start at BMI 25 or more.
  - The floor message gives no number, and gain goals are exempt from the floor.
  - "Goals are for adults." is added.
  - Grid lines stay, and the goal line is fgFaint.
  - No band is drawn when holding.
  - Points are drawn in the overlay.
  - The haptics are graded.
  - The moment lands in the slot, not the toast.

#### Own choices (no source found)
- The start exception (goal inside the trend's range) and the clamp.
- Inferring direction instead of asking.
- The 0.05 kg reach tolerance, and rounding down for closer and up for to go.
- The flip exactly at half.
- Only real weigh-in days for points.
- The 0.35 s and 0.5 s delays.
- Ranking the goal above 10% above 5%.
- One label on the newest point in view.
- The fgFaint line and the fgMuted label; the 12 pt clearance; the twice-the-span domain rule; the 196 pt plot.
- The bgInset popover.
- The height wheel ranges and the 170 cm start; the floor not blocking gain goals.
- No age question.
- Goal actions open while locked.
- "Goal" as the word.
- The subtitle carrying the last value.
- The fit estimate and the size estimate.

#### Sources
- Behaviour and motivation:
  - https://pmc.ncbi.nlm.nih.gov/articles/PMC5370453/ (Samdal et al. 2017)
  - https://business.columbia.edu/faculty/research/goal-gradient-hypothesis-resurrected-purchase-acceleration-illusionary-goal (Kivetz, Urminsky and Zheng 2006)
  - https://ideas.repec.org/a/oup/jconrs/doi10.1086-663827.html (Koo and Fishbach 2012)
  - https://www.kellogg.northwestern.edu/faculty/research/detail/2011/stuck-in-the-middle-the-psychophysics-of-goal-pursuit (Bonezzi et al. 2011)
  - https://leeds-faculty.colorado.edu/dahe7472/deci%201999.pdf (Deci, Koestner and Ryan 1999)
- Clinical thresholds:
  - https://www.acc.org/About-ACC/Press-Releases/2013/11/12/15/20/111213ACC_AHA_Obesity_Guideline (ACC/AHA 2013, adults with overweight or obesity, 5 to 10%)
  - https://www.cdc.gov/healthy-weight-growth/losing-weight/index.html
  - https://pubmed.ncbi.nlm.nih.gov/33567185/ (STEP 1)
  - https://www.wypartnership.co.uk/application/private_files/6216/8621/1661/NICE-TA875-Semaglutide-for-obesity-briefing-for-integrated-care-systems.pdf (NICE TA875)
  - https://discovery.ucl.ac.uk/id/eprint/10149199/1/Diabetes%20Obesity%20Metabolism%20-%202022%20-%20Wilding%20-%20Weight%20regain%20and%20cardiometabolic%20effects%20after%20withdrawal%20of%20semaglutide.pdf (Wilding et al. 2022)
- Care:
  - https://mhealth.jmir.org/2019/6/e14239 and https://pmc.ncbi.nlm.nih.gov/articles/PMC6604512/ (Honary et al. 2019)
  - https://www.allianceforeatingdisorders.com/health-tracking-apps-and-disordered-eating/
  - https://beateatingdisorders.org.uk/news/beat-campaigners-celebrate-improvement-in-nhs-app
  - https://help.lifesum.com/de/article/i-am-unable-to-enter-my-weight-when-creating-my-account-why-1c8068
  - https://www.cdc.gov/bmi/child-teen-calculator/bmi-categories.html
  - https://www.frontiersin.org/journals/computer-science/articles/10.3389/fcomp.2023.1215588/full
  - https://pmc.ncbi.nlm.nih.gov/articles/PMC8643308 (Hahn et al. 2021)
  - https://pmc.ncbi.nlm.nih.gov/articles/PMC4157390/ (Steinberg et al. 2014)
- Apps:
  - https://help.macrofactorapp.com/en/articles/22-get-to-know-your-dashboard
  - https://macrofactor.com/goal-features/
  - https://apps.apple.com/us/app/-/id1553503471
  - https://www.iphonejd.com/?p=5491 (Happy Scale)
  - https://www.runsforcookies.com/2021/12/happy-scale-app-giveaway-premium.html (Happy Scale start date)
  - https://www.mynetdiary.com/ipad_help_plan.html (first weigh-in as start; Start Over)
  - https://www.cnbc.com/2021/03/31/robinhood-gets-rid-of-confetti-feature-amid-scrutiny-over-gamification.html
  - https://leancrew.com/all-this/2025/04/plotting-a-plunge/
  - https://support.apple.com/en-nz/guide/stocks/stc4cfc704df/8.0/mac/27
- Apple design guidance:
  - https://developer.apple.com/design/human-interface-guidelines/charts
  - https://developer.apple.com/design/human-interface-guidelines/charting-data
  - https://developer.apple.com/design/human-interface-guidelines/playing-haptics
  - https://developer.apple.com/design/human-interface-guidelines/feedback
  - https://developer.apple.com/design/human-interface-guidelines/menus
  - https://developer.apple.com/design/human-interface-guidelines/pull-down-buttons
  - https://developer.apple.com/design/human-interface-guidelines/alerts
  - https://developer.apple.com/videos/play/wwdc2022/110342/
  - https://developer.apple.com/videos/play/wwdc2023/10037/
- Apple API documentation:
  - https://developer.apple.com/documentation/charts/rulemark
  - https://developer.apple.com/documentation/charts/axismarks
  - https://developer.apple.com/documentation/charts/chartproxy
  - https://developer.apple.com/documentation/charts/annotationoverflowresolution
  - https://developer.apple.com/documentation/swiftui/view/chartxselection(value:)
  - https://developer.apple.com/documentation/swiftui/view/chartplotstyle(content:)
  - https://developer.apple.com/documentation/swiftui/view/chartyscale(domain:type:)
  - https://developer.apple.com/documentation/foundation/unitlength/init(forlocale:usage:)
- Repo:
  - origin/main 164a893: REDESIGN.md (lines 4, 19, 22); Shared/Theme.swift; Taken/Views/ProgressSummary.swift; Taken/Views/ItemRow.swift (line 205); Taken/Pro/PaywallView.swift (timelineDot); Taken/Views/Components.swift (TimeWheelSheet, MonoTimeButton); Taken/AppModel.swift (Haptics)
  - the feat/weight-tab WIP commit 957d125, read only
  - CI run 39680393222 screenshots
  - Tom's MyNetDiary screenshots 1.webp to 7.webp

### Weight tab page: entry first, 2026-10-22 (replaces the page layout in v1 and in "Goal and moments"; built on feat/weight-tab)

Tom saw the page as built (CI shots 60-weight and 61-weight-log) and found it overwhelming. What he pictured was "a big number in the middle of the screen", or "nothing, maybe a flashing cursor". A tap brings up the keyboard, he types the number, taps "Weigh in", and the small "Last weigh-in" line he likes is there, "and that would be it". The graph stays out of sight until he scrolls or uses a toggle. Two concepts were drawn up and judged. This section is the result.

#### Verdict
"The Number" wins, with grafts from "Weigh-in, lit".
- It is the closest reading of Tom's words: one big number, a cursor, the small "Last weigh-in" line, and nothing else until he scrolls.
- It keeps amber for the moments the addendum defines (5%, 10%, the goal), so a weigh-in on its own is never rewarded.
- It builds on the branch. The sheet's field becomes the page, and the model, the Goal sheet, the chart, the lit points and the trend content are reused as they are.

Grafted from "Weigh-in, lit":
- VoiceOver's escape gesture closes the keypad without saving. The decimal pad has no key for that.
- Closing the keypad without saving throws the typed number away, because an unsaved number must never look saved. "The Number" kept it.
- The range hint waits until the number looks finished, so "8" on the way to "88" never shows a warning.
- Screen two exists from the first weigh-in, with "Your trend starts here." under its single dot.
- There is no plausibility check against the last weigh-in. Undo fixes typos.

Not taken from "Weigh-in, lit":
- A lit check and "Weighed in" on every save. In Taken, lit means done and earned: All taken, and the goal's points. Lighting every weigh-in would reward the act of weighing itself. v1's care section and the addendum's rule ("Points are information, not reward") keep that out, and HIG Feedback asks to match feedback to how much the event matters.
- The large title, a subtitle carrying the value, and the goal distance on the resting screen. Together they put 4 numbers and 3 lines of text where Tom asked for "that would be it". Instead, the goal distance shows right after each weigh-in (section 4) and always one scroll down.
- An empty field with no number. Tom's first picture was a big number. The grey last weigh-in gives him one and still reads as a field waiting for today.

Changed in "The Number" after checking it against Apple's docs and the repo:
- No containerRelativeFrame. Apple's doc says its size is the container's "subtracting any safe area insets". The keypad, the Weigh in bar and the Undo toast all change the safe area, so the number would jump each time. Instead the page height is measured once, with the keyboard ignored and outside the bottom inset, and frozen while typing.
- No .viewAligned snapping. With large text, screen two can be taller than the phone, and view-aligned snapping would make its middle hard to reach. A small custom ScrollTargetBehavior snaps only between the number and the trend and leaves everything below free.
- The grey number uses fgSubtle, not fgFaint. Computed from Theme.swift with the WCAG formula, fgFaint on the canvas is 2.58:1 (Signal) to 2.71:1 (Phosphor), under the 3:1 that large text needs. fgSubtle is 4.81:1 to 5.19:1. The chevron uses fgSubtle too, because a control needs 3:1.
- The drawn caret also honours iOS 18's Prefer Non-Blinking Cursor setting. Apple says it "is relevant for apps that draw custom insertion indicators".
- The digits are Geist Mono Regular, not Medium, with the decimal point pulled in (own calls, section 2).
- The long-press items are "Edit…" and "Delete" (own call).

#### What stays, and what this replaces
Everything in v1 and the addendum that is not page layout stays as written:
- data and storage: weights.json and WeighIn, the trend maths, ranges, units and bounds
- WeightGate and the paywall rules
- Profile's switch and the Today offer
- the More menu: Kilograms, Pounds, Set Goal…, Change Goal…, Clear Goal, Hide Weight Tab
- the goal: the Goal sheet, height, the floor, the start and direction rules
- the lit points and how the chart draws them, and the slot copy
- the change line, and the chart itself: the 196 pt plot, the goal line, the axes, the scrub and its accessibility
- care rules, store and privacy

This section replaces:
- In v1: the "Layout, top to bottom" and "Empty state" bullets, and the demo screen list.
- In v1's "Logging a weigh-in": the sheet parts only (SheetRoute.weighIn, the detent, the auto-focused field, "Now", Save). Its parse, bounds, never-saved placeholder, no-choices and WeighIn rules stay.
- In the addendum: "The page, top to bottom" and "Fit"; where the moment shows (the slot, the toast copy, the chart point's spring); and the "Screens" table.

#### 1. The page at a glance
The page is one ScrollView with two screens:
- Screen one opens first. It holds More and the avatar top right, one big number in the middle with its unit, one small line under it, and a small chevron at the bottom.
- Screen two is one scroll down, or one tap on the chevron. It holds the trend, how close it is to the goal, the chart card, and All weigh-ins.

The mockups below are at iPhone width. A | right before a number is the amber caret, ~ marks grey digits, and * is the lit dot.

A. How it opens, not yet weighed in today:
```
+----------------------------------------+
| 9:41                                   |
|                             (...)  (AM)|
|                                        |
|                                        |
|                                        |
|                                        |
|           |~88.35~  kg                 |
|                                        |
|     Last weigh-in yesterday, 07:42     |
|                                        |
|                                        |
|                                        |
|                                        |
|                                        |
|                   v                    |
| ( Today   To-do   History   [Weight] ) |
+----------------------------------------+
```
B. Typing, with the keypad up and "88.1" typed. The number has not moved.
```
+----------------------------------------+
|                             (...)  (AM)|
|                                        |
|                                        |
|                                        |
|           88.1|      kg                |
|                                        |
|     Last weigh-in yesterday, 07:42     |
|                                        |
| [              Weigh in              ] |
|----------------------------------------|
|      1      |      2      |      3     |
|      4      |      5      |      6     |
|      7      |      8      |      9     |
|      .      |      0      |     <x     |
+----------------------------------------+
```
C. Just saved, and this weigh-in reached the goal:
```
+----------------------------------------+
|                             (...)  (AM)|
|                                        |
|                                        |
|                                        |
|              88.1  kg                  |
|                                        |
|          * Trend reached 87.0.         |
|                                        |
|                                        |
|                                        |
| +------------------------------------+ |
| | Weighed in                    Undo | |
| +------------------------------------+ |
| ( Today   To-do   History   [Weight] ) |
+----------------------------------------+
```
With no crossing and a goal set, the line reads "Trend 1.1 kg to 87.0". With no goal, it reads "Last weigh-in today, 07:42".

D. Screen two, snapped into place:
```
+----------------------------------------+
| 9:41                                   |
|  Trend                                 |
|  88.1 kg                               |
|  1.1 kg to 87.0                        |
| +------------------------------------+ |
| | [ W | 30D | 90D | Y | All ]        | |
| | -9.7 kg since 4 Mar                | |
| |  dots, amber trend, goal line      | |
| |  87.0, lit points, one -5% label   | |
| | Ticks: weekly doses                | |
| +------------------------------------+ |
| +------------------------------------+ |
| | All weigh-ins                151 > | |
| +------------------------------------+ |
| ( Today   To-do   History   [Weight] ) |
+----------------------------------------+
```
In the app, the change line and the label use the U+2212 minus, as in the addendum.

Counts on screen one, on first open, not weighed in today, with a goal set:
- 2 numbers: 88.35 and 07:42.
- 4 controls: the number, More, the avatar and the chevron.
- Also visible: the caret and the unit.

For comparison, the page Tom saw had about 15 numbers and 9 controls above the tab bar.

#### 2. Screen one: elements, order, sizes, tokens
Sizes are in points. Fonts use the app's helpers (Font.sans, Font.mono, Font.monoFixed). Side margins are 20, and the canvas is theme.bg.

1. **Top bar.**
   - Nothing visible on the left.
   - On the right, WeightMoreMenu (unchanged: ellipsis.circle 22, fgMuted, 44 x 44) then ProfileButton, in an HStack with spacing 12. The menu has trailing padding -8.
   - Both sit 10 below the top of the scroll content. That is exactly where TabHeader puts them on the other tabs (its HStack's top padding 8 plus the controls' top padding 2), so the corner never jumps when switching tabs.
   - At the leading edge sits an invisible 1 x 1 accessibility element with the label "Weight" and the isHeader trait.
2. **Space above the block:** two equal Spacers, the first with minLength 16.
3. **The figure block.** It is full width, at least 160 tall, with 20 padding above and below, and is one tap target (contentShape Rectangle).
   - **The figure line**, centred: HStack(alignment: .firstTextBaseline, spacing: 8) { lock, only when locked; digits box; unit }.
   - **Digits.**
     - Font.monoFixed(72, .mono): Geist Mono Regular at a fixed size, with lineLimit 1 and fixedSize.
     - Each cell is 43.2 wide, because Geist Mono's advance is 600 of 1000 units (measured from Taken/Fonts/GeistMono-Regular.ttf).
     - The decimal separator is pulled in with kerning -11 on the last whole digit and on the separator. Otherwise the point's 8.9 pt of ink leaves about 21 pt of air on each side.
     - One function, figureText(_:), draws every string in the box (grey, typed, saved and sizing), so widths always match.
   - **Digits box.** A ZStack(alignment: .leading) of three layers:
     - (a) figureText(sizing).hidden(), where sizing is the longer of the grey value and the draft;
     - (b) figureText(shown) in its colour;
     - (c) HStack(spacing: 0) { figureText(draftWhileTyping).hidden(); caret }.

     The box keeps the grey number's width while typing, so nothing re-centres. The caret sits right after the typed digits, or at the leading edge before anything is typed. Use the content transition numericText for changes made while not typing (save, Undo) and identity while typing.
   - **Caret.**
     - A Capsule, 3 wide and 59 tall, in theme.signal, offset x -1.5 so its centre sits on the box edge.
     - Vertically centred in the box. Geist Mono's line box (ascent 1005, descent 295) is centred on its cap height, so a centred 59 pt caret runs from 4 below the baseline to 4 above the 51.1 pt cap height. No alignment guide is needed.
   - **Lock**, only when model.weightAccess == .locked, and instead of the caret: lock.fill, 17 semibold, theme.signalInk, 6 before the digits box, centred the same way.
   - **Unit.**
     - "kg" or "lb" in Font.sans(22, .sansMedium, relativeTo: .title2), capped at .accessibility1 (the cap applies to the unit only).
     - fgSubtle beside grey or absent digits, fgMuted beside typed or saved digits.
     - Hidden from VoiceOver.
   - **Widest case.** Seven characters ("1000.55" can be typed, though it is out of range) take 280 + 3 + 8 + 27 = 318. That is inside the 335 that a 375 wide iPhone leaves, so nothing ever scales or truncates.
   - **Gap:** 12.
   - **The small line.** Centred, full width, lineLimit 3. Section 4 gives its words, font and colour. At the default size every version fits one line on a 375 wide iPhone: the longest, the 10% sentence with its dot, measures 316; "Last weigh-in Wednesday, 07:42" measures 228.
   - **The real TextField** lies over the figure line as an overlay. It is invisible and not hit-testable (section 5).
4. **Space below the block:** three equal Spacers, the first with minLength 16. Two above and three below put the block's centre 40% of the way down the free space, the optical centre (own call).
5. **Chevron row.**
   - A Button, 44 x 44: chevron.down, 12 semibold, fgSubtle, centred, 8 above the bottom of screen one (the top of the tab bar).
   - It is always laid out. When there is no screen two, or while typing, it has opacity 0, is hidden from VoiceOver and is not hit-testable, so the block never moves when it comes or goes.

Screen one is at least pageHeight tall: the space between the status bar and the top of the tab bar, measured with the keyboard ignored (section 13). It grows when large text needs more room. Show the content only once pageHeight > 0, so there is no first-frame jump.

Estimated positions on an iPhone 16 (393 x 852) at the default text size, for CI to confirm:
- buttons from 69 to 113
- block centre about 376
- small line ends about 436
- chevron centre about 740
- tab bar from about 771

With the keypad up, the Weigh in button's top is about 486, so the block stays where it is.

#### 3. What the big number shows
| Situation | Digits | Colour | Caret |
|---|---|---|---|
| Never weighed in | none | unit in fgSubtle | before the unit, pulsing |
| Last weigh-in on an earlier day, not typing | the last weigh-in, WeightFormat.value ("88.35", "88,35" in de_DE, "194.8" in lb) | fgSubtle | pulses 3 times, then steady |
| Last weigh-in today, not typing | today's latest weigh-in | fg | none |
| Typing, nothing typed yet | the last weigh-in, today's included | fgSubtle | blinking at the leading edge |
| Typing | the draft, as typed | fg | blinking after the last digit, solid while keys are pressed |
| Locked | as the first three rows; never typing | as above | the lock instead |

The big number always shows a weigh-in, never the trend: a smoothed 89.0 where 89.3 was just typed would read as a bug. The grey number can never be saved, because Weigh in stays dimmed while the draft is empty.

#### 4. What the small line says
These rules are checked in order, and the first that applies wins.

1. **Typing, and the draft looks finished but parses outside the unit's bounds.**
   - Copy: "Between 20 and 350 kg" or "Between 44 and 770 lb".
   - Style: Font.sans(15, .sans, relativeTo: .subheadline), fgSubtle, never red.
   - "Looks finished" (own rule) means the draft contains a decimal separator followed by a digit, or has 3 or more whole digits. So "19" shows nothing, while "19.5" and "883" show the hint.
2. **Not typing, and a weigh-in saved on this visit lit a point (weight.justReached).**
   - It shows the lit dot and the addendum's moment sentence: "Trend is now 5% below where you started.", "Trend is now 10% below where you started." or "Trend reached 87.0.".
   - Words are in Font.sans(15, .sansMedium, relativeTo: .subheadline) and the number in Font.mono(15, .monoMedium, relativeTo: .subheadline), all in theme.signalInk.
   - The dot is WeightLitPoint(springs:, bead: false): 8 pt in theme.signal with glow(0.35) at radius 4. It sits 8 before the text, with its centre 5 above the first line's baseline (set with an alignment guide).
   - It springs only the first time it appears in a visit. Track this with weight.momentPlayed, which endVisit resets.
3. **Not typing, a weigh-in was saved on this visit (weight.justSaved), a goal is set, and the readout is not goalOnly.**
   - It shows the closing-in line with "Trend" in front, so it never reads as arithmetic on the big number.
   - Numbers, with their unit, are in Font.mono(15, .monoMedium, relativeTo: .subheadline), fg. Words are in Font.sans(15, .sans, relativeTo: .subheadline), fgMuted.

   | Readout | Line |
   |---|---|
   | closer | "Trend 4.2 kg closer to 87.0" |
   | to go | "Trend 1.1 kg to 87.0" |
   | holding | "Trend holding near 87.0" |
   | from | "Trend 0.9 kg from 87.0" |
   | goal only | none; rule 4 applies |
4. **Otherwise: WeightCopy.lastLine, back to v1's form.**
   - Copy: "Last weigh-in today, 07:42", "Last weigh-in yesterday, 07:42", "Last weigh-in Tuesday, 07:42", "Last weigh-in 14 Oct, 07:42", "Last weigh-in 3 Mar 2025, 07:42", or "No weigh-ins yet".
   - Style: Font.sans(15, .sans, relativeTo: .subheadline), fgSubtle, with the time in the same font, as Tom saw it.
   - It never counts missed days.

The lines from rules 2 and 3 last one visit. This is the addendum's rule, moved here from the slot. The visit ends when the tab disappears, when the app leaves the foreground, when Undo is tapped, or when the next weigh-in is saved. While typing, rule 1 or rule 4 shows, and the visit's line comes back if the keypad closes without a save. Changes crossfade over 0.2 s.

#### 5. Entering a weigh-in
- **Nothing takes focus on appear.** There is no defaultFocus and no focus in onAppear, for three reasons:
  - HIG Focus and selection says "Avoid changing focus without people's interaction".
  - An automatic keypad would cover the tab bar on every visit.
  - Tom described tapping to bring it up.
- **The tap.** A tap anywhere on the block calls model.requireWeightPro { focused = true }:
  - With Pro, for the first weigh-in, or with a purchase pending, the keypad comes up at once.
  - When locked, the paywall opens instead. The keypad comes up after a purchase, because requireWeightPro runs the action once Pro is on.
  - While Pro is still being checked, it waits for the check (existing behaviour).
- **The field.**
  - The field is TextField("", text: $weight.draft) with:
    - .keyboardType(.decimalPad), which shows the locale's separator (88,35 in de_DE)
    - .focused($focused)
    - .onSubmit(save), for a hardware keyboard
    - .autocorrectionDisabled()
    - .foregroundStyle(.clear) and .tint(.clear): no system caret, because the drawn one stands in
    - .allowsHitTesting(false)
    - placed over the figure line as an overlay
  - The field is clear rather than at opacity 0, so VoiceOver still finds it.
  - Fallback, if CI shows that focus does not take on a field that is not hit-testable (the probe reads focus=0 on weight-entry): let the field take touches itself (remove allowsHitTesting(false) and the block's tap gesture), put a clear Button over it only when locked, and drop the long-press menu. Edit and Delete stay in All weigh-ins and as VoiceOver actions.
- **The keypad** is the system decimal pad (HIG Virtual keyboards: use the keyboard type that suits the content). The number does not move.
  - On small phones or with large text, the small line's bottom may come within 16 of the Weigh in button.
  - In that case, 0.35 s after focus the page scrolls up just enough: ScrollViewReader scrollTo(WeightAnchor.block, anchor: .bottom), with .snappy at 0.25 s.
- **The Weigh in bar.**
  - It is PrimaryButton(title: "Weigh in", enabled: kg != nil): full width, side margins 20, 8 above, 12 below.
  - It lives in the ScrollView's bottom safeAreaInset and shows only while focused, with an opacity transition.
  - The keyboard is a safe-area region (SafeAreaRegions.keyboard), so the bar rides on top of it. The decimal pad has no Return key, so the button is required.
  - "Weigh in" is Tom's word. There is no Cancel.
- **Typing.**
  - Run WeightFormat.sanitize(maxDecimals: unit.decimals) on every change. That allows 2 decimals in kg and 1 in lb, and at most 4 whole digits, as now.
  - The grey number goes at the first character and comes back if everything is deleted.
  - Weigh in stays dimmed until WeightFormat.kilograms(draft, unit:, locale:) returns a value: 20 to 350 kg, or 44 to 770 lb.
- **Save**, from Weigh in or Return:
  1. Read kg, set focused = false, then call model.saveWeighIn(kg:).
  2. The keypad and the bar go down. The digits stay where they are, as today's number in fg.
  3. The small line changes (section 4).
  4. The soft haptic plays, or Haptics.success 0.35 s later for the goal (existing code).
  5. The toast reads "Weighed in" with Undo.
  6. 0.5 s later VoiceOver hears "Weighed in, 88.35 kilograms." plus the moment, if any (existing).
- **Leaving without saving.** Any of these ends typing:
  - a tap anywhere on screen one outside the block
  - any scroll (.scrollDismissesKeyboard(.immediately))
  - VoiceOver's escape gesture (.accessibilityAction(.escape))
  - switching apps

  Whenever focus ends, the draft is cleared.
- **Nothing else is on the capture path:** no date, time, note, unit, goal, sheet, Cancel or plausibility check. A wrong number is fixed with Undo or in All weigh-ins, as in v1.

#### 6. Every state
1. **Never weighed in** (the tab was just turned on).
   - The caret and "kg" sit at the centre, with the caret pulsing. The line reads "No weigh-ins yet".
   - There is no chevron and no screen two, and the page does not scroll (scrollBounceBehavior(.basedOnSize)). Set Goal… is dimmed (addendum).
   - The first save leads to state 4. Screen two appears with one dot and "Your trend starts here.", and the chevron fades in.
2. **Not weighed in today** (the usual morning). The grey last weigh-in shows with the caret pulsing 3 times, then steady. The line reads "Last weigh-in yesterday, 07:42", and the chevron shows.
3. **Typing.** As in section 5: the number stays still and the caret blinks. The line shows "Last weigh-in …" or the range hint. Weigh in sits above the keypad, and the chevron and the toast are hidden.
4. **Just saved, no crossing.**
   - Today's number shows in fg, with no caret.
   - The line reads "Trend 1.1 kg to 87.0" with a goal, or "Last weigh-in today, 07:42" without one.
   - The "Weighed in" toast with Undo sits above the tab bar and covers the chevron for its 4 seconds.
5. **A point just crossed.** This happens only from a save here, dated today, that creates a new point (WeightGoals.fresh, unchanged).
   - The line crossfades to the dot and the sentence at the save. The dot springs 0.35 s later, once the keypad is down, with the All taken spring: response 0.38, damping 0.55, scale 0.55 to 1, glow 0.7 at radius 8 easing to 0.35 at radius 4. Under Reduce Motion it fades in (easeOut 0.18).
   - The goal plays Haptics.success instead of the soft haptic. 5% and 10% keep the soft haptic.
   - On screen two the point is already drawn lit, with no animation.
   - Undo removes the weigh-in, the point and the sentence. Saving the same number again lights it again.
   - Never confetti, stars, praise or a sheet.
6. **Already weighed in today** (a later visit).
   - Today's latest weigh-in shows in fg, with no caret. The line reads "Last weigh-in today, 07:06", and the chevron shows.
   - A tap logs another weigh-in: the field focuses empty with today's number as the grey hint, and Weigh in saves a second weigh-in. The trend keeps the day's lowest (v1).
   - A long press opens "Edit…" and "Delete" (section 8).
7. **Goal set or not.** Screen one is the same either way, apart from rule 3's line after a save. With a goal, screen two shows the addendum's slot, goal line and points.
8. **Pro locked after the first weigh-in.**
   - The lock replaces the caret. The number and the line are as in state 2 or 6.
   - A tap opens the paywall, never the keypad. In the long-press menu, Edit… opens the paywall (editing is gated, as in v1) and Delete stays open.
   - Screen two, the chart, All weigh-ins, the CSV and the goal actions stay open: "we never hold someone's record hostage". The tab is never hidden.
9. **Pounds.** The same page in lb: a grey "194.8", the unit "lb", one decimal, bounds 44 to 770, the hint "Between 44 and 770 lb", and the line "Trend 2.4 lb to 191.8". The percent sentences do not change, and there are no stones (v1).
10. **Dynamic Type:** section 11. **VoiceOver:** section 12.
11. **After Undo** of today's only weigh-in: back to state 2 (or state 1), with the caret pulsing again.
12. **After Erase all data while locked:** no number, the lock, "No weigh-ins yet", and a tap opens the paywall. firstWeighInAt survives Erase (v1).

#### 7. Screen two: where the graph lives
- **How to get there.** Scroll down, or tap the chevron, which calls withAnimation(.snappy(duration: 0.35)) { proxy.scrollTo(WeightAnchor.trend, anchor: .top) }. The scroll is not animated under Reduce Motion, and VoiceOver reads the chevron as "Show trend". Scrolling was chosen over a toggle because a toggle would add a control to screen one, and a scroll costs nothing.
- **Snapping.** WeightFoldSnap (section 13): a scroll that would stop between the number and the top of the trend lands on whichever is nearer to the system's projected stop, so a flick goes all the way. Below the fold, scrolling is free. Snapping is off while typing.
- **Height.** Screen two is at least pageHeight tall, so its top can rest at the top of the screen. Any extra room stays empty canvas.
- **Contents, top to bottom** (top padding 20, bottom padding 28):
  1. "Trend", in Font.sans(14, .sansMedium, relativeTo: .footnote), fgSubtle.
  2. 2 below: the trend value in Font.mono(34, .monoMedium, relativeTo: .largeTitle), fg, with numericText, lineLimit 1 and minimumScaleFactor 0.7. Then, 6 to the right, the unit in Font.sans(18, .sansMedium, relativeTo: .title3), fgMuted.
  3. 2 below: the addendum's slot, with lineLimit 2. Without a goal it reads "smooths daily swings" in fgSubtle; with a goal, the closing-in line ("1.1 kg to 87.0"). It no longer shows the moment sentence, which now lives on screen one.

     Items 1 to 3 form one VoiceOver element with the isHeader trait: "Trend 88.1 kilograms. 1.1 kilograms to your goal, 87.0." This is the branch's headlineSpoken without the moment.
  4. 16 below: the chart Card (padding 16, VStack spacing 14), as on the branch:
     - WeightRangePicker: W, 30D, 90D, Y, All; default All; the choice is remembered.
     - The change line.
     - WeightChart: the 196 plot, dots, the amber monotone trend at 2.5, weekly dose ticks, the goal RuleMark, at most three lit points, at most one percent label, and the scrub popover.
     - "Ticks: weekly doses", when there are ticks.
     - With only one weigh-in day: no range picker and no change line, just the single dot, then "Your trend starts here." in Font.sans(15, .sans, relativeTo: .subheadline), fgSubtle.
  5. 16 below: the All weigh-ins row, unchanged.
- **What screen two does not have:** a card around items 1 to 3, a Log weigh-in button, an expand control, or a second chart.
- **Fit.** About 600 tall, which fits between the status bar and the tab bar on the 6.1 inch iPhone at the default size. CI's weight_fits checks the chart card on the scrolled screen.

#### 8. Goal distance, moments, editing
- **Goal distance.**
  - On screen two it is always in the slot under the trend (the addendum's copy).
  - On screen one it appears only during the visit after a save, as "Trend 1.1 kg to 87.0" (section 4, rule 3). Every morning's weigh-in ends with how close he is, and the resting screen stays one number and one line.
- **The moment sentence.** On screen one, in the small line, with the lit dot, for one visit (rule 2). It is not in the slot and not in the toast.
- **The goal itself** is still set only from the More menu. Nothing about it shows while typing.
- **Editing.**
  - Right after a save, use Undo in the toast. It shows for 4 s, and with VoiceOver it stays until dismissed (existing).
  - Later, use All weigh-ins on screen two: tap a row to edit it, or swipe to delete (v1).
- **The long-press shortcut** applies on today's number only (state 6, not typing). It opens a context menu with "Edit…" and "Delete" (role destructive).
  - **Edit…** calls model.editWeighIn(id). That runs requireWeightPro, then sets weight.editOnOpen = id and sheet = .weighIns. On appear, WeighInList sets path = [id] in a transaction with animations disabled, so the editor is already open and Back leads to the list.
  - **Delete** calls model.deleteWeighIn(id), with the existing toast "Weigh-in deleted 89.3 kg" and Undo.
  - In every other state the menu's content is empty, so no menu appears.
  - Put .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous)) on the figure line.
- **Logging another** is a tap (state 6). There is no edit-or-add question on the capture path.

#### 9. Pro locked
See state 8.

#### 10. Pounds
See state 9.

#### 11. Dynamic Type
- The digits are fixed at 72, already a display size, and never scale.
- The unit scales up to .accessibility1.
- The small line scales and wraps to 3 lines. The Weigh in button scales (minimum height 54). The chevron is fixed.
- Screen one grows past pageHeight when its content needs it, and the fold moves with it.
- With the keypad up, the 16 pt rule in section 5 keeps the line clear of the button. CI proves this at AX3 on the 6.1 inch iPhone.
- Screen two follows the addendum: the slot wraps to 2 lines, the card grows, and scrolling below the fold is free.

#### 12. VoiceOver and other accessibility
- **Order:**
  1. "Weight", as a heading
  2. More
  3. Profile
  4. the field
  5. the small line
  6. Weigh in, while typing
  7. Show trend
  8. screen two: the trend element (a heading), the range picker, the change line, the chart (the addendum's summary, elements and Audio Graph), the ticks caption, and All weigh-ins
- **The field.** The drawn digits, caret, lock and unit are hidden from VoiceOver.

  | State | Label | Value | Hint | Actions |
  |---|---|---|---|---|
  | Not weighed in today, unlocked | "Today's weight in kilograms" | the draft | "Double-tap to type today's weight." | escape while typing |
  | Weighed in today, unlocked | "Today's weigh-in" | "89.3 kilograms" when not typing; the draft while typing | "Double-tap to log another weigh-in." | "Edit weigh-in" and "Delete weigh-in" when not typing; escape while typing |
  | Locked | as above | as above | "Logging needs Taken Pro. Opens Taken Pro." | "Delete weigh-in" when today has one |
- **The small line** speaks the number the grey digits show:
  - "Last weigh-in 88.35 kilograms, yesterday at 07:42"
  - on a day already weighed in: "Last weigh-in today at 07:06"
  - after a save: "Trend 1.1 kilograms to your goal, 87.0"
  - the moment: WeightGoalCopy.spokenMoment
  - the hint: "Between 20 and 350 kilograms"
- **Announcements:**
  - after a save (existing)
  - the range hint, once per typing session, when it first appears
  - Goal set and Goal cleared (existing)
- **Weigh in** reads "Weigh in, button", dimmed until the number is valid.
- **Contrast.** The grey number and the small line are fgSubtle: 4.81:1 to 5.19:1 in every look. The chevron and the lock pass 3:1. The moment line is signalInk, 5.44:1 in Blush and higher elsewhere.
- **Reduce Motion:** no caret pulse; the dot fades in instead of springing; the chevron scroll is not animated.
- **Prefer Non-Blinking Cursor** (iOS 18 and later): read AccessibilitySettings.prefersNonBlinkingTextInsertionIndicator and observe its change notification. When it is on, the drawn caret neither pulses nor blinks. On iOS 17 only Reduce Motion applies.
- **Haptics** follow Taken's Haptics switch.

#### 13. Code
All of this stays inside #if DEBUG || TAKEN_INTERNAL. WeightTabRootView keeps its name, because it is the App Store marker.

Files:
- **Taken/Weight/WeightTabRootView.swift.** Rewritten as below.
  - It keeps WeightMoreMenu and WeightToastDock.
  - WeightTrendPage lives here, built from the existing helpers (lineText, changeLine, allWeighInsRow, headlineSpoken).
  - The headline card, the empty card and both Log weigh-in buttons go.
- **New: Taken/Weight/WeightEntryView.swift.** WeightEntryPage (top bar, figure block, chevron), WeightFigureLine, WeightCaret, WeightSmallLine and WeightFoldSnap.
- **New: Shared/WeightEntry.swift.** Pure and tested: WeightFigure, WeightLine, WeightEntry and WeightFold.
- **Deleted: Taken/Weight/WeighInSheet.swift.**
- **Taken/AppModel.swift.** Remove SheetRoute.weighIn (id "weigh-in") and case "weight-log". Add the new demo cases.
- **Taken/Views/TodayView.swift (RootView).** Remove case .weighIn: WeighInSheet(). Under -demo, the launch argument "-type ax3" applies .dynamicTypeSize(.accessibility3) to the root.
- **Taken/Weight/WeightModel.swift.**
  - Remove openWeighIn(). Add the in-memory fields below, endVisit() and editWeighIn(_:).
  - saveWeighIn sets justSaved and drops the toast's value: Toast(message: WeightCopy.weighedIn, undo: .removeWeighIn(saved.id)).
  - undoWeight(.removeWeighIn) also clears justSaved.
- **Taken/Weight/WeightChart.swift.** Drop justReached: points are always drawn lit. WeightLitPoint gains bead: Bool = true. Update the header comment.
- **Taken/Weight/WeighInList.swift.** Open straight at editOnOpen.
- **Taken/Weight/WeightGoalSheet.swift.** Comments only, where they mention the weigh-in sheet.
- **Shared/WeightData.swift.** WeightCopy (section 15), WeightDemo, and DemoData.weighIns(now:includeToday:).
- **Shared/WeightGoal.swift.** WeightGoalCopy.visit and spokenVisit, both added to all.
- **Taken/DemoProbe.swift and scripts/screenshots.sh.** Section 14.
- **REDESIGN.md and SPEC.md 3.12.** Replace the layout and demo-screen paragraphs with this section.

Pure types:
```swift
enum WeightAnchor: Hashable { case entry, block, trend }
enum WeightFigure: Equatable { case empty, ghost(kg: Double), today(kg: Double), typing(String) }
enum WeightLine: Equatable { case last, range, closing(GoalReadout), moment(WeightMoment) }
enum WeightEntry {
    static func figure(last: WeighIn?, today: DayKey, clock: DayClock, draft: String, focused: Bool) -> WeightFigure
    static func showsRangeHint(_ draft: String, unit: WeightUnit, locale: Locale) -> Bool
    static func line(focused: Bool, draft: String, unit: WeightUnit, locale: Locale, hasGoal: Bool,
                     justSaved: Bool, justReached: WeightMoment?, readout: GoalReadout?) -> WeightLine
}
enum WeightFold {
    /// Between the top and the fold, the nearer of the two; anywhere else, where the scroll was going.
    static func snap(_ y: CGFloat, fold: CGFloat) -> CGFloat {
        guard fold > 0, y > 0, y < fold else { return y }
        return y < fold / 2 ? 0 : fold
    }
}
```
WeightModel additions (in memory, never stored):
```swift
var draft = ""             // cleared whenever focus ends
var entryFocused = false   // mirrors the page's FocusState, for DemoProbe
var justSaved: UUID?       // the weigh-in saved on this visit
var momentPlayed = false   // the dot springs once per visit
var editOnOpen: UUID?      // Edit… on today's number
var onTrend = false        // DemoProbe: screen two at the top
func endVisit() { justReached = nil; justSaved = nil; momentPlayed = false; draft = "" }
```
The root:
```swift
struct WeightTabRootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme
    @Environment(\.locale) private var locale
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focused: Bool
    @State private var pageHeight: CGFloat = 0   // status bar to tab bar, keyboard ignored
    @State private var fold: CGFloat = 0         // screen one's height

    var body: some View {
        let weight = model.weight
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    WeightEntryPage(focused: $focused, showTrend: { showTrend(proxy) })
                        .frame(minHeight: pageHeight, alignment: .top)
                        .background { GeometryReader { g in
                            Color.clear.onChange(of: g.size.height, initial: true) { _, h in fold = h } } }
                        .id(WeightAnchor.entry)
                    if !weight.isEmpty {
                        WeightTrendPage()
                            .frame(minHeight: pageHeight, alignment: .top)
                            .id(WeightAnchor.trend)
                    }
                }
                .padding(.horizontal, 20)
                .opacity(pageHeight > 0 ? 1 : 0)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.immediately)
            .scrollTargetBehavior(WeightFoldSnap(fold: fold, enabled: !focused))
            .background(theme.bg.ignoresSafeArea())
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if focused {
                    PrimaryButton(title: WeightCopy.weighIn, enabled: kilograms != nil) { save() }
                        .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 12)
                        .transition(.opacity)
                } else {
                    WeightToastDock()
                }
            }
            // After the inset, so neither the toast nor the button changes it; the keyboard is ignored.
            .background {
                GeometryReader { g in
                    Color.clear.onChange(of: g.size, initial: true) { _, _ in
                        guard !focused else { return }
                        let f = g.frame(in: .global)
                        pageHeight = (f.maxY - g.safeAreaInsets.bottom) - (f.minY + g.safeAreaInsets.top)
                    }
                }
                .ignoresSafeArea(.keyboard)
            }
            .onChange(of: focused) { _, now in
                model.weight.entryFocused = now
                if !now { model.weight.draft = "" } else { keepLineClear(proxy) }
            }
        }
        .onChange(of: model.weight.draft) { _, typed in
            let clean = WeightFormat.sanitize(typed, locale: locale, maxDecimals: model.weight.unit.decimals)
            if clean != typed { model.weight.draft = clean }
        }
        .onAppear { model.weight.refresh() }
        .onDisappear { focused = false; model.weight.endVisit() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { focused = false; model.weight.endVisit() } }
    }

    private var kilograms: Double? {
        WeightFormat.kilograms(model.weight.draft, unit: model.weight.unit, locale: locale)
    }

    private func save() {
        guard let kg = kilograms else { return }
        focused = false
        model.saveWeighIn(kg: kg)   // sets justSaved, justReached, haptic, toast, announcement
    }

    private func showTrend(_ proxy: ScrollViewProxy) {
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.35)) { proxy.scrollTo(WeightAnchor.trend, anchor: .top) }
    }
}

/// Snaps between the number and the trend; free below the fold; off while typing (iOS 17).
struct WeightFoldSnap: ScrollTargetBehavior {
    var fold: CGFloat
    var enabled: Bool
    func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
        guard enabled else { return }
        target.rect.origin.y = WeightFold.snap(target.rect.minY, fold: fold)
    }
}
```
Implementation notes:
- **The keyboard safe area.** Only the measuring reader ignores the keyboard. The ScrollView keeps the keyboard's safe area, so the bar rides on the keypad. Never apply ignoresSafeArea(.keyboard) to the ScrollView.
- **keepLineClear(proxy).** 0.35 s after focus, if the small line's global bottom is more than buttonTop - 16, run withAnimation(.snappy(duration: 0.25)) { proxy.scrollTo(WeightAnchor.block, anchor: .bottom) }. Read both frames through preference keys. Because of the block's 20 bottom padding and the bar's 8 top padding, the line ends 28 above the button.
- **If the bar hides behind the floating tab bar** on the Xcode 26.6 SDK (shot 61-weight-entry shows it), move it to ToolbarItemGroup(placement: .keyboard).
- **The figure block** has three modifiers:
  - .contentShape(Rectangle())
  - .onTapGesture { guard !focused else { return }; model.requireWeightPro { focused = true } }
  - .contextMenu { if !focused, let today { Button(WeightCopy.edit) { model.editWeighIn(today.id) }; Button(WeightCopy.delete, role: .destructive) { model.deleteWeighIn(today.id) } } }
- **Screen one's background** gets .contentShape(Rectangle()).onTapGesture { if focused { focused = false } }.
- **The caret, unfocused.**
  - Use .phaseAnimator([1.0, 0.3, 1.0, 0.3, 1.0, 0.3], trigger: pulse) with .easeInOut(duration: 0.6). It runs through the phases once per trigger and returns to 1, taking about 3.6 s, which is under WCAG 2.2.2's 5 s.
  - pulse goes up on appear, and whenever the figure becomes grey or empty again (after Undo).
- **The caret, focused.**
  - It loops 0.5 s on and 0.5 s off with 0.1 s fades.
  - It restarts on every keystroke (.id(draft)), so it stays solid while typing.
- **The caret, either way:** steady under Reduce Motion or Prefer Non-Blinking Cursor.
- **Save order.** Read kg, set focused = false, then call saveWeighIn. The digits do not flash: the unfocused figure is computed from the model, which the same transaction has already updated.
- **DemoProbe.** Under -demo, call DemoProbe.record(model) whenever focus, the figure kind, the line kind or onTrend changes.

#### 14. CI: demo screens, probes and shots
Demo data:
- DemoData.weighIns(now:includeToday:). With includeToday false, the history ends yesterday at 07:xx, and yesterday is never skipped, so the line always reads "yesterday".
- WeightDemo: the screens below open on Weight, and "weight-log" is gone.
- WeightModel.demo sets the in-memory fields:
  - draft and focus for the entry screens; the page applies focus 450 ms after appear
  - justSaved for weight-goal-saved
  - justReached for the moment screens, as weight-goal-moment does today
  - the scroll to screen two for its shots: scrollTo without animation, 450 ms after appear

DemoProbe:
- weightLines gains these lines:
  - focus=0|1
  - figure=empty|ghost|today|typing
  - line=last|range|closing|moment
  - scroll=entry|trend: trend when screen two's top is within 1 pt of the visible top
  - weightlock=0|1
- A new recordWeightEntryFit(lineBottom:buttonTop:shift:) writes tmp/taken-weight-entry-fit.txt with these lines:
  - line=
  - button=
  - shift=, the block's centre after focus minus before
  - fits=1 when line <= button - 16, with 0.5 of slack
  - still=1 when abs(shift) <= 0.5
- recordWeightFit stays, now measured on screen two after the demo's scroll. Read the frame with .onChange(of: proxy.frame(in: .global).maxY), not only on size changes, so the value written is the one after the scroll.

scripts/screenshots.sh:
- shoot takes an optional fourth argument of extra launch arguments.
- Add weight_entry_fits <name> [still].
- Remove 61-weigh-in, 61-weigh-in-blush, 68-weigh-in-6.3in, 69-weigh-in-6.1in, and every sheet=weigh-in check.
- No new name may end in a store frame's state: today, today-done, add, day, log or settings. tools/store-shots/generate.mjs matches the end of a file name, which is why the "weighed in today" shot is 76-weight-weighed.

Every row below also lands tab=weight sheet=none weight=1, unless it says unchanged.

| Shot | -screen | Shows | lands |
|---|---|---|---|
| 60-weight, -blush, -phosphor, -ice | weight | grey number, caret, "Last weigh-in yesterday, ...", chevron | goal=0 focus=0 figure=ghost line=last scroll=entry |
| 61-weight-entry, -blush | weight-entry | keypad up, "88.1" typed, Weigh in enabled | focus=1 figure=typing line=last; weight_entry_fits still |
| 61-weight-entry-range | weight-entry-range | "883" typed, "Between 20 and 350 kg", Weigh in dimmed | focus=1 line=range |
| 62-weight-empty | weight-empty | caret, "kg", "No weigh-ins yet" | goal=0 focus=0 figure=empty |
| 62-weight-first | weight-first | one weigh-in today; screen two with one dot and "Your trend starts here." | scroll=trend |
| 63-weight-list, -blush | weight-list | unchanged | unchanged |
| 70-weight-goal, -blush, -phosphor, -ice | weight-goal | screen two: goal line, one point, "1.1 kg to 87.0" | goal=1 points=1 scroll=trend |
| 71-weight-goal-moment | weight-goal-moment | screen one: 87.1, lit dot, "Trend is now 10% below where you started." | goal=1 points=2 figure=today line=moment |
| 71-weight-goal-saved | weight-goal-saved | screen one: "Trend 1.1 kg to 87.0" | goal=1 figure=today line=closing |
| 72-weight-goal-reached | weight-goal-reached | screen two: three points, "Holding near 87.0" | goal=1 points=3 scroll=trend |
| 72-weight-goal-reached-moment | weight-goal-reached-moment | screen one: "Trend reached 87.0." | goal=1 points=3 line=moment |
| 73-weight-goal-sheet (-blush), 74-weight-goal-low | unchanged | unchanged | unchanged |
| 76-weight-weighed | weight-weighed | today's number in fg, "Last weigh-in today, ..." | figure=today line=last |
| 77-weight-trend, -blush, -phosphor, -ice | weight-trend | screen two without a goal | goal=0 scroll=trend |
| 78-weight-locked | weight-locked | the lock instead of the caret (the locked screen's Pro state, with weigh-ins) | weightlock=1 figure=ghost |
| 79-weight-lb | weight-lb | grey number in lb | figure=ghost |
| 64-profile-weight(-data), 65-today-weight-offer(-blush), 66 and 67 links | unchanged | unchanged | unchanged |

Smaller iPhones:
- **6.3 inch:**
  - 68-weight-6.3in (weight)
  - 68-weight-entry-6.3in (weight-entry, with weight_entry_fits still)
- **6.1 inch:**
  - 69-weight-6.1in (weight)
  - 69-weight-entry-6.1in (weight-entry; lands focus=1; weight_entry_fits still)
  - 69-weight-entry-ax3-6.1in (weight-entry with -type ax3; weight_entry_fits without still)
  - 69-today-weight-offer-6.1in (unchanged)
  - 75-weight-goal-6.1in (weight-goal; lands goal=1 scroll=trend; weight_fits)

#### 15. Copy
New strings, all in WeightCopy unless marked:
- "Weigh in"
- "Between 20 and 350 kg" and "Between 44 and 770 lb", built from unit.bounds; spoken "Between 20 and 350 kilograms"
- "Show trend"
- "Your trend starts here."
- "Edit…" and "Delete" for the long-press menu; "Edit weigh-in" and "Delete weigh-in" for the VoiceOver actions
- field labels: "Today's weight in kilograms", "Today's weight in pounds", "Today's weigh-in"
- hints: "Double-tap to type today's weight.", "Double-tap to log another weigh-in.", "Logging needs Taken Pro. Opens Taken Pro."
- spoken small line: "Last weigh-in 88.35 kilograms, yesterday at 07:42", and "Last weigh-in today at 07:06"
- WeightGoalCopy.visit: "Trend 4.2 kg closer to 87.0", "Trend 1.1 kg to 87.0", "Trend holding near 87.0", "Trend 0.9 kg from 87.0"; in lb, "Trend 2.4 lb to 191.8"
- WeightGoalCopy.spokenVisit: "Trend 4.2 kilograms closer to your goal, 87.0", "Trend 1.1 kilograms to your goal, 87.0", "Trend holding near your goal, 87.0", "Trend 0.9 kilograms from your goal, 87.0"

Changed:
- lastLine goes back to v1's form, "Last weigh-in yesterday, 07:42", replacing "Last 88.35 kg · yesterday, 07:42". The value now lives in the big number.
- The save toast reads "Weighed in" with Undo, without the value.

Removed: "Log weigh-in", "Now", "Log your first weigh-in. Your trend starts here.", and "Last" if nothing else uses it.

Rules: the existing copy tests apply to all of these.
- No em or en dash, no "!", and no "free".
- WeightCopy never uses lose, loss, ideal or goal.
- WeightGoalCopy keeps its whole-word bans.
- Every string with "goal" lives in WeightGoalCopy.

#### 16. Tests
New file, TakenTests/WeightEntryTests.swift:
1. **WeightEntry.figure:**
   - never weighed in gives empty
   - last weigh-in yesterday gives ghost
   - last weigh-in today gives today
   - focused with an empty draft gives ghost of the last weigh-in, today's included
   - focused with a draft gives typing
2. **showsRangeHint:**
   - kg: "8", "19", "88.1" and "" give no hint; "19.5", "883", "1000" and "350.5" do
   - lb: "40" and "195.5" give no hint; "40.5" and "800" do
   - de_DE: "19,5" gives the hint
3. **WeightEntry.line priority:**
   - while typing, the range hint beats everything; otherwise typing shows last
   - moment beats closing
   - closing needs justSaved, a goal, and a readout other than goalOnly
   - goalOnly, or no goal, gives last
4. **WeightFold.snap:**
   - y <= 0 and y >= fold are unchanged
   - y in between snaps to the nearer edge
   - fold 0 leaves y unchanged
5. **Sizing:** the box string is the longer of the grey value and the draft.

Updates to TakenTests/WeightTests.swift:

6. **lastLine:** "Last weigh-in today, 07:42", "Last weigh-in yesterday, 07:42", "Last weigh-in Monday, 07:42", "Last weigh-in 14 Oct, 07:42", "Last weigh-in 3 Mar 2025, 07:42", "No weigh-ins yet", and the spoken forms.
7. **The logging test.**
   - model.requireWeightPro { opened = true } runs at once for the first weigh-in.
   - saveWeighIn shows the toast "Weighed in" with time nil and Undo, and sets justSaved to the new id.
   - Undo removes the weigh-in and clears justSaved and justReached.
   - After that, requireWeightPro opens the paywall and does not run the action.
   - Remove the SheetRoute.weighIn assertions.
8. **editWeighIn:**
   - with access, sheet == .weighIns and editOnOpen == id
   - when locked, the paywall opens and no sheet does
9. **endVisit** clears justSaved, justReached, momentPlayed and draft.
10. **Copy.**
    - WeightCopy.all and WeightGoalCopy.all include every new string and pass the rules.
    - visit and spokenVisit are correct in kg and lb, and goalOnly gives nil.
11. **Demo.**
    - The new screens open on Weight with the tab on.
    - weight has no weigh-in today and one yesterday.
    - weight-first has exactly one weigh-in.
    - weight-goal-saved has justSaved set and a to-go readout between 1.1 and 1.3.
    - weight-locked gives weightAccess .locked.

TakenTests/WeightGoalTests.swift is unchanged, apart from anything that expected the moment in the slot.

#### 17. Removed from the page Tom saw
- The "Weight" large title and its subtitle. More and the avatar stay, in the same spot.
- The headline card: "Trend", the 40 pt trend value, the slot, and the Log weigh-in button. The trend and the slot move to screen two without a card; the button goes.
- The right-hand "Last" column. It is already gone on the branch.
- The empty card: the scalemass disc, "Log your first weigh-in. Your trend starts here." and its button.
- The weigh-in sheet: WeighInSheet, SheetRoute.weighIn, openWeighIn, "Log weigh-in", "Now" and its Save.
  - Its sanitize, parse and bounds logic already lives in WeightFormat, and the page reuses it.
  - DemoProbe needs no code change for the sheet, because sheet= prints whatever is open. The CI lines that expected sheet=weigh-in go.
- From screen one: the range control, the chart, the change line (which had already replaced the three change rows), "Ticks: weekly doses" and All weigh-ins. All of them are on screen two, unchanged.
- From the addendum's page:
  - the moment in the slot, which is now the small line
  - the chart point's spring; the point is now drawn lit
  - the subtitle with the value, back to "Last weigh-in …"
  - the value in the save toast

#### 18. Own calls (no source decided these)
- No visible title, and the hidden "Weight" heading instead.
- The grey last weigh-in as the big number until today's weigh-in. The figure always shows a weigh-in, never the trend.
- Typography: Geist Mono Regular at 72, the separator pulled in by 11 on each side, the 3 x 59 caret, and the 17 pt lock in signalInk.
- Layout: the block at 40% of the free space, the 12 gap, and the 16 keyboard clearance.
- Caret timing: three pulses then steady, and the focused blink timings.
- Discarding the draft when the keypad closes without a save.
- The "looks finished" rule for the range hint, and its single announcement.
- "Trend" in front of the closing-in line on screen one, and no line for goalOnly.
- A chevron rather than a toggle, and the custom fold snap with its threshold at half the fold.
- Screen two from the first weigh-in, with "Your trend starts here.".
- The long-press menu and its labels, and Edit… opening the editor directly.
- The point on screen two drawn already lit, with the spring only on screen one.
- The -type demo argument.
- All the position estimates. CI's probes are the proof.

#### 19. Sources
- **Apple HIG** (fetched 2026-10-22 for the concepts; reused):
  - Text fields: a hint shows the field's purpose, a separate label is needed because placeholder text disappears, and the keyboard type should suit the content. https://developer.apple.com/design/human-interface-guidelines/text-fields
  - Focus and selection: "Avoid changing focus without people's interaction". https://developer.apple.com/design/human-interface-guidelines/focus-and-selection
  - Virtual keyboards. https://developer.apple.com/design/human-interface-guidelines/virtual-keyboards
  - Entering data: "Dynamically validate field values". https://developer.apple.com/design/human-interface-guidelines/entering-data
  - Feedback: match the significance of the information to how it is delivered. https://developer.apple.com/design/human-interface-guidelines/feedback
  - Playing haptics. https://developer.apple.com/design/human-interface-guidelines/playing-haptics
  - Menus: verbs, and an ellipsis when more input follows. https://developer.apple.com/design/human-interface-guidelines/menus
  - Charts. https://developer.apple.com/design/human-interface-guidelines/charts
- **WWDC22 session 110342**: one inline chart, with no zoom view. https://developer.apple.com/videos/play/wwdc2022/110342/
- **Apple API docs, fetched today as JSON:**
  - containerRelativeFrame(_:alignment:), iOS 17: "the size of a container ... subtracting any safe area insets". https://developer.apple.com/documentation/swiftui/view/containerrelativeframe(_:alignment:)
  - ScrollTargetBehavior and updateTarget(_:context:), iOS 17: called when a scroll gesture ends and when the scrollable view's size changes. https://developer.apple.com/documentation/swiftui/scrolltargetbehavior and https://developer.apple.com/documentation/swiftui/scrolltargetbehavior/updatetarget(_:context:)
  - SafeAreaRegions.keyboard, iOS 14: "The safe area matching the current extent of any software keyboard". https://developer.apple.com/documentation/swiftui/safearearegions/keyboard
  - phaseAnimator(_:trigger:content:animation:), iOS 17. https://developer.apple.com/documentation/swiftui/view/phaseanimator(_:trigger:content:animation:)
  - AccessibilitySettings.prefersNonBlinkingTextInsertionIndicator, iOS 18: "relevant for apps that draw custom insertion indicators". https://developer.apple.com/documentation/accessibility/accessibilitysettings/prefersnonblinkingtextinsertionindicator
- **Apple API docs, reused from the concepts and not re-fetched:**
  - https://developer.apple.com/documentation/swiftui/view/scrolldismisseskeyboard(_:)
  - https://developer.apple.com/documentation/swiftui/view/focused(_:)
  - https://developer.apple.com/documentation/swiftui/view/defaultfocus(_:_:priority:)
- **WCAG 2.2:**
  - 2.2.2 Pause, Stop, Hide (reused). https://www.w3.org/WAI/WCAG22/Understanding/pause-stop-hide.html
  - 1.4.3 Contrast (Minimum), not re-fetched today. https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum.html
  - 1.4.11 Non-text Contrast, not re-fetched today. https://www.w3.org/WAI/WCAG22/Understanding/non-text-contrast.html
- **NN/g, The Illusion of Completeness**: a full-height hero needs an edge cue. https://www.nngroup.com/articles/illusion-of-completeness/
- **Clock's Stopwatch**: a big number with laps below. That it has no title is an observation. https://imore.com/how-use-stopwatch-iphone-and-ipad
- **Prior research reused**: journal wf_3896280d-dc8, research:craft and research:language. It covers HIG Charts, haptics, confetti and gamification, Taken's tokens and type scale, and the All taken spring and glow.
- **Repo, origin/feat/weight-tab f10e80a:**
  - Taken/Weight: WeightTabRootView.swift, WeighInSheet.swift, WeightChart.swift (WeightLitPoint), WeightModel.swift (saveWeighIn, requireWeightPro, undoWeight), WeighInList.swift
  - Shared: WeightData.swift (WeightCopy, WeightFormat, WeightDemo), WeightGoal.swift (WeightGoalCopy), Theme.swift
  - Taken/Views: Components.swift (PrimaryButton, Card), ProgressSummary.swift, TodayView.swift (RootView, LockedBar, ToastView)
  - Taken/Profile/Profile.swift (TabHeader), Taken/AppModel.swift (SheetRoute, Toast, Haptics, demo routing), Taken/DemoProbe.swift
  - scripts/screenshots.sh, and tools/store-shots/generate.mjs (the store frame state names)
- **Own measurements:**
  - Taken/Fonts/GeistMono-Regular.ttf, Geist-Regular.ttf and Geist-Medium.ttf, read with fontTools: advance 600 per 1000 em, cap height 710, ascent 1005, descent 295; the point's ink is 8.9 pt at 72 pt; line widths measured at 15 pt.
  - Contrast ratios from Theme.swift's hex values, with the WCAG formula.
- **Tom's reaction and the CI shots**: 60-weight.png, 61-weight-log.png and small/65-today-weight-offer.png.

#### Built (feat/weight-tab), and where it differs from the section above
- The unit follows the digits: it sits 8 after the trailing edge of whatever the number shows, on the digits' baseline, in every state (Tom, after CI run 39817898631: the unit sat high at rest and far right while typing). The line is still centred on the longer of the grey value and the draft, and the digits start where the grey ones did, so the number does not move while typing (CI checks shift 0.0).
- Screen one runs on under the floating tab bar and the home indicator, empty, so screen two starts below the bottom of the screen and nothing of it shows through the bar. The page height comes from the scroll view's frame, which stops at the safe area while it reports the full insets, and the tab bar's top from the toast dock on the bottom safe area (measured in CI: 62 to 769 on a 393 x 852 iPhone, insets 62 and 83).
- The caret's pulse and blink run as a small task rather than phaseAnimator, so the pulse always ends at full strength, and it holds still under `-demo` so captures are steady.
- Dates on the chart show the day as well as the month when the window spans two months or less, so a first week never reads "Oct Oct Oct".
- Section 13's file list is followed, with two additions: `WeightModel.entryRequested` (the tap's `requireWeightPro` action sets it and the page focuses the field, which avoids capturing focus state in a main-actor closure) and `WeightScrollFrame`.

## Extras policy, 2026-10-22 (summary of the focus-vs-bundle decision)

Tom asked whether to-dos and a daily weigh-in would put off someone who came for pills, and whether "Tom's personal app for his life" at $1.99 to $2.99 a month would sell better. Researched as of 22 Oct 2026 and reviewed by a critic.

- Decision: a pill-first app with quiet extras. Taken is sold as the pill and supplement log; voice to-dos stay as a tab; the weigh-in is a tab people switch on, offered in the app only to stacks with a GLP-1 medicine; one Taken Pro at today's prices covers everything. Not pills-only, not an all-in-one life app, not separate apps.
- Why: Taken wins or loses on the store page, where Apple ranks the name, subtitle, keywords and category and search shows one to three screenshots. Shown next to specialists, an all-in-one is judged worse at the specialist's job (Chernev 2007), and unrelated information weakens belief in the core job (Meyvis and Janiszewski 2002; Zhang, Fishbach and Kruglanski 2007). Medisafe and MyTherapy keep weight out of their names; MyNetDiary's weight chart is a free extra in a "Calorie Counter". Inside the app the risk is ease of use, so extras stay off Today and the logging path.
- Weight fits better than to-dos: pill-app users ask for other health tracking (Park 2019) and the leading GLP-1 tracker sells doses and weight together. Daily weighing with a trend graph caused bigger negative mood swings in women aged 18 to 22 (Pacanowski 2023), so weight is offered where it is part of the job and is a switch for everyone else.
- The test any future extra must pass: (1) a once-a-day personal check that fits the pill routine; (2) no new tap, row, chip or choice before a dose is logged; (3) one tap or one sentence, on the iPhone, no account, permission only on first use; (4) its own tab behind a Profile switch, off by default if it touches body, food or mood; (5) never in the name, subtitle, promotional text, keywords, tags, first three screenshots or first description lines; (6) inside the one Pro, no new price or tier; (7) within five tabs; (8) no streak, badge or nudge of its own; (9) removed after six months if reviews and support mail show nobody wants it. Voice to-dos fail point 1 and stay as Tom's stated exemption; food or calorie logging and skincare fail today.
- Both extras: never on Today's list, in the Add sheet, in onboarding or between opening Taken and logging a dose; introduced by at most one contextual row; the app never shows or hides a tab on its own; listed last in the description.
- Price: keep $19.99 a year with the 7-day trial, $3.99 a month and $49.99 lifetime, with the hard paywall after the first dose. No pills-only tier, add-on or $1.99 plan: at 15% commission $1.99 needs about twice the subscribers, comparable apps charge the same or more, and the yearly plan already works out at about $1.67 a month.
- Measurement: Taken collects no analytics, so defaults are set on today's evidence and change on reviews, support mail and App Store Connect's broad signals.

Sources: https://developer.apple.com/app-store/search/, https://developer.apple.com/app-store/product-page/, https://developer.apple.com/design/human-interface-guidelines/tab-bars, https://developer.apple.com/documentation/tipkit, https://developer.apple.com/app-store/review/guidelines/, https://www.revenuecat.com/state-of-subscription-apps/, https://adapty.io/state-of-in-app-subscriptions/, https://apps.apple.com/us/app/medisafe-medication-management/id573916946, https://apps.apple.com/us/app/mytherapy-pill-reminder/id662170995, https://apps.apple.com/us/app/shotsy-glp-1-tracker/id6499510249, https://apps.apple.com/us/app/happy-scale/id532430574, https://apps.apple.com/us/app/mynetdiary-calorie-counter/id287529757, https://academic.oup.com/jcr/article/33/4/430/1790298 (Chernev 2007), https://ideas.repec.org/a/oup/jconrs/v28y2002i4p618-35.html (Meyvis and Janiszewski 2002), https://pubmed.ncbi.nlm.nih.gov/17352599/ (Zhang, Fishbach and Kruglanski 2007), https://mhealth.jmir.org/2019/1/e11919 (Park 2019), https://pubmed.ncbi.nlm.nih.gov/37339756/ (Pacanowski 2023), https://pubmed.ncbi.nlm.nih.gov/26293454/ (Madigan 2015), https://ideas.repec.org/a/cup/bpubpo/v3y2019i02p159-186_00.html (Jachimowicz 2019), https://developer.apple.com/app-store/small-business-program/

## Weight tab in 1.1, 2026-10-23

Tom, 2026-10-22, on holding the Weight tab for 1.2: "Stop making more versions. Just publish it to the App Store. I want to see it." App Store Connect takes one version submission per platform at a time (https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/overview-of-submitting-for-review) and 1.0 is still in App Review, so the tab goes in 1.1, the update submitted when 1.0 clears, not in a version of its own.

### Built
- The Weight tab is in every build. The `#if DEBUG || TAKEN_INTERNAL` gate is gone from every weight type and view: Shared/WeightData.swift, WeightEntry.swift, WeightGoal.swift and WeightStore.swift, Taken/Weight, and the weight parts of AppModel, RootView, ProfileView, TodayPromptRow, TabHeader, `TodayPrompt` and DemoProbe. It is still off for every install (`WeightState.showsTab` nil) and comes in only through Profile's switch or Today's one-time offer.
- Debug only, like `-demo` itself (Guideline 2.5.19, https://developer.apple.com/app-store/review/guidelines/): `WeightDemo`, the demo weigh-ins and weekly shot in `DemoData`, `WeightModel.demo`, the weight `-screen` cases in AppModel and ProfileView, the Weight tab's demo focus and scroll, and `DemoTypeSize`, the only reader of `-type`. No App Store build reads a weight launch argument or carries a weight screen name.
- scripts/check-app-store-build.sh is main's again: `WeightTabRootView` is out of the must-be-absent markers and out of the `--internal` presence check. The owner-only markers (TakenInternalPro, the eval's, the voice note log's) and the unread-binary control still fail the check closed.
- scripts/screenshots.sh: every store frame, both sets, 01 to 06, must leave `weight=0` and `offer=0` in the demo probe, so the 1.1 screenshots show the app as it installs: three tabs and no weight row.
- Still `#if DEBUG || TAKEN_INTERNAL`, owner only: the internal Pro unlock (`InternalBuild`), TodoEval and the voice note log.

### Unchanged
- The store rules from "Weight tab, 2026-10-22" and "Extras policy, 2026-10-22": weight is a quiet extra, off by default, and never in the name, subtitle, keywords, description, promotional text or screenshots. What's New has one neutral line in every set and the review notes describe the switch, the offer, weights.json on the iPhone and the goal sentence ("Review fixes and the Weight tab in 1.1" above); scripts/check-store-metadata.py allows weight words in those two places only.

### Own choices (no source)
- `taken://weight` is in every build with the tab: the Weight tab, or Today while it is off, like `taken://todo`.
- The weight demo hooks are compiled out of Release builds rather than left unreachable, one step past main's rule (only the arguments are Debug only), so no weight screen name ships.

## Tap the row to log, 2026-10-25

Tom, verbatim: "I wanted to tap that I've taken vitamin D today. So I clicked the vitamin D3 bar and this weird shit popped up about options for it ... I want to open, tap, forget. And the fact that it didn't give me that nice dopamine explosion and it brought up a fucking menu really made me want to delete the app there and then." "They want to tap the bar ... It's too niggly, higgledy piggledy to have to fucking tap a certain point on the bar." "To edit the same things ... figure out a better place to do that ... Maybe a little pen somewhere that puts it in edit mode would be better."

### Verdict
The whole Today row is one tap target that does what the ring alone did: a pending row logs, a taken row shows its times, nothing ever un-takes, and a locked row opens the paywall. Editing moves to an explicit edit mode, entered with a text "Edit" beside the Stack title (it reads "Done" while editing), where every row shows a chevron and a tap opens the item sheet. The long-press menu stays as a shortcut.

### Why
- Apple: "people expect tap to activate or select an object" (https://developer.apple.com/design/human-interface-guidelines/gestures), a list row may toggle state on a tap ("The feedback can vary depending on whether selecting the item reveals a new view or toggles the item's state"), and "In iOS and iPadOS, people must enter an edit mode before they can select table items" (https://developer.apple.com/design/human-interface-guidelines/lists-and-tables). Logging is the row's job; opening it is editing.
- Target size: "The larger the target, the shorter the movement time to it", and a label plus icon is a bigger target only if "you do make the entire area clickable" (NN/g, https://www.nngroup.com/articles/fitts-law/). The ring's 72 by 60 pt zone already met Apple's 44 pt minimum (https://developer.apple.com/design/human-interface-guidelines/buttons); the complaint was where it sits and that the rest of the row did something else.
- The closest shipped layout to Taken's old row, iOS 16's Home tiles (tap the icon to toggle, the name for the controls, https://www.smart-secure.co.uk/blog/news/what-are-the-apple-homekit-changes-in-ios16/), drew Tom's complaint word for word: taps opening settings instead of toggling (https://forums.macrumors.com/threads/ios16-homeapps-button-redesign-doesnt-make-sense.2351238/, https://forums.macrumors.com/threads/homekit-light-switching.2373369/; read through search summaries, the forum refuses a direct fetch).
- Habit apps make the whole tile the log target: Streaks, "a big button" (https://apps.apple.com/be/story/id1272004658), with editing behind an Edit button (https://apps.apple.com/us/app/streaks/id963034692); (Not Boring) Habits (https://www.tapsmart.com/apps/review-not-boring-habits/); Today I Done, tap the task to light it, long-press for edit mode (https://apps.apple.com/us/app/-/id6749781054). Supplement trackers sell one-tap logging (https://apps.apple.com/app/id6747706941). To-do apps keep a separate circle because their rows hold content opened often (Things, https://culturedcode.com/things/support/articles/2803582/; Reminders, https://support.apple.com/kb/ht4970), and even they add whole-row completion (Todoist swipe actions, https://www.todoist.com/help/articles/how-to-change-your-swipe-actions-D5DQOQz6). Habitify keeps Taken's old split (https://intercom.help/habitify-app/en/articles/9387661-track-progress-on-good-habit).
- The guard against a mistaken tap is Undo, not a hold, a menu or a confirmation: "Do not use confirmation dialogs for routine actions" and "do go to great lengths to provide undo" (https://www.nngroup.com/articles/confirmation-dialog/); Apple reserves confirmations for important actions (https://developer.apple.com/design/human-interface-guidelines/feedback) and asks that an undo show its result (https://developer.apple.com/design/human-interface-guidelines/undo-and-redo); Habitify added an Undo prompt after every check-in to remove accidental ones (https://feedback.habitify.me/changelog/prompt-the-undo-button-to-revert-the-check-in-action). Taken's 4 s toast with Undo, and Undo last dose in the long-press menu, already do this. Hold-to-log (Streaks, Not Boring, https://support.notbor.ing/Habits-Guide-668040348b1d4778b5a00a66096aff3e) is slower than the one tap Tom asked for. Medication-first apps are slower still (Apple Health Medications: plus, Taken, Done, https://support.apple.com/en-ca/105064; Medisafe: tap the dose, then Take, https://help-center.medisafe.com/en/articles/8103135-how-can-i-choose-the-time-i-marked-my-dose), and both keep correcting a dose on a separate path (https://help-center.medisafe.com/en/articles/8102984-i-took-my-meds-at-a-different-time-how-do-i-change-the-time-taken), as Taken's Set time does.
- Editing needs a visible way in: a context menu "is hidden by default, so people might not know it's there", and "Always make context menu items available in the main interface, too" (https://developer.apple.com/design/human-interface-guidelines/context-menus). Apple Health edits its own home list with "Edit next to Pinned", then Done (https://support.apple.com/en-ca/HT203037); SwiftUI's EditButton is the same text control, "Done" while editing (https://developer.apple.com/documentation/swiftui/editbutton); and UIKit turns a row's normal selection off while editing (https://developer.apple.com/documentation/uikit/uitableview/allowsselectionduringediting) and can show a disclosure accessory in its place (https://developer.apple.com/documentation/uikit/uitableviewcell/editingaccessorytype).
- One SwiftUI Button with a ButtonStyle keeps the platform's touch handling (https://developer.apple.com/documentation/swiftui/buttonstyle; Apple says to use a ButtonStyle, not a tap gesture, for anything that acts as a button, https://developer.apple.com/documentation/swiftui/view/ontapgesture(count:perform:)), so a scroll that starts on a row cancels it before it logs, as UIScrollView cancels any control's touch (https://developer.apple.com/documentation/uikit/uiscrollview/cancancelcontenttouches). The iOS 18 regression where a scroll fires a Button is reported only inside sheets (https://developer.apple.com/forums/thread/770551, https://developer.apple.com/forums/thread/775266); Today is a tab, and none of the workarounds posted there (extra drag gestures, which break the press state) are used.

### Built
- `ItemRowView` is one Button over the name, the frequency line, the gap, the time and the ring (`contentShape(Rectangle())`), with the old name half and ring half merged. `ItemRowPressStyle` is `RowPressStyle`'s flat inset highlight plus the ring giving a little (0.9, `.snappy(duration: 0.16)`, the old ring press) through an environment value read inside the label. It calls `AppModel.tap` exactly as the ring did: requirePro, `log`, the light impact haptic or the success haptic when the day becomes All taken, the toast with Undo, or the soft haptic and the times for a taken row. Not today rows are the same view.
- The logging moment, on the tapped row only: `AppModel.rowLogs` counts doses a tap on each row has logged, and when it goes up the row washes in the look's `signalWash` (in 0.1 s, out over 0.6 s) while the ring lifts to 1.12 and settles on DoseRing's own spring (`response: 0.3, dampingFraction: 0.55`), on top of the ring's fill and the haptic. The wash is an in-place fade of the whole row, not a sweep across it. Take all, a widget, Siri and Set time do not play it. It plays once per dose: `.task(id:)` runs "before the view appears" as well as when its id changes (https://developer.apple.com/documentation/swiftui/view/task(id:name:priority:file:line:_:)), and TabView brings Today back with its state kept, so the row counts the moments it has played and a return to Today replays none, as `WeightModel.momentPlayed` keeps the goal moment from replaying. Reduce Motion keeps the wash and drops the lift and the ring's 0.9 press, which now fires on every press of the row (the row's inset highlight still shows it): Apple asks to reduce "automatic and repetitive animations, including zooming, scaling, and peripheral motion" and to replace movement "with fades" (https://developer.apple.com/design/human-interface-guidelines/accessibility), and WCAG 2.3.3 asks that "Motion animation triggered by interaction can be disabled" through the system's reduce motion setting (https://www.w3.org/WAI/WCAG22/Understanding/animation-from-interactions.html). Haptics are unchanged and still follow Profile's switch (https://developer.apple.com/design/human-interface-guidelines/playing-haptics: "Prefer using haptics to complement other feedback", "Avoid overusing haptics").
- Edit mode: `EditStackButton` ("Edit", "Done" in semibold while editing, Geist in the look's signal ink, 44 pt, VoiceOver "Edit stack" or "Done") sits before the "+", with its own hit area and space between the two (Apple's HIG: "Keep actions with text labels separate", https://developer.apple.com/design/human-interface-guidelines/toolbars). `AppModel.editingStack`: a row's tap opens `SheetRoute.editItem` and `tap` never logs; the chevron cross-fades in where the time and the ring were; an open detail closes; Take all steps aside; the toast stays. It ends on Done, on any change of tab (the `tab` setter), when Taken goes to the background with no sheet up (`didEnterBackground`, from the scene phase) and when the stack empties. Closing an item sheet keeps it, so several items can be edited in a row, and a sheet still up when Taken goes to the background keeps it too, so the mode never changes under a sheet and the next row tap after it opens that item rather than logging. In locked mode the item sheet opens as it always has.
- VoiceOver: still one element per row. Its default action is the tap (opens the item sheet in edit mode), its hint says so ("Double tap to edit." while editing), and Edit item, Undo last dose and Set time stay its named actions (https://developer.apple.com/documentation/swiftui/view/accessibilityaction(named:_:)). Dynamic Type is as before; CI captures both modes at accessibility size 3.
- CI: `-screen today-edit` (DemoProbe `edit=1`), captured in Signal, in Blush and at accessibility size 3 (41-today-edit, 41-today-edit-blush, 41-today-edit-ax3, each landing `edit=1`), Today logging at that size (42-today-ax3, landing `edit=0`), and every store frame must land `edit=0`. Unit tests: TakenTests/TodayRowTests.swift.

### Own choices (no source)
- The chevron as the edit-mode affordance (UIKit's disclosure accessory is the closest documented one), its 14 pt size and fgSubtle colour.
- The moment's numbers: the 1.12 lift, the 0.1 s in and 0.6 s out of the wash, and the wash at the look's existing 10% `signalWash` rather than a new token.
- The wash plays with Reduce Motion on, as a fade.
- Leaving the toast in place in edit mode (Undo is not logging), and keeping "+" beside Done.
- Ending edit mode on any tab change and on the background, rather than keeping it until Done, and keeping it through the background while a sheet is up.
- The Edit and Done hints: "Then a tap on an item opens it instead of logging it." and "A tap on an item logs it again."

### Where this differs from what Tom said (one line each)
- "A little pen": the button is the word "Edit", because Apple's HIG says to prefer symbols "except for actions like edit that aren't well-represented by symbols" (https://developer.apple.com/design/human-interface-guidelines/toolbars) and lists the pencil as Rename (https://developer.apple.com/design/human-interface-guidelines/icons).
- "Dopamine explosion": the moment is the ring's spring, a soft wash and the haptic Taken already plays, no confetti, because Apple asks for haptics and motion that complement each other without overuse (https://developer.apple.com/design/human-interface-guidelines/playing-haptics) and Taken's design rules keep its motion calm (SPEC 4).

### Open: needs Tom's iPhone
- Tap Vitamin D3 anywhere on its row: it logs with the haptic, the ring lifts and the row washes; switch to History and back: no wash, no lift; scroll Today starting on a row: nothing logs; long-press: the menu, nothing logs. Edit, a row, the sheet, lock the iPhone and come back, close it, another row (it opens), Done. No unit test can press a real row; the simulator captures prove the layout only.
- The store description and the review notes still say "Tap the ring beside an item", which stays true; they can say "Tap an item" with the next submission.
