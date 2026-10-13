# Taken Pro (version 1.1): monetization spec

Owner's brief (Tom, 2026-10-13): "Your job is to make as much money as possible from this app ... but obviously, at the same time, deliver the highest quality app possible." "I don't want it to turn into the other apps. The other apps' free tier is unusable because you get an unskippable ad every five swipes ... that'd be a horrible experience." He suggested a trial that converts to paid, and a way for him to keep it at no cost for life.

## Decision and evidence

- Hard paywall with an opt-in App Store trial beats freemium by a wide margin: median download-to-paid by day 35 is 10.7% vs 2.1%, revenue per install at day 60 is $3.09 vs $0.38, and 12-month retention is the same (RevenueCat State of Subscription Apps 2026, 115k apps).
- Trials of 4 days or fewer convert about 30% worse than longer ones; 7 days is the common sweet spot (RevenueCat trial-length analysis, Superwall 2025 benchmark). Health & Fitness trial-to-paid median is 37.7% to 42% and annual plans dominate (about 60% of plan mix) (RevenueCat 2026, Adapty 2026).
- 82% of trial starts happen on day 0, so the offer appears in the first session, right after the first "aha" (the first dose logged).
- So: no ads ever, no crippled free tier. Everyone gets the whole app; continuing to log after the first session needs Pro, with 7 days on us on the yearly plan for new subscribers.

## Products (App Store Connect; product ids are fixed)

| Product id | Type | Price (USD tier, Apple localizes) | Offer |
| --- | --- | --- | --- |
| `com.tombaxter.taken.pro.yearly` | Auto-renewable, group "Taken Pro" | $19.99 / year | Introductory offer: 1 week at no charge, new subscribers |
| `com.tombaxter.taken.pro.monthly` | Auto-renewable, group "Taken Pro" (same level as yearly) | $3.99 / month | none |
| `com.tombaxter.taken.pro.lifetime` | Non-consumable | $49.99 once | none |

Never hard-code prices or trial length in UI: read `Product.displayPrice`, `subscription.subscriptionPeriod` and `subscription.introductoryOffer` (and `isEligibleForIntroOffer`) from StoreKit 2.

## Entitlement (code owns money)

`isPro` is true when ANY of:
1. A verified, unrevoked transaction for either subscription is in `Transaction.currentEntitlements` (includes the intro trial and billing grace period).
2. A verified transaction for the lifetime product exists.
3. **Founding member**: `AppTransaction.shared` is verified, `environment == .production`, and `originalAppVersion` (on iOS this is the CFBundleVersion of the first download) parses to an integer `<= FoundingMember.maxBuild`. `maxBuild` is a constant set to the last 1.0.x build number shipped (passed in at build time or committed before the 1.1 build; the release engineer sets it). In sandbox/TestFlight `originalAppVersion` is "1.0", which must NOT count, so App Review sees the paywall.

Implement it as a pure function over a small value type (inputs: subscription state, lifetime owned, app-transaction environment and original version, maxBuild) with unit tests, plus an `@MainActor` `ProStore` that listens to `Transaction.updates` from launch, refreshes on foreground, and caches `{isPro, reason, checkedAt, expiresAt?}` into the App Group store so the widget extension and App Intents can read it without StoreKit. Cached Pro stays valid until `expiresAt` for a plan set not to renew or in a billing grace period, for 3 days past `expiresAt` for a plan set to renew, or forever (lifetime/founding). Only the app can see a renewal, so that margin is what keeps a payer's widgets, control, Siri and nudge working when the plan renews or the introductory week converts and Taken was not opened that day; the app itself asks StoreKit before it ever locks a renewing plan. A missing cache counts as not Pro except during the first session described below, which ends with the first dose ever (kept in the ledger, so erasing the log never reopens it).

A StoreKit answer only takes Pro away when it proves something: with no app transaction (offline, signed out) what was known stands, and an app transaction that fails verification never removes founding membership or a 1.0 log's pending state (purchases are still re-read, so a refund counts). Restore asks for a fresh app transaction when the one on the phone is missing or unverified.

## Where the paywall appears

- **First run is untouched**: empty state, Add sheet, stack added. The user taps their first dose and sees it light up (the aha). About 1.5 s after that first dose, the paywall sheet slides up once.
- **After that, without Pro (locked mode)**: TODAY still shows the stack, today's log and the history grid; the day sheet and CSV export still work (we never hold someone's record hostage). Logging a dose, TAKE ALL, backfill, Set time, and adding items open the paywall instead. A slim mono bar under the status panel: `PRO ENDED · TAP TO CONTINUE` (or `START 7 DAYS ON US` if eligible for the intro offer).
- **Widgets and Control Center when locked**: show the stack state read-only with a small `PRO` lock glyph; any tap deep-links `taken://pro` (opens the paywall). Intents (Siri/Shortcuts) that log return a dialog: "Logging needs Taken Pro. Open Taken to continue." and do not write. "Did I take it?" keeps answering (read-only).
- **Voice to-dos (REDESIGN.md, SPEC 3.10)**: the first voice note ever needs no Pro, so people feel it. After it, a tap on the mic, a quick capture (Siri, the control, the Lock Screen, the quick action) or typed to-dos open the paywall when Pro is not active, and listening starts once Pro is on. Completing, editing and deleting to-dos always work. Same rule as logging (`TodoGate` over `ProGate`), with the first voice note (`firstNoteAt` in `todos.json`, kept through Erase all data) in place of the first dose.
- **Reminders when locked**: do not schedule nudges. Settings > REMINDER says `THE NUDGE NEEDS TAKEN PRO` (a tap opens the paywall), and turning NUDGE on opens the paywall; the notification permission prompt comes once Pro is on.
- **Settings > PRO section**: status line (`FOUNDING MEMBER · PRO FOR LIFE`, `PRO YEARLY · RENEWS 12 OCT 2027`, `PRO YEARLY · RENEWING` while a renewal is on its way, `PRO LIFETIME`, `TRIAL · ENDS 19 OCT`, `NOT ACTIVE`), `Restore purchases`, `Redeem code` (StoreKit `offerCodeRedemption`), `Manage subscription` (`manageSubscriptionsSheet`; for a lifetime or founding member only while a subscription still renews, with the line "Your subscription still renews. Taken Pro is yours for good, so you can cancel it."), and the Terms/Privacy links. Restore that finds nothing says "No active Taken Pro on this Apple Account." (true for a new customer and for a plan that ended).

## Paywall design (Taken visual language, SPEC section 4)

One sheet, no carousel, no fake urgency, no countdowns, no dark patterns.
- Header: the capsule mark, `TAKEN PRO` mono label, headline in Geist: "Keep your record." Subline: "Every dose, logged to the minute. Widgets, Lock Screen, Siri."
- Four short mono bullets with amber dots, each something only Pro unlocks (the log, history and CSV export stay open without it): `ONE TAP LOGGING + TAKE ALL`, `HOME, LOCK SCREEN + CONTROL CENTER`, `SIRI + THE EVENING NUDGE`, `VOICE TO-DOS`.
- Plan picker (yearly preselected): YEARLY card shows `7 DAYS ON US` tag when eligible, then the billed amount as the most prominent price element: "$19.99 / year" with "about $1.67 / month" smaller; MONTHLY "$3.99 / month"; LIFETIME "$49.99 once". A plan the App Store did not return shows `--` and cannot be chosen, the first plan it did return is preselected, and with none the button reads `TRY AGAIN` and asks again.
- Primary button: eligible yearly -> `START 7 DAYS ON US`; otherwise `CONTINUE`. Directly under it, always visible, the plain terms line Apple requires: "7 days on us, then $19.99 per year. Renews automatically until cancelled. Cancel anytime in Settings at least 24 hours before renewal." (built from StoreKit values for the selected plan; lifetime: "One payment. Yours for good.").
- Footer links: `Restore` · `Redeem code` · `Terms of Use` (https://www.apple.com/legal/internet-services/itunes/dev/stdeula/) · `Privacy` (https://tjbaxter.github.io/taken/privacy.html).
- Close button top right (an X). Closing simply returns to locked mode; the sheet is not shown again automatically in the same session.
- Purchase via `product.purchase()`; handle `.success(verified)`, `.pending`, `.userCancelled`, and errors with a calm inline message. Success: the ALL TAKEN-style lock-in animation + success haptic, sheet closes, and the pending dose tap that opened it is applied.
- Copy rules: no em or en dashes, never the word "free" anywhere in our own UI (Apple's system sheet may say it; that is fine), no exclamation marks.

## Testing and CI

- `Taken/Taken.storekit` StoreKit configuration with the three products and the 1-week intro offer, wired into the scheme's Run action for local testing; unit tests run the entitlement function and paywall copy builder.
- New screenshot states: `-screen paywall` (yearly selected, eligible) and `-screen locked` (TODAY in locked mode), both with `-demo`.
- Keep Swift 6 strict concurrency clean; no third-party SDKs (the listing promises no third-party code).

## Listing changes for 1.1

- Description gains a TAKEN PRO block: "Taken Pro yearly: 7 days on us for new subscribers, then $19.99 a year. Or $3.99 a month, or $49.99 once. Payment is charged to your Apple Account. Subscriptions renew automatically unless cancelled at least 24 hours before the end of the period; manage or cancel in Settings." plus `Terms of Use: https://www.apple.com/legal/internet-services/itunes/dev/stdeula/`. Only the yearly plan has the introductory week, and only for new subscribers, so the listing never puts it before every plan.
- What's New for 1.1 written by the builder; App Review notes explain the founding-member rule and that sandbox shows the paywall.
- Privacy label stays "Data Not Collected": purchases go through Apple and nothing leaves the device.

## Built in 1.1.0

Implemented as written, with four refinements recorded in SPEC.md 3.9: purchases go through SwiftUI's `PurchaseAction` (StoreKit 2's `product.purchase()` with the right window for its sheet); a log that predates 1.1 is never locked before StoreKit has answered for it (every 1.0 App Store download is a founding member); the one automatic paywall also follows a first dose logged from a widget, the next time Taken opens; and a Control Center control cannot open an app without universal links, so when locked it shows a lock, logs nothing, and Taken offers that TAKE ALL with the paywall when it next opens (the same for Siri and the nudge).

The 1.1 review round (2026-10-13) added: the 3 day renewal margin on the cache, with the app waiting for StoreKit on every foreground before locking a renewing plan, asking it again while open across a period end, and Siri and the nudge (which run in the app) asking it before they refuse; the rule that only a verified app transaction makes a no conclusive (`Entitlement.next`, unit tested); `firstDoseAt` in the ledger, so the first session ends for good; `renewingSubscription` on the status for MANAGE SUBSCRIPTION; and the paywall's third bullet naming the nudge instead of history and export, which never needed Pro.
