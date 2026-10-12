# Taken

Did I take it? Know for sure.

Taken is a source of truth for a daily pill and supplement stack. Tap when taken. Look later and see it, with the exact time. No accounts, no ads, no tracking, no network. Everything stays on the iPhone.

- One tap logs a dose from the app, the Home Screen widget, the Lock Screen, Control Center, the evening nudge or Siri.
- Adding a stack needs no typing: quick-pick chips, a frequency, done.
- Daily, 2x and 3x daily, alternate days, or chosen weekdays. A configurable day start keeps a 1 a.m. dose on the right day.
- Five-week log, streak and 30-day adherence. Backfill any day from the log.

The product, design and release contract is [SPEC.md](SPEC.md).

## Layout

| Path | What |
| --- | --- |
| `project.yml` | XcodeGen spec. The `.xcodeproj` is generated, never committed. |
| `Shared/` | Model, day logic, store, intents, reminders. Compiled into the app and the widget extension. |
| `Taken/` | The app: SwiftUI screens, Siri phrases, notification actions, fonts, assets. |
| `TakenWidgets/` | Home and Lock Screen widgets and the Control Center control. |
| `TakenTests/` | Unit tests for day rollover, frequencies, streaks, take all, undo, backfill, CSV, the store and the nudge plan. |
| `scripts/` | CI helpers: Xcode selection, simulator choice, screenshots. |

Data lives in one JSON file in the App Group `group.com.tombaxter.taken`, read and written through `NSFileCoordinator` so the app, widgets, intents and notification actions never overwrite each other.

## CI

`.github/workflows/ci.yml` runs on every push to `main` (docs and brand changes excluded) and on demand. On a `macos-26` runner with Xcode 26 it generates the project, builds, runs the unit tests on an iOS 26 iPhone simulator, and captures App Store screenshots on the iPhone 17 Pro Max simulator with `-demo` data. The PNGs are in the run's `screenshots` artifact.

The app accepts `-demo` (seeded stack and five weeks of history in a temporary store, never the real one) and `-screen today|today-done|add|settings|day` to open straight onto a state.

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

Optional repository variable `ASC_APP_ID`: the app's numeric Apple ID, passed to `altool` so the upload always lands on this app.

Both App IDs need the App Group capability with `group.com.tombaxter.taken`, and both profiles must include it. Expected profile names are `Taken App Store` and `Taken Widgets App Store`; the workflow reads the real names from the installed profiles, so other names also work. Team `F7YRP3B2U8`.

## Licences

Geist and Geist Mono are by Vercel under the SIL Open Font License 1.1 (`Taken/Fonts/OFL.txt`).
