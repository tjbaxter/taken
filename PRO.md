# Taken Pro (version 1.1): monetization spec

Owner's brief (Tom, 2026-10-13): "Your job is to make as much money as possible from this app ... but obviously, at the same time, deliver the highest quality app possible." "I don't want it to turn into the other apps. The other apps' free tier is unusable because you get an unskippable ad every five swipes ... that'd be a horrible experience." He suggested a trial that converts to paid, and a way for him to keep it at no cost for life.

## Decision and evidence

- Hard paywall with an opt-in App Store trial beats freemium by a wide margin: median download-to-paid by day 35 is 10.7% vs 2.1%, revenue per install at day 60 is $3.09 vs $0.38, and 12-month retention is the same (RevenueCat State of Subscription Apps 2026, 115k apps).
- Trials of 4 days or fewer convert about 30% worse than longer ones; 7 days is the common sweet spot (RevenueCat trial-length analysis, Superwall 2025 benchmark). Health & Fitness trial-to-paid median is 37.7% to 42% and annual plans dominate (about 60% of plan mix) (RevenueCat 2026, Adapty 2026).
- 82% of trial starts happen on day 0, so the offer appears in the first session, right after the first "aha" (the first dose logged).
- So: no ads ever, no crippled free tier. Everyone gets the whole app; continuing to log after the first session needs Pro, starting with 7 days on us.

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

Implement it as a pure function over a small value type (inputs: subscription state, lifetime owned, app-transaction environment and original version, maxBuild) with unit tests, plus an `@MainActor` `ProStore` that listens to `Transaction.updates` from launch, refreshes on foreground, and caches `{isPro, reason, checkedAt, expiresAt?}` into the App Group store so the widget extension and App Intents can read it without StoreKit. Cached Pro stays valid until `expiresAt` (subscription) or forever (lifetime/founding); a missing cache counts as not Pro except during the first session described below.

## Where the paywall appears

- **First run is untouched**: empty state, Add sheet, stack added. The user taps their first dose and sees it light up (the aha). About 1.5 s after that first dose, the paywall sheet slides up once.
- **After that, without Pro (locked mode)**: TODAY still shows the stack, today's log and the history grid; the day sheet and CSV export still work (we never hold someone's record hostage). Logging a dose, TAKE ALL, backfill, Set time, and adding items open the paywall instead. A slim mono bar under the status panel: `PRO ENDED · TAP TO CONTINUE` (or `START 7 DAYS ON US` if eligible for the intro offer).
- **Widgets and Control Center when locked**: show the stack state read-only with a small `PRO` lock glyph; any tap deep-links `taken://pro` (opens the paywall). Intents (Siri/Shortcuts) that log return a dialog: "Logging needs Taken Pro. Open Taken to continue." and do not write. "Did I take it?" keeps answering (read-only).
- **Reminders when locked**: do not schedule nudges.
- **Settings > PRO section**: status line (`FOUNDING MEMBER · PRO FOR LIFE`, `PRO YEARLY · RENEWS 12 OCT 2027`, `PRO LIFETIME`, `TRIAL · ENDS 19 OCT`, `NOT ACTIVE`), `Restore purchases`, `Redeem code` (StoreKit `offerCodeRedemption`), `Manage subscription` (`manageSubscriptionsSheet`), and the Terms/Privacy links.

## Paywall design (Taken visual language, SPEC section 4)

One sheet, no carousel, no fake urgency, no countdowns, no dark patterns.
- Header: the capsule mark, `TAKEN PRO` mono label, headline in Geist: "Keep your record." Subline: "Every dose, logged to the minute. Widgets, Lock Screen, Siri."
- Three short mono bullets with amber dots: `ONE TAP LOGGING + TAKE ALL`, `HOME, LOCK SCREEN + CONTROL CENTER`, `FULL HISTORY + CSV EXPORT`.
- Plan picker (yearly preselected): YEARLY card shows `7 DAYS ON US` tag when eligible, then the billed amount as the most prominent price element: "$19.99 / year" with "about $1.67 / month" smaller; MONTHLY "$3.99 / month"; LIFETIME "$49.99 once".
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

- Description gains a TAKEN PRO block: "Taken Pro: 7 days on us, then $19.99 a year, or $3.99 a month, or $49.99 once. Payment is charged to your Apple Account. Subscriptions renew automatically unless cancelled at least 24 hours before the end of the period; manage or cancel in Settings." plus `Terms of Use: https://www.apple.com/legal/internet-services/itunes/dev/stdeula/`.
- What's New for 1.1 written by the builder; App Review notes explain the founding-member rule and that sandbox shows the paywall.
- Privacy label stays "Data Not Collected": purchases go through Apple and nothing leaves the device.

## Built in 1.1.0

Implemented as written, with four refinements recorded in SPEC.md 3.9: purchases go through SwiftUI's `PurchaseAction` (StoreKit 2's `product.purchase()` with the right window for its sheet); a log that predates 1.1 is never locked before StoreKit has answered for it (every 1.0 App Store download is a founding member); the one automatic paywall also follows a first dose logged from a widget, the next time Taken opens; and a Control Center control cannot open an app without universal links, so when locked it shows a lock, logs nothing, and Taken offers that TAKE ALL with the paywall when it next opens (the same for Siri and the nudge).
