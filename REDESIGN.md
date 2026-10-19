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
- The eval is a link (`taken://todo-eval`), not a launch argument, because CI cannot run Apple's model and a TestFlight app takes no launch arguments. It answers only in a build carrying the `TakenInternalPro` marker (the EAS "internal" profile). Note 6 is "Restock Always pads and Native deodorant"; note 11 says "by Thursday" (due 2026-10-22), since "before Thursday" could mean Wednesday.

Keep as one (SPEC 3.10)
- One tap after the save instead of a review step before it: Apple's HIG asks for generated results that are easy to refine or revert (https://developer.apple.com/design/human-interface-guidelines/generative-ai), and Doist's lesson from Ramble is that easy correction beats perfect first-time accuracy (https://www.producttalk.org/building-todoist-ramble-how-doist-turned-voice-braindumps-into-real-time-task-capture/). Ramble, Stuff and Reminders preview before saving (https://www.todoist.com/help/articles/dictate-to-add-tasks-with-ramble-P1Raq7vVF), which would break "one tap, voice note, done".
- It lasts 10 s, or until the list changes, the mic is tapped or the tab is left, and is also an accessibility custom action on each task of that note while it is live, because a timed line alone is easy to miss with VoiceOver or Switch Control. Own choice.

Personal and Work (SPEC 3.10)
- One list in view at a time, and a note lands in the list in view: Superlist creates voice tasks "directly in the selected list" (https://help.superlist.com/en/articles/224824-create-tasks-and-notes-with-your-voice-talk), Ramble applies the project in view, Sunsama's contexts filter to one (https://help.sunsama.com/docs/usage-guides/channels-and-contexts), and a segmented control suits closely related views with noun labels (https://developer.apple.com/design/human-interface-guidelines/segmented-controls). The names are in the Voice to-dos section above.
- The Lock Screen to-do widget follows the list in view and is reloaded whenever it changes; it stays a StaticConfiguration so no placed widget breaks. Own choice.

Add sheet: type mode and type-ahead (SPEC 3.3)
- The field is pinned under the header, where neither the keyboard nor the Add bar can cover it, as Apple Health puts a name field at the top with matches under it (https://support.apple.com/en-gb/HT213351). Baymard: keep sticky elements out of the space between a field and the keyboard, and show 4 to 8 suggestions on mobile (https://baymard.com/blog/autocomplete-design). The posted workaround of scrolling after the keyboard appears races it (https://forums.swift.org/t/swiftui-how-to-implement-natural-textfields-keyboard-avoidance-in-scrollview/67616).
- No matchedGeometryEffect across the ScrollView edge (no source shows it behaving there); the field slides in with opacity and a move from the top. Focus is set on appear, because `defaultFocus` is evaluated only when the window first appears or a focus binding moves focus (https://developer.apple.com/documentation/swiftui/view/defaultfocus(_:_:priority:)).
- Typo tolerance follows the engines' documented defaults: 1 typo from 4 letters and 2 from 8, a first-letter typo ranked as two (https://www.algolia.com/doc/guides/managing-results/optimize-search-results/typo-tolerance/in-depth/configuring-typo-tolerance), and a swap of two letters counts as one (https://meilisearch.com/docs/resources/internals/typo_tolerance). Apple's search-field guidance is to suggest as people type (https://developer.apple.com/design/human-interface-guidelines/search-fields).
- The list ships in the binary and was checked offline against RxNorm (public domain, https://www.nlm.nih.gov/research/umls/rxnorm/docs/prescribe.html) and the NIH Dietary Supplement Label Database (https://dsld.od.nih.gov/); names are not copyrightable (https://www.copyright.gov/help/faq/faq-protect.html).

New chips and Weekly (SPEC 3.3)
- Semaglutide and Tirzepatide are approved prescription medicines and dosed weekly on a regularly scheduled day (https://medical.lilly.com/us/products/answers/what-should-a-patient-do-if-they-miss-a-dose-of-zepbound-tirzepatide-209169). The leading GLP-1 tracker lists both and leaves retatrutide out (https://apps.apple.com/us/app/-/id6499510249), and the FDA says retatrutide and cagrilintide cannot be compounded and warns sellers labelling them "for research purposes" (https://www.fda.gov/drugs/drug-alerts-and-statements/fdas-concerns-unapproved-glp-1-drugs-used-weight-loss). Apple Health offers weekly schedules (https://support.apple.com/guide/iphone/track-your-medications-iph811670c81/ios).
- Semaglutide starts on Weekly and switches to Daily in one tap, because the same tracker names daily oral doses.
- Birth Control is a daily pill many women take: NCHS Data Brief 539 reports pill use at 16.8% among US women aged 20 to 29, as their contraceptive method (https://www.cdc.gov/nchs/products/databriefs/db539.htm). It balances Finasteride and keeps the grid neutral. (The plan called it "the most-used daily pill", which the data brief does not say.)
- Weekly saves as a one-day Days set, so the file format does not change; missed-day, streak and nudge logic is unchanged tonight.

Agents through Shortcuts (SPEC 3.7)
- App Intents that return values are the on-device route shipping apps use: Things' Find Items and Get Item (https://www.macstories.net/reviews/things-3-17-overhauls-the-apps-shortcuts-actions/), Claude's "Ask Claude" action (https://support.claude.com/en/articles/10263469-use-claude-app-intents-shortcuts-and-widgets-on-ios), and iOS 26 "Use Model" taking app entities (https://developer.apple.com/videos/play/wwdc2025/260/). `ReturnsValue` is iOS 16 (https://developer.apple.com/documentation/appintents/returnsvalue) and `EnumerableEntityQuery` iOS 17 (https://developer.apple.com/documentation/appintents/enumerableentityquery). Data processed only on the device is not collected (https://developer.apple.com/app-store/app-privacy-details/), so the label stays Data Not Collected.

Contracts and store copy
- Apple allows one app version submission under review per platform at a time (https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/overview-of-submitting-for-review), so 1.1 goes in only after 1.0 leaves review, and its What's New lists only what merged.
- docs/ (the public support site) is unchanged tonight: 1.1 is not in the App Store and publishing public copy needs Tom's yes. The proposed copy is below.

### Where this differs from what Tom said (one line each)
- Transcription and sorting: Apple's on-device model with a grounded prompt and code checks, not a cloud model, because Apple's guidance is on-device first and a cloud model would break "Nothing you say is sent anywhere".
- Business to-dos: the list is named Work, because Personal and Work are Apple's own default Focus names and Sunsama uses #work and #personal.
- Female and male toggle: none, because Apple's HIG says to avoid unnecessary references to specific genders, including in glyphs, and that colours carry culture-specific meanings (https://developer.apple.com/design/human-interface-guidelines/inclusion); Birth Control and type-ahead cover it instead.
- Peptides: only Semaglutide and Tirzepatide, because retatrutide is unapproved, cannot be compounded and the leading tracker omits it; the pitch is a weekly dose on the right day, not "peptides".
- An API key for Claude: none, because a key needs a public server of Taken's own and ChatGPT's Apps SDK takes OAuth 2.1 only (https://developers.openai.com/apps-sdk/build/auth); Shortcuts actions on the phone work with Ask Claude and Ask ChatGPT today.
- Over-the-air updates: not possible, because Taken is native Swift, so every change is an App Store build through review, and Android does not exist yet.
- A usage limit: none, because nothing runs on a server of ours, so there is no per-use cost to protect.

### Not built tonight
- Opt-in "Smarter sorting" on Private Cloud Compute (retires a written promise; needs Xcode 27, an entitlement and Tom's call), third-party cloud models (break zero network calls and Data Not Collected), two-pass extraction and custom adapters (only if the eval misses), a review-before-save preview, DictationTranscriber, a per-task list chosen by speech, a configurable or Focus-filtered widget, an All view, the gender toggle, a goal row, research peptides, brand names as chips or metadata, Every N days, iOS 27 App Schemas, a hosted key or MCP server, Apple Health export, Spotlight indexing, accounts and social features.

### Open: needs Tom's iPhone or Tom's call
- Run `taken://todo-eval` from Safari on the internal build; the bar is 11 of 12. If notes fail, compare the model's lines with the saved ones. The new instructions run longer than Apple's "one to three paragraphs", so A/B a shorter version if the eval misses.
- Time a 2-minute ramble against the 15 s sorting limit (`spoken` adds output tokens).
- Check whether SpeechTranscriber finalises punctuated segments ("Order."), and whether names transcribe better at all on iOS 26.
- The custom field on a 6.1 inch iPhone at default and large text, and on an iPhone SE: the slide-in, the keyboard and the rows.
- App Review 2.5.19 ("no hidden, dormant, or undocumented features"): the eval link and the internal Pro unlock are runtime-gated code in the App Store binary. Internal builds share the App Store Connect build list, so submit a build from release.yml, never an internal one. Compiling them out for App Store builds needs a change to the EAS build step, left for Tom.
- A late weekly dose: after a missed injection day there is no nudge, Take all, Siri or widget log, and the streak breaks, though the dose still logs from its ring. Keeping a weekly item pending until it is logged is Tom's call (no dosing windows are encoded).
- Age rating stays 4+ (Apple: medical information is "diagnoses or guidance"; the GLP-1 tracker is 13+). In the UK, keep drug names, "GLP-1", "jab" and "pen" out of metadata, screenshots and ads, and never pair "weekly shot" with weight language (CAP rule 12.12, HMR 2012 reg 284(1)).
- Tom's questions: may a voice note's words ever leave the iPhone (Private Cloud Compute, opt-in, iOS 27)? Will Taken ever run its own server? After TestFlight, does he want a quiet goal row (Hair, Cycle, Pregnancy, Gym, Sleep)? The recommendation for each is not now.

### Proposed support-site copy (not published)
For https://tjbaxter.github.io/taken/ once 1.1 is in the App Store and Tom says yes. No Anthropic or OpenAI logos, and never presented as an integration.

docs/index.html, a new section after "Log it from wherever your hand already is":

> **Use Taken with your AI.**
> Taken's Shortcuts actions hand your day to the assistant you already use, on your iPhone.
> - Ask what is left: in Shortcuts, add "Taken: Did I take it?" and "Taken: Get to-dos", then "Ask Claude" or "Ask ChatGPT" with the prompt "Here is my day: [results]. Tell me what's left."
> - Turn a thought into a to-do: add "Use Model" (On-Device), then "Taken: Add to-do".
>
> Taken never sends your log anywhere. A shortcut you build can. What it sends, and to whom, is up to you.

docs/index.html, the Ask Siri card could add: Say "What's on my to-do list in Taken" to hear your open to-dos.

docs/privacy.html, section 08 (Siri, Shortcuts and widgets), one more line:

> If you use Shortcuts to pass Taken data to another app or AI service, that service's privacy policy applies. Taken itself sends nothing.

docs/privacy.html, section 03, the to-dos line could read: your to-dos: the words of each one, which list it is on (Personal or Work), when it is due if you said, and when you finished it (never the audio of a voice note), and the date of your first voice note.

docs/privacy.html, section 04 could add: To hear names right, Taken gives the on-device speech recognition the names in your stack and its list of common supplements. They stay on your iPhone.
