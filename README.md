# Taken

Did I take it? Know for sure.

Taken is a source of truth for a daily pill and supplement stack. Tap when taken. Look later and see it, with the exact time. No accounts, no ads, no tracking, no network calls of its own. Everything stays on the iPhone.

- One tap logs a dose from the app, the Home Screen widget, the Lock Screen, Control Center, the evening nudge or Siri.
- Three tabs (1.1): Today (the stack, one calm progress line, a + beside it), To-do (voice to-dos) and History (five weeks, streak and 30-day adherence; backfill any day). The avatar on each tab opens Profile: a name and a photo if you want them, and every setting.
- Adding a stack needs no typing: quick-pick chips (27, Birth Control, Semaglutide and Tirzepatide among them), how often each is taken, done. Typing is optional: + CUSTOM opens a field pinned under the header with type-ahead over a bundled list of 299 names, typo tolerant ("tum" finds Turmeric), on the iPhone with no lookup.
- Daily, every other day, weekly on a chosen day, 2x and 3x daily, or chosen weekdays. A wake-up time keeps a 1 a.m. dose on the right day.
- Voice to-dos (1.1): one tap on the mic, say what needs doing in your own messy words, and Taken turns it into tasks with times, on the iPhone (SpeechAnalyzer or on-device SFSpeechRecognizer, then Apple Foundation Models where Apple Intelligence runs). Siri, the Action button, Control Center, the Lock Screen and the app icon start a note. Code checks every task against the words said and joins one action the model split (a shop or website said after it, a list of things, a lone word), and Keep as one puts a split note back together with one tap. Two lists, Personal and Work, as headed sections of one scrolling list: drag a heading onto the other list to put it on top, and a note goes to the list on top (a chip on the Listening card sends one note to the other). Talk for up to 5 minutes; a long note is sorted in parts while you talk, and whatever the model cannot sort is saved as you said it, so no word is lost. The first note needs nothing; after it, voice to-dos are part of Taken Pro.
- Shortcuts (1.1): "Did I take it?" returns its answer as a value, and "Get to-dos" and "Add to-do" read and add to the list, so a shortcut can hand them to Ask Claude, Ask ChatGPT or Use Model. Taken itself sends nothing.
- Four looks in Profile: Signal (amber on black, the default), Blush (light, rose on warm off-white), Phosphor (green) and Ice (cyan). The widgets, the Control Center control and the app icon follow the look.

- Taken Pro (1.1): the first dose needs nothing; logging after it needs Pro: yearly (7 days on us for new subscribers), monthly or lifetime through StoreKit 2. Everyone whose first download was 1.0 keeps Pro for life. The log, history and CSV export always stay readable.

The product, design and release contract is [SPEC.md](SPEC.md); how Taken makes money is [PRO.md](PRO.md).

## Layout

| Path | What |
| --- | --- |
| `project.yml` | XcodeGen spec. The `.xcodeproj` is generated, never committed. |
| `Shared/` | Model, day logic, store, intents, reminders, the bundled name list and the type-ahead (`Catalog.swift`, `Suggest.swift`), the Taken Pro rule, cache and copy (`Pro.swift`, `ProCopy.swift`), and the looks (`Theme.swift`: every colour, radius and bracket a view or widget draws with, injected through the environment). Compiled into the app and the widget extension. |
| `Taken/` | The app: the tab bar and SwiftUI screens (`Views/`: Today, History, Profile, the sheets), Siri phrases, notification actions, fonts, assets. `Profile/` keeps the optional name and photo on the iPhone. |
| `Taken/Pro/` | StoreKit 2 (`ProStore`) and the paywall. StoreKit runs only in the app; the widgets, control and intents read its cached answer. |
| `Taken/Taken.storekit` | Local StoreKit configuration (three products, the group, the introductory week), set on the scheme's Run action and never bundled. |
| `Taken/Todo/` | Voice to-dos: the To-do tab, on-device speech and the names it listens for (`TodoSpeech.swift`, `TodoVocabulary.swift`), the one list and its headings (`TodoRootView.swift`, `TodoSections.swift`, `TodoModel+Lists.swift`), the Listening card with its list chip (`TodoListeningCard.swift`), long notes cut into parts and sorted one at a time (`TodoChunking.swift`, `NoteSorter.swift`), the Foundation Models sorter and the checks on what it returns (`TodoExtraction.swift`, `TodoFoundationModels.swift`, `TodoGrounding.swift`), the internal builds' sorting eval and voice note log (`TodoEval.swift`, `VoiceNoteLog.swift`), the Shortcuts actions for agents (`TodoAgentIntents.swift`), the Home Screen quick action. The data, store and the New voice to-do intent are `Shared/Todo*.swift`. |
| `TakenWidgets/` | Home and Lock Screen widgets, the Control Center controls (Take all, New voice to-do) and the Lock Screen to-do widget (its faces are in `Shared/TodoWidgetViews.swift`, so the app's widget gallery draws them too). |
| `TakenTests/` | Unit tests for day rollover and the wake-up time, frequencies, streaks, take all, undo, backfill, CSV, the store, the nudge plan, the Taken Pro entitlement rule, the gate, the paywall copy, voice to-dos (the one list and moving a list, the stop rule, every word kept, long notes in parts, sorting, grounding against the words said, due dates, Keep as one, Personal and Work, notifications, the Shortcuts actions, the voice note log), the type-ahead and the catalog, Weekly, and the redesign (a frequency per added item, the profile, the tabs a capture opens, erase). |
| `scripts/` | CI helpers: Xcode selection, simulator choice, screenshots. |

Data lives in one JSON file in the App Group `group.com.tombaxter.taken`, read and written through `NSFileCoordinator` so the app, widgets, intents and notification actions never overwrite each other.

## CI

`.github/workflows/ci.yml` runs on every push to `main` (docs and brand changes excluded) and on demand. On `macos-26` runners with the Xcode in `.xcode-version` (26.6), the same Xcode EAS ships with, it generates the project and, in parallel: builds and runs the unit tests on an iOS 26 iPhone simulator; builds Release for a generic iOS device without signing; and captures App Store screenshots on the iPhone 17 Pro Max simulator with `-demo` data. The PNGs are in the run's `screenshots` artifact.

The app accepts `-demo` (seeded stack, five weeks of history and a demo profile in temporary files, never the real ones) and `-screen today|today-done|add|settings|look|day|log|item` to open straight onto a state (`settings` and `look` open Profile, `log` the History tab, `day` a day sheet over it, `item` the item sheet), and `-theme signal|blush|phosphor|ice` to pick the look; CI captures today, today-done, History, the paywall, the widgets and Profile > Look in every look. `-screen widgets` renders the widget designs in the app for review and `-screen empty` shows first run. `-screen paywall` and `-screen locked` show Taken Pro's paywall and Today without Pro, `-screen settings-locked` Profile without Pro, `-screen paywall-no-yearly` the paywall when the App Store returned every plan but yearly, `-screen widgets-locked` the read-only widgets and `-screen widgets-standby` the small widget as StandBy and CarPlay draw it, on black without its canvas; under `-demo` StoreKit is never called (CI has no App Store account), so the paywall shows StoreKit-shaped demo plans. `-screen todo` shows the To-do tab with demo tasks, Personal on top, `-screen todo-work` the same with Work on top, `-screen todo-work-empty` three open on Personal and nothing on Work (Tom's case), `-screen todo-recording` shows it listening with the words on screen and the list chip, `-screen todo-cap` a note at 4:20 ("0:40 left"), `-screen todo-type` the type sheet with its chip, `-screen todo-empty` its first run, and `-screen widgets-todo` the Lock Screen to-do widget and the Control Center controls. `-screen add-search` opens the Add sheet in type mode with "tum" typed (Turmeric suggested); CI captures it and `todo-work` in every look. The link checks fail the job unless `taken://pro` shows the paywall and `taken://todo` and `taken://todo/record` bring the To-do tab to the front over Profile, and the screen checks unless `-screen todo-work` opens with Work on top (`todoOrder=work,personal todoInto=work`), `todo-work-empty` with Personal on top, `todo-cap` listening, `todo-type` with the type sheet, and `-screen add-search` opens the Add sheet (the demo app writes what is in front to `tmp/taken-ui-state.txt`).

CI cannot run Apple's on-device model, so internal TestFlight builds (the EAS `internal` profile, generated from `project.internal.yml` with the `TAKEN_INTERNAL` compilation condition and the `TakenInternalPro` marker) answer the link `taken://todo-eval`: open it from Safari on the iPhone and 15 fixed notes run through the real sorter (two of them 2 and 5-minute rambles, which pass only if every part sorts in 15 s or less), with the bar at 14 of 15. They also answer `taken://todo-log` and Profile > Internal > Voice note log: what each note heard, how it was cut and what was saved, kept on the iPhone and copied by hand. App Store builds do not contain the eval, the voice note log or the internal Pro unlock (App Review Guideline 2.5.19); `scripts/check-app-store-build.sh` checks the binary of every Release build in CI, release.yml and EAS.

To buy Taken Pro in the simulator, run from Xcode: the scheme's Run action uses `Taken/Taken.storekit`. A copy installed with `simctl` has no StoreKit configuration.

## Release to TestFlight

`.github/workflows/release.yml` runs on demand or on a `v*` tag. It first checks that a green ci.yml run on main covers the code (that commit or an ancestor, with nothing outside docs, brand and Markdown changed since), so nothing ships that the build, the tests and the screenshot link checks have not passed. It archives with manual signing, exports an App Store IPA and uploads it with the App Store Connect API key (`altool`, with `xcodebuild -exportArchive` upload as the fallback). The build number is the run number plus the optional `build_offset` input, so it always increases. A `v1.2.3` tag sets the version to 1.2.3.

Repository secrets (names only, values never go in the repo):

| Secret | Contents |
| --- | --- |
| `ASC_KEY_ID` | App Store Connect API key ID |
| `ASC_ISSUER_ID` | API key issuer ID |
| `ASC_KEY_P8_BASE64` | The `.p8` key, base64 |
| `DIST_CERT_P12_BASE64` | Apple Distribution certificate with private key, `.p12`, base64 |
| `DIST_CERT_PASSWORD` | Password of that `.p12` |
| `PROFILE_APP_BASE64` | App Store profile for `com.tombaxter.taken`, base64 |
| `PROFILE_WIDGETS_BASE64` | App Store profile for `com.tombaxter.taken.widgets`, base64 |

The same project also ships through EAS Build (`eas.json`; `.eas/build/build-ios.yml` for the App Store, `.eas/build/build-ios-internal.yml` for the `internal` profile), which runs `xcodegen generate` and signs with EAS-held credentials for the targets `Taken` and `TakenWidgets`. Internal builds are exported "TestFlight internal testing only", so App Store Connect keeps them for internal testers and never offers them for an App Store version or App Review; `scripts/check-eas-configs.sh` (CI) keeps the two configs' checks the same. `eas.json` names its build image in full (`macos-tahoe-26.5-xcode-26.6`), never an alias such as `latest`, which Expo moves to each new image without notice (it went from Xcode 26.6 to 27.1 on 2026-10-16). `scripts/check-xcode.sh` runs in CI, release.yml and EAS and fails the build unless the active Xcode is the one in `.xcode-version` and the `eas.json` image carries it, and it checks the built app's `DTXcode` and `DTXcodeBuild`, so a TestFlight or App Store build is built by the Xcode CI tested. A new Xcode means changing `.xcode-version`, the image and, if `macos-26` lacks that Xcode, the runner label, in one change. Release signing settings in `project.yml` are plain keys so either path can set them.

`.github/workflows/internal-testflight.yml` (on demand only) builds the internal TestFlight build without an EAS cloud build: after the same "CI passed for this code" gate as release.yml, it runs `eas build -p ios -e internal --local` on the `macos-26` runner with the internal profile's custom steps unchanged, then `eas submit` to TestFlight internal testing. eas-cli is pinned to 24.11.0. It needs the `EXPO_TOKEN` repository secret (an Expo robot token), set on the two eas steps only and never printed, and it has not run yet.

Optional repository variable `ASC_APP_ID`: the app's numeric Apple ID, passed to `altool` so the upload always lands on this app.

Both App IDs need the App Group capability with `group.com.tombaxter.taken`, and both profiles must include it. Expected profile names are `Taken App Store` and `Taken Widgets App Store`; the workflow reads the real names from the installed profiles, so other names also work. Team `F7YRP3B2U8`.

## Licences

Geist and Geist Mono are by Vercel under the SIL Open Font License 1.1 (`Taken/Fonts/OFL.txt`).
