# Taken 1.1.0: App Store Connect submission checklist

Everything App Store Connect asks for version 1.1.0, in the order its pages ask, with the file each value comes from. `scripts/check-store-metadata.py` checks every text below against Apple's limits in CI (ci.yml, "Store metadata"). Why each choice was made, with sources: REDESIGN.md, "App Store pack for 1.1".

## 0. Before you start

- 1.0 has left App Review. App Store Connect takes one version submission per platform at a time (https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/overview-of-submitting-for-review).
- Business, Agreements: the Paid Apps Agreement is signed and reads Active, with the bank account and tax forms Business asks for. 1.0 is a free app with no in-app purchases, so it may never have been signed. Apple: "To sell your apps on the App Store or offer In-App Purchases, the Account Holder must sign the Paid Apps Agreement", "This agreement must be active in order for you to submit or update paid apps and In-App Purchases" and "You won't be able to create a new app or In-App Purchase until you've agreed to the most recent version of the Paid Apps Agreement" (https://developer.apple.com/help/app-store-connect/manage-agreements/sign-and-update-agreements). Do this before section 4.
- The build: a new one, from `.github/workflows/app-store-build.yml` run on main once both of these are merged:
  1. this pack (pull request #10), and
  2. the Weight tab (pull request #11), which removes its `#if DEBUG || TAKEN_INTERNAL` gate, the `WeightTabRootView` marker and its `--internal` presence check in `scripts/check-app-store-build.sh` together. A build from before it lacks what What's New and the review notes describe (Guidelines 2.3.1(a) and 2.3.12).
- Attach only that build, with every `scripts/check-ipa.sh` line OK (`scripts/check-app-store-build.sh`, Guideline 2.5.19, among them). Never 1.1.0 (23) or any build from before both merges: none has the Weight tab. Never an internal build: internal builds are exported TestFlight internal testing only and App Store Connect never offers them for a version; 1.1.0 (8) and (9) predate that and still show as Ready to Submit, so never pick them.
- Read the Primary Language (App Information, General, Primary Language). Section 2 keeps it as it is.

## 1. App Information (shared by every version)

| Field | Value | From |
| --- | --- | --- |
| Name, each localization | `Taken: Pill & Supplement Log` | `store/metadata/<set>/name.txt` |
| Subtitle, each localization | `Did I take it? Know for sure.` | `store/metadata/<set>/subtitle.txt` |
| Privacy Policy URL, each localization | `https://tjbaxter.github.io/taken/privacy.html` | `store/metadata/<set>/privacy_url.txt` |
| Primary Language | Leave it as it is for 1.1 (section 2) | |
| Category | Primary: Health & Fitness (secondary as 1.0 has it) | SPEC.md section 5 |
| Content Rights | As 1.0 answered it | |
| Age Rating | 13+, answers below | REDESIGN.md, "Age rating 13+" |
| License Agreement | Apple's standard EULA (the description links it) | PRO.md |

Age rating questionnaire (Apple's categories, https://developer.apple.com/help/app-store-connect/reference/app-information/age-ratings-values-and-definitions/):
- In-App Controls: Parental Controls No. Age Assurance No.
- Capabilities: Unrestricted Web Access No. User-Generated Content No. Social Media No. Messaging and Chat No. Advertising No.
- Mature Themes: Profanity or Crude Humor None. Horror/Fear Themes None. Alcohol, Tobacco, or Drug Use or References None.
- Medical or Wellness: **Medical or Treatment Information: Infrequent. Health or Wellness Topics: Yes.**
- Sexuality or Nudity: None to all three.
- Violence: None to all four.
- Chance-Based Activities: Gambling No. Simulated Gambling None. Contests None. Loot Boxes No.
- The result must read 13+. Screenshots still suit 4+ (Guideline 2.3.8).

## 2. Localizations: which copy and which screenshots

One listing for every storefront: every localization gets the same copy and the neutral screenshots.

| Localization | Copy | Screenshots, 6.9 inch and 6.3 inch |
| --- | --- | --- |
| English (U.S.), the Primary Language or not | `store/metadata/en-US/` (in 1.1 the same text as `neutral/`) | `store/appstore/iphone-6.9/neutral/`, `store/appstore/iphone-6.3/neutral/` |
| English (U.K.), English (Australia), English (Canada) and any other localization 1.0 has | `store/metadata/neutral/` | the neutral set |

Decided, so nothing here is left for submission day:
- No Japanese localization, and English (U.S.) holds the neutral rules. Japan lists Japanese and English (US) (https://developer.apple.com/help/app-store-connect/reference/app-information/app-store-localizations), so English (U.S.) reaches Japan as well as the United States. The same page names no order between the storefront's language, the device's language and the primary language ("the language shown to each customer could be impacted by factors like the App Store language for their location, their device's language settings, languages you've added, and your primary language"), so a Japanese localization would not reliably keep English (U.S.) out of Japan, and no Apple page documents English text in one.
- The neutral rules: no medicine name and no price, in both sets. Most countries ban promoting prescription medicines to the public, the United States and New Zealand being the exceptions (REDESIGN.md, "Store screenshots for the 1.1 submission"), and Japan bans it too. Storefronts charge in their own currency, so a written price is false outside the United States (Guideline 2.3.1(a), "promoting a false price"); the product page lists each in-app purchase in the visitor's currency and the paywall shows StoreKit's price. `scripts/check-store-metadata.py` checks both rules on both sets in CI.
- The en-US screenshots (`store/appstore/iphone-6.9/en-US/`, `store/appstore/iphone-6.3/en-US/`, with a Semaglutide row and the medicine chips) go to no localization.
- No localization needs adding and the Primary Language stays as it is: where no localization matches, the primary language shows (https://developer.apple.com/help/app-store-connect/manage-app-information/localize-app-information), and every localization shows the same listing.
- Weight words: only What's New's line for the Weight tab, in every localization (Guideline 2.3.12; REDESIGN.md "Weight tab", Store, privacy and positioning). The English (U.S.) description line that spec allows is left out: the description has 4 characters to spare and the line needs 66, and English (U.S.) is also shown in Japan and, while it is the Primary Language, wherever no localization matches.

Screenshots: upload all six PNGs of a set, in order 01 to 06, to both iPhone sizes: iPhone 6.9" Display (1320 x 2868, `iphone-6.9`) and iPhone 6.3" Display (1206 x 2622, `iphone-6.3`). The medium display is the size App Store Connect requires (https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications). The contact sheets (`store/appstore/contact-sheet-<set>.jpg`) are for looking, not for upload.

## 3. Pricing and Availability

- Price: the no-charge tier, as 1.0. Taken Pro is in-app purchases (section 4).
- Availability: every country or region, as 1.0 (Tom: "We're a global app on the App Store").

## 4. In-App Purchases and Subscriptions (before the version page)

First, the Paid Apps Agreement must read Active (section 0). Values in `store/iap/products.json`; product ids are fixed (PRO.md). Each needs its display name and description in every localization the app has (the same text in each), and the review screenshot `store/iap/paywall.png` (the paywall as ci.yml captures it, refreshed by store-shots.yml).

| Product id | Type | Price (USD) | Offer | Display name | Description |
| --- | --- | --- | --- | --- | --- |
| `com.tombaxter.taken.pro.yearly` | Auto-renewable, 1 year, group Taken Pro | 19.99 | Introductory offer, 1 week at no charge, new subscribers | Taken Pro Yearly | One-tap logging, widgets, Siri, voice to-dos |
| `com.tombaxter.taken.pro.monthly` | Auto-renewable, 1 month, group Taken Pro | 3.99 | none | Taken Pro Monthly | One-tap logging, widgets, Siri, voice to-dos |
| `com.tombaxter.taken.pro.lifetime` | Non-Consumable | 49.99 | none | Taken Pro Lifetime | All of Taken Pro, yours for good |

- Subscription group display name: Taken Pro. App name display: use the app's name.
- Levels: leave them as App Store Connect has them. PRO.md puts monthly at the yearly plan's level and `Taken/Taken.storekit` has yearly at 1 and monthly at 2; either way a switch from yearly to monthly takes effect at the next renewal date (a crossgrade between different durations, or a downgrade: https://developer.apple.com/help/app-store-connect/reference/in-app-purchases-and-subscriptions/auto-renewable-subscription-information), which is what the trial reminder's price assumes.
- Review notes for each: `review_notes` in `store/iap/products.json`.
- The first subscription and the first non-consumable must go to review with a new app version, together with the subscription group (https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-in-app-purchase). Each status must read Ready to Submit before the next step.

## 5. App Privacy

Data Not Collected, unchanged (https://developer.apple.com/app-store/app-privacy-details/). Purchases go through Apple; speech, sorting, weigh-ins and every file stay on the iPhone.

## 6. Version 1.1.0 (iOS App, + Version, 1.1.0)

Per localization, with the set from section 2:

| Field | From | Limit |
| --- | --- | --- |
| Screenshots, iPhone 6.9" and 6.3" | `store/appstore/iphone-6.9/<set>/`, `store/appstore/iphone-6.3/<set>/` | up to 10 per size |
| Promotional Text | `store/metadata/<set>/promotional_text.txt` | 170 characters |
| Description | `store/metadata/<set>/description.txt` | 4000 characters |
| Keywords | `store/metadata/<set>/keywords.txt` | 100 bytes |
| Support URL | `store/metadata/<set>/support_url.txt` (https://tjbaxter.github.io/taken/, which has the contact address Apple asks for) | |
| Marketing URL | `store/metadata/<set>/marketing_url.txt` | |
| What's New in This Version | `store/metadata/<set>/release_notes.txt` | 4000 characters |

For the version as a whole:

| Field | Value |
| --- | --- |
| Version | 1.1.0 |
| Copyright | 2026 Thomas Baxter |
| Build | The app-store-build.yml build from main after pull requests #10 and #11 (section 0); never 1.1.0 (23) |
| In-App Purchases and Subscriptions | Select all three: Taken Pro Yearly, Taken Pro Monthly, Taken Pro Lifetime |
| App Review Information, Sign-in required | Off |
| Contact | Thomas Baxter, tjpb2@cantab.ac.uk (`store/metadata/review_information/email_address.txt`), and the phone number on the account |
| Notes | `store/metadata/review_information/notes.txt` (4000 bytes; step 12 is the Weight tab, so the build must have it) |
| Attachment | none |
| Version Release | Manually release this version, so the 1.1 support and privacy text goes live with it (pull request #12; own choice) |

## 7. Submit

Add for Review, with version 1.1.0, the subscription group and all three in-app purchases in one submission, then Submit to App Review.

## 8. After approval

1. On the day 1.1.0 goes live (released by hand), merge pull request #12, "Site text for 1.1 (merge on release day)" (branch `release/1.1-site`: the privacy policy with weigh-ins, the weight goal and 13+, and the 1.1 support answers), after setting the effective date in `docs/privacy.html` to that day. GitHub Pages publishes `docs/` from main.
