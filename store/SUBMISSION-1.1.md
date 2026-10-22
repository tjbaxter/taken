# Taken 1.1.0: App Store Connect submission checklist

Everything App Store Connect asks for version 1.1.0, in the order its pages ask, with the file each value comes from. `scripts/check-store-metadata.py` checks every text below against Apple's limits in CI (ci.yml, "Store metadata"). Why each choice was made, with sources: REDESIGN.md, "App Store pack for 1.1".

## 0. Before you start

- 1.0 has left App Review. App Store Connect takes one version submission per platform at a time (https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/overview-of-submitting-for-review).
- The build. Only a build from `.github/workflows/app-store-build.yml` goes in: never an internal build. Internal builds are exported TestFlight internal testing only and App Store Connect never offers them for a version; 1.1.0 (8) and (9) predate that and still show as Ready to Submit, so never pick them. `scripts/check-app-store-build.sh` (Guideline 2.5.19) and the rest of `scripts/check-ipa.sh` ran on the IPA before upload.
  - Current build: **1.1.0 (23)**, from app-store-build.yml run 39680420022 (https://github.com/tjbaxter/taken/actions/runs/39680420022) on main at 164a893, every check-ipa.sh line OK.
  - If main has changed in anything that goes into the app since that commit (`git diff --stat 164a893 origin/main -- Taken Shared TakenWidgets project.yml .eas eas.json app.json`), run app-store-build.yml again from main and attach the new build instead. Merging the App Store pack's pull request changes four Swift files (demo data and the Debug-only `-demo-stack` argument, which no App Store build reads), so after it merges, rebuild before you submit.
- Read the Primary Language first: App Information, General, Primary Language. Section 2 depends on it.

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

Every storefront but the United States, Canada and Japan lists English (U.K.) as its default or an additional language, Australia and New Zealand list English (Australia) too, Canada lists English (Canada), and English (U.S.) is listed only in the United States (default) and Japan (additional) (https://developer.apple.com/help/app-store-connect/reference/app-information/app-store-localizations). Where no localization matches, the primary language shows (https://developer.apple.com/help/app-store-connect/manage-app-information/localize-app-information).

| Localization | Copy | Screenshots, 6.9 inch and 6.3 inch |
| --- | --- | --- |
| English (U.S.) | `store/metadata/en-US/` | `store/appstore/iphone-6.9/en-US/`, `store/appstore/iphone-6.3/en-US/` (only when English (U.S.) is not the primary language: see below) |
| English (U.K.) | `store/metadata/neutral/` | `store/appstore/iphone-6.9/neutral/`, `store/appstore/iphone-6.3/neutral/` |
| English (Australia) | `store/metadata/neutral/` | the neutral set |
| English (Canada) | `store/metadata/neutral/` | the neutral set |

If the Primary Language is English (U.S.), it is what every storefront without a matching localization shows, so in 1.1 English (U.S.) takes the **neutral** copy and the **neutral** screenshots too. Add English (U.K.) in 1.1 with the neutral set uploaded to it (a new language starts with the primary language's screenshots, so upload them; do not leave them derived). Once 1.1 is approved, change the Primary Language to English (U.K.) in the next version, then give English (U.S.) `store/metadata/en-US/` and the en-US screenshots. Apple's rule for a new primary language: it was added to a previous version, App Review approved it, and its own screenshots, at the same sizes as the current primary's, were approved (same page). If the Primary Language is already English (U.K.), English (Australia) or English (Canada), English (U.S.) gets its own copy and screenshots in 1.1.

Japan lists English (U.S.) as its one English, so once English (U.S.) shows the en-US set, Japanese storefront visitors can see it too. A Japanese localization holding the neutral text and screenshots would keep it to the United States; no Apple page says whether English text in a Japanese localization is acceptable, so that is Tom's call.

Screenshots: upload all six PNGs of a set, in order 01 to 06, to both iPhone sizes: iPhone 6.9" Display (1320 x 2868, `iphone-6.9`) and iPhone 6.3" Display (1206 x 2622, `iphone-6.3`). The medium display is the size App Store Connect requires (https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications). The contact sheets (`store/appstore/contact-sheet-<set>.jpg`) are for looking, not for upload.

## 3. Pricing and Availability

- Price: the no-charge tier, as 1.0. Taken Pro is in-app purchases (section 4).
- Availability: every country or region, as 1.0 (Tom: "We're a global app on the App Store").

## 4. In-App Purchases and Subscriptions (before the version page)

Values in `store/iap/products.json`; product ids are fixed (PRO.md). Each needs its display name and description in every localization the app has (the same text in each), and the review screenshot `store/iap/paywall.png` (the paywall as ci.yml captures it, refreshed by store-shots.yml).

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

Data Not Collected, unchanged (https://developer.apple.com/app-store/app-privacy-details/). Purchases go through Apple; speech, sorting and every file stay on the iPhone.

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
| Build | 1.1.0 (23), or the newer app-store-build.yml build (section 0) |
| In-App Purchases and Subscriptions | Select all three: Taken Pro Yearly, Taken Pro Monthly, Taken Pro Lifetime |
| App Review Information, Sign-in required | Off |
| Contact | Thomas Baxter, tjpb2@cantab.ac.uk (`store/metadata/review_information/email_address.txt`), and the phone number on the account |
| Notes | `store/metadata/review_information/notes.txt` (4000 bytes) |
| Attachment | none |
| Version Release | Manually release this version, so the 1.1 support and privacy text in `docs/` goes live with it (REDESIGN.md, "Publish with 1.1"; own choice) |

## 7. Submit

Add for Review, with version 1.1.0, the subscription group and all three in-app purchases in one submission, then Submit to App Review.

## 8. After approval

1. Publish REDESIGN.md's "Publish with 1.1" text to `docs/`, then release 1.1.0 by hand.
2. If English (U.S.) was the primary language: in the next version, change the primary language to English (U.K.) and give English (U.S.) its own copy and screenshots (section 2).
