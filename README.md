# Taken

Did I take it? Know for sure.

Taken is a source of truth for a daily pill and supplement stack. Tap when taken. Look later and see it, with the exact time. No accounts, no ads, no tracking, no network calls of its own. Everything stays on the iPhone.

- One tap logs a dose from the app, the Home Screen widget, the Lock Screen, Control Center, the evening nudge or Siri.
- Adding a stack needs no typing: quick-pick chips, a frequency, done.
- Daily, 2x and 3x daily, alternate days, or chosen weekdays. A configurable day start keeps a 1 a.m. dose on the right day.
- Five-week log, streak and 30-day adherence. Backfill any day from the log.
- Voice to-dos (1.1): one tap on the mic, say what needs doing in your own messy words, and Taken turns it into tasks with times, on the iPhone (SpeechAnalyzer or on-device SFSpeechRecognizer, then Apple Foundation Models where Apple Intelligence runs). Siri, the Action button, Control Center, the Lock Screen and the app icon start a note. The first note needs nothing; after it, voice to-dos are part of Taken Pro.
- Four looks in Settings: Signal (amber on black, the default), Blush (light, rose on warm off-white), Phosphor (green) and Ice (cyan). The widgets, the Control Center control and the app icon follow the look.

- Taken Pro (1.1): the first dose needs nothing; logging after it needs Pro: yearly (7 days on us for new subscribers), monthly or lifetime through StoreKit 2. Everyone whose first download was 1.0 keeps Pro for life. The log, history and CSV export always stay readable.

The product, design and release contract is [SPEC.md](SPEC.md); how Taken makes money is [PRO.md](PRO.md).

## Layout

| Path | What |
| --- | --- |
| `project.yml` | XcodeGen spec. The `.xcodeproj` is generated, never committed. |
| `Shared/` | Model, day logic, store, intents, reminders, the Taken Pro rule, cache and copy (`Pro.swift`, `ProCopy.swift`), and the looks (`Theme.swift`: every colour, radius and bracket a view or widget draws with, injected through the environment). Compiled into the app and the widget extension. |
| `Taken/` | The app: SwiftUI screens, Siri phrases, notification actions, fonts, assets. |
| `Taken/Pro/` | StoreKit 2 (`ProStore`) and the paywall. StoreKit runs only in the app; the widgets, control and intents read its cached answer. |
| `Taken/Taken.storekit` | Local StoreKit configuration (three products, the group, the introductory week), set on the scheme's Run action and never bundled. |
| `Taken/Todo/` | Voice to-dos: the To-do tab, on-device speech (`TodoSpeech.swift`), the Foundation Models extractor and the checks on what it returns (`TodoExtraction.swift`, `TodoFoundationModels.swift`), the Home Screen quick action. The data, store and the New voice to-do intent are `Shared/Todo*.swift`. |
| `TakenWidgets/` | Home and Lock Screen widgets, the Control Center controls (Take all, New voice to-do) and the Lock Screen to-do widget. |
| `TakenTests/` | Unit tests for day rollover, frequencies, streaks, take all, undo, backfill, CSV, the store, the nudge plan, the Taken Pro entitlement rule, the gate and the paywall copy. |
| `scripts/` | CI helpers: Xcode selection, simulator choice, screenshots. |

Data lives in one JSON file in the App Group `group.com.tombaxter.taken`, read and written through `NSFileCoordinator` so the app, widgets, intents and notification actions never overwrite each other.

## CI

`.github/workflows/ci.yml` runs on every push to `main` (docs and brand changes excluded) and on demand. On `macos-26` runners with Xcode 26 it generates the project and, in parallel: builds and runs the unit tests on an iOS 26 iPhone simulator; builds Release for a generic iOS device without signing; and captures App Store screenshots on the iPhone 17 Pro Max simulator with `-demo` data. The PNGs are in the run's `screenshots` artifact.

The app accepts `-demo` (seeded stack and five weeks of history in a temporary store, never the real one) and `-screen today|today-done|add|settings|look|day|log` to open straight onto a state, and `-theme signal|blush|phosphor|ice` to pick the look; CI captures today, today-done, the log, the paywall, the widgets and Settings > LOOK in every look. `-screen widgets` renders the widget designs in the app for review and `-screen empty` shows first run. `-screen paywall` and `-screen locked` show Taken Pro's paywall and TODAY without Pro, `-screen settings-locked` Settings without Pro, `-screen paywall-no-yearly` the paywall when the App Store returned every plan but yearly, `-screen widgets-locked` the read-only widgets and `-screen widgets-standby` the small widget as StandBy and CarPlay draw it, on black without its canvas; under `-demo` StoreKit is never called (CI has no App Store account), so the paywall shows StoreKit-shaped demo plans. `-screen todo` shows the To-do tab with demo tasks and `-screen todo-recording` shows it listening, with the words on screen.

To buy Taken Pro in the simulator, run from Xcode: the scheme's Run action uses `Taken/Taken.storekit`. A copy installed with `simctl` has no StoreKit configuration.

## Release to TestFlight

`.github/workflows/release.yml` runs on demand or on a `v*` tag. It archives with manual signing, exports an App Store IPA and uploads it with the App Store Connect API key (`altool`, with `xcodebuild -exportArchive` upload as the fallback). The build number is the run number plus the optional `build_offset` input, so it always increases. A `v1.2.3` tag sets the version to 1.2.3.

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

The same project also ships through EAS Build (`eas.json`, `.eas/build/build-ios.yml`), which runs `xcodegen generate` and signs with EAS-held credentials for the targets `Taken` and `TakenWidgets`. Release signing settings in `project.yml` are plain keys so either path can set them.

Optional repository variable `ASC_APP_ID`: the app's numeric Apple ID, passed to `altool` so the upload always lands on this app.

Both App IDs need the App Group capability with `group.com.tombaxter.taken`, and both profiles must include it. Expected profile names are `Taken App Store` and `Taken Widgets App Store`; the workflow reads the real names from the installed profiles, so other names also work. Team `F7YRP3B2U8`.

## Licences

Geist and Geist Mono are by Vercel under the SIL Open Font License 1.1 (`Taken/Fonts/OFL.txt`).
