# Taken for Android: the build contract (SPEC-ANDROID, v0.1)

Owner: Tom Baxter. Written 25 Oct 2026 on branch `feat/android`, from `main` at `d20e898` (the iPhone 1.1 code in App Review) plus the Today row change on `feat/tap-row-to-log` (`21caeb6`). This file is the contract every Android builder works to. `SPEC.md`, `PRO.md` and `REDESIGN.md` stay the product truth: where this file is silent, the iPhone behaviour is the Android behaviour, translated into Android's own conventions. Where the two apps must differ, this file says how and why.

How decisions are marked:
- **[Source]** a vendor's developer docs, policy page or a shipping app says so; the URL is given.
- **[Own choice]** no source decides it. Kept as small as possible, with the reason.
- **[Tom]** only Tom can decide it. Collected in section 19.

Tom, 25 Oct 2026, verbatim: "it makes no sense that we're not on the Google Play Store as well. So I also want to put Taken on the Google Play Store." And on Today: "I want to open, tap, forget ... you shouldn't have to tap the little circle in the corner ... They want to tap the bar ... to edit the same things ... Maybe a little pen somewhere that puts it in edit mode would be better." And on CI: "apparently you've been using loads of my GitHub minutes ... I'd rather you either build on AWS because we have unlimited AWS credits or you find a better way to do that." Section 15.6 answers the minutes point.

---

## 1. Decisions at a glance

| Topic | Decision | Basis |
| --- | --- | --- |
| Approach | Native Kotlin + Jetpack Compose app in `android/` of this repo. Logic ported by hand to a pure Kotlin `:core` module, with the iPhone's XCTest cases carried over as JUnit tests | [Source] section 2 |
| Package | `com.tombaxter.taken` (same as the iPhone bundle id; permanent on Play) | [Own choice] matches iOS; Play package names "are unique and permanent" https://support.google.com/googleplay/android-developer/answer/9859152 |
| SDK levels | compileSdk 37, targetSdk 36, minSdk 28 | [Source] + [Own choice], section 3.2 |
| UI | Material 3 components, themed entirely from Taken's look tokens and Geist; no dynamic colour, no stock Material palette | [Own choice] keeps the brand, section 6 |
| Today row | Whole row logs; a pencil beside "+" toggles edit mode where a tap opens the item sheet; long-press keeps Undo last dose, Set time (or Open weekday), Edit item | Tom + [Source], section 7.2 |
| Persistence | Typed DataStore 1.2.1 per file, kotlinx-serialization JSON in the iPhone's exact shapes | [Source] section 5 |
| Billing | Play Billing Library 9.1.0; two subscription products (yearly with a 7-day trial offer, monthly) and one one-time lifetime product, all with the iPhone's product ids, because a phone with no server can tell plans apart only by product id; no server; entitlement from the phone's own purchases | [Source] + [Own choice] + [Tom], section 9 |
| Reminders | Inexact `AlarmManager.setWindow` (10-minute window), no exact-alarm permission | [Source] section 10.4 |
| Voice | On-device `SpeechRecognizer` only; the note saved one line per sentence (the iPhone's no-model fallback) on every phone | [Source] section 11 |
| Widgets | Glance 1.2.0 stack widget (rows log in one tap) and to-do capture widget; one Quick Settings tile "Take all"; two static shortcuts | [Source] section 10 |
| CI | GitHub ubuntu-24.04 runners: core tests, app unit tests, Roborazzi JVM screenshots (PNGs uploaded for Tom), lint, release AAB; `android-release.yml` signs the AAB for Play by hand dispatch. No emulator, no Mac | [Source] section 15 |
| iOS CI | `ci.yml` ignores `android/**`; the iOS ship gates exclude `android/**` | [Own choice] section 15.5 |
| Signing | Upload key (RSA 4096, 30 years) made once on the Mac with `openssl` (25 Oct 2026), stored as GitHub Actions secrets through `secret-move.sh`, backed up in the login Keychain; Play App Signing holds the app key; certificate SHA-256 in the appendix | [Source] section 16 |

---

## 2. Approach and why

**Native Kotlin + Jetpack Compose, in `android/` of this repository.** Google calls Compose "Android's recommended modern toolkit for building native UI" (https://developer.android.com/develop/ui/compose). Every Android surface Taken needs has a first-party Kotlin API: Glance widgets, Quick Settings tiles, notifications and alarms, Play Billing, the on-device speech recognizer.

Measured from the repo: about 24.6k lines of Swift. About 9.4k are Foundation-only logic (`Shared/*` minus the widget views, plus `Taken/Todo/TodoGrounding.swift`, `TodoExtraction`, `NoteSorter`, `TodoChunking`); the rest is SwiftUI or Apple-only frameworks (WidgetKit, AppIntents, StoreKit, Speech, FoundationModels, Charts, UserNotifications), none of which has a cross-platform layer. So Android needs its own code for every platform surface under any approach.

Rejected, with sources:
- **Skip** (skip.dev). Its docs say "we do not recommend trying to migrate an existing Xcode project" (https://skip.dev/docs/project-types/); "Complete apps can't yet be built on Linux", so every Android build would need macOS (https://skip.dev/docs/faq/); SkipUI lists no Charts and no widgets (https://github.com/skiptools/skip-ui); SkipMarketplace subscription expiry is "iOS only, Android subscriptions require server verification" (https://skip.dev/docs/modules/skip-marketplace/); Fuse "adds approximately 60 megabytes" (https://skip.dev/docs/modes/).
- **Kotlin Multiplatform.** Swift export is only Alpha in Kotlin 2.4 (https://kotlinlang.org/docs/whatsnew24.html), and sharing logic would put a Kotlin framework into the shipping iPhone app, against SPEC 2's "Apple frameworks only".
- **Swift SDK for Android.** It ships no UI layer; the Kotlin bridge swift-java is pre-1.0 at 0.7.0 (https://github.com/swiftlang/swift-java/releases); it adds a Swift toolchain and the NDK to every Android build (https://www.swift.org/documentation/articles/swift-sdk-for-android-getting-started.html).

Precedent: Bitwarden left a shared codebase for two native apps (https://www.helpnetsecurity.com/2025/01/17/bitwarden-native-mobile-applications/); Google's own reference app Now in Android is Kotlin + Compose with Roborazzi screenshots on Linux CI (https://github.com/android/nowinandroid).

**The real risk is the two apps drifting apart.** It is handled by porting the tests, not by sharing code: every pure rule is ported 1:1 into `:core`, and every iPhone test case that pins it is carried into JUnit with the same name, the same London fixtures and the same expected strings (section 8). Nothing in `Taken/`, `Shared/`, `TakenWidgets/` or `project.yml` changes for Android.

---

## 3. Platform and stack

### 3.1 Versions

The newest stable release at least about two weeks old on 25 Oct 2026. Builders may move to a newer patch at build time under the same rule, and say so in the commit.

| Piece | Version | Source and note |
| --- | --- | --- |
| Kotlin | 2.4.21 (2026-10-08) | https://repo1.maven.org/maven2/org/jetbrains/kotlin/kotlin-gradle-plugin/ . Compose compiler and serialization plugins at the Kotlin version (https://developer.android.com/develop/ui/compose/compiler) |
| Android Gradle Plugin | 9.4.1 (2026-09-18) | Needs Gradle 9.6+ and JDK 17, supports API 37 (https://developer.android.com/build/releases/agp-9-4-0-release-notes). Built-in Kotlin: no `kotlin-android` plugin (https://developer.android.com/build/releases/agp-9-0-0-release-notes) |
| Gradle wrapper | 9.8.1 (2026-10-07) | https://services.gradle.org/versions/all |
| JDK | 17 (Temurin, `actions/setup-java@v6`) | AGP 9.4's minimum |
| Compose BOM | 2026.09.00 (Compose UI 1.12.1, Material3 1.4.0) | https://dl.google.com/dl/android/maven2/androidx/compose/compose-bom/2026.09.00/compose-bom-2026.09.00.pom |
| Navigation | Navigation 3, 1.2.0 (2026-09-23) | https://developer.android.com/guide/navigation/navigation-3 . The back stack is a list Taken owns, which suits three or four tabs, sheets and `taken://` routes |
| Persistence | DataStore 1.2.1 (2026-03-11), kotlinx-serialization-json 1.11.0 | https://developer.android.com/topic/libraries/architecture/datastore . DataStore 1.3.0 (2026-10-21) is too new |
| Billing | `com.android.billingclient:billing-ktx:9.1.0` (2026-06-18) | Version 8+ required since 31 Aug 2026 (https://developer.android.com/google/play/billing/release-notes). Its POM brings Play services (base, basement, location, tasks) and Google's data transport libraries (https://dl.google.com/dl/android/maven2/com/android/billingclient/billing/9.1.0/billing-9.1.0.pom); section 3.3 lists the permissions they add |
| Fragment (a version floor only) | `androidx.fragment:fragment` 1.9.1 (2026-09-23) as a Gradle dependency constraint | Play services under Billing bring Fragment 1.1.0, and the Activity Result API (the photo picker) needs 1.3.0 or later wherever Fragment is present (androidx.activity's lint check `InvalidFragmentVersionForActivityResult`). A constraint raises it without making Fragment a dependency of Taken's own (https://docs.gradle.org/current/userguide/dependency_constraints.html) |
| Widgets | Glance 1.2.0 (2026-08-26) + `glance-appwidget-testing` | https://developer.android.com/jetpack/androidx/releases/glance |
| Unit tests | JUnit 4 + kotlin-test | `:core` runs on the plain JVM, no Robolectric |
| Screenshots | Robolectric 4.17 (2026-09-10) + Roborazzi 1.76.0 (2026-09-29) | https://github.com/robolectric/robolectric/releases/tag/robolectric-4.17 , https://github.com/takahirom/roborazzi . Paparazzi 2.0 and Google's Compose Preview Screenshot Testing are still alpha (https://github.com/cashapp/paparazzi/issues/1979 , https://developer.android.com/studio/preview/compose-screenshot-testing). Roborazzi 1.77.0 (2026-10-22) is too new |
| Dependency injection | None: a manual `AppContainer` in the `Application` | [Own choice] Google documents manual DI (https://developer.android.com/training/dependency-injection/manual) but recommends Hilt "when possible" (https://developer.android.com/training/dependency-injection). Taken's graph is a handful of objects (four stores, a billing client, a scheduler, a clock), and Hilt adds KSP that every AGP upgrade must track. Revisit if the graph grows |

**Dependency rule** [Own choice, mirrors SPEC 2]: AndroidX/Jetpack, Kotlin's own libraries and the Play Billing Library only. No analytics, crash reporting, ads, ML Kit or Firebase SDK, ever: Play's Data safety form counts data "transmitted off device from your app by libraries and/or SDKs" (https://support.google.com/googleplay/android-developer/answer/10787469), and Taken's promise is that nothing is collected. Any new library needs a line in this file saying it sends nothing off the phone.

### 3.2 Identifiers and SDK levels

- `applicationId` and `namespace`: `com.tombaxter.taken`. Debug builds add `.debug` so a debug install never collides with the Play build [Own choice].
- **targetSdk 36.** "Starting August 31, 2026", new apps "must target Android 16 (API level 36) or higher" (https://developer.android.com/google/play/requirements/target-sdk). That makes edge-to-edge and predictive back mandatory and ignores orientation locks on screens 600 dp and wider (https://developer.android.com/about/versions/16/behavior-changes-16).
- **compileSdk 37** (Android 17 is out; Now in Android does the same). Move target to 37 before Play requires it.
- **minSdk 28 (Android 9).** [Own choice] Auto Backup is end-to-end encrypted only from Android 9 (https://developer.android.com/identity/data/autobackup), and section 13's "nothing collected" reading depends on that; Health Connect also starts at 28. It still reaches about 95% of Play devices (https://composables.com/android-distribution-chart). Features with a higher floor are gated at runtime: on-device speech 31, its language check and download 33, notification permission 33, in-app tile request 33, generated widget previews 35.
- **versionName** `1.0.0` for the first Play release [Own choice: Android's own first release, independent of iPhone 1.1], written once, in `app/build.gradle.kts`. **versionCode** = `version_code_offset` (an input of `android-release.yml`, default 1000, never below) + that workflow's run number, so every upload is higher, as Play requires ("each successive release of your app uses a greater value", at most 2100000000, https://developer.android.com/studio/publish/versioning). The run number "begins at 1 for the workflow's first run, and increments with each new run" and "does not change if you re-run the workflow run" (https://docs.github.com/en/actions/reference/workflows-and-actions/contexts#github-context), so the job refuses a re-run: one code never names two different bundles. Run numbers restart only if the workflow file is renamed or recreated; then the offset is raised past the last code used. Every other build is versionCode 1 [Own choice].
- Phones and tablets, any orientation. No orientation lock anywhere: it is ignored at 600 dp and wider anyway, and the layouts must work in landscape [Own choice for phones].

### 3.3 Permissions (the whole list)

The release checks (`android/ci/check-bundle.sh`, in `android.yml` and `android-release.yml`) print the bundle's permissions with the library each came from and fail on anything not in this list until it is reviewed and added here [Own choice].

| Permission | Why | When asked |
| --- | --- | --- |
| `com.android.vending.BILLING` | Play Billing (added by the library) | never asked |
| `POST_NOTIFICATIONS` | nudge, trial reminder, to-do due times | in context only (section 10.4) |
| `RECORD_AUDIO` | voice to-dos | first mic tap |
| `RECEIVE_BOOT_COMPLETED` | reschedule alarms after a restart | never asked; its receiver is enabled only while a reminder is on |
| `INTERNET`, `ACCESS_NETWORK_STATE` | declared by `com.google.android.datatransport:transport-backend-cct` 3.1.8, a compile dependency of the Play Billing Library 9.1.0 (its POM, 3.1), seen in the first merged manifest with Billing (android.yml run 40199849803). Taken's own code makes no network call | never asked (install-time permissions) |

Haptics use `View.performHapticFeedback` (Compose `LocalHapticFeedback`), which needs no permission.

Libraries add a few for their own components, which the first merged manifest will show and this table will then list: Glance runs its actions on WorkManager, whose manifest is expected to declare `WAKE_LOCK`, `ACCESS_NETWORK_STATE` and `FOREGROUND_SERVICE`, and AndroidX Core declares the app's own `com.tombaxter.taken.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION`. None of them is a runtime permission or sends anything off the phone.

Forbidden, checked by CI: `com.google.android.gms.permission.AD_ID` (removed with `tools:node="remove"` as a guard; Play asks every app about the Advertising ID, https://support.google.com/googleplay/android-developer/answer/6048248), `SCHEDULE_EXACT_ALARM`, `USE_EXACT_ALARM` (section 10.4). `INTERNET` was forbidden unless a reviewed library needs it; the Play Billing Library is that library (row above), so it is allowed with its source named, and no other source may add it without a new row here. Not removed with `tools:node="remove"`: no Google source documents doing that to the Billing Library's dependencies [Own choice to ship the library as Google ships it]. The manifest also declares the `<queries>` entry for `android.speech.RecognitionService`, which apps targeting Android 11+ need (https://developer.android.com/reference/android/speech/SpeechRecognizer).

---

## 4. Repository layout, modules and packages

```
android/
  SPEC-ANDROID.md            this file
  settings.gradle.kts        includes :core and :app
  build.gradle.kts
  gradle/libs.versions.toml  every version in section 3.1, nowhere else
  gradle/wrapper/            committed; setup-gradle validates the wrapper checksum
  gradlew, gradlew.bat
  ci/                        check-bundle.sh (the release bundle checks, 15.4) and play-upload.py (the Play upload, 15.4)
  core/                      plain Kotlin/JVM library: no Android dependency at all
    src/main/kotlin/com/tombaxter/taken/core/
      day/        DayKey, DayClock, day(of:) for doses and weigh-ins           (Shared/DayMath.swift)
      model/      Item, Dose, Frequency, eras, pauses, StackSettings, StackState,
                  lenient JSON codecs                                          (Shared/Model.swift)
      stack/      StackEngine, mutations, CSV, Today row rules                 (Shared/StackLogic.swift, AppModel tap rules)
      format/     Fmt                                                          (Shared/Format.swift)
      catalog/    the 299 entries, codes, Suggest, AddPlan, FrequencyChoice    (Shared/Catalog.swift, Suggest.swift)
      retention/  TodayPrompts, repairDay, WeightOffer                         (Shared/Retention.swift)
      pro/        PurchaseFact, ProStatus, Entitlement, ProGate, ProCopy,
                  ProLedger, ProRoute; Play.kt: Play's facts as plain values,
                  PlayCatalog, PlayEntitlement                                 (Shared/Pro.swift, ProCopy.swift)
      reminders/  nudge plan, TrialReminder and TrialAsk, to-do due-time plan  (Shared/Reminders.swift, TrialReminder.swift)
      todo/       TodoState, ordering, TodoText, chunker, NoteSorter, prompt,
                  validation, grounding G1 to G7, merge, fallback lines        (Shared/TodoData.swift, Taken/Todo/*)
      weight/     units, format, parse, trend, window, axis, ticks, goal,
                  moments, readout, change line, import, export, entry rules   (Shared/Weight*.swift)
      theme/      look tokens, radii, contrast maths                           (Shared/Theme.swift)
      demo/       demo stack, to-dos, weigh-ins, seeded LCG                    (Shared/DemoData.swift)
    src/test/kotlin/...      the ported XCTest files, same names (section 8)
  app/                       the Android application
    src/main/kotlin/com/tombaxter/taken/
      TakenApp.kt (Application + AppContainer), MainActivity.kt
      data/       DataStore serializers and stores (taken, pro, todos, weights, profile), photo file
      ui/theme/   TakenTheme: tokens -> MaterialTheme + LocalTakenColors, Geist type, shapes
      ui/shell/   tabs, header with avatar, sheets host, snackbar host, router
      ui/today/ ui/add/ ui/item/ ui/history/ ui/day/ ui/profile/ ui/paywall/ ui/todo/ ui/weight/ ui/components/
      ProSource.kt  what the screens read of Taken Pro; BuildWiring (src/debug, src/release) picks the source
      billing/    BillingGateway (the boundary the tests fake), PlayBilling (the one BillingClient, Play's types to
                  :core's), ProStore (Taken Pro: lifecycle, purchases, acknowledgement, pro.json)
      notify/     channels, alarm scheduler, receivers (alarm, action, boot, time, package replaced)
      widget/     Glance stack widget, to-do widget, callbacks, rollover refresh
      tile/       TakeAllTileService
      voice/      SpeechRecognizer capture, permission flow
    src/main/res/font/       geist_regular/medium/semibold.ttf, geist_mono_regular/medium/semibold.ttf (+ OFL.txt in assets/licenses)
    src/main/res/xml/        shortcuts.xml, widget infos, data_extraction_rules.xml, backup_rules.xml, file_paths.xml
    src/debug/               demo wiring, screen routes for screenshots (never in release)
    src/test/kotlin/...      Robolectric unit tests and Roborazzi screenshot tests
```

Two modules only [Own choice]: `:core` mirrors the iPhone's Foundation-only `Shared/` and runs in seconds on any JVM; everything Android lives in `:app`. Fonts are copied from `Taken/Fonts/` (SIL OFL) with the licence file.

---

## 5. Persistence and the JSON shape

### 5.1 Files and stores

The iPhone keeps one JSON file per concern in its App Group. Android keeps the same files, with the same names and shapes, in the app's private storage through DataStore (`context.dataStoreFile(name)`, so `files/datastore/<name>`):

| File | Type | Android notes |
| --- | --- | --- |
| `taken.json` | `StackState` | the stack, every dose, settings and the look |
| `pro.json` | `ProLedger` | cached Pro answer and paywall bookkeeping; Erase never touches it |
| `todos.json` | `TodoState` | |
| `weights.json` | `WeightState` | |
| `profile.json` | `Profile` | `{"name": "..."}` |
| `profile-photo.jpg` | JPEG in `filesDir` | centre square, at most 600 px, quality 85; replaced whole through `AtomicFile` (https://developer.android.com/reference/androidx/core/util/AtomicFile), one write at a time |

The screen updates at once from a write and the file follows; once no write of the app's is on its way, the screen is set to what the file holds. A save that fails (a full disk) therefore puts the screen back, so a dose that was not saved never shows as taken, as on the iPhone, where a write that fails never reaches the screen (`Taken/AppModel.swift` `write`). A write whose file moved on is replayed onto it, and every new dose or item id is made before the write, so the replay stores the ids the screen and its Undo hold.

[Source] Google: DataStore "is ideal for small datasets", and Room suits "large or complex datasets, partial updates, or referential integrity" (https://developer.android.com/topic/libraries/architecture/datastore). Taken rewrites a small whole state, like the iPhone's "one Codable file, written atomically". DataStore's `updateData` is a transactional read-modify-write, which is what `NSFileCoordinator` gives the iPhone. Android has no App Group: widgets, the tile and notification receivers run in the app's own process, so one DataStore instance per file in `AppContainer` serves them all; DataStore's rule is never more than one instance per file per process (same page). The iPhone's Darwin "didChange" notification becomes the store's `Flow` plus an explicit widget and tile refresh after every write (section 10).

### 5.2 Encoding rules (must match the iPhone)

So that a file, an export or a later "move from iPhone" can cross between the apps [Own choice: costs nothing, and lets the store tests port 1:1]:
- Keys and nesting exactly as `Shared/Model.swift`, `Pro.swift`, `TodoData.swift`, `WeightData.swift` and `WeightGoal.swift` write them; the ported StoreTests, TodoStoreTests and WeightStoreTests pin them. Keys written sorted.
- Dates as **seconds since 1970 as a JSON number**: integral values written without a fraction, others as a double. A custom serializer does this; kotlinx's default `1.76051052E9` style is not used.
- UUIDs as **uppercase hyphenated** strings.
- Optional fields **omitted when absent** (`explicitNulls = false`); settings keys written only when true or only when false exactly as the iPhone does (`nudgeOfferDone`, `widgetInviteDone`, `trialReminderEnabled`, `dayStartHour` always written).
- `Frequency`: `{"kind":"daily","times":1..3}`, `{"kind":"alt"}`, `{"kind":"weekdays","days":[...]}` with **1 = Sunday ... 7 = Saturday**, days written sorted; Weekly is a one-day set.
- `DayKey` as a plain Int ordinal in settings, `{"ordinal": n}` in the weight goal, `"YYYY-MM-DD"` in to-dos, exactly as now.
- `ProPendingAction` as `{"takeAll":{}}` or `{"log":{"_0":"<UUID>"}}`.

Decoding is as lenient as the iPhone's: a bad optional value becomes its default and never costs the file; required item fields missing make the file unreadable; one unreadable to-do never costs the others (lossy array); unknown keys are ignored (`ignoreUnknownKeys = true`). Tests compare parsed JSON trees, not bytes.

**Unreadable file**: the DataStore serializer's `readFrom` runs the lenient decoder; a `CorruptionException` goes to a `ReplaceFileCorruptionHandler` that first copies the raw file to `taken-unreadable-<unix>.json` (and the to-do and weight equivalents) next to it, then starts from the empty default. Never overwritten silently, as on the iPhone. Erase all data deletes the set-aside copies.

**Android-only fields** (the iPhone ignores unknown keys): `pro.json` gains `trialEnds` (`{"<purchaseTimeMillis>": <trialEnd seconds>}`, section 9.4). Nothing else.

**Left out on Android**: `todos.json`'s legacy `area`, `lastArea`, `areaOrder` (iPhone internal builds only); `pro.json`'s founding and legacy meaning (`legacyLog` always written false, and a **missing ledger reads as not legacy**, the opposite of the iPhone's default).

### 5.3 Erase all data

Exactly the iPhone's `AppModel.eraseAll`, `StackState.eraseAll`, `TodoState.eraseAll`, `WeightState.eraseAll` and `ProfileStore.erase`: the stack, doses, settings (except the look, `nudgeOfferDone`, `widgetInviteDone`), to-dos (keeps `firstNoteAt`), weigh-ins, goal, height (keeps `showsTab`, `unit`, `offerAnswered`, `firstWeighInAt`), profile name and photo, set-aside files go; `pro.json` stays. On Android it also cancels every alarm, withdraws every notification, and refreshes widgets and the tile.

### 5.4 Backup

Auto Backup on, through `android:dataExtractionRules` (Android 12+) and `android:fullBackupContent` (Android 11 and lower): include the five JSON files and the photo; exclude caches and set-aside files; `<cloud-backup disableIfNoEncryptionCapabilities="true">` and, for 11 and lower, `requireFlags="clientSideEncryption"`. [Source] backups go to "a private folder in the user's Google Drive", "end-to-end encrypted on devices running Android 9 or higher using the device's PIN, pattern, or password" (https://developer.android.com/identity/data/autobackup). Why this keeps "nothing collected" true is section 13.

---

## 6. Look and feel on Android

### 6.1 Theme: Material 3, Taken's tokens

- `TakenTheme(look)` builds a Material 3 `ColorScheme` from the look's tokens (`Shared/Theme.swift`, ported in `core/theme`): `background`/`surface` = `bg`, `surfaceContainer*` = `bgRaised`/`bgInset`, `onSurface` = `fg`, `onSurfaceVariant` = `fgMuted`, `outline` = `lineStrong`, `outlineVariant` = `line`, `primary` = `signal`, `onPrimary` = `onSignal`, `error` = `danger`, and every other slot set explicitly so no stock Material colour can appear. Roles Material lacks (`signalInk`, `signalEdge`, `signalWash`, `fgSubtle`, `fgFaint`, `button`, `buttonText`, `buttonLamp`, glow strength, the radius scale) live in `LocalTakenColors` and `LocalTakenShapes`. [Own choice]
- **No dynamic colour** (Material You wallpaper colours would override the look). [Own choice]
- Blush is light, Signal, Phosphor and Ice dark, whatever the system setting, as on the iPhone. `enableEdgeToEdge(SystemBarStyle...)` sets light or dark system bar icons per look.
- Typography: Geist Regular, Medium, SemiBold for every word; Geist Mono for times, counts and prices; the Add sheet's chips and the widgets in mono caps with letter spacing. iPhone point sizes become the same `sp` values (Geist SemiBold 34 sp large titles, Geist 17 sp row names, Geist Mono 15 sp times) [Own choice]. Every Material component's text style is overridden through `Typography`.
- Shapes from the look's radius scale (card 14 or 16, half for cells and fields, control for chips).
- Touch feedback: Android's ripple, tinted from `fg` at low alpha, never Material's default [Own choice: the ripple is Android's touch convention].
- Launch: Android 12+ splash screen on `#08090A` with the capsule glyph (https://developer.android.com/develop/ui/views/launch/splash-screen), then a light look fades in over 0.4 s as on the iPhone.
- Never: stock purple, Material's default fonts, FABs, elevation shadows. Surfaces are flat with a 1 px hairline and the soft signal glow on lit elements only (SPEC 4).
- Contrast: the iPhone's AA rules (4.5:1 for `fg`, `fgMuted`, `fgSubtle`, `signalInk`, `danger` on canvas and panels; 3:1 for the check on a lit disc) are ported as unit tests in `core/theme`.

### 6.2 Android conventions Taken follows

- **Navigation**: a Material 3 `NavigationBar` at the bottom on phones with Today (pill), To-do (checklist), History (calendar) and Weight (scale, only while on), using Material Symbols glyphs; navigation bars are for "Three to five destinations of equal importance" on "Compact window sizes" (https://developer.android.com/develop/ui/compose/components/navigation-bar). At 600 dp and wider a `NavigationRail` through `NavigationSuiteScaffold` (https://developer.android.com/develop/ui/compose/layouts/adaptive/build-adaptive-navigation), and content capped at a readable width, centred [Own choice for the width]. CORE builds have two tabs (Today, History) because To-do lands with NEXT 5: that two-item bar is a CORE-only state, below the guidance's three, and no production release ships with it (To-do comes before the store launch, NEXT 8; internal testing tracks are not public). Beside the rail the content pads the bottom system bar inset itself, since the rail pads only its own side.
- **Back**: system back and predictive back. At targetSdk 36 "`onBackPressed` is not called" (behaviour changes page above); Compose uses `BackHandler`/`PredictiveBackHandler`, never for logging or business logic (https://developer.android.com/guide/navigation/custom-back/predictive-back-gesture). Back closes a sheet or dialog, then leaves Today's edit mode, then stops listening (keeping the words, as a tap on the mic would), then from To-do, History or Weight returns to Today, then leaves the app: "the start destination is ... the last screen the user sees when they return to the launcher after pressing the Back button" (https://developer.android.com/guide/navigation/principles).
- **Edge-to-edge**: every screen pads for system bar and IME insets; the Take all dock and the mic dock sit above the navigation bar and the gesture area (https://developer.android.com/develop/ui/compose/system/system-bars).
- **TalkBack**: one node per row with `onClickLabel`/`onLongClickLabel` and `customActions` for anything behind a long-press or swipe (https://developer.android.com/develop/ui/compose/accessibility/api-defaults , https://developer.android.com/develop/ui/compose/accessibility/semantics). Every iPhone VoiceOver label, hint and announcement is reused word for word unless section 6.4 changes it. Touch targets 48 dp minimum (`minimumInteractiveComponentSize()` on custom controls).
- **Font scale**: all text in `sp`, tested at 200%: Android 14+ scales "up to 200%" and "you should still perform UI testing with the maximum font size enabled" (https://developer.android.com/about/versions/14/features).
- **Haptics** (https://developer.android.com/develop/ui/views/haptics/haptic-feedback), all off with Profile's Haptics switch and always subject to the system's touch feedback setting: a take = `CONFIRM` ("a short and light vibration" for a successful action); All taken = `CONFIRM` with the visual moment; long-press = the platform default from `combinedClickable`; chips, menus, looks, ranges = `SEGMENT_TICK`; undo and the times detail = `VIRTUAL_KEY_RELEASE`. [Own choice for the mapping beyond CONFIRM]
- **Motion**: the iPhone's numbers (0.18 to 0.3 s; the ring spring; the 0.3 s look crossfade). Android's "Remove animations" setting scales Compose animations to zero; the row wash still shows as a single frame of colour [Own choice].

### 6.3 Platform equivalents for each iPhone control

| iPhone | Android |
| --- | --- |
| Tab bar | `NavigationBar` / `NavigationRail` |
| Sheet (medium/large) | Material 3 `ModalBottomSheet` (handles predictive back) |
| Profile sheet with its own navigation | A full-screen destination with a top app bar and back arrow; changes save as they are made, no Done [Own choice: Android settings are full screens reached with Up and back] |
| Paywall sheet | Full-screen dialog with a visible close button (section 9.6) |
| Context menu on long-press | `DropdownMenu` anchored to the row |
| Toast with Undo | Taken-styled snackbar in a `SnackbarHost`, action "Undo" (https://developer.android.com/develop/ui/compose/components/snackbar); 4 s, lengthened by `AccessibilityManager.getRecommendedTimeoutMillis` (https://developer.android.com/reference/android/view/accessibility/AccessibilityManager) and kept until dismissed while TalkBack runs, as VoiceOver keeps it on the iPhone |
| Confirm dialog | `AlertDialog` |
| 24-hour time wheel | Material 3 `TimePicker` in a dialog, `is24Hour = true` |
| Date pickers | Material 3 `DatePicker` |
| Toggle | Material 3 `Switch`, token colours |
| Segmented range picker (W, 30D, 90D, Y, All) | `SingleChoiceSegmentedButtonRow` |
| Frequency menu | `ExposedDropdownMenuBox` |
| Swipe left to delete | `SwipeToDismissBox` end-to-start, plus a TalkBack "Delete" action |
| Drag to reorder | Drag handles in a reorder mode, plus TalkBack "Move up" / "Move down" actions [Own choice, no library] |
| PhotosPicker | `ActivityResultContracts.PickVisualMedia`, no media permission (https://developer.android.com/training/data-storage/shared/photopicker) |
| Share sheet for CSV | Android Sharesheet with a `FileProvider` URI (https://developer.android.com/training/sharing/send) |
| File importer | `ActivityResultContracts.OpenDocument` for `text/csv`, `text/tab-separated-values`, `text/plain` (https://developer.android.com/training/data-storage/shared/documents-files) |
| "Open Settings" | `Settings.ACTION_APP_NOTIFICATION_SETTINGS`; the app's details page for the microphone |
| Manage subscription sheet | Play's subscription center link (section 9.6) |

### 6.4 Copy

The iPhone's copy rules apply unchanged and are tested in every copy object: no em or en dash, never the word "free" (not even inside a word), no exclamation mark, sentence case, the weekly and weight wording rules, generic medicine names only. Strings are ported word for word except those that name Apple surfaces. Android wording [Own choice, Tom may edit]:

| iPhone | Android |
| --- | --- |
| "Your log stays on this iPhone. No account, no ads, no tracking." | "Your log stays on this phone. No account, no ads, no tracking." |
| "Everything stays on this iPhone. No accounts. No ads. No tracking." | "Everything stays on this phone. No accounts. No ads. No tracking." |
| "...Kept on this iPhone." (Weight, height) | "...Kept on this phone." |
| Erase: "...your profile from this iPhone. It cannot be undone." | "...your profile from this phone. It cannot be undone." |
| "Log from your Lock Screen: add the Taken widget" | "Log from your home screen: add the Taken widget" |
| "The widgets and the app icon follow it." | "The widgets follow it." |
| Look hint "Applies this look to Taken, its widgets and its icon." | "Applies this look to Taken and its widgets." |
| Paywall subline "Widgets, Lock Screen, Siri." | "Widgets, quick settings, the nudge." |
| Paywall rows "Home Screen, Lock Screen and Control Center", "Siri and the evening nudge" | "Home screen widgets and a quick settings tile", "The evening nudge" |
| "No active Taken Pro on this Apple Account." | "No active Taken Pro on this Google account." |
| "No connection to the App Store. Try again." | "No connection to Google Play. Try again." |
| "The App Store did not finish that. Try again." | "Google Play did not finish that. Try again." |
| "Purchases are turned off on this iPhone." | "Google Play cannot take payments on this phone or account right now." (for `BILLING_UNAVAILABLE` and `FEATURE_NOT_SUPPORTED`, whose causes Google lists as an out-of-date Play Store, an unsupported country, purchases blocked by an admin, or a payment method Play cannot charge, https://developer.android.com/google/play/billing/errors; built 25 Oct 2026, replacing this file's earlier "Purchases are turned off on this phone.", which named one cause of four) |
| "Apple could not verify that purchase. Try Restore." | Not used: the phone has no verification step of its own (section 9.4) |
| Terms "...Cancel anytime in Settings at least 24 hours before renewal." | "...Cancel anytime in Google Play." (section 9.6) |
| Trial reminder "...Cancel at least 24 hours before in Settings > your name > Subscriptions." | "...Cancel before then in Google Play > Subscriptions." Google's own steps: "go to subscriptions in Google Play", then "Cancel subscription" (https://support.google.com/googleplay/answer/7018481); a trial cancelled before its end is not charged (https://developer.android.com/google/play/billing/subscriptions), and Play has no 24-hour rule (built 25 Oct 2026, replacing "...in Google Play, Payments & subscriptions.") |
| Profile > Taken Pro "Restore purchases" and "Redeem code" | No buttons; the footnote "Restore is automatic. Taken checks Google Play for your purchases each time it opens." (section 9.5) |
| Trial ask hint "Shows the iPhone's notification prompt." | "Shows Android's notification prompt." |
| "Voice to-dos need on-device speech recognition, which this iPhone does not have for your language." | "Voice to-dos need on-device speech recognition, which this phone does not have for your language." |
| The three Apple Intelligence sorting notes | Not used; Android shows "Saved as you said it, one line per sentence. Tap one to edit." (section 11) |
| Mic usage string | Rationale text before the system prompt (section 11): "Taken listens only while the mic is on, to turn what you say into to-dos. The audio stays on this phone and is never saved." |

New Android-only copy: the in-app health line in Profile, About (section 14.3); "Pro yearly · not renewing" and "Pro yearly · renewing" in place of a renewal date (section 9.5); the paywall's "Logging needs Taken Pro after your first dose. Your record stays readable without it." (section 9.6); Profile's "Restore is automatic. Taken checks Google Play for your purchases each time it opens." (section 9.5). All of it lives in `ProCopy` and `TrialReminder`, whose tests check the copy rules.

---

## 7. Screens, iOS to Android

### 7.1 The map

Every screen keeps its content, order, copy and rules from SPEC 3 and its Swift views (named in the first column). This table gives only the Android form.

| iPhone screen (Swift home) | Android form | Phase |
| --- | --- | --- |
| Shell: tabs, avatar top right, sheets from the root, links, 20 s ticker, foreground refresh (`TakenApp`, `AppModel`, `RootView`) | `MainActivity` with one Compose tree; tab header (large Geist title, subtitle, avatar `IconButton` 48 dp, TalkBack "Profile and settings"); one sheet at a time from the root; `taken://` routes on an intent filter, parsed by the ported `ProRoute`/`TodoCaptureRoute`; refresh on `ON_START` (reload stores, Pro, reschedule, widget check, pending log offer, intro paywall); a 20 s ticker while started | CORE; Pro parts built in NEXT 2 (Play asked on `ON_START` and `ON_RESUME`, the pending log offer, the intro paywall) |
| Today, first run (`EmptyStackView`) | Same card and "Add to stack" | CORE |
| Today with a stack (`TodayView`, `ProgressSummary`, `ItemRow`, `TodayPromptRow`, `BottomDock`) | Section 7.2 | CORE (quiet rows partly NEXT) |
| Add sheet (`AddSheet.swift`) | Full-height `ModalBottomSheet`: chip grid (`FlowRow`), `+ CUSTOM` type mode with the field pinned under the header, type-ahead rows sized by `rowCapacity`, How often rows with frequency menus and weekday toggles, Add bar above the IME | CORE |
| Item sheet (`ItemEditorView`) | `ModalBottomSheet` from Today; a pushed screen from Profile's Stack list; Name, How often, Archive, Delete item with its `AlertDialog`; saves on close | CORE |
| Set time sheet | `ModalBottomSheet` with the title, subtitle and a 24-hour `TimePicker` (input mode), "Set to 07:42" / "Log at 07:42" / disabled "That time is still to come" | CORE |
| History (`HistoryView`, `HistoryGrid`) | Same: two stat cards, the 5 x 7 grid (cells are buttons with the iPhone's TalkBack labels), the two lines (Android wording) | CORE |
| Day sheet (`DaySheet`) | `ModalBottomSheet`: Log at row with a time dialog, items with dose chips (tap: remove confirm) and "+ 08:00" | CORE |
| Profile (`ProfileView`) | Full-screen destination; sections in the iPhone's order. CORE: header (photo, name, streak line), Stack (reorder, archive, delete), Look, Your day, Feel, Data (Export CSV, Erase all data), About. NEXT 2 (built): Taken Pro between Feel and Data (9.5). NEXT: Reminder, Weight, Export/Import weight CSV, "Add the Take all tile" (Android 13+, section 10.2) | CORE + NEXT |
| Look picker | Four live swatches side by side; tap recolours the app with a 0.3 s crossfade and refreshes widgets | CORE |
| Paywall, intro paywall | Section 9.6: a full-screen dialog, edge to edge, its bar icons following the look | NEXT 2, built |
| Trial ask | Section 10.4, from the seam in 9.7 | NEXT 3 |
| Widget help sheet | Not built: Android's launcher shows its own pin dialog (section 10.1) | |
| To-do tab, edit and type sheets | Section 11 | NEXT |
| Weight tab and its sheets | Section 12 | NEXT |
| Internal tools (eval, voice note log) | Left out | |

### 7.2 Today: the row (from day one)

Tom asked for "open, tap, forget". The iPhone ships it on `feat/tap-row-to-log` (REDESIGN.md, "Tap the row to log", 2026-10-25, with its sources). Android ships the same behaviour from its first build.

**A tap anywhere on a Stack or Not today row** does what the ring did, through the ported rule `AppModel.tap`:
- pending, an open week, or a Not today row with nothing logged: **log a dose now** (`requirePro`: when locked, the paywall, and the dose is logged once Pro is on). `CONFIRM` haptic; the ring fills; the snackbar "<Name> taken at 07:42" with Undo for 4 s; TalkBack announces "<Name> taken at 7:42 AM.".
- otherwise (everything due is taken, a weekly row logged for its week outside the early window): **never un-takes**; a soft haptic toggles the times detail ("Taken at 07:42 · 9h 12m ago").
- **The logging moment** plays on the tapped row only (not for Take all, a widget, the tile or Set time): the row washes in `signalWash` (in 0.1 s, out over 0.6 s) and the ring lifts to 1.12 and settles on the ring's spring; the `CONFIRM` haptic. With animations removed, the wash only.
- Implementation [Source]: one `Modifier.combinedClickable(onClick = tap, onClickLabel = ..., onLongClick = openMenu, onLongClickLabel = "Options")` over the whole row, so the long-press haptic and TalkBack's "double tap and hold" come from the platform (https://developer.android.com/develop/ui/compose/touch-input/pointer-input/tap-and-press , https://developer.android.com/develop/ui/compose/accessibility/api-defaults). A drag that starts on a row scrolls the list and logs nothing (the scroll consumes the gesture before the click fires); a Robolectric test pins it.
- The guard against a mistaken tap is the snackbar's Undo and Undo last dose in the menu, never a confirmation or a hold (REDESIGN.md cites NN/g, https://www.nngroup.com/articles/confirmation-dialog/).

**The pencil** beside the Stack title's "+" puts the stack in edit mode.
- An `IconButton` (48 dp target, its own space before the "+") with the Material Symbols **edit** glyph (https://fonts.google.com/icons?selected=Material+Symbols+Outlined:edit), wrapped in a `TooltipBox` with a `PlainTooltip` "Edit stack" ("Plain tooltips: Describe elements or actions of icon buttons", https://developer.android.com/develop/ui/compose/components/tooltip). While editing it shows the **check** glyph, tooltip and label "Done". Colour `signalInk`. TalkBack hints, the iPhone's: "Then a tap on an item opens it instead of logging it." and "A tap on an item logs it again."
- Why a pencil on Android when the iPhone shows the word "Edit": Apple's HIG says edit is not well represented by a symbol, so the iPhone uses a word; Material's symbol set has an Edit glyph, and Android apps use the pencil for edit (Google Contacts' "Edit (pencil icon)", https://wartburg.teamdynamix.com/TDClient/123/Portal/KB/ArticleDet?ID=8038). Tom asked for "a little pen". [Source + Tom]
- **In edit mode**: a row's tap opens the item sheet and never logs; a chevron (`chevron_right`, 14 dp, `fgSubtle`) cross-fades in where the time and ring were; an open times detail closes; Take all steps aside; the snackbar stays; the row's `onClickLabel` is "Edit <Name>" and its hint "Double tap to edit.". Closing an item sheet keeps edit mode, so several items can be edited in a row.
- **Edit mode ends** on the check, on any tab change, when Taken goes to the background (`ON_STOP` that is not a configuration change: a rotation, fold or resize also stops the activity, and `isChangingConfigurations` tells them apart, https://developer.android.com/reference/android/app/Activity#isChangingConfigurations()), when the stack empties, and on system back (Android only, [Source] the back order in 6.2). Locked mode does not change it: the item sheet always opens. What a sheet holds (the Add sheet's picks, the item sheet's draft) is kept across a configuration change with `rememberSaveable` (https://developer.android.com/develop/ui/compose/state-saving).

**Long-press** keeps the menu, in order: **Undo last dose** (disabled with no dose), **Set time…** (when the row's last dose was logged today, or it has none and the row is today's) or **Open <Weekday>**, **Edit item**. The same three are the row's TalkBack `customActions` ("Undo last dose", "Set time" or "Open <Weekday>", "Edit item").

**TalkBack on the row**: one node; label as the iPhone's `ItemRowView.accessibilityLabel` ("Vitamin D3, taken at 7:42 AM." and the other forms); `onClickLabel` "Log <Name>" (pending), "Show times" (taken), "See Taken Pro plans" (locked), "Edit <Name>" (edit mode).

The rest of Today is SPEC 3.1 unchanged: the title and long day; the progress line and the All taken moment (the check springs in with `CONFIRM`); the locked bar; at most one quiet row (section 8.1 rules; Android wording); "Stack" with the pencil and "+"; the Stack card; Not today; the bottom dock with the snackbar and **Take all** (2 or more quick-loggable rows, the count in Geist Mono, one tap logs them all at one moment, Undo removes all).

---

## 8. Business rules ported 1:1, and the tests that carry them

### 8.1 What is ported

Into `:core`, translated line for line from the Swift named, with the Swift kept as the truth when they disagree. SPEC 3.3, 3.8 and the doc comments in each Swift file describe each rule in full.

1. **DayKey and DayClock** (`DayMath.swift`): ordinals from 1970-01-01 by Hinnant's `days_from_civil`; weekday 1 = Sunday; `mondayIndex`; the day start = wake-up minus 4 h, clamped 0 to 12; `day(for:)`, `start/end(of:)`, `nextRollover`, `date(on:hour:minute:)`; `day(of: dose)` at the dose's own UTC offset. Kotlin uses `java.time` (`ZonedDateTime`, `ZoneId`, `ZoneOffset`), `en_US_POSIX`-equivalent `Locale.ROOT` for parsing.
2. **Settings rules**: `dayStartHour(forWake:)`, `wakeMinutes(forDayStartHour:)`, nudge time default wake + 13 h, backfill wake + 1 h, `setReminder` answers the offer.
3. **StackEngine**: eras, pauses, active and due rules, alternate days, R1 credit (a, b with its 1 to 3 days, c), R2 open week, `weekRow`, `takesEarlyDose`, R3 quick paths, `itemDay`, `DaySummary` and its statuses, `todaySummary`, `sheetSummary`, the 3600 s repeat guard (`canQuickLog`, `quickLogRows`, `quickLogResumes`), `nextDueDay`, the streak, the 30-day % (floor, today counts only what is taken), the 5-week grid, `loggedAnything`.
4. **Mutations and CSV**: add, update (eras), archive and pauses, delete, reorder, `logDose` with the zone's offset, `logActiveDose`, `logNextDoseIfPending`, `takeAllPending`, `removeDoses`, `undoLastDose`, `setDoseTime`, `restore`, `eraseAll`; CSV `date,time,item,code`, oldest first, current zone, RFC 4180 quoting, `\n` and a trailing newline, `taken-log.csv`.
5. **Today's tap rules** (`AppModel.tap`, `notTodayRow`, `offersSetTime`, `setTimeDose`, `takeAllCount`, the edit-mode rule): pure functions in `core/stack`, so the row behaviour is unit tested without a UI.
6. **Fmt**: every function in `Shared/Format.swift`, 24-hour times on screen whatever the locale; spoken times in the locale's short style with narrow and no-break spaces made plain.
7. **Catalog** (the 299 entries copied as data), `lookupKey`, `entry(named:)`, `entry(matching:)`, `sanitizeCode`, `code(for:)`, `derivedCode`; **Suggest** (folding, tiers 0 to 3, `prefixDistance` with transpositions, typo budget, ordering, `literal`, `rows`, `firstPick`, `segments`, `rowCapacity`); **AddPlan** and `FrequencyChoice`.
8. **Today's one quiet row** (`TodayPrompts.pick` order, `repairDay`, the widget invite day rules, `WeightOffer.shows`). Android's widget check reads Taken's placed home-screen widgets (section 10.1) where the iPhone reads Lock Screen families.
9. **Pro** (`ProGate.access` and its tests in CORE, so locked mode can be built against a fake status; the rest built in NEXT 2, plus `Play.kt`, the Android facts, section 9.4): `PurchaseFact`, `ProStatus` (`activeUntil`, `isActive`, `awaitingRenewal`, `lapsedRenewal`), `Entitlement.evaluate` and `next` (founding paths removed), `ProGate.access` (without the internal and legacy steps), `allowsLogging`, `nudgeWindow`, `requirePro` decisions, the intro paywall rule, the pending log (10 minutes, not more than 60 s ahead), `ProCopy` (every function in `Shared/ProCopy.swift`, prices from Play's `formattedPrice` and micros), `ProRoute`.
10. **Trial** (built in NEXT 2): `TrialReminder` (`LEAD_DAYS` 3, `fireDate`, `plan`, `planFor`, `body`, `nextMark`, `notice`, `isRenewingTrial`), `TrialAsk.shows` (Android meaning: notification permission not yet granted and the system prompt still available) and its words.
11. **Reminders** (NEXT): `Reminders.plan` (14 days, ids `taken.nudge.day.<ordinal>`, bodies "2 pending: VD3, FSH", "+<rest>" after 4), `nudgeDay`, `isCurrent`, `staleDelivered`, `staleBody`; `TodoNotifications.plan` (open tasks with a time to come, soonest first, at most 30, body "Due 16:00").
12. **To-do** (NEXT): `TodoState` operations (`replaceNote`, `mergeNote`, complete, reopen, update, delete, restore, prune at 30 days), `TodoOrdering`, `TodoText` (`dueParts`, `dueLabel`, `isOverdue`, `spokenDue`, `clean`, `cleanKeepingLength`), `TodoGate`, `TodoChunker`, `NoteSorter` (the actor becomes a coroutine-confined class with the same budgets), `TodoPrompt` (instructions verbatim), `TodoValidation` (`validate`, `assemble`, `lines`, `asSaid`, `parseDue`, `nextOccurrence`), `TodoGrounding` G1 to G7 with every word list verbatim, `TodoMerge` (Keep as one), the capture timing rules (`shouldStop`: 300 s cap, 30 s quiet, the "1 minute left" mark at 240 s; level maths), `TodoCaptureRoute` (90 s), `TranscriptionVocabulary`, the transcript join rules of `RecognizerTranscript` (section 11).
13. **Weight** (NEXT): units and exact lb conversion, `WeightFormat` (parse, sanitize, locale), the Hacker's Diet trend, window, axis, ticks, change and change line, goal (start day, direction band 0.68 kg, BMI floor, moments, readout, `fresh`), height units, `WeightEntry` rules, CSV export and import, `WeightGate`, the care rules for copy.
14. **Theme tokens and contrast**; **DemoData** (the seeded LCG `state × 6364136223846793005 + 1442695040888963407`, output `state >> 33`) for screenshots; **Profile** name rules and initials.

### 8.2 The tests carried over

The iPhone has 28 XCTest files plus `TestSupport.swift` on `main` (408 test functions), and `TodayRowTests.swift` (9) on `feat/tap-row-to-log`. Each becomes a JUnit class of the same name in `core/src/test` (pure cases) or `app/src/test` (Robolectric cases), each `testX` keeping its name. Fixtures port as they are: **Europe/London**, `londonClock(dayStartHour = 4)`, `at(y, m, d, h, min)`, Mon 12 Oct 2026, Thu 15 and Thu 22 Oct 2026, the to-do eval context Mon 19 Oct 2026 10:00 London, the trial fixture Wed 28 Oct 2026 09:14 to Wed 4 Nov 09:14. The expected strings and numbers carry over unchanged; that is the point.

| XCTest file | Android | Phase |
| --- | --- | --- |
| DayLogicTests | port all (Siri sentence case kept as a pure test of `SiriAnswers` text even though no Siri surface ships, since the nudge and widget share the rules) | CORE |
| WeeklyWeekTests | port all | CORE |
| RedesignTests | port pure cases; the voice to-do and nudge-opening cases adapt to Android routing | CORE/NEXT |
| RetentionTests | port; the Lock Screen widget check adapts to the home-screen widget check; demo case adapts | CORE |
| TodayRowTests (tap-row branch) | port all 9: a row tap logs and plays the moment on that row only; a taken row shows its times; Not today logs the same way; Take all plays no row moment; a locked row opens the paywall; edit mode opens the item sheet and never logs; edit mode ends on leaving Today, background and an empty stack (plus back on Android); the edit screen route; TalkBack labels and hints | CORE |
| StoreTests | port; concurrency becomes DataStore's single-writer guarantee; set-aside file test kept | CORE |
| ThemeTests | port tokens, round trip, erase keeps the look, contrast; leave out icons and StandBy | CORE |
| SuggestTests, CatalogTests | port all | CORE |
| DemoDataTests | adapt (the same demo sets, read by debug screenshot code) | CORE |
| ProGateTests | port, minus `testALogFrom10IsNeverLockedOnAGuess` (legacy) | CORE |
| EntitlementTests | adapt to Play's facts (section 9.4); founding, sandbox and TestFlight cases left out; "what a check keeps" asks whether Play answered | NEXT 2, built |
| ProCopyTests | port all, Android copy where 6.4 changes it; the status lines rewritten for no period end on the phone (9.5) | NEXT 2, built |
| TrialReminderTests | port the rules and words; the ask's orchestration around sheets and voice notes goes with the Reminders phase | NEXT 2, built |
| (Android only) PlayBillingRulesTests, ProStoreTests, PaywallTests | Play's facts in every state, the store over a fake billing client, the paywall on screen (9.8) | NEXT 2, built |
| ReminderPlanTests | port all | NEXT |
| TodoStoreTests, TodoGroundingTests, TodoChunkingTests, NoteSorterTests | port all (the model is a canned `ChunkSorting`) | NEXT |
| TodoExtractionTests | port; the Apple Intelligence lines and Info.plist strings left out | NEXT |
| TodoModelTests | port; voice note log cases left out | NEXT |
| TodoOneListTests | keep the one-list behaviour cases; legacy list files left out | NEXT |
| RecognizerTranscriptTests | port the join rules (section 11 uses them on API 31 and 32) | NEXT |
| AgentIntentTests | port only the sentences that a surface still uses; Siri and Shortcuts left out | NEXT |
| WeightTests, WeightGoalTests, WeightEntryTests, WeightStoreTests | port all; demo screens adapt | NEXT |
| VoiceNoteLogTests | left out | |

A unit test that would need an iPhone-only fact (StoreKit's expiry, App Intents metadata) is rewritten against the Android fact, and the commit says which.

---

## 9. Taken Pro on Google Play Billing

Built on `feat/android-pro` (NEXT 2, 25 Oct 2026). Where the build differs from this file's first draft, the text below says so and why.

### 9.1 What stays

PRO.md's model, unchanged: the whole app for everyone, the first dose ever needs no Pro, then a hard paywall for logging (one automatic showing, 1.5 s after the first dose, never again on its own), no ads ever, the record never held hostage (reading, undo, removing doses, the item and day sheets, CSV exports, to-do completion and editing, the Weight chart: never gated). Yearly $19.99 with 7 days on us for new customers (the default), monthly $3.99, lifetime $49.99. Prices, periods and the offer are always read from Play, never written in the app. Founding members do not exist on Android.

### 9.2 Products in Play Console

[Source] facts: product ids "must start with a number or lowercase letter", may use lowercase letters, digits, underscores and periods; base plan and offer ids use lowercase letters, numbers and hyphens; a free trial "must be between 3 days and 3 years"; an offer's eligibility is "New customer acquisition" ("Never had this subscription" or "Never had any subscription"), "Upgrade" or "Developer determined" (https://support.google.com/googleplay/android-developer/answer/140504). A one-time product's buy purchase option should be "legacy compatible" for Billing 7 and older (https://developer.android.com/google/play/billing/one-time-product-multi-purchase-options-offers). Products can be created only after a build with the Billing Library is on a track (https://developer.android.com/google/play/billing/getting-ready).

| Play object | Id | Setup |
| --- | --- | --- |
| Subscription | `com.tombaxter.taken.pro.yearly` | base plan `yearly`, auto-renewing, 1 year, US$19.99 (other countries from Play's conversion); offer `trial-7d`: "New customer acquisition", "Never had any subscription", one free trial phase of 7 days |
| Subscription | `com.tombaxter.taken.pro.monthly` | base plan `monthly`, auto-renewing, 1 month, US$3.99, no offer |
| One-time product | `com.tombaxter.taken.pro.lifetime` | non-consumable, buy purchase option `lifetime`, legacy compatible, US$49.99 |

Subscription settings: "Allow one free trial per app" checked, which "restricts the user to getting one free trial per app" (https://developer.android.com/google/play/billing/subscriptions). With "Never had any subscription" it matches Apple's rule that the introductory week is for someone new to the whole subscription group (PRO.md). Grace period and account hold stay at Play's defaults: account hold is "60 days minus any grace period duration" (https://support.google.com/googleplay/android-developer/answer/12154973). The step-by-step for the Console is the `play_console_setup` list returned with NEXT 2.

**Two subscription products, not one with two base plans** [Source facts, Own choice for the decision]. Google's own model puts billing periods as base plans of one subscription: its help article's example has monthly and annual base plans under one "Premium Membership" subscription, and separate subscriptions for different benefits (https://support.google.com/googleplay/android-developer/answer/12154973). That model needs a server to read: a `Purchase` on the phone gives its product ids and nothing about the base plan, offer, expiry or trial phase (https://developer.android.com/reference/com/android/billingclient/api/Purchase); those come only from the Play Developer API's `purchases.subscriptionsv2`, which "is considered the source of truth" and runs on a backend (https://developer.android.com/google/play/billing/lifecycle/subscriptions). Taken has no server (19, item 3). With one subscription and two base plans the phone could not tell yearly from monthly, so it could not name the plan in Profile or the price the trial reminder must state. With one product per plan, the product id is the plan, as on the iPhone, and the ids are the iPhone's. Shipping client-side apps do the same: Tasks.org's open-source Google Play build sells one subscription product per period and reads the period from the product id on the phone (https://github.com/tasks/tasks/blob/main/kmp/src/commonMain/kotlin/org/tasks/billing/SubscriptionSkus.kt). What it costs: Play treats yearly and monthly as two subscriptions, so the trial's eligibility and the one-trial setting above keep one trial per person; and a change between them is a cancel and a new purchase, not Play's in-place plan change. The paywall never sells to someone who holds Pro, and a purchase started while a subscription is held asks Play again and turns Pro on instead of selling a second one, so the replacement parameters this file's first draft planned (`SubscriptionProductReplacementParams`) are not used [Own choice].

### 9.3 The billing client

As Google documents it (https://developer.android.com/google/play/billing/integrate), in `billing/PlayBilling.kt` and `billing/ProStore.kt`:
- One `BillingClient` per process, `enablePendingPurchases(PendingPurchasesParams...enableOneTimeProducts())`, `enableAutoServiceReconnection()`, which Google "strongly recommends"; `onBillingServiceDisconnected` only records the state, and a call made while disconnected reconnects by itself.
- **Connect** at `ON_START` ("when your app is launched or comes to the foreground"). A first connection that fails with a retriable code (`SERVICE_UNAVAILABLE`, `SERVICE_DISCONNECTED`, `ERROR`, `NETWORK_ERROR`) is tried again with Google's own simple retry, 3 tries 2 s apart (the `connectWithRetry` sample, https://developer.android.com/google/play/billing/errors); `BILLING_UNAVAILABLE` is never retried by itself ("Automatic retries are unlikely to help", same page).
- **`queryPurchasesAsync`** for subscriptions and one-time products after connecting and on every `ON_RESUME` ("call queryPurchasesAsync() in your app's onResume() method"). The answer counts as Play's only when both come back OK. Calls made together share one question.
- **`queryProductDetailsAsync`** for the three products when Taken starts (so Today's locked bar can say "Start 7 days on us") and each time the paywall opens (Google: caching `ProductDetails` "is not recommended, as stale objects can cause launchBillingFlow() failures"). It returns "a maximum of 50 user eligible offers per subscription", so **the trial offer coming back means the person may have it**. A plan that does not come back is "--" on the paywall and cannot be chosen.
- **`launchBillingFlow`** with the chosen plan's offer token: the trial offer's while Play returns it, else the base plan's; for the lifetime, its purchase option's token ("you must set the offer token corresponding to the offer selected by the user", one-time products page above).
- **`PurchasesUpdatedListener`**: each purchase flow's result, and purchases that finish while Taken runs (a pending one approved). `USER_CANCELED` says nothing; `ITEM_ALREADY_OWNED` asks Play again ("call queryPurchasesAsync()", errors page) and turns Pro on.
- **Grant only PURCHASED**; a `PENDING` purchase grants nothing and is never acknowledged ("Only grant entitlement when the purchase transitions from PENDING to PURCHASED", integrate page). The paywall says "Waiting for approval. Taken Pro turns on as soon as it goes through." and so does Profile.
- **Acknowledge** every PURCHASED purchase of Taken's that is not acknowledged, right away and on every query, retrying with Google's exponential backoff (2 s then 4 s, 3 tries, the acknowledgement sample on the errors page): within three days or it is "automatically refunded and entitlement revoked". Never consume the lifetime.
- **Refunds and revocations**: a refunded and revoked purchase, an expired subscription and one on account hold are no longer returned (lifecycle page above), so the next answer locks; pro.json follows, so widgets and the tile lock too.
- **In-app messages**: `showInAppMessages` with the transactional category each time Taken opens, so Play shows its own snackbar about a declined payment with a link to fix it ("We recommend that you call this API whenever the user opens the app", https://developer.android.com/google/play/billing/subscriptions).
- **Waiting for Play**: at most 4 s (the iPhone's) before the cached answer stands; a cached subscription answer that has run out (9.4) waits for Play on every return before anything locks, so a payer never sees a lock on a guess.
- **Which source** [Own choice]: release builds, and so every build on Play, use `ProStore` over `PlayBilling` (`src/release/.../BuildWiring.kt`). Debug builds carry the `.debug` package, which Play sells nothing to, so they read Pro as on (`ProSource.untilBilling`, `src/debug`); the tests drive the real `ProStore` through a fake `BillingGateway`.
- Response codes map to the copy in 6.4: `SERVICE_UNAVAILABLE`, `NETWORK_ERROR`, `SERVICE_DISCONNECTED` to "No connection to Google Play. Try again."; `BILLING_UNAVAILABLE`, `FEATURE_NOT_SUPPORTED` to "Google Play cannot take payments on this phone or account right now."; `ITEM_UNAVAILABLE` to "Taken Pro is not sold in this country yet."; `USER_CANCELED` to nothing; anything else to "Google Play did not finish that. Try again." [Own choice for the words]
- Receivers (widget callbacks, notification actions, the tile) read pro.json; their one recheck before refusing a log (the iPhone's `mayLog`) belongs to NEXT 3 and 4, which can call `ProSource.refresh()` inside `goAsync()`'s time.

### 9.4 From Play's facts to the ported rule

`core/pro/Play.kt` copies Play's `Purchase` and `ProductDetails` into plain values, and `PlayEntitlement.facts` turns the purchases into the iPhone's `PurchaseFact`s, which the ported `Entitlement.evaluate` (founding removed) works out exactly as on the iPhone:

- **Lifetime** `PURCHASED` becomes `{isPro, reason: lifetime}`, for good; a subscription still renewing next to it is noted for Profile.
- **Subscription** returned by the query: Play's documented behaviour is that a cancelled subscription "is still returned" until it expires, one in grace period is returned, one on account hold or paused is not (lifecycle page). So: `isPro`, `reason` from the product id, `willRenew = isAutoRenewing()`, `billingIssue` false (grace is invisible on the phone and grants access anyway), `plan` from the product id, and `renewsTo` from the purchase's `PendingPurchaseUpdate` when a change waits for the renewal.
- **Period end is unknown on the phone** (no expiry in `Purchase`), so the cached `expiresAt` is a check horizon [Own choice]: `checkedAt + 72 h` for a renewing subscription, to which `ProStatus` adds its 3-day renewal margin, so widgets, the tile and the nudge keep a renewing payer unlocked for 6 days after Taken last heard from Play; `checkedAt + 24 h` for one set not to renew. Past it, the app waits for Play before anything locks (9.3). Whether Pro changed ignores the moving horizon (`PlayEntitlement.sameEntitlement`), so a new check is not a change.
- **Trial**: known only on the phone that bought it. When a purchase made through the paywall used the trial offer, Taken records `trialEnds[purchaseTime] = purchaseTime + the offer's free phase` in pro.json (`getPurchaseTime()` is "the subscription signup time. It won't change after renewal", Purchase reference). While that end is ahead the reason is `trial` and `expiresAt` is the real end; after it, `yearly`. Restored on another phone, the subscription reads as `yearly`: no trial line and no reminder there, and Google Play itself emails before a trial ends (https://android-developers.googleblog.com/2020/04/building-user-trust-through-more.html).
- **What a check keeps** (`Entitlement.next`): Play's answer to both questions is conclusive; with no answer (offline, Play unavailable), finding nothing proves nothing and what was known stands; a purchase found always counts. Where the iPhone needs a verified app transaction before a no counts, Android needs Play's own answer.
- **Left out**: founding members, `AppTransaction`, `legacyLog`, the `.pending` gate state, Redeem code (Play's purchase flow takes promo codes itself) [Own choice].

### 9.5 The gate and the status lines

`ProGate.access` as ported: cached status active, pro; nothing ever logged, first session; waiting for Play's first answer this launch (at most 4 s), checking; else locked. `requirePro` waits through checking, as on the iPhone. Profile's Taken Pro section, between Feel and Data as on the iPhone: the status line with its dot ("Checking" before Play's first answer, then "Not active", "Pro lifetime", "Trial · ends 1 Nov" for a trial known on this phone, "Pro yearly · renewing", "Pro yearly · not renewing", and the monthly equivalents; no renewal date, which the phone never sees), the line for a lifetime member whose subscription still renews, "Waiting for approval..." while a purchase is pending, **See plans** while Pro is off, **Manage subscription** (Play's subscription center, `https://play.google.com/store/account/subscriptions?sku=<productId>&package=com.tombaxter.taken`, or the list without a held subscription, Google's recommended deep link, https://developer.android.com/google/play/billing/subscriptions, and the "online method to cancel" Play's policy asks for), and **Privacy Policy**. No Restore button [built 25 Oct 2026, changed from this file's first draft]: Play returns the account's purchases from any phone to `queryPurchasesAsync`, which Taken calls on every start and resume (integrate page), so the footnote says "Restore is automatic. Taken checks Google Play for your purchases each time it opens." The paywall keeps a Restore link for an explicit check, which answers "Restored. Taken Pro is on." or "No active Taken Pro on this Google account."

### 9.6 The paywall

`ui/paywall/Paywall.kt`: the iPhone paywall's content and rules (headline "Keep your record.", the subline and four feature rows in Android wording, plan cards with Yearly selected and "7 days on us" while Play offers it, the trial timeline "Today: full Pro / Day 4: we remind you / Day 7: $19.99 a year starts", the button titles, success lighting the button then closing after 1.15 s and running the tap that opened it), as a full-screen dialog in Taken's look. The intro paywall is the same screen, opened once about 1.5 s after the first dose ever (or the next time Taken opens after a first dose from elsewhere), never over a sheet in use, and never again on its own. Google Play's Subscriptions policy shapes it [Source] (https://support.google.com/googleplay/android-developer/answer/9900533):
- A clearly visible close (48 dp, top bar; "Dismiss button is missing or not clearly visible" is a violation), which system back and predictive back also close; the record stays readable behind it.
- Before purchase: the price, billing frequency, trial length, when the trial becomes paid and what it costs, how to cancel, and "whether a subscription is required to use the app". The terms line under the button: "7 days on us, then $19.99 per year. Renews automatically until cancelled. Cancel anytime in Google Play." (monthly: "$3.99 per month. Renews..."; lifetime: "One payment. Yours for good."), then "Logging needs Taken Pro after your first dose. Your record stays readable without it." [Own choice for the wording]
- The yearly card's billed amount "$19.99 / year" is the most prominent price; "about $1.67 / month" stays smaller under it ("Annual subscriptions that most prominently display their pricing in terms of monthly cost" is a violation).
- Links: Restore and Privacy. No Terms of Use link until Taken has its own terms page (19, item 9): Apple's standard EULA does not apply on Play, and Play's policy asks for no terms link.
- Plans come from `ProductDetails` (`PlayCatalog`): the base plan's recurring phase gives the price and period; an offer whose first phase costs nothing is the trial ("P7D" and "P1W" read the same, as ProCopyTests pin).
- Android conventions: each plan card is a radio button in a selectable group for TalkBack, with the iPhone's card label; 48 dp targets; at 150% text and above the button and terms scroll with the plans so nothing is cut off; edge to edge.
- The timeline's reminder step is left out when notifications are turned off for Taken (`Platform.notificationsOff`); not asked yet counts as on, as the iPhone counts "not determined", since the trial ask may follow.

### 9.7 The trial reminder and its seam

`core/reminders/TrialReminder.kt` ports the plan, its words and its tests: 72 hours before the trial's end at the earliest, on the day the paywall promised, at the nudge time or 10:00, the end's day and date, the price it renews at, the doses logged, how to cancel ("Cancel before then in Google Play > Subscriptions."), at most once, withdrawn when the trial converts, is cancelled, or Profile's Trial reminder is off. Taken Pro posts nothing itself. The seams for the Reminders and Widgets phases (NEXT 3 and 4), on `AppModel`:
- `trialReminderPlan()`, and from pro.json alone `TrialReminder.planFor(ledger, state, now, zone)`: the reminder that should exist now (its `fireAt`, its local time and its `body`), or null. The Reminders phase schedules it with its alarm (10.4) under the tag `TrialReminder.IDENTIFIER` and writes `ProLedgers.withTrialReminder(ledger, TrialReminder.nextMark(...))`.
- `onTrialStarted`: called when the paywall closes after a trial started there; the Reminders phase shows the trial ask there (`TrialAsk.shows`, Continue and Not now, 10.4).
- `trialReminderDeliverable`: until the Reminders phase says the notification can be delivered, Today shows the reminder's words as its quiet row from the reminder's moment until the trial ends (the iPhone's notice while notifications are off), so the paywall's "we remind you" holds in every build.
- `onProChanged`: Pro itself changed; widgets, the tile and the alarms follow it.
- Locked widgets and the tile open `taken://pro?then=...` (10.1, 10.2); `AppModel.handle` opens the paywall and logs what was asked for once Pro is on, or logs it at once if Pro is on by then. A refused log recorded in pro.json (`ProLedgers.recordPending`) is offered again when Taken opens, for 10 minutes.

### 9.8 Testing purchases

License testers' test cards and Play's compressed renewals (trial 3 minutes, monthly 5, yearly 30) (https://developer.android.com/google/play/billing/test). In CI: `:core` tests (EntitlementTests, ProCopyTests and TrialReminderTests ported by name, PlayBillingRulesTests for every Play state) and Robolectric tests over a fake `BillingGateway` (ProStoreTests: no purchase, trial, monthly, yearly, lifetime, pending, cancelled but active, expired, refunded, Play unavailable, the 4 s wait, the purchase flow's answers, acknowledgement backoff; PaywallTests: the policy's disclosures on screen, close, a purchase running the tap that opened it, the intro paywall once, Profile's states and Manage; PlayBillingTests: Play's own `Purchase` read as facts, codes by name). A real test purchase needs a person with an Android phone or an emulator signed in to a license tester's Google account [Tom], section 19.

---

## 10. Surfaces outside the app

### 10.1 Home-screen widgets (Glance 1.2.0)

- **Stack widget**, `SizeMode.Responsive` at 2x1, 2x2, 4x2 and 4x4 (tier 1 asks for 2x1 and two more, https://developer.android.com/docs/quality-guidelines/widget-quality): the counter "2/3" in mono with the segmented bar and **TAKE ALL** (ready count; "LOGGED 07:42" inside the repeat hour; "ALL\nTAKEN"; "LOCKED 21:12"; the empty states), and from 2x2 up the rows, pending first, each row **one tap logs that item's next dose** through `actionRunCallback` (https://developer.android.com/develop/ui/compose/glance/user-interaction), refused inside the repeat hour exactly as the iPhone's `logNextDoseIfPending`. A plain clickable row with the ring drawn as an image, never Glance's `CheckBox` (a checkbox reads as a toggle, and a second tap must never un-log) [Own choice]. Rows at least 48 dp tall (WL-4.2).
- **Locked** (no Pro after the first dose): read-only with the PRO mark; taps use `actionStartActivity` to `taken://pro?then=log&item=<id>` or `taken://pro?then=take-all`; activities cannot start from callback actions on Android 12+ (same interaction page).
- **Look**: `GlanceTheme` with `ColorProviders` from the look's tokens (https://developer.android.com/develop/ui/compose/glance/theme); system corner radius for the widget frame (WS-2); widgets cannot use custom fonts, so `FontFamily.Monospace` for times and counts and the system sans for names (https://developer.android.com/develop/ui/compose/glance/build-ui).
- **Refresh**: after every write `updateAll`; `updatePeriodMillis = 0`; one non-waking `AlarmManager.set(RTC, ...)` for the earliest of the next rollover, the repeat guard ending and the Pro cache horizon, whose receiver calls `updateAll`; also from the boot and time-change receivers [Own choice from documented parts: https://developer.android.com/develop/background-work/services/alarms/schedule].
- **Preview**: generated previews on Android 15+ with the demo stack in the current look, published on first launch and on a look change (rate-limited to about two calls an hour); a static `previewImage` below 15 (https://developer.android.com/develop/ui/compose/glance/generated-previews).
- **The widget invite** (Today's quiet row, the iPhone's rules for when it shows): "Log from your home screen: add the Taken widget"; a tap calls `requestPinGlanceAppWidget` (https://developer.android.com/develop/ui/compose/glance/pin-in-app), shown only when the launcher supports pinning. The "already has a widget" check is `GlanceAppWidgetManager.getGlanceIds(StackWidget)` not empty [Own choice].
- **To-do capture widget**: a mic that opens `taken://todo/record` with `actionStartActivity` (listening starts in the app, the 90 s rule), "To-do · 4" and the open list in the To-do tab's order (`LazyColumn`), "Tap to see your list" when empty.
- Lock-screen widgets: not built (section 18).

### 10.2 Quick Settings tile and shortcuts

- **One tile, "Take all"** (`TileService`, active mode, `requestListeningState` after each write): `STATE_ACTIVE` while something is pending, `STATE_INACTIVE` when all is taken, subtitle a count only ("2 left"), never item names, because tiles show over the lock screen; logs from the lock screen with no unlock, like the iPhone's control. Locked: "Taken Pro" with a lock; a tap opens the paywall with `startActivityAndCollapse(PendingIntent)` after `unlockAndRun` (https://developer.android.com/develop/ui/views/quicksettings-tiles , https://developer.android.com/about/versions/14/behavior-changes-14). Icon: the pill glyph, white vector, 24 dp. Offered only from Profile ("Add the Take all tile", Android 13+, `requestAddTileService`), never on Today, so Today keeps one quiet row [Own choice].
- **Two static shortcuts** in `shortcuts.xml` (https://developer.android.com/develop/ui/views/launch/shortcuts): "New voice to-do" (To-do, listening) and "Take all" (Today, runs Take all with its snackbar and Undo, or the paywall when locked).

### 10.3 Links

`taken://today`, `taken://todo`, `taken://todo/record`, `taken://pro`, `taken://pro?then=take-all`, `taken://pro?then=log&item=<UUID>`, `taken://weight`, handled by `MainActivity`'s intent filter and parsed by the ported route code. Widgets, the tile and shortcuts use explicit intents carrying the same strings. Debug builds only: `taken://screen/<name>` for screenshots. A link is handled once: a recreated activity (rotation, fold, resize, process death) and a task relaunched from Recents (`FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY`) get the first intent back and never replay it, and `onNewIntent` calls `setIntent`, the way Navigation keeps a deep-link-handled flag in saved state (`KEY_DEEP_LINK_HANDLED`, https://android.googlesource.com/platform/frameworks/support/+/refs/heads/androidx-main/navigation/navigation-runtime/src/androidMain/kotlin/androidx/navigation/NavController.android.kt).

### 10.4 Notifications and reminders

- **Channels** (one each, so each can be silenced): "Evening nudge", "Trial reminder", "To-do due times" (https://developer.android.com/develop/ui/views/notifications/build-notification).
- **Asking**: `POST_NOTIFICATIONS` only from the nudge offer's Turn on, Profile's Nudge switch, or the trial ask, in context, as Google advises: "Ask for a permission in context, when the user starts to interact with the feature that requires it" (https://developer.android.com/training/permissions/requesting). The rationale screen is shown only when `shouldShowRequestPermissionRationale()` is true (https://developer.android.com/develop/ui/views/notifications/notification-permission).
- **The trial ask differs from the iPhone**: Android's guidance is "Always provide the option to cancel an educational UI flow" with a "no thanks" button (https://developer.android.com/training/permissions/requesting), where Apple's HIG asks for one button. So the Android sheet has **Continue** and **Not now** [Source]. It shows once, after a trial starts in the paywall, only while the system prompt can still appear, with the iPhone's waiting rules (no sheet opening or closing, no voice note).
- **After a permanent denial** (two denials, https://developer.android.com/training/permissions/requesting), Profile's Nudge row reads "Notifications are off for Taken. Open Settings" and opens the app's notification settings when tapped. Taken never nags; Google says not to link to settings "in an effort to convince the user", so the link appears only on that row, at the person's own tap [Own choice reading of the guidance].
- **Timing**: `AlarmManager.setWindow(RTC_WAKEUP, fireAt, 10 minutes)` for the nudge, the trial reminder and to-do due times. Play limits `USE_EXACT_ALARM` to alarm, timer and calendar apps (https://support.google.com/googleplay/android-developer/answer/9888170), and `SCHEDULE_EXACT_ALARM` is denied by default from Android 14 (https://developer.android.com/about/versions/14/changes/schedule-exact-alarms); Google: create "an inexact alarm whenever possible" and use `setWindow()` for "Action within a time window" (https://developer.android.com/develop/background-work/services/alarms/schedule). In use, a 20:00 nudge lands 20:00 to 20:10; in Doze it lands when the phone is picked up. [Tom] accepts this timing (section 19).
- **Scheduling** [Own choice]: the ported plans decide what and when (14 nudge days, one trial reminder, up to 30 to-do times); Android keeps **one alarm per kind**, for the soonest planned moment, and when it fires posts that notification and schedules the next. Rebuilt after every write, on every `ON_START`, when Pro changes, on `BOOT_COMPLETED` (not the locked boot broadcast: the stores live in credential-encrypted storage, unreadable before the first unlock), `TIME_SET`, `TIMEZONE_CHANGED` and `MY_PACKAGE_REPLACED` (all allowed for this purpose, https://developer.android.com/develop/background-work/background-tasks/broadcasts/broadcast-exceptions); the boot receiver is enabled only while a reminder is on.
- **The nudge**: "2 pending: VD3, FSH", actions **TAKE ALL** (a `BroadcastReceiver`; `setAuthenticationRequired(false)`, so it works from the lock screen like the iPhone's) and **OPEN** (`PendingIntent.getActivity` directly; trampolines are banned from Android 12, https://developer.android.com/about/versions/12/behavior-changes-12). Every SPEC 3.5 rule carries over: the logical day per nudge, last night's TAKE ALL logs nothing and says so, locked TAKE ALL records the pending Take all and posts "Logging needs Taken Pro. Open Taken to continue.", stale nudges withdrawn on every rebuild (`NotificationManager.getActiveNotifications`), tap opens that day.
- **The trial reminder**: the ported rules and body (Android wording), only for a trial known on this phone (9.4), withdrawn when it no longer applies.
- **To-do due times**: title the task, body "Due 16:00"; only when notifications are already allowed; a tap opens To-do scrolled to it with the wash.

---

## 11. To-do voice

The iPhone's one list, its order, Done today, rows, sheets, Keep as one, undo, notices and gate, unchanged (SPEC 3.10; `Taken/Todo/*`, `Shared/TodoData.swift`). Voice capture stays tap, speak, end: no waveform, no new choice on the capture path.

- **Recognizer**: only `SpeechRecognizer.createOnDeviceSpeechRecognizer` (API 31+), after `isOnDeviceRecognitionAvailable`. Never the default recognizer, which "is likely to stream audio to remote servers" (https://developer.android.com/reference/android/speech/SpeechRecognizer). On API 33+, `checkRecognitionSupport` for the phone's language; a supported language not yet installed starts `triggerModelDownload` for next time and offers "Type it instead" now. Below 31, or with no on-device recognition, the blocker card says so and offers "Type it instead". Nothing is ever sent to a server.
- **Extras** (https://developer.android.com/reference/android/speech/RecognizerIntent): `EXTRA_PREFER_OFFLINE`, `EXTRA_PARTIAL_RESULTS`, `EXTRA_ENABLE_FORMATTING` (API 33, full stops for the sentence split), `EXTRA_SEGMENTED_SESSION` (API 33, so a long note stays one session), `EXTRA_BIASING_STRINGS` (API 33) fed by the ported `TranscriptionVocabulary`.
- **Long notes on API 31 and 32** [Own choice]: no segmented sessions, so when the recognizer ends a session on a pause before the stop rules say so, capture restarts and joins the transcripts with the ported `RecognizerTranscript` rules (the iPhone's fix for the same start-over shape).
- **The ring's level** from `RecognitionListener.onRmsChanged` through the ported noise-floor maths (https://developer.android.com/reference/android/speech/RecognitionListener). The 300 s cap, 30 s quiet stop, "1 minute left" at 240 s, the screen kept on only while starting or listening, and leaving the app stops and saves.
- **Sorting**: Android 1.0 saves every note **as said, one line per sentence** (`TodoValidation.lines`, the iPhone's no-model path), and shows "Saved as you said it, one line per sentence. Tap one to edit." for 8 s. The whole pipeline (chunker, sorter, prompt, validation, grounding, merge) is ported and tested behind `ChunkSorting` anyway, so a model can be added later without new rules. No on-device model in 1.0: ML Kit's GenAI APIs (Gemini Nano) send "Device or other identifiers" and diagnostics to Google with no documented way to turn it off (https://developers.google.com/ml-kit/android-data-disclosure), which would end "nothing collected" [Source, Tom decides later, section 19].
- **Permissions**: `RECORD_AUDIO` on the first mic tap; a rationale only when Android says one is due, with the mic string in 6.4 and a "Not now"; denied, the blocker card with Open Settings and Type it instead (Google: "promote full usability of text functionality", https://developer.android.com/training/permissions/requesting).

---

## 12. Weight

The optional tab, **off by default**, exactly SPEC 3.12 and `Taken/Weight/*`, `Shared/Weight*.swift`: the entry-first page with the big number (Geist Mono 72 sp, the decimal keypad and the Weigh in bar above the IME), the snap to the trend page, the chart, the More menu, All weigh-ins, the weigh-in editor, the goal sheet, the offer on Today, CSV export and import, the care rules for copy. The chart is drawn on a Compose `Canvas` (https://developer.android.com/develop/ui/compose/graphics/draw/overview): dots, the monotone trend line (Fritsch and Carlson, the iPhone's interpolation), the goal rule with its label, the lit points, the weekly dose ticks, the scrub with its popover; TalkBack gets the iPhone's chart summary and one focusable node per weigh-in. [Own choice: no third-party chart; Vico has no monotone curve and documents no TalkBack support, https://guide.vico.patrykandpatrick.com/cartesian-charts/linecartesianlayer]. No Health Connect in 1.0.

---

## 13. Privacy and "nothing collected"

Taken for Android collects nothing, as on the iPhone. That holds because:
1. No analytics, crash, ads, Firebase or ML Kit SDK (3.1).
2. Play Billing: "If your app uses a payment service such as ... Google Play's billing system ... you don't need to declare collection of the data that the payment service collects", provided the app never accesses it (https://support.google.com/googleplay/android-developer/answer/10787469). Taken keeps purchase facts on the phone and sends nothing anywhere. The Billing Library itself carries Google's data transport libraries and the `INTERNET` permission (3.3); whatever it sends is the payment service's own, which the same sentence covers. Our reading; Tom confirms with the Data safety form (section 19, item 11).
3. Voice: on-device recognizer only (section 11).
4. Backup: data "only processed locally ... and not sent off device" is out of scope, and so is data sent off device that is "unreadable by you or anyone other than the sender and recipient" through end-to-end encryption (same page). Auto Backup on Android 9+ is end-to-end encrypted with the screen lock and goes to the person's own Drive (section 5.4), with unencrypted cloud backup switched off. Our reading; Play does not name Auto Backup.

The privacy policy at https://tjbaxter.github.io/taken/privacy.html gains an Android section (Google Play Billing, Android backup, notifications, on-device speech) and its publisher line must match the Play developer account (section 19).

---

## 14. The Google Play listing plan

### 14.1 Order of work

From Google's documented dependencies (research by URL in each step):
1. Tom picks the developer account and name (19.1). Check that account's payments profile (the merchant's full address shows on the listing, https://support.google.com/googleplay/android-developer/answer/7161426) and its fee tier.
2. CI builds a signed release AAB (section 16).
3. In Play Console, by hand through the "Taken slave chrome" session: Create app (Taken, English (United States), App, no charge to download, contact email), accepting Play's declarations [Tom]; upload AAB #1 to **Internal testing**. The first AAB must go through the Console: "The first APK or App Bundle needs to be uploaded via the Google Play Console" (https://github.com/Triple-T/gradle-play-publisher). This enrols Play App Signing and unlocks products.
4. Create and activate the three products (9.2); add Tom as a license tester.
5. App content (14.3), store listing (14.2).
6. Read the pre-launch report's screenshots and crashes for AAB #1 and #2 (Firebase Test Lab devices, https://support.google.com/googleplay/android-developer/answer/9844487), Tom's only look at real devices.
7. Production with managed publishing on, so Tom chooses the go-live moment; budget up to about 7 days for the first review (https://support.google.com/googleplay/android-developer/answer/9859751).

### 14.2 Store listing

- **App name**: "Taken: Pill & Supplement Log" (28 of 30 characters). Fallback "Taken: Supplement Tracker".
- **Short description** (80): "Did I take it? Know for sure. One tap logs each pill and supplement." (68)
- **Full description** (4,000): rewritten from the iPhone text (4,065 characters and Apple-specific), with no Siri, Lock Screen, Control Center, Action button, Apple Intelligence, iPhone or App Store words, and including, nearly word for word, "Taken is not a medical device and does not diagnose, treat, cure, or prevent any medical condition." and "Always consult a healthcare professional for medical advice, diagnosis, or treatment." (Health Content and Services policy, https://support.google.com/googleplay/android-developer/answer/16679511).
- **Files**: `store/play/en-US/title.txt`, `short_description.txt`, `full_description.txt`, `changelogs/<versionCode>.txt`, `images/phoneScreenshots/`, `images/featureGraphic.png`, `images/icon.png` (fastlane supply's layout, so any publishing tool reads it, https://docs.fastlane.tools/actions/supply/) [Own choice]. A `scripts/check-play-metadata.py` in `android.yml` checks the limits, the copy rules, the two disclaimer sentences and the absence of Apple words.
- **Category**: Health & Fitness (Medisafe's choice; MyTherapy uses Medical) [Tom, recommended].
- **Contact**: tjpb2@cantab.ac.uk; website https://tjbaxter.github.io/taken/.
- **Graphics** (https://support.google.com/googleplay/android-developer/answer/9866151): icon 512 x 512 full square, no rounding or shadow (Play masks it); feature graphic 1024 x 500, no alpha; **phone screenshots 1080 x 1920** (the long side may be at most twice the short; 4 or more at 1080 x 1920 portrait for promotion eligibility), real app only, no device frames, captions under 20% of the image. Rendered by Roborazzi at `w405dp-h720dp-xxhdpi` (405 x 3 = 1215, 720 x 3 = 2160: 9:16 and over 1080 px, so promotion-eligible, and tall enough that the hero frame shows a pending row above Take all, which 360 x 640 dp cut off) [Own choice on the size]. Icon and feature graphic rendered from `brand/` tokens by the same tooling as the iPhone icons [Own choice].
- **Screenshot set**: the iPhone's neutral set (no prescription medicine names, a "Weekly shot" row, the type-ahead "mag") for every Play locale [Own choice: one set, and no policy question about naming medicines in store graphics].

### 14.3 App content answers

| Form | Answer | Source |
| --- | --- | --- |
| Privacy policy | https://tjbaxter.github.io/taken/privacy.html with the Android section | https://support.google.com/googleplay/android-developer/answer/10144311 |
| Data safety | "Does your app collect or share any of the required user data types?" **No** (section 13) | https://support.google.com/googleplay/android-developer/answer/10787469 |
| Health apps declaration | **Medication and Treatment Management**; **Nutrition and Weight Management** (the Weight tab ships, off by default); never Medical Device Apps | https://support.google.com/googleplay/android-developer/answer/14738291 |
| Health disclaimer in the app | Profile, About: "Taken is a personal log. It is not a medical device and does not diagnose, treat, cure, or prevent any medical condition. Ask a healthcare professional for medical advice, diagnosis, or treatment." | Health Content and Services page above |
| Content rating (IARC) | Category: utility, productivity, communication or other; No to violence, sexuality, language, gambling, controlled substances (logging one's own medicines is not drug content, our reading). Expected Everyone / PEGI 3. Play has no 13+ setting | https://support.google.com/googleplay/android-developer/answer/188189 ; peers Medisafe and MyTherapy rated Everyone |
| Target audience | 13 to 15, 16 to 17, 18 and over (the iPhone's 13+) | https://support.google.com/googleplay/android-developer/answer/9867159 |
| Ads | No | https://support.google.com/googleplay/android-developer/answer/9859455 |
| Advertising ID | No (and no `AD_ID` in the merged manifest) | https://support.google.com/googleplay/android-developer/answer/6048248 |
| Financial features | "My app doesn't provide any financial features" | https://support.google.com/googleplay/android-developer/answer/13849271 |
| Government, News, COVID-19 | No | |
| App access | All functionality is available without special access; note that Taken Pro is a Google Play subscription with a 7-day trial on yearly | |
| Account deletion | Not applicable: no accounts | |
| Exact alarms | Not declared: Taken does not use them | |

---

## 15. CI

### 15.1 Where it runs

All Android work runs on GitHub's standard `ubuntu-24.04` runners. The Mac builds nothing; there is no emulator in CI for 1.0. The runner image already has Android platforms 36 and 37, build-tools, Kotlin 2.4.21 and Gradle 9.8.1 (https://github.com/actions/runner-images/blob/main/images/ubuntu/Ubuntu2404-Readme.md); Now in Android builds, unit-tests and runs Roborazzi on `ubuntu-latest` the same way (https://github.com/android/nowinandroid/blob/main/.github/workflows/Build.yaml).

### 15.2 `.github/workflows/android.yml`

- **Triggers**: `push` on any branch (`branches: ["**"]`, never tags: "Path filters are not evaluated for pushes of tags", https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax) with `paths: [android/**, store/play/**, .github/workflows/android.yml, scripts/check-play-metadata.py]`; `workflow_dispatch`. Not `pull_request_target`. `concurrency: android-${{ github.ref }}`, cancel in progress. `permissions: contents: read`.
- **Setup** (every job), each action pinned to a full commit SHA with its version in a comment ("the only way to use an action as an immutable release", https://docs.github.com/en/actions/security-for-github-actions/security-guides/security-hardening-for-github-actions): `actions/checkout` v7.0.1, `actions/setup-java` v6.0.1 (Temurin 21: Robolectric 4.17 runs API 36 only on Java 21, https://github.com/robolectric/robolectric/blob/robolectric-4.17/robolectric/src/main/java/org/robolectric/plugins/DefaultSdkProvider.java; the app still compiles to Java 17), `gradle/actions/setup-gradle` v6.4.0 (caching and wrapper validation), `actions/upload-artifact` v7.0.2, working directory `android/`.
- **Jobs**:
  1. `core`: `./gradlew :core:test` (minutes, pure JVM).
  2. `app`: `./gradlew :app:testDebugUnitTest :app:lintDebug :app:assembleDebug`; lint warnings that Google marks as errors fail the job.
  3. `screenshots`: `./gradlew :app:recordRoborazziDebug`; uploads `android/app/build/outputs/roborazzi/**/*.png` as the artifact **`android-screenshots`** (30 days). These PNGs are how Tom sees the app. Record only in CORE; once Tom approves a set, it is committed as baselines and the job switches to `verifyRoborazziDebug` with diff images on failure [Own choice; Roborazzi documents both, record and verify on the same OS].
  4. `release`: `./gradlew :app:bundleRelease` (R8, unsigned) and `android/ci/check-bundle.sh` on the bundle, the same checks `android-release.yml` runs (15.4).
  5. `store`: `python3 scripts/check-play-metadata.py` (NEXT).
- Test reports uploaded on failure only (7 days).

### 15.3 The screenshot set

Rendered by Robolectric (native graphics) + Roborazzi from the debug demo data, no emulator. Names mirror the iPhone's `scripts/screenshots.sh` so the two sets can be compared side by side:
- **Every look** (Signal, Blush, Phosphor, Ice): today, today-done, log (History), paywall, locked, settings-pro-trial, settings-pro-yearly, settings-pro-lifetime, settings-pro-locked, widgets, look, todo, add-search.
- **Taken Pro in Signal** (NEXT 2): paywall-intro, paywall-trial-used, paywall-no-yearly, paywall-loading, paywall-offline, paywall-monthly, paywall-lifetime, paywall-pending and paywall-unlocked (Signal and Blush), today-trial-notice, settings-pro-yearly-ending, settings-pro-monthly, settings-pro-pending; the paywall at font scale 2.0, on the small phone and on the tablet; locked at font scale 2.0.
- **Signal, plus Blush where marked**: empty, today-edit (Signal, Blush, and at font scale 2.0), today-row-moment (a row mid-wash, by advancing the Compose clock), today-menu (the long-press menu), add, item, day, settings (Profile), locked, settings-locked, paywall-no-yearly, today-nudge-offer, today-repair, today-widget-invite, today-weight-offer, trial-ask, todo-recording, todo-cap, todo-empty, todo-blocker, the Weight screens (weight, weight-entry, weight-entry-range, weight-empty, weight-first, weight-weighed, weight-trend, weight-locked, weight-lb, weight-list, weight-goal, weight-goal-saved, weight-goal-moment, weight-goal-reached, weight-goal-sheet, weight-goal-low).
- **Widgets** through `glance-appwidget-testing` (https://github.com/google/glance-experimental-tools/blob/main/appwidget-testing): the stack widget at 2x1, 2x2, 4x2, 4x4, locked, all taken, empty; the to-do widget.
- **Larger text**: today, item, paywall and the 4x2 widget at font scale 2.0 (the device font scale through Robolectric's `@Config(fontScale = 2f)`, https://robolectric.org/device-configuration/, so sheets, which are their own windows, scale too). Text that the iPhone keeps fixed (`monoFixed`: the History grid's day numbers, the Add chips, the day sheet's time pills) stays fixed on Android too.
- **Sizes**: the review set on a current phone, `w411dp-h914dp-420dpi` (1080 x 2400, a Pixel-class 20:9 screen), a small phone `w320dp-h568dp-xhdpi`, and one landscape tablet `w1280dp-h800dp-land-xhdpi` (https://robolectric.org/device-configuration/); the store set at `w405dp-h720dp-xxhdpi` (14.2). Robolectric draws no system bars, so every review frame gets a 24 dp status bar and a 24 dp navigation bar as window insets (Compose's `DeviceConfigurationOverride.WindowInsets`), and edge-to-edge padding shows as on a device [Own choice: the sizes]. Sheets are their own windows and draw without them.
- **What a tap does**: `today-row-moment` (Signal, Blush) by holding the Compose clock 0.1 s after a tap on Magnesium, and `today-logged` (the snackbar with Undo) once it settles; `settings-look` and `settings-data` scroll Profile to its Look and Data sections.
- **Store set**: `store/play/...` frames from the neutral demo stack on the most recent Thursday at 21:41, as on the iPhone.
- **Link checks**: Robolectric tests that each `taken://` route lands where it should (`taken://pro` shows the paywall, `taken://todo` and `taken://todo/record` bring To-do to the front over Profile, `taken://weight` opens Weight or Today while it is off). They fail the `app` job.
- The tile and the notification shade are system UI and are not drawn on the JVM: their state mappers are unit tested, and the pre-launch report shows real devices. An emulator job on the KVM-enabled Linux runners (https://github.blog/changelog/2024-04-02-github-actions-hardware-accelerated-android-virtualization-now-available/) can be added later if Tom wants home-screen captures.

### 15.4 `.github/workflows/android-release.yml`

Built in NEXT 1. Every step has a comment in the file with its source.

- **Trigger**: `workflow_dispatch` only, on `ubuntu-24.04`, `permissions: contents: read` and `actions: read` (the gate lists `android.yml`'s runs), actions pinned to full commit SHAs. Any branch may build, so the first internal build could be made before CORE reaches `main`; **only `main` uploads to Play** [Own choice]. GitHub dispatches a workflow by file name only from the default branch ("not found on the default branch"), so while the file was on `feat/android-pro` alone it was registered once through a push that ran nothing (commit `9c069fe`, reverted in `a4e659d`) and is dispatched by its id, `gh workflow run 396033517 --ref <branch>`; once on `main`, by name. `concurrency: android-release` with `queue: max`: one release at a time, since Play allows a user "only a single edit open at a time" (https://developers.google.com/android-publisher/edits).
- **Gate**: a green `android.yml` run covers this commit: it or an ancestor with no change since under `android/` (Markdown aside, as `.github/actions/ship-setup` ignores Markdown for `ci.yml`), `android.yml`, `store/play/` and the check script; any branch's run counts.
- **versionCode** as section 3.2: `version_code_offset` + the run number; re-runs refused. **versionName** from `app/build.gradle.kts`.
- **Signing** (section 16): the base64 keystore secret decoded into `$RUNNER_TEMP/taken-upload.p12` with `umask 077` and mode 600, never into the workspace (GitHub's documented way to keep a binary in a secret, https://docs.github.com/en/actions/how-tos/write-workflows/choose-what-workflows-do/use-secrets); its path, the password secret and the alias variable go to Gradle as the environment variables `TAKEN_UPLOAD_STORE_FILE`, `TAKEN_UPLOAD_STORE_PASSWORD` and `TAKEN_UPLOAD_KEY_ALIAS`, read by the `upload` signing config (Google: keep signing information out of build files, https://developer.android.com/studio/publish/app-signing; GitHub: "Avoid passing secrets between processes from the command line", same GitHub page). The secrets are set only on the two steps that use them; an `always()` step deletes the keystore and stops the Gradle daemon. `./gradlew :app:bundleRelease -PtakenVersionCode=<code> --no-build-cache --no-configuration-cache` with R8, and the Gradle cache read-only for this job, so the shipped bundle reuses no task output and the signing values never land in Gradle's on-disk configuration cache [Own choice].
- **Checks on the AAB** (`android/ci/check-bundle.sh`, shared with `android.yml`), one OK or FAIL line each, read from the bundle itself: its proto manifest and resources become a binary APK through `aapt2 convert` (https://developer.android.com/tools/aapt2#convert) and are read with `aapt2 dump badging` and `dump xmltree`. Package `com.tombaxter.taken`; targetSdk 36; minSdk 28; versionCode equal to the run's; versionName major.minor.point; not debuggable; permissions against 3.3 with each one's source from Gradle's merger report; the Play Billing Library (the `BILLING` permission, its version in the manifest's meta-data, and the Play Store service string its client binds to, which R8 keeps only while Taken's `BillingClient` is in the code); 16 KB page sizes by both of Google's checks (https://developer.android.com/guide/practices/page-sizes): every `.so`'s LOAD segments aligned to 2**14 or more, and `BundleConfig.pb` asking for `PAGE_ALIGNMENT_16K`, read by bundletool's published schema (https://github.com/google/bundletool/blob/master/src/main/proto/config.proto) because the runner has no bundletool; no debug or demo code (demo strings absent from the dex, no debug-only activity); and the signature: `jarsigner -verify` passes with no unsigned entries, and `keytool -printcert -jarfile` shows exactly one signer with one certificate whose SHA-256 is the upload certificate's (appendix; a public value, the one Play Console shows).
- **Where the AAB goes**: a workflow artifact named after the file, `taken-<versionName>-<versionCode>.aab`, uploaded with `archive: false` so the download is the `.aab` itself, kept **7 days**, for the hand upload in step 14.1.3 [Own choice: the AAB holds no secret, the source is public and the upload key's private half is not in it; the iPhone's rule against binary artifacts otherwise stands]. The job summary prints the file, its size in bytes and MB, versionCode, versionName, the signer's SHA-256, the bundle's SHA-256 and the commit, and warns above 10 MB: the browser session used for the first hand upload takes at most 10 MB per file [Tom's setup, not a Play limit].
- **From AAB #2 on**, a separate job `play` uploads to Internal testing. It runs only on `main` and only once the repository variables `PLAY_WORKLOAD_IDENTITY_PROVIDER` and `PLAY_SERVICE_ACCOUNT` exist; until then it is skipped, never failed. Only that job has `id-token: write`: it signs in with **Workload Identity Federation** through `google-github-actions/auth` v3.0.0 ("Workload Identity Federation is recommended over Service Account Keys", https://github.com/google-github-actions/auth) as a service account invited in Play Console with release rights to Internal testing, for an access token with the `androidpublisher` scope, and `android/ci/play-upload.py` runs the Android Publisher API's edits flow with Python's standard library: insert, `bundles.upload`, `tracks.update` to `internal` with the release status input (`completed`, or `draft` while Play still treats the app as a draft), commit (https://developers.google.com/android-publisher/edits , https://developers.google.com/android-publisher/api-ref/rest/v3/edits.tracks) [Own choice: no third-party publishing tool]. The Google Cloud project, service account, pool and Play Console invitation are NEXT 2 and need Tom; none exists yet. Promotion to production stays a click in Play Console.
- Default log levels; secrets set only on the steps that use them; nothing secret printed.

### 15.5 Keeping the iPhone workflows off Android changes

- `ci.yml`: add `android/**`, `store/play/**`, `.github/workflows/android.yml`, `.github/workflows/android-release.yml` and `scripts/check-play-metadata.py` to `paths-ignore`, so an Android commit never starts its macOS jobs.
- `.github/actions/ship-setup/action.yml` (used by `internal-testflight.yml` and `app-store-build.yml`) and `release.yml` each compare a green `ci.yml` run to `HEAD` with `git diff --quiet "$sha" "$head" -- . ':(exclude)docs/**' ...`. Add `':(exclude)android/**' ':(exclude)store/play/**' ':(exclude).github/workflows/android*.yml' ':(exclude)scripts/check-play-metadata.py'` to both, or every Android commit on `main` would block the next iPhone ship until `ci.yml` ran again for nothing.
- These edits land in the first CORE commit that adds `android/` code, with this section cited.

### 15.6 Tom's GitHub minutes, and AWS

- GitHub: "GitHub Actions usage is free for self-hosted runners and for public repositories that use standard GitHub-hosted runners"; only larger runners are charged in public repositories (https://docs.github.com/en/billing/concepts/product-billing/github-actions). `tjbaxter/taken` is public and its jobs use standard runner labels, so Taken's runs cost nothing; whatever used up the included minutes ran in private repositories (most of Tom's repositories are private). Where minutes are counted, a Linux 2-core minute is $0.006 and a macOS minute $0.062 (same page), so Android stays on Linux and the iPhone's macOS jobs no longer run for Android commits (15.5).
- AWS is ready if Tom still wants it: CodeBuild can host GitHub Actions jobs, switched by one `runs-on: codebuild-<project>-${{ github.run_id }}-${{ github.run_attempt }}` line after a CodeBuild runner project and webhook are set up (https://docs.aws.amazon.com/codebuild/latest/userguide/action-runner.html). Not chosen for 1.0: GitHub recommends "that you only use self-hosted runners with private repositories" because forks of a public repository can run code on them (https://docs.github.com/en/actions/how-tos/manage-runners/self-hosted-runners/add-runners), and Taken's runs already cost nothing. [Tom] section 19.

---

## 16. Signing

- **Play App Signing** holds the app signing key: new apps are enrolled automatically with Google-generated keys (https://support.google.com/googleplay/android-developer/answer/9842756). Taken signs only with an **upload key**, which "must be an RSA key of 2048 bits or more" (same page); Google: "keep the upload key secret", and a lost upload key can be reset in Play Console (https://developer.android.com/studio/publish/app-signing).
- **Made on 25 Oct 2026**, as below. The secrets `ANDROID_UPLOAD_KEYSTORE_BASE64` and `ANDROID_UPLOAD_KEYSTORE_PASSWORD` and the variable `ANDROID_UPLOAD_KEY_ALIAS` (`upload`) exist in `tjbaxter/taken`; never make another key. `android-release.yml` signs with it (15.4) and checks the bundle's signer against the certificate's SHA-256 in the appendix.
- **Made once, on the Mac, by the agent** (no JDK on the Mac, so LibreSSL's `openssl`, which writes the PKCS12 keystore AGP and `keytool` read) [Own choice for the tool]:
  1. `d="$(mktemp -d)"; chmod 700 "$d"`.
  2. `openssl rand -hex 32 > "$d/pw"` (one password: Google says the key password "should be the same as your keystore password", same page).
  3. `openssl genrsa -out "$d/key.pem" 4096`; `openssl req -new -x509 -key "$d/key.pem" -days 10958 -subj "/CN=Taken upload key/O=Taken" -out "$d/cert.pem"` (30 years: "Your key should be valid for at least 25 years", same page).
  4. `openssl pkcs12 -export -inkey "$d/key.pem" -in "$d/cert.pem" -name upload -passout file:"$d/pw" -out "$d/upload.p12"`.
  5. GitHub secrets, value never shown: `base64 < "$d/upload.p12" | bash /Users/tombaxter/.claude/tools/secret-move.sh ANDROID_UPLOAD_KEYSTORE_BASE64 --from stdin --to github:tjbaxter/taken:actions` and `bash /Users/tombaxter/.claude/tools/secret-move.sh ANDROID_UPLOAD_KEYSTORE_PASSWORD --from stdin --to github:tjbaxter/taken:actions < "$d/pw"`. The alias `upload` is a repository variable, not a secret.
  6. Backup in the macOS login Keychain, the value passed on stdin to `security -i` so it never appears in a process list: two generic passwords, service `Taken Android upload keystore` (the base64) and `Taken Android upload keystore password`, account `tom` [Own choice for the mechanism].
  7. `openssl x509 -in "$d/cert.pem" -noout -fingerprint -sha256` (public) is recorded in this file's appendix after the first run; then `rm -rf "$d"`.
- **Never** in the repo: `.gitignore` gains `*.jks`, `*.keystore`, `keystore.properties`, `local.properties`, `android/**/build/`, `android/.gradle/`.
- Play Console's "Android developer verification" registers the package automatically for verified organizations; check its status after the first upload (https://developer.android.com/developer-verification).

---

## 17. Build phases

### CORE (now)

Done when `android.yml` is green on `feat/android` and Tom has the `android-screenshots` artifact:
- Gradle project, version catalog, wrapper, `.gitignore`; the iPhone workflow exclusions (15.5); `android.yml` jobs core, app, screenshots.
- `:core`: day clock, model and JSON codecs, stack engine, mutations and CSV, Today's tap and edit-mode rules, Fmt, catalog, Suggest, AddPlan, retention rules, theme tokens and contrast, demo data, and `ProGate` with a fake status source; their ported tests (8.2, CORE rows).
- `:app`: TakenTheme (four looks, Geist), shell (tabs, header, avatar, sheets host, snackbar, back order, edge-to-edge), Today with the whole-row tap, the logging moment, pencil edit mode and long-press menu, Take all, the quiet rows that need no other phase (repair; the nudge offer waits for Reminders, NEXT 3, so Today never offers a nudge this build cannot post, and only the demo capture shows it; widget invite once the widget exists), Add sheet with type-ahead, item sheet, Set time, History with the grid and day sheet, Profile basics (name, photo, stack list with reorder, archive, delete, look, wake-up time, haptics, Export CSV, Erase all data, About with the health line), the DataStore stores with set-aside, Auto Backup rules.
- Robolectric tests for the row (TodayRowTests port), the link routes and the store; Roborazzi screenshots for every CORE screen in every look.

### NEXT (in this order, each a PR with its tests and screenshots)

Play lets products be created only after a build containing the Billing Library is on a track (9.2), and the first build must be uploaded by hand (14.1), so the first internal build comes first. It needs Tom's account choice (19, item 1) and CORE merged to `main`.

1. **First internal build**: `billing-ktx` in the app with the client connecting, the upload key (16), `android-release.yml`, AAB #1 to Internal testing by hand (14.1, step 3), then the three products (9.2) and Tom as a license tester. **Built on `feat/android-pro`** (25 Oct 2026): Billing 9.1.0 with `PlayBilling` connecting at `onStart`, the signing config and Play version code from the environment, `android/ci/check-bundle.sh` in both workflows, and `android-release.yml` green with a signed AAB. Still open: the hand upload to Internal testing (Tom's account choice, 19 item 1), the three products, the license tester, and the Play app signing certificate for the appendix.
2. **Pro and Billing**: entitlement mapping, paywall, intro paywall, pending logs, Profile's Taken Pro section, locked mode everywhere, the Play Developer API upload from CI (15.4). **Built on `feat/android-pro`** (25 Oct 2026), section 9: `ProStore` over Play Billing in release builds, the paywall and intro paywall, Profile's Taken Pro, the trial notice on Today, the trial reminder's plan and the seams for NEXT 3 and 4 (9.7), with the ported tests and the Taken Pro screenshots. Still open: the Play Developer API upload from CI, which needs Tom's Google Cloud project, service account and Play Console invitation (15.4); the products in Play Console once the payments profile exists (the `play_console_setup` steps); a real test purchase (19, item 10).
3. **Reminders**: channels, the permission flow, nudge with TAKE ALL and OPEN, trial reminder and ask, to-do due times, the receivers.
4. **Widget and tile**: stack widget, to-do widget, tile, shortcuts, previews, rollover refresh, widget invite.
5. **To-do voice**: the ported pipeline, the recognizer, the tab, sheets, notices, Keep as one.
6. **Weight**: the tab, chart, sheets, CSV, offer.
7. **Looks and icons**: adaptive launcher icon with its own monochrome layer (https://developer.android.com/develop/ui/views/launch/icon_design_adaptive), widget theming per look, splash.
8. **Store listing and launch**: listing text, feature graphic, icon, store screenshots, privacy policy Android section, terms page, `check-play-metadata.py`, the App content forms (14.3), production with managed publishing.

---

## 18. Left out of Android 1.0

| Part | Why |
| --- | --- |
| Founding members, 1.0 legacy, `.pending` gate state | No Android 1.0 users |
| Siri, App Intents, Shortcuts actions, App Actions, AppFunctions | App Actions do not reach Gemini (https://discuss.ai.google.dev/t/how-to-invoke-custom-dynamic-shortcuts-and-app-functions-with-gemini/103215); AppFunctions is an experimental preview (https://developer.android.com/ai/appfunctions). Revisit when public |
| Lock-screen widgets, StandBy, CarPlay | Phone lock-screen widgets need an unlock to interact (https://www.androidauthority.com/lock-screen-widgets-on-phones-android-16-qpr2-3589668/); the tile and the nudge's TAKE ALL are the lock-screen paths |
| Per-look launcher icons | `activity-alias` switching (Telegram's way) can remove the icon a person placed on the home screen (https://blog.danlew.net/2014/01/16/preserve-your-launchers-use-activity-alias/) [Tom may overrule] |
| On-device language model for sorting notes | Section 11 [Tom may overrule] |
| Redeem code | Play's purchase flow takes promo codes |
| Health Connect | Later, with its own rationale screen and declaration |
| Moving a record between iPhone and Android | Later; the JSON shapes already match, and Android 16 QPR2's cross-platform transfer with Apple's AppMigrationKit is the documented route (https://developer.android.com/identity/data/autobackup) |
| Internal eval and voice note log | Owner-only iPhone tools |
| Action button | No Android equivalent |

---

## 19. Needs Tom

1. **Which Play developer account shows on the listing.** Tom's Play account is an organization account (Flair Technologies Ltd) whose public developer name is "PestLine AI", and Play shows that name on every app in the account, which breaks "Taken is its own brand". Options from Google's docs: (A) rename the account's developer name (renames every app in it, after review); (B) a second organization account on the same D-U-N-S number with its own name, for example "Thomas Baxter" to match the iPhone listing ("Yes, you can create multiple developer accounts using one DUNS number", and "Your developer name does not need to match the organization name", https://support.google.com/googleplay/android-developer/answer/13634888; US$25 once); (C) a personal account is not workable: new personal accounts need "a minimum of 12 testers who have been opted in continuously for at least 14 days" (https://support.google.com/googleplay/android-developer/answer/14151465) and a check on a physical Android phone. Recommended: B. Either way the merchant address shown is the payments profile's.
2. **Accepting Play's terms and declarations** when the app is created, and signing in to Play Console: only Tom.
3. **No server for purchases.** Google strongly recommends verifying purchases on a backend (https://developer.android.com/google/play/billing/security) and documents client-only acknowledgement as possible (https://developer.android.com/google/play/billing/integrate). Taken has no servers by design. Recommended: no server for 1.0, matching the iPhone's promise; the cost is weaker protection against tampered installs, and no period end or trial end on a phone that did not buy. A small verifier (for example on AWS) would add exact dates but means sending purchase tokens off the phone and declaring "Purchase history" in Data safety.
4. **Gemini Nano sorting of voice notes**: better sorting on recent flagships, but Data safety would have to list device identifiers and diagnostics as collected. Recommended: no for 1.0.
5. **Launcher icon per look**: possible, but a home-screen icon can vanish on some launchers. Recommended: one icon (with Android's own themed icon).
6. **Nudge timing**: inexact, 20:00 to 20:10 while the phone is in use, at pick-up when idle, and no "Alarms and reminders" permission. Recommended: accept.
7. **Play category**: Health & Fitness (recommended) or Medical.
8. **CI host**: Taken's Android CI runs at no cost on GitHub because the repository is public (15.6). Recommended: keep it there; say if you still want it on AWS CodeBuild, which is one line per job once a CodeBuild project exists.
9. **Words Tom should read before launch**: the Android copy changes (6.4), the Play full description, the privacy policy's Android section and publisher line, and a Terms of Use page for the support site (Apple's standard EULA does not cover Play). Until that page exists the Android paywall shows Restore and Privacy only (9.6); adding the link is one line in `ProCopy` and the paywall.
10. **One real test purchase** before production, by someone with an Android phone (or Tom on an emulator signed in to a license tester account), since no CI can buy through Play.
11. **The Billing Library's own network access.** Play Billing 9.1.0 brings Google's data transport libraries, which declare `INTERNET` and `ACCESS_NETWORK_STATE` (3.3). Taken's code makes no network call, and Play's Data safety guidance exempts data "the payment service collects" (13). Recommended: accept, and answer the Data safety form "No data collected" as planned; say if you would rather have those permissions stripped, which no Google source documents for this library.
12. **Two subscription products, not one with base plans** (9.2). Google's own model is one subscription with a base plan per billing period, but a phone with no server cannot read the base plan of a purchase, so Taken sells yearly and monthly as two products with the iPhone's ids. The product ids are permanent once created. Recommended: accept; it changes only if Taken ever gets a server (item 3).

---

## Appendix: facts to fill in as the build goes

- Upload certificate SHA-256: `B2:31:09:1A:B4:4E:2D:CB:82:65:A2:18:61:CA:14:1E:5F:DA:96:8A:2E:BC:4B:17:0B:84:00:1F:74:F2:38:7B` (made 25 Oct 2026, section 16; `android-release.yml` checks every bundle's signer against it)
- Play app signing certificate SHA-256: (from Play Console after AAB #1)
- Play Console app id, service account email, Workload Identity pool: (after NEXT 2: needs Tom's Google Cloud project and the Play Console invitation, 15.4)
- Products created and active in Play Console (9.2): (after the payments profile exists; the `play_console_setup` steps)
