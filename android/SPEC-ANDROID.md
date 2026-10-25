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
| Billing | Play Billing Library 9.1.0; two subscription products (yearly with a 7-day trial offer, monthly) and one one-time lifetime product, all with the iPhone's product ids; no server | [Source] + [Own choice] + [Tom], section 9 |
| Reminders | Inexact `AlarmManager.setWindow` (10-minute window), no exact-alarm permission; one alarm per kind for its soonest moment (built in NEXT 3) | [Source] section 10.4 |
| Voice | On-device `SpeechRecognizer` only; the note saved one line per sentence (the iPhone's no-model fallback) on every phone | [Source] section 11 |
| Widgets | Glance 1.2.0 stack widget (rows log in one tap) and to-do capture widget; one Quick Settings tile "Take all"; two static shortcuts | [Source] section 10 |
| CI | GitHub ubuntu-24.04 runners: core tests, app unit tests, Roborazzi JVM screenshots (PNGs uploaded for Tom), lint, release AAB. No emulator, no Mac | [Source] section 15 |
| iOS CI | `ci.yml` ignores `android/**`; the iOS ship gates exclude `android/**` | [Own choice] section 15.5 |
| Signing | Upload key (RSA 4096, 30 years) made once on the Mac with `openssl`, stored as GitHub Actions secrets through `secret-move.sh`, backed up in the login Keychain; Play App Signing holds the app key | [Source] section 16 |

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
| Billing | `com.android.billingclient:billing-ktx:9.1.0` (2026-06-18) | Version 8+ required since 31 Aug 2026 (https://developer.android.com/google/play/billing/release-notes) |
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
- **versionName** `1.0.0` for the first Play release [Own choice: Android's own first release, independent of iPhone 1.1]. **versionCode** = 1000 + the `android-release.yml` run number, so every upload is higher, as Play requires [Own choice].
- Phones and tablets, any orientation. No orientation lock anywhere: it is ignored at 600 dp and wider anyway, and the layouts must work in landscape [Own choice for phones].

### 3.3 Permissions (the whole list)

The release job prints the merged manifest's permissions and fails on anything not in this list until it is reviewed and added here [Own choice].

| Permission | Why | When asked |
| --- | --- | --- |
| `com.android.vending.BILLING` | Play Billing (added by the library) | never asked |
| `POST_NOTIFICATIONS` | nudge, trial reminder, to-do due times | in context only (section 10.4) |
| `RECORD_AUDIO` | voice to-dos | first mic tap |
| `RECEIVE_BOOT_COMPLETED` | reschedule alarms after a restart | never asked; its receiver (which also hears `TIME_SET`, `TIMEZONE_CHANGED` and `MY_PACKAGE_REPLACED`) is enabled only while a reminder is armed |

Haptics use `View.performHapticFeedback` (Compose `LocalHapticFeedback`), which needs no permission.

Libraries add a few for their own components, which the first merged manifest will show and this table will then list: Glance runs its actions on WorkManager, whose manifest is expected to declare `WAKE_LOCK`, `ACCESS_NETWORK_STATE` and `FOREGROUND_SERVICE`, and AndroidX Core declares the app's own `com.tombaxter.taken.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION`. None of them is a runtime permission or sends anything off the phone.

Forbidden, checked by CI: `com.google.android.gms.permission.AD_ID` (removed with `tools:node="remove"` as a guard; Play asks every app about the Advertising ID, https://support.google.com/googleplay/android-developer/answer/6048248), `SCHEDULE_EXACT_ALARM`, `USE_EXACT_ALARM` (section 10.4), and `INTERNET` unless a reviewed library needs it (Taken itself makes no network calls). The manifest also declares the `<queries>` entry for `android.speech.RecognitionService`, which apps targeting Android 11+ need (https://developer.android.com/reference/android/speech/SpeechRecognizer).

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
                  ProLedger, ProRoute                                          (Shared/Pro.swift, ProCopy.swift)
      reminders/  nudge plan, trial reminder rules, to-do due-time plan        (Shared/Reminders.swift, TrialReminder.swift)
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
      billing/    BillingClient wrapper -> PurchaseFact, ProductDetails -> plan prices and offers
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

- **Navigation**: a Material 3 `NavigationBar` at the bottom on phones with Today (pill), To-do (checklist), History (calendar) and Weight (scale, only while on), using Material Symbols glyphs; navigation bars are for "Three to five destinations of equal importance" on "Compact window sizes" (https://developer.android.com/develop/ui/compose/components/navigation-bar). At 600 dp and wider a `NavigationRail` through `NavigationSuiteScaffold` (https://developer.android.com/develop/ui/compose/layouts/adaptive/build-adaptive-navigation), and content capped at a readable width, centred [Own choice for the width]. CORE builds had two tabs (Today, History); NEXT 5 adds To-do between them, as on the iPhone, so every build from NEXT 5 on has the guidance's three. Beside the rail the content pads the bottom system bar inset itself, since the rail pads only its own side.
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
| "Purchases are turned off on this iPhone." | "Purchases are turned off on this phone." |
| "Apple could not verify that purchase. Try Restore." | "Google Play could not confirm that purchase. Try Restore." |
| Terms "...Cancel anytime in Settings at least 24 hours before renewal." | "...Cancel anytime in Google Play." (section 9.6) |
| Trial reminder "...Cancel at least 24 hours before in Settings > your name > Subscriptions." | "...Cancel before then in Google Play, Payments & subscriptions." |
| Trial ask hint "Shows the iPhone's notification prompt." | "Shows Android's notification prompt." |
| "Voice to-dos need on-device speech recognition, which this iPhone does not have for your language." | "Voice to-dos need on-device speech recognition, which this phone does not have for your language." |
| The three Apple Intelligence sorting notes | Not used; Android shows "Saved as you said it, one line per sentence. Tap one to edit." (section 11) |
| Mic usage string | Rationale text before the system prompt (section 11): "Taken listens only while the mic is on, to turn what you say into to-dos. The audio stays on this phone and is never saved." |

New Android-only copy: the in-app health line in Profile, About (section 14.3); "Pro yearly · not renewing" (section 9.5); the paywall's "Logging needs Taken Pro after your first dose. Your record stays readable without it." (section 9.6).

---

## 7. Screens, iOS to Android

### 7.1 The map

Every screen keeps its content, order, copy and rules from SPEC 3 and its Swift views (named in the first column). This table gives only the Android form.

| iPhone screen (Swift home) | Android form | Phase |
| --- | --- | --- |
| Shell: tabs, avatar top right, sheets from the root, links, 20 s ticker, foreground refresh (`TakenApp`, `AppModel`, `RootView`) | `MainActivity` with one Compose tree; tab header (large Geist title, subtitle, avatar `IconButton` 48 dp, TalkBack "Profile and settings"); one sheet at a time from the root; `taken://` routes on an intent filter, parsed by the ported `ProRoute`/`TodoCaptureRoute`; refresh on `ON_START` (reload stores, Pro, reschedule, widget check, pending log offer, intro paywall); a 20 s ticker while started | CORE (Pro parts NEXT) |
| Today, first run (`EmptyStackView`) | Same card and "Add to stack" | CORE |
| Today with a stack (`TodayView`, `ProgressSummary`, `ItemRow`, `TodayPromptRow`, `BottomDock`) | Section 7.2 | CORE (quiet rows partly NEXT) |
| Add sheet (`AddSheet.swift`) | Full-height `ModalBottomSheet`: chip grid (`FlowRow`), `+ CUSTOM` type mode with the field pinned under the header, type-ahead rows sized by `rowCapacity`, How often rows with frequency menus and weekday toggles, Add bar above the IME | CORE |
| Item sheet (`ItemEditorView`) | `ModalBottomSheet` from Today; a pushed screen from Profile's Stack list; Name, How often, Archive, Delete item with its `AlertDialog`; saves on close | CORE |
| Set time sheet | `ModalBottomSheet` with the title, subtitle and a 24-hour `TimePicker` (input mode), "Set to 07:42" / "Log at 07:42" / disabled "That time is still to come" | CORE |
| History (`HistoryView`, `HistoryGrid`) | Same: two stat cards, the 5 x 7 grid (cells are buttons with the iPhone's TalkBack labels), the two lines (Android wording) | CORE |
| Day sheet (`DaySheet`) | `ModalBottomSheet`: Log at row with a time dialog, items with dose chips (tap: remove confirm) and "+ 08:00" | CORE |
| Profile (`ProfileView`) | Full-screen destination; sections in the iPhone's order. CORE: header (photo, name, streak line), Stack (reorder, archive, delete), Look, Your day, Feel, Data (Export CSV, Erase all data), About. NEXT 3 (built): Reminder between Look and Your day (10.4). NEXT: Taken Pro, Weight, Export/Import weight CSV, "Add the Take all tile" (Android 13+, section 10.2) | CORE + NEXT |
| Look picker | Four live swatches side by side; tap recolours the app with a 0.3 s crossfade and refreshes widgets | CORE |
| Paywall, trial ask | Section 9.6 and 10.4 | NEXT |
| Widget help sheet | Not built: Android's launcher shows its own pin dialog (section 10.1) | |
| To-do tab, edit and type sheets (`TodoRootView`, `TodoListeningCard`, `TodoSheets`) | Section 11: the third tab (checklist), a `LazyColumn` with the header, the open tasks and Done today; the dock (undo bar, one line, the 76 dp mic, "Tap to finish"); the edit and type sheets as `ModalBottomSheet`s with Cancel, the title and Save or Add | NEXT 5 (built) |
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
9. **Pro** (`ProGate.access` and its tests in CORE, so locked mode can be built against a fake status; the rest NEXT): `PurchaseFact`, `ProStatus` (`activeUntil`, `isActive`, `awaitingRenewal`, `lapsedRenewal`), `Entitlement.evaluate` and `next` (founding paths removed), `ProGate.access` (without the internal and legacy steps), `allowsLogging`, `nudgeWindow`, `requirePro` decisions, the intro paywall rule, the pending log (10 minutes, not more than 60 s ahead), `ProCopy` (every function in `Shared/ProCopy.swift`, prices from Play's `formattedPrice` and micros), `ProRoute`.
10. **Trial** (NEXT): `TrialReminder` (`leadDays` 3, `fireDate`, `plan`, `body`, `nextMark`, `notice`, `isRenewingTrial`), `TrialAsk.shows` (Android meaning: notification permission not yet granted and the system prompt still available).
11. **Reminders** (NEXT 3, built): `Reminders.plan` (14 days, ids `taken.nudge.day.<ordinal>`, bodies "2 pending: VD3, FSH", "+<rest>" after 4), `nudgeDay`, `isCurrent`, `staleDelivered`, `staleBody`; `TodoNotifications.plan` (open tasks with a time to come, soonest first, at most 30, body "Due 16:00"). Android's delivery rules over them are `core/reminders/ReminderSchedule.kt` (10.4, as built).
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
| EntitlementTests | adapt to Play's facts (section 9.4); founding, sandbox and TestFlight cases left out | NEXT |
| ProCopyTests | port all, Android copy where 6.4 changes it | NEXT |
| TrialReminderTests | port the rules; the ask orchestration adapts | NEXT |
| ReminderPlanTests | port all (built in NEXT 3; `ReminderScheduleTests` adds Android's delivery rules, `ReminderTests` and `NotificationFlowTests` the Robolectric cases) | NEXT 3 (built) |
| TodoStoreTests, TodoGroundingTests, TodoChunkingTests, NoteSorterTests | port all (the model is a canned `ChunkSorting`) | NEXT |
| TodoExtractionTests | port; the Apple Intelligence lines and Info.plist strings left out | NEXT |
| TodoModelTests | port; voice note log cases left out; Android adds the capture path through a fake `VoiceHost` (prompt, rationale, blockers, busy, a tap, nothing heard, leaving the app, back, the first note on the house, links, the notification seam, a failed save). `TodoScreenTests` (Robolectric) adds the tab's place, the row's TalkBack node, a tap on the words, swipe and Undo, the mic, the blocker's Type it instead and the edit sheet | NEXT 5 (built) |
| TodoOneListTests | keep the one-list behaviour cases; legacy list files left out | NEXT |
| RecognizerTranscriptTests | port the join rules (section 11 uses them on API 31 and 32) | NEXT |
| AgentIntentTests | port only the sentences that a surface still uses; Siri and Shortcuts left out | NEXT |
| WeightTests, WeightGoalTests, WeightEntryTests, WeightStoreTests | port all; demo screens adapt | NEXT |
| VoiceNoteLogTests | left out | |

A unit test that would need an iPhone-only fact (StoreKit's expiry, App Intents metadata) is rewritten against the Android fact, and the commit says which.

---

## 9. Taken Pro on Google Play Billing

### 9.1 What stays

PRO.md's model, unchanged: the whole app for everyone, the first dose ever needs no Pro, then a hard paywall for logging (one automatic showing, 1.5 s after the first dose, never again on its own), no ads ever, the record never held hostage (reading, undo, removing doses, the item and day sheets, CSV exports, to-do completion and editing, the Weight chart: never gated). Yearly $19.99 with 7 days on us for new customers (the default), monthly $3.99, lifetime $49.99. Prices, periods and the offer are always read from Play, never written in the app.

### 9.2 Products in Play Console

[Source] facts: product ids "must start with a number or lowercase letter", may use lowercase letters, digits, underscores and periods, up to 40 characters, and a trial phase lasts "between 3 days and 3 years" (https://support.google.com/googleplay/android-developer/answer/140504); a trial is a new customer acquisition offer on an auto-renewing base plan (https://support.google.com/googleplay/android-developer/answer/12154973); the lifetime is a non-consumable one-time product with a buy purchase option marked legacy compatible (https://developer.android.com/google/play/billing/one-time-products). Products can be created only after a build with the Billing Library is on a track (https://developer.android.com/google/play/billing/getting-ready).

| Play object | Id | Setup |
| --- | --- | --- |
| Subscription | `com.tombaxter.taken.pro.yearly` | base plan `yearly`, auto-renewing, 1 year, US$19.99, other countries filled by Play from the US price; offer `trial-7d`: eligibility "New customer acquisition", one 7-day phase at no charge; Play Console's one-trial-per-app setting on (https://developer.android.com/google/play/billing/subscriptions) |
| Subscription | `com.tombaxter.taken.pro.monthly` | base plan `monthly`, auto-renewing, 1 month, US$3.99, no offer |
| One-time product | `com.tombaxter.taken.pro.lifetime` | non-consumable, purchase option `lifetime` (buy, legacy compatible), US$49.99 |

Grace period and account hold stay at Play's defaults.

**Why two subscription products, not one with two base plans** [Own choice built on documented facts]: the device must know which plan a person has (status line, trial reminder price, the price the plan renews at), and Taken has no server. A `Purchase` on the device exposes the product ids (`getProducts()`) but no base plan, offer, expiry or trial phase (https://developer.android.com/reference/com/android/billingclient/api/Purchase); those live only in the Play Developer API's subscription resource (`purchases.subscriptionsv2`, https://developer.android.com/google/play/billing/lifecycle/subscriptions). With one product per plan, the product id is the plan. The ids are the iPhone's, so the rule code maps one id to one plan on both stores. Switching plans across products is supported by Play's replacement parameters (same subscriptions page); the paywall only shows to people without an active plan, so it never needs one, but if an active subscription is ever found when a purchase starts, the flow passes `SubscriptionProductReplacementParams` with Google's recommended mode (upgrade `CHARGE_PRORATED_PRICE`, downgrade `DEFERRED`).

### 9.3 The billing client

- One `BillingClient` in `AppContainer`, `enablePendingPurchases(PendingPurchasesParams...enableOneTimeProducts())`, `enableAutoServiceReconnection()` (Billing 8+, release notes above).
- Connect at launch; `queryPurchasesAsync` for subscriptions and one-time products after connecting and on every `ON_RESUME`: "Your app should also call `queryPurchasesAsync()` in your app's `onResume()` method" (https://developer.android.com/google/play/billing/integrate).
- `queryProductDetailsAsync` for the three products each time the paywall opens; it returns "a maximum of 50 user eligible offers per subscription" (same page), so **the trial offer being present means the person is eligible**. Products that come back unfetched are "missing" on the paywall (shown as `--`, not selectable).
- **Acknowledge** every `PURCHASED` purchase that is not acknowledged, right away and on every query: within three days or it is "automatically refunded and entitlement revoked" (same page). Never consume the lifetime.
- `PENDING` purchases grant nothing; the paywall shows "Waiting for approval. Taken Pro turns on as soon as it goes through."
- Receivers (widget callbacks, notification actions, the tile) may connect and query once when the cached status lapses (`mayLog`'s one recheck), inside `goAsync()`'s time [Own choice].
- Response codes map to the copy in 6.4: `SERVICE_UNAVAILABLE`, `NETWORK_ERROR`, `SERVICE_DISCONNECTED` to "No connection to Google Play. Try again."; `BILLING_UNAVAILABLE` to "Taken Pro is not sold in this country yet."; `USER_CANCELED` to nothing; `ITEM_ALREADY_OWNED` to a restore; anything else to "Google Play did not finish that. Try again." [Own choice]

### 9.4 From Play's facts to the ported rule

The ported `Entitlement.evaluate` takes `PurchaseFact`s built from `queryPurchasesAsync` (suspended subscriptions excluded, the default):

- **Lifetime** `PURCHASED` → `{isPro, reason: lifetime}`, for good.
- **Subscription** returned by the query → active. Play's documented behaviour: a cancelled subscription "is still returned" until it expires; one in grace period is returned and "shown as active"; one in account hold or paused is not returned (https://developer.android.com/google/play/billing/lifecycle/subscriptions). So: `isPro` true, `reason` from the product id (`yearly` or `monthly`, or `trial`, below), `willRenew = isAutoRenewing()`, `billingIssue` false (grace is invisible on the device and grants access anyway), `plan` and `renewsTo` from the product id.
- **Period end is unknown on the device** (no expiry in `Purchase`, above). Android's cached `expiresAt` is therefore a check horizon, not a period end [Own choice]: `checkedAt + 72 h` for a renewing subscription (the iPhone's 3-day renewal margin, so widgets, the tile and the nudge never lock a payer who has not opened Taken), `checkedAt + 24 h` for one set not to renew. Past it, the app asks Play before anything locks (`lapsedRenewal`), and a receiver makes one recheck before refusing a log.
- **Trial**: a trial is known only on the phone that bought it. When a purchase made through the paywall used `trial-7d`, Taken records `trialEnds[purchaseTime] = purchaseTime + the offer's no-charge phase` in `pro.json` (`getPurchaseTime()` is "the subscription signup time. It won't change after renewal", Purchase reference). While that end is in the future the reason is `trial`; after it, `yearly`. Restored on another phone, the subscription reads as `yearly`: no trial line and no in-app trial reminder there, and Google Play itself emails before a trial ends (https://android-developers.googleblog.com/2020/04/building-user-trust-through-more.html).
- **Left out**: founding members, `AppTransaction`, `legacyLog`, the `.pending` gate state, Redeem code (Play's purchase flow takes promo codes itself) [Own choice].

### 9.5 The gate and the status lines

`ProGate.access` as ported: cached status active → pro; nothing ever logged → first session; waiting for Play's first answer this launch (at most 4 s) → checking; else locked. Everything that needs Pro after the first dose, and everything that never does, is PRO.md's list. Profile's Taken Pro status lines on Android [Own choice where the period end is unknown]: "Not active", "Pro lifetime", "Trial · ends 1 Nov" (trial known), "Pro yearly · renewing", "Pro yearly · not renewing", and the monthly equivalents. "Restore purchases" reruns the query: "Restored. Taken Pro is on." or "No active Taken Pro on this Google account." "Manage subscription" opens `https://play.google.com/store/account/subscriptions?sku=<productId>&package=com.tombaxter.taken` (https://developer.android.com/google/play/billing/subscriptions).

### 9.6 The paywall

The iPhone paywall's content and rules (headline "Keep your record.", four feature rows with Android wording, plan cards with Yearly selected and "7 days on us" while eligible, the trial timeline "Today: full Pro / Day 4: we remind you / Day 7: $19.99 a year starts", the button titles, success lighting the button then closing after 1.15 s and running the tap that opened it), as a full-screen dialog in Taken's look. Google Play's Subscriptions policy shapes the Android version [Source] (https://support.google.com/googleplay/android-developer/answer/9900533):
- A clearly visible close button (48 dp, top bar); the record stays readable behind it.
- Disclose before purchase the price, billing frequency, trial length, when the trial becomes paid and what it costs, how to cancel, and "whether the app requires a subscription". The terms line: "7 days on us, then $19.99 per year. Renews automatically until cancelled. Cancel anytime in Google Play." plus "Logging needs Taken Pro after your first dose. Your record stays readable without it." [Own choice for the wording]
- The yearly card's main price is "$19.99 / year"; "about $1.67 / month" stays smaller under it, never the most prominent figure.
- The online way to cancel is the subscription center link (Profile, Manage subscription).
- Restore and Privacy links stay; Terms of Use links to a Taken terms page on the support site (section 19, item 9), since Apple's standard EULA does not apply on Play.
- Plans come from `ProductDetails`: the base plan's last pricing phase gives the price and period; a phase with `priceAmountMicros == 0` is the trial ("7 days" and "1 week" read the same, as ProCopyTests pin).

### 9.7 Testing purchases

License testers' test cards and Play's compressed renewals (trial 3 minutes, monthly 5, yearly 30) (https://developer.android.com/google/play/billing/test). Unit and screenshot tests use a fake `BillingClient` boundary with StoreKit-shaped demo plans, as the iPhone's `-demo` does. A real test purchase needs a person with an Android phone or an emulator signed in to a tester's Google account [Tom], section 19.

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

`taken://today`, `taken://todo`, `taken://todo/record`, `taken://todo?task=<UUID>` (a tapped due time, NEXT 3), `taken://nudge?day=<ordinal>` (a tapped nudge, its OPEN or its stale note, NEXT 3), `taken://pro`, `taken://pro?then=take-all`, `taken://pro?then=log&item=<UUID>`, `taken://weight`, handled by `MainActivity`'s intent filter and parsed by the ported route code. Widgets, the tile and shortcuts use explicit intents carrying the same strings. Debug builds only: `taken://screen/<name>` for screenshots. A link is handled once: a recreated activity (rotation, fold, resize, process death) and a task relaunched from Recents (`FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY`) get the first intent back and never replay it, and `onNewIntent` calls `setIntent`, the way Navigation keeps a deep-link-handled flag in saved state (`KEY_DEEP_LINK_HANDLED`, https://android.googlesource.com/platform/frameworks/support/+/refs/heads/androidx-main/navigation/navigation-runtime/src/androidMain/kotlin/androidx/navigation/NavController.android.kt).

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

**As built in NEXT 3** (`core/reminders/ReminderSchedule.kt`, `app/.../notify/*`, `NotificationsModel.kt`, `ui/profile/ReminderSection.kt`), without the trial reminder and its ask, which Taken Pro owns (9.7); where Android's form needed a choice:
- **Channels**: ids `taken.nudge`, `taken.trial`, `taken.todo`, named "Evening nudge", "Trial reminder", "To-do due times", created when Taken starts ("execute this code when your app starts. It's safe to call repeatedly", https://developer.android.com/develop/ui/views/notifications/build-notification), importance DEFAULT ("Makes a sound", https://developer.android.com/develop/ui/views/notifications/channels) [Own choice for the mapping: the iPhone plays the default sound and never asks for Time Sensitive]. Category `CATEGORY_REMINDER`; the small icon is Material Symbols' pill in white.
- **The scheduling API** is `ReminderScheduler.rebuild()` (`AppContainer.reminders`), the one entry point, safe at any moment: it posts what came due since each kind's armed moment, arms each kind's one alarm for its next planned moment (`ReminderSchedule.nextAlarm`) or cancels it, withdraws what no longer applies (`ReminderSchedule.withdrawn`: the iPhone's `staleDelivered` rules), and enables the restart receiver only while something is armed. It runs off the main thread, one rebuild at a time, and a caller returns once a rebuild that began after its call has finished. Called from every write to taken.json or todos.json (the stores' changes, so a notification's TAKE ALL counts too), every `ON_START`, permission granted, an alarm, TAKE ALL, `BOOT_COMPLETED`, `TIME_SET`, `TIMEZONE_CHANGED` and `MY_PACKAGE_REPLACED`. Pro changing calls it through the Pro lane's `AppModel.onProChanged` (9.7) once the integrator connects them. Nothing is armed or posted while Android will not show Taken's notifications, as the iPhone adds its requests "only with permission".
- **One alarm per kind, and the armed moment** [Own choice]: setWindow alarms are "deferred until the device exits Doze" and "all alarms are canceled when a device shuts down" (https://developer.android.com/develop/background-work/services/alarms/schedule), and a rebuild may run before a late alarm. So each kind's armed moment is kept (`taken.reminders` SharedPreferences, written with `commit` off the main thread: a few numbers, outside Auto Backup's include list, so a restored phone never posts the old phone's reminders; the alarm's own intent carries the same moment, which stands in if the record was lost to a kill), and whatever came due since it (`ReminderSchedule.due`: planned just before that moment, due by now, read from the files as they are now) is posted by the next rebuild, whichever runs it. A nudge is posted only on its own logical day (last night's never shows the next morning, as `isCurrent` keeps TAKE ALL from logging it); a due time only on its own date, since "Due 16:00" names no day. Tasks.org ships the same one-alarm shape: one PendingIntent, set for the next reminder (https://github.com/tasks/tasks/blob/main/app/src/main/java/org/tasks/jobs/WorkManagerImpl.kt `scheduleNotification`).
- **The trial reminder's slot**: `TrialReminderSlot` in :core (`planned(at)`, `stillApplies(now)`, `posted(reminder, now)`, tag `taken.pro.trial-end`, the iPhone's identifier) and `AppContainer.trialReminders`, `TrialReminderSlot.none` until the integrator plugs in the Pro lane's `TrialReminder.plan` and its mark (`ProLedgers.withTrialReminder` in `posted`). The "Trial reminder" channel and its alarm are already there. Its ask's Continue calls `NotificationsModel.request`, the same flow as Turn on.
- **The permission flow** (`NotificationsModel`, the iPhone's `setReminderEnabled`): Turn on and Profile's Nudge switch run `requirePro` first, then: allowed, the nudge comes on (the offer's toast "Nudge on at 20:00"); Android 13+ and not granted, the explanation if `shouldShowRequestPermissionRationale` says so ("Notifications for Taken", "Taken nudges you at 20:00 if anything is still pending, and tells you when a to-do with a time is due. Nothing else.", Continue and Not now [Own choice for the words]), then Android's prompt from `ActivityResultContracts.RequestPermission`, registered in MainActivity so the answer survives a rotation. A first no is taken as said: no toast and no Settings row, and the next Turn on explains and asks again ("Accept the user's preference", https://developer.android.com/training/permissions/requesting) [Own choice: the iPhone toasts "Notifications are off for Taken in Settings" after any no, which on Android would point to Settings while the prompt can still come]. Once Android will not ask again (a second no, or notifications turned off in Settings, or below Android 13 with them off), the offer's toast is "Notifications are off for Taken in Settings" and Profile shows "Notifications are off for Taken. Open Settings", the only Settings link, opening `ACTION_APP_NOTIFICATION_SETTINGS`. Not now changes nothing. On every `ON_START` the row follows what Android says (the iPhone: shown while denied and the nudge is on).
- **Profile > Reminder** (between Look and Your day, the iPhone's order): Nudge switch; Time (Geist Mono, the 24-hour time dialog, "Nudge time") while on; "The nudge needs Taken Pro" with a lock and chevron while locked, which opens the paywall; the Settings row above. Android adds one row [Own choice]: when only the "Evening nudge" channel is off, "Nudge notifications are off for Taken. Open Settings" opens that channel's page (`ACTION_CHANNEL_NOTIFICATION_SETTINGS`; Google: "suggest that the user change it and provide an action to open the channel settings", channels page above). Footnote "If anything is still pending at this time, Taken nudges you." The Trial reminder switch joins with the trial reminder (9.7).
- **The nudge**: the body only, as on the iPhone, with TAKE ALL (`PendingIntent.getBroadcast` to `NudgeActionReceiver`, `setAuthenticationRequired(false)`) and OPEN (`PendingIntent.getActivity`). A tap and OPEN carry `taken://nudge?day=`: today's opens Today, an earlier day's opens its sheet over History, Profile closes (the iPhone's `openDay(fromNudge:)`), and the nudge leaves the shade (a tap's `setAutoCancel`; for OPEN, which an action button does not dismiss on Android, Taken withdraws it, as an answered notification goes on the iPhone). Activities open with `FLAG_ACTIVITY_NEW_TASK` on MainActivity, the task's root and only `singleTask` activity, so a running Taken gets the link through `onNewIntent` [Own choice: Google's TaskStackBuilder pattern, https://developer.android.com/develop/ui/views/notifications/navigation, would build a parent stack of MainActivity alone and its `CLEAR_TASK` restarts the screen mid-note].
- **TAKE ALL** runs inside `goAsync()`'s time ("the broadcast execution limit still applies", https://developer.android.com/reference/android/content/BroadcastReceiver#goAsync()). The tapped nudge goes, as an action's notification goes on the iPhone, then: last night's logs nothing and posts the stale note; locked records the pending Take all in pro.json and posts "Logging needs Taken Pro. Open Taken to continue." (Pro's one recheck, `ProSource.refresh()`, is the integrator's to add there, 9.3); otherwise `takeAllPending` at that moment, the first dose noted, and a rebuild. Pro's answer is the source's, or pro.json's cached status while the source has none yet (a receiver in a fresh process).
- **The lock screen**: `VISIBILITY_PRIVATE` with a public version that shows "2 pending" or "Due 16:00", never codes or a to-do's words, when the person's lock screen hides sensitive content (https://developer.android.com/develop/ui/views/notifications/build-notification) [Own choice, as the tile never names items over the lock screen, 10.2].
- **Receivers**: the alarm and TAKE ALL receivers are not exported (only Taken's PendingIntents reach them). The restart receiver is exported, as Google's broadcasts page says for receivers that listen "for broadcasts sent from the system" (https://developer.android.com/develop/background-work/background-tasks/broadcasts), checks the action, and does nothing but a rebuild; it is off in the manifest and enabled only while something is armed. The four broadcasts are exempt for exactly this use (https://developer.android.com/develop/background-work/background-tasks/broadcasts/broadcast-exceptions), and `MY_PACKAGE_REPLACED` "is only sent to the application that was replaced" (https://developer.android.com/reference/android/content/Intent#ACTION_MY_PACKAGE_REPLACED). Clock changes for daylight saving need nothing: each moment is planned with the zone's rules.
- **Erase all data** empties taken.json and todos.json, and the rebuild that follows cancels every alarm and withdraws every notification (5.3).

---

## 11. To-do voice

The iPhone's one list, its order, Done today, rows, sheets, Keep as one, undo, notices and gate, unchanged (SPEC 3.10; `Taken/Todo/*`, `Shared/TodoData.swift`). Voice capture stays tap, speak, end: no waveform, no new choice on the capture path.

- **Recognizer**: only `SpeechRecognizer.createOnDeviceSpeechRecognizer` (API 31+), after `isOnDeviceRecognitionAvailable`. Never the default recognizer, which "is likely to stream audio to remote servers" (https://developer.android.com/reference/android/speech/SpeechRecognizer). On API 33+, `checkRecognitionSupport` for the phone's language; a supported language not yet installed starts `triggerModelDownload` for next time and offers "Type it instead" now. Below 31, or with no on-device recognition, the blocker card says so and offers "Type it instead". Nothing is ever sent to a server.
- **Extras** (https://developer.android.com/reference/android/speech/RecognizerIntent): `EXTRA_PREFER_OFFLINE`, `EXTRA_PARTIAL_RESULTS`, `EXTRA_ENABLE_FORMATTING` (API 33, full stops for the sentence split), `EXTRA_SEGMENTED_SESSION` (API 33, so a long note stays one session), `EXTRA_BIASING_STRINGS` (API 33) fed by the ported `TranscriptionVocabulary`.
- **Long notes on API 31 and 32** [Own choice]: no segmented sessions, so when the recognizer ends a session on a pause before the stop rules say so, capture restarts and joins the transcripts with the ported `RecognizerTranscript` rules (the iPhone's fix for the same start-over shape).
  - *As built (NEXT 5)*: the restart runs on every API level, not only 31 and 32, because every extra may be ignored ("Depending on the recognizer implementation, this value may have no effect", RecognizerIntent page above): a segmented session that ends before Taken's stop is followed by a new one too. The iPhone's safety numbers carry over unchanged (at most 200 restarts, a session that ended within 0.5 s waits 0.3 s, the last words are waited for at most 2 s after `stopListening`) [Own choice]. The segmented session's type is `EXTRA_SPEECH_INPUT_MINIMUM_LENGTH_MILLIS` with 300 000 ms ("The recognizer will not stop recognizing speech before this amount of time"), so the session lasts the whole 5 minutes unless the stop rules end it first; segments come through `onSegmentResults` and each is kept as it arrives. The docs do not say whether the partial results after a segment cover only the next segment or the whole session, so a result that starts with every word of the session's finished segments (four words or more) has them taken off (`TranscriptJoin.afterRepeat`, tested in RecognizerTranscriptTests) [Own choice: nothing said is dropped either way]. Formatting is `FORMATTING_OPTIMIZE_QUALITY` [Own choice: the full stops decide the lines]. On API 33+ a language that is only `supported` triggers the download and shows "This phone is downloading speech recognition for your language. Until it is ready, type your to-dos instead." with Type it instead; `ERROR_LANGUAGE_UNAVAILABLE` at the start does the same. Everything runs on the main thread, as the class requires, through `voice/OnDeviceSpeechCapture.kt`, behind the `VoiceCapture` and `VoiceHost` seams that the tests fake.
- **The ring's level** from `RecognitionListener.onRmsChanged` through the ported noise-floor maths (https://developer.android.com/reference/android/speech/RecognitionListener). The 300 s cap, 30 s quiet stop, "1 minute left" at 240 s, the screen kept on only while starting or listening, and leaving the app stops and saves.
  - *As built (NEXT 5)*: `onRmsChanged`'s scale is the recognizer's own ("the new RMS dB value"), not dBFS, so the noise floor starts at the first reading instead of the iPhone's -60, and the ring fills at 12 dB above the room (`TodoCapture.relativeRingLevel`) [Own choice]. The screen stays on through the view's `keepScreenOn`, which "is equivalent to using FLAG_KEEP_SCREEN_ON", cleared as soon as listening ends (https://developer.android.com/develop/background-work/background-tasks/awake/screen-on). Leaving the app (`ON_STOP` that is not a configuration change) stops and saves; the To-do model lives in the app's main scope, not an activity's, so the save reaches todos.json after the activity is gone. No background-time API is needed: with no model the save takes milliseconds after the recognizer's last words [Own choice]. Back stops listening and keeps the words before it returns to Today (6.2).
- **Sorting**: Android 1.0 saves every note **as said, one line per sentence** (`TodoValidation.lines`, the iPhone's no-model path), and shows "Saved as you said it, one line per sentence. Tap one to edit." for 8 s. The whole pipeline (chunker, sorter, prompt, validation, grounding, merge) is ported and tested behind `ChunkSorting` anyway, so a model can be added later without new rules. No on-device model in 1.0: ML Kit's GenAI APIs (Gemini Nano) send "Device or other identifiers" and diagnostics to Google with no documented way to turn it off (https://developers.google.com/ml-kit/android-data-disclosure), which would end "nothing collected" [Source, Tom decides later, section 19].
- **Permissions**: `RECORD_AUDIO` on the first mic tap; a rationale only when Android says one is due, with the mic string in 6.4 and a "Not now"; denied, the blocker card with Open Settings and Type it instead (Google: "promote full usability of text functionality", https://developer.android.com/training/permissions/requesting).
  - *As built (NEXT 5)*: the rationale is an `AlertDialog` titled "Voice to-dos" with Continue and Not now (Google: "include a 'cancel' or 'no thanks' button that lets the user continue using your app without granting the permission", same page). Not now changes nothing: no blocker, and the next mic tap asks again the same way [Own choice]. The prompt is registered in `MainActivity` with `ActivityResultContracts.RequestPermission`, so its answer reaches the tab after a rotation. The mic stays idle while the prompt is up and one answer goes with each prompt, so an answer lost to a process restart never leaves the mic waiting: the next tap asks again [Own choice]. Open Settings opens the app's details page (6.3). The manifest declares `RECORD_AUDIO` and the `<queries>` intent for `android.speech.RecognitionService`.

**As built in NEXT 5** (`TodoModel.kt`, `ui/todo/*`, `voice/*`), where Android's form needed a choice:
- **The model** is `TodoModel`, Taken/Todo/TodoModel.swift line for line on the :core pipeline: the note saved at once as said under a new note id and hidden while it is sorted, then replaced (`replaceNote`), every id made before its write so a replayed write stores the same ones; `todos.json` through DataStore (`TodoPersistence`, the stack's pattern: the screen at once, the file after, a failed save shows "Could not save. Try again." and the screen goes back to the file). An unreadable `todos.json` is set aside as `todos-unreadable-<unix>.json` (5.2).
- **Keep as one** is built and tested, and dormant in 1.0: it is offered only after a model split a note (`keepable` needs `TodoSorting.MODEL`), and Android 1.0 has no model. It wakes up with a model behind `ChunkSorting`.
- **Rows**: one TalkBack node per task, the iPhone's label ("Call the dentist, due tomorrow at 9:00 AM", "Buy milk, done at 4:40 PM"), click label "mark done" or "mark not done" (TalkBack reads "Double tap to mark done", the iPhone's hint), custom actions Edit, Delete and, while offered, Keep as one. The circle and the words are separate 48 dp targets. From a font scale of 1.5 the due day and time sit under the title (three lines), and the edit sheet's date and time under "When", so at 200% nothing is cut to a word [Own choice: the iPhone keeps them side by side]. The listening card's four-line window is four of its own lines (`25.sp.toDp() * 4`): Android 14's font scaling is non-linear, so 100 sp is not four times 25 sp (https://developer.android.com/about/versions/14/features). Swipe to the start deletes (`SwipeToDismissBox`, 6.3) with the undo bar for 4 s; swipe to the end finishes the task (or reopens a done one) and the row springs back, which is Android's own documented pattern for a to-do list ("If the item is swiped from start to end, it calls the onToggleDone lambda", https://developer.android.com/develop/ui/compose/touch-input/user-interactions/swipe-to-dismiss) and an addition to the iPhone, which has the circle only [Source]; TalkBack has both as the row's click and its Delete action. The row keeps a plain `SwipeToDismissBoxState` in `remember`, not the saveable `rememberSwipeToDismissBoxState`: `SwipeToDismissBox` calls `onDismiss` from an effect keyed on the settled value, and `LazyColumn` restores an item's saveable state by its key, so a task put back with Undo came back already swiped away and was deleted again (found by `TodoScreenTests`) [Source: the component's code, https://github.com/androidx/androidx/blob/androidx-main/compose/material3/material3/src/commonMain/kotlin/androidx/compose/material3/SwipeToDismissBox.kt].
- **Haptics** (6.2's constants) [Own choice for the mapping]: a task done and a note saved are `CONFIRM`; listening starting and stopping, "1 minute left", a reopen, a delete, Undo and Keep as one are the soft key release.
- **Sheets**: the edit sheet is a `ModalBottomSheet` with Cancel, "Edit to-do" and Save (Save waits for words), the field (1 to 4 lines), Due, Time, When (Material 3 `DatePickerDialog` for the date, the 24-hour `TimeDialog` for the time, the date shown as the iPhone's en_GB "Thu 22 Oct 2026"), and Delete to-do. The type sheet has Cancel, "Type your to-dos" and Add, the field focused on open. Both keep what was typed across a rotation (`rememberSaveable`).
- **Links**: `taken://todo` closes any sheet and Profile and brings To-do to the front; `taken://todo/record` does the same and asks to listen, and the tab starts listening once it is uncovered (the iPhone's 450 ms, then up to 12 x 150 ms), only when the request is at most 90 s old. A busy microphone gets two more tries 700 ms apart for a link, none for a tap.
- **Due-time notifications** (the Reminders step, 10.4): the seam is `TodoNotificationScheduler` in `AppContainer.todoNotifications`. `TodoModel` hands it the tasks after every write that changed a task and on every return to the front, one rebuild at a time, the newest winning. NEXT 3 plugs it into `ReminderScheduler.rebuild()`, which reads todos.json: the tasks handed over are on their way there, and the file's change rebuilds again with what was saved, so a failed save never leaves a due time behind. A tapped notification opens `taken://todo?task=<UUID>`, which calls `TodoModel.reveal(id)` (scroll and wash).
- **Not built here**: the to-do widget and the "New voice to-do" shortcut (NEXT 4).

---

## 12. Weight

The optional tab, **off by default**, exactly SPEC 3.12 and `Taken/Weight/*`, `Shared/Weight*.swift`: the entry-first page with the big number (Geist Mono 72 sp, the decimal keypad and the Weigh in bar above the IME), the snap to the trend page, the chart, the More menu, All weigh-ins, the weigh-in editor, the goal sheet, the offer on Today, CSV export and import, the care rules for copy. The chart is drawn on a Compose `Canvas` (https://developer.android.com/develop/ui/compose/graphics/draw/overview): dots, the monotone trend line (Fritsch and Carlson, the iPhone's interpolation), the goal rule with its label, the lit points, the weekly dose ticks, the scrub with its popover; TalkBack gets the iPhone's chart summary and one focusable node per weigh-in. [Own choice: no third-party chart; Vico has no monotone curve and documents no TalkBack support, https://guide.vico.patrykandpatrick.com/cartesian-charts/linecartesianlayer]. No Health Connect in 1.0.

---

## 13. Privacy and "nothing collected"

Taken for Android collects nothing, as on the iPhone. That holds because:
1. No analytics, crash, ads, Firebase or ML Kit SDK (3.1).
2. Play Billing: "If your app uses a payment service such as ... Google Play's billing system ... you don't need to declare collection of the data that the payment service collects", provided the app never accesses it (https://support.google.com/googleplay/android-developer/answer/10787469). Taken keeps purchase facts on the phone and sends nothing anywhere.
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
  4. `store`: `python3 scripts/check-play-metadata.py` (NEXT).
- Test reports uploaded on failure only (7 days).

### 15.3 The screenshot set

Rendered by Robolectric (native graphics) + Roborazzi from the debug demo data, no emulator. Names mirror the iPhone's `scripts/screenshots.sh` so the two sets can be compared side by side:
- **Every look** (Signal, Blush, Phosphor, Ice): today, today-done, log (History), paywall, widgets, look, todo, add-search. From NEXT 5 every To-do screen is drawn in every look: todo, todo-recording, todo-cap, todo-empty, todo-blocker, todo-unavailable, todo-saved (a note just saved as said, washed, with its line), todo-deleted (the undo bar), todo-edit, todo-type, todo-mic-ask (the rationale); todo, todo-recording and todo-edit at 200% text, todo and todo-recording on the small phone, todo on the tablet. From NEXT 3, in every look: notify-ask (the explanation before Android's notification prompt) and Profile scrolled to Reminder: settings-reminder (the nudge on with its time), settings-reminder-off (the Settings row), settings-reminder-channel (only the nudge's channel off), settings-reminder-locked, nudge-time (the nudge time's dialog); settings-reminder, -off, -locked and notify-ask at 200% text. The notifications themselves are system UI: `ReminderTests` checks each one's channel, words, public version, actions and intents through Robolectric's notification and alarm shadows.
- **Signal, plus Blush where marked**: empty, today-edit (Signal, Blush, and at font scale 2.0), today-row-moment (a row mid-wash, by advancing the Compose clock), today-menu (the long-press menu), add, item, day, settings (Profile), locked, settings-locked, paywall-no-yearly, today-nudge-offer, today-repair, today-widget-invite, today-weight-offer, trial-ask, todo-recording, todo-cap, todo-empty, todo-blocker, the Weight screens (weight, weight-entry, weight-entry-range, weight-empty, weight-first, weight-weighed, weight-trend, weight-locked, weight-lb, weight-list, weight-goal, weight-goal-saved, weight-goal-moment, weight-goal-reached, weight-goal-sheet, weight-goal-low).
- **Widgets** through `glance-appwidget-testing` (https://github.com/google/glance-experimental-tools/blob/main/appwidget-testing): the stack widget at 2x1, 2x2, 4x2, 4x4, locked, all taken, empty; the to-do widget.
- **Larger text**: today, item, paywall and the 4x2 widget at font scale 2.0 (the device font scale through Robolectric's `@Config(fontScale = 2f)`, https://robolectric.org/device-configuration/, so sheets, which are their own windows, scale too). Text that the iPhone keeps fixed (`monoFixed`: the History grid's day numbers, the Add chips, the day sheet's time pills) stays fixed on Android too.
- **Sizes**: the review set on a current phone, `w411dp-h914dp-420dpi` (1080 x 2400, a Pixel-class 20:9 screen), a small phone `w320dp-h568dp-xhdpi`, and one landscape tablet `w1280dp-h800dp-land-xhdpi` (https://robolectric.org/device-configuration/); the store set at `w405dp-h720dp-xxhdpi` (14.2). Robolectric draws no system bars, so every review frame gets a 24 dp status bar and a 24 dp navigation bar as window insets (Compose's `DeviceConfigurationOverride.WindowInsets`), and edge-to-edge padding shows as on a device [Own choice: the sizes]. Sheets are their own windows and draw without them.
- **What a tap does**: `today-row-moment` (Signal, Blush) by holding the Compose clock 0.1 s after a tap on Magnesium, and `today-logged` (the snackbar with Undo) once it settles; `settings-look` and `settings-data` scroll Profile to its Look and Data sections.
- **Store set**: `store/play/...` frames from the neutral demo stack on the most recent Thursday at 21:41, as on the iPhone.
- **Link checks**: Robolectric tests that each `taken://` route lands where it should (`taken://pro` shows the paywall, `taken://todo` and `taken://todo/record` bring To-do to the front over Profile, `taken://weight` opens Weight or Today while it is off). They fail the `app` job.
- The tile and the notification shade are system UI and are not drawn on the JVM: their state mappers are unit tested, and the pre-launch report shows real devices. An emulator job on the KVM-enabled Linux runners (https://github.blog/changelog/2024-04-02-github-actions-hardware-accelerated-android-virtualization-now-available/) can be added later if Tom wants home-screen captures.

### 15.4 `.github/workflows/android-release.yml`

- `workflow_dispatch` only, from `main` only.
- **Gate**: a green `android.yml` run covers this commit (it or an ancestor with no change since under `android/`, `store/play/`, the workflow and the check script), the same shape as `.github/actions/ship-setup`'s gate.
- Decode the keystore from secrets into `$RUNNER_TEMP` (never into the workspace), pass the path and password to Gradle through environment variables read by the `signingConfig` (Google: keep signing information out of build files, https://developer.android.com/studio/publish/app-signing), `./gradlew :app:bundleRelease` with R8 on, `versionCode = 1000 + github.run_number`.
- **Checks on the AAB**, one OK or FAIL line each: targetSdk 36; minSdk 28; versionCode; 16 KB page sizes: Taken's code is pure Kotlin, which "already supports 16 KB devices", but AndroidX ships two small native libraries (Compose's graphics path, DataStore's shared counter), so every `.so` in the bundle has each LOAD segment aligned to 2**14 or more, Google's documented check (https://developer.android.com/guide/practices/page-sizes); merged manifest permissions against 3.3; no `AD_ID`; no debug-only classes or `taken://screen` routes; the upload certificate's SHA-256 fingerprint printed (a public value, to match Play Console's).
- **Where the AAB goes**: the first one only, as a workflow artifact with `retention-days: 1` for the hand upload in step 14.1.3, deleted after the upload [Own choice: the AAB holds no secret, the source is public and the upload key's private half is not in it; the iPhone's rule against binary artifacts otherwise stands]. From AAB #2 on, nowhere but Play: the job signs in with **Workload Identity Federation** through `google-github-actions/auth@v3` ("Workload Identity Federation is recommended over Service Account Keys", https://github.com/google-github-actions/auth) as a service account invited in Play Console with release rights to Internal testing, and calls the Android Publisher API's edits flow (insert, bundles.upload, tracks.update to `internal`, commit; https://developers.google.com/android-publisher/edits) [Own choice: no third-party publishing tool]. Promotion to production stays a click in Play Console.
- Default log levels; secrets set only on the steps that use them; nothing printed.

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

1. **First internal build**: `billing-ktx` in the app with the client connecting, the upload key (16), `android-release.yml`, AAB #1 to Internal testing by hand (14.1, step 3), then the three products (9.2) and Tom as a license tester.
2. **Pro and Billing**: entitlement mapping, paywall, intro paywall, pending logs, Profile's Taken Pro section, locked mode everywhere, the Play Developer API upload from CI (15.4).
3. **Reminders**: channels, the permission flow, nudge with TAKE ALL and OPEN, trial reminder and ask, to-do due times, the receivers. **Built on `feat/android-features`** (25 Oct 2026, 10.4 as built) without the trial reminder and its ask, which Taken Pro owns: the Reminders side is ready for them (the "Trial reminder" channel, its alarm, `TrialReminderSlot` and `NotificationsModel.request`), and the integrator connects `AppContainer.trialReminders`, `AppModel.onProChanged` and `onTrialStarted` (9.7).
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
9. **Words Tom should read before launch**: the Android copy changes (6.4), the Play full description, the privacy policy's Android section and publisher line, and a Terms of Use page for the support site (Apple's standard EULA does not cover Play).
10. **One real test purchase** before production, by someone with an Android phone (or Tom on an emulator signed in to a license tester account), since no CI can buy through Play.

---

## Appendix: facts to fill in as the build goes

- Upload certificate SHA-256: (after section 16, step 7)
- Play app signing certificate SHA-256: (from Play Console after AAB #1)
- Play Console app id, service account email, Workload Identity pool: (NEXT 2)
