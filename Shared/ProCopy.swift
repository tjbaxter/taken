import Foundation

// The paywall's and Settings' words, built from what StoreKit says about each product, never from numbers in the
// code (PRO.md). Pure, so every line Apple requires is unit tested. Copy rules: no em or en dashes, never the word
// for no charge, no exclamation marks.

/// A billing period as StoreKit gives it: 1 year, 1 month, 1 week (or 7 days).
struct PlanPeriod: Hashable, Sendable {
    enum Unit: Hashable, Sendable {
        case day
        case week
        case month
        case year
    }

    let value: Int
    let unit: Unit

    init(value: Int, unit: Unit) {
        self.value = max(value, 1)
        self.unit = unit
    }

    /// Days in it, for day and week periods.
    var days: Int? {
        switch unit {
        case .day: return value
        case .week: return value * 7
        case .month, .year: return nil
        }
    }

    /// Months in it, for month and year periods.
    var months: Int? {
        switch unit {
        case .month: return value
        case .year: return value * 12
        case .day, .week: return nil
        }
    }

    var unitWord: String {
        switch unit {
        case .day: return "day"
        case .week: return "week"
        case .month: return "month"
        case .year: return "year"
        }
    }
}

/// A product's introductory offer.
struct IntroTerms: Hashable, Sendable {
    enum Mode: Hashable, Sendable {
        /// The whole span costs nothing ("7 days on us").
        case onUs
        /// A reduced price each period.
        case payAsYouGo
        /// One reduced payment for the span.
        case payUpFront
    }

    let mode: Mode
    let period: PlanPeriod
    let periodCount: Int
    let displayPrice: String

    init(mode: Mode, period: PlanPeriod, periodCount: Int, displayPrice: String) {
        self.mode = mode
        self.period = period
        self.periodCount = max(periodCount, 1)
        self.displayPrice = displayPrice
    }
}

/// One plan as the paywall shows it, in StoreKit's terms: its display price, its price as a number with the
/// storefront's currency, its billing period (nil for one payment) and its introductory offer.
struct PlanOffer: Hashable, Sendable {
    let plan: ProPlan
    let displayPrice: String
    let price: Decimal
    let currencyCode: String
    let locale: Locale
    let period: PlanPeriod?
    let intro: IntroTerms?

    init(plan: ProPlan, displayPrice: String, price: Decimal, currencyCode: String, locale: Locale,
         period: PlanPeriod?, intro: IntroTerms?) {
        self.plan = plan
        self.displayPrice = displayPrice
        self.price = price
        self.currencyCode = currencyCode
        self.locale = locale
        self.period = period
        self.intro = intro
    }
}

enum ProCopy {
    static let termsOfUseURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    static let privacyURL = URL(string: "https://tjbaxter.github.io/taken/privacy.html")!

    static let headline = "Keep your record."
    static let subline = "Every dose, logged to the minute. Widgets, Lock Screen, Siri."
    static let features = ["ONE TAP LOGGING + TAKE ALL", "HOME, LOCK SCREEN + CONTROL CENTER", "FULL HISTORY + CSV EXPORT"]

    /// What Siri, Shortcuts and a nudge say when logging needs Pro.
    static let lockedDialog = "Logging needs Taken Pro. Open Taken to continue."
    static let renewalTerms = "Renews automatically until cancelled. Cancel anytime in Settings at least 24 hours before renewal."
    static let lifetimeTerms = "One payment. Yours for good."

    /// The whole introductory span: "7 days", "1 month".
    static func span(_ intro: IntroTerms) -> String {
        if let days = intro.period.days {
            let total = days * intro.periodCount
            return total == 1 ? "1 day" : "\(total) days"
        }
        let total = intro.period.value * intro.periodCount
        let word = intro.period.unitWord
        return total == 1 ? "1 \(word)" : "\(total) \(word)s"
    }

    /// "7 DAYS ON US", for an introductory offer that costs nothing. Nil for any other kind.
    static func introTag(_ intro: IntroTerms?) -> String? {
        guard let intro, intro.mode == .onUs else { return nil }
        return "\(span(intro).uppercased()) ON US"
    }

    /// The card's billed amount and its unit: ("$19.99", "/ year"), ("$49.99", "once").
    static func price(_ offer: PlanOffer) -> (amount: String, unit: String) {
        guard let period = offer.period else { return (offer.displayPrice, "once") }
        return (offer.displayPrice, period.value == 1 ? "/ \(period.unitWord)" : "/ \(period.value) \(period.unitWord)s")
    }

    /// "about $1.67 / month", under a yearly price. Smaller than the billed amount, which stays the headline.
    static func monthlyEquivalent(_ offer: PlanOffer) -> String? {
        guard let period = offer.period, period.unit == .year, let months = period.months, months > 0 else { return nil }
        let style = Decimal.FormatStyle.Currency(code: offer.currencyCode, locale: offer.locale)
        let perMonth = offer.price / Decimal(months)
        return "about \(perMonth.formatted(style)) / month"
    }

    /// The introductory offer the customer can still have on this plan, if any.
    static func liveIntro(_ offer: PlanOffer?, eligible: Bool) -> IntroTerms? {
        guard eligible, let offer, offer.plan.isSubscription else { return nil }
        return offer.intro
    }

    /// The primary button: START 7 DAYS ON US while the offer applies, CONTINUE otherwise.
    static func cta(_ offer: PlanOffer?, eligible: Bool) -> String {
        if let tag = introTag(liveIntro(offer, eligible: eligible)) { return "START \(tag)" }
        return "CONTINUE"
    }

    /// The plain terms line under the button, for the selected plan.
    /// "7 days on us, then $19.99 per year. Renews automatically until cancelled. Cancel anytime in Settings at
    /// least 24 hours before renewal."
    static func terms(_ offer: PlanOffer, eligible: Bool) -> String {
        guard let period = offer.period else { return lifetimeTerms }
        let recurring = "\(offer.displayPrice) \(per(period))"
        var lead = "\(recurring)."
        if let intro = liveIntro(offer, eligible: eligible) {
            switch intro.mode {
            case .onUs:
                lead = "\(span(intro)) on us, then \(recurring)."
            case .payAsYouGo:
                lead = "\(intro.displayPrice) \(per(intro.period)) for \(span(intro)), then \(recurring)."
            case .payUpFront:
                lead = "\(intro.displayPrice) for \(span(intro)), then \(recurring)."
            }
        }
        return "\(lead) \(renewalTerms)"
    }

    /// The terms line before StoreKit has answered: true for every subscription, exact for none.
    static func termsWithoutPrices(_ plan: ProPlan) -> String {
        plan.isSubscription ? renewalTerms : lifetimeTerms
    }

    /// "per year", "every 3 months".
    static func per(_ period: PlanPeriod) -> String {
        period.value == 1 ? "per \(period.unitWord)" : "every \(period.value) \(period.unitWord)s"
    }

    /// The slim bar under the status panel in locked mode.
    static func lockedBar(eligible: Bool?, intro: IntroTerms?) -> String {
        if eligible == true, let tag = introTag(intro) { return "START \(tag)" }
        if eligible == false { return "PRO ENDED \u{00B7} TAP TO CONTINUE" }
        return "TAKEN PRO \u{00B7} TAP TO CONTINUE"
    }

    /// Settings > PRO status line: "FOUNDING MEMBER · PRO FOR LIFE", "PRO YEARLY · RENEWS 12 OCT 2027",
    /// "PRO LIFETIME", "TRIAL · ENDS 19 OCT", "NOT ACTIVE".
    static func statusLine(_ status: ProStatus?, now: Date, timeZone: TimeZone = .current) -> String {
        guard let status, status.isActive(at: now) else { return "NOT ACTIVE" }
        switch status.reason {
        case .founding:
            return "FOUNDING MEMBER \u{00B7} PRO FOR LIFE"
        case .lifetime:
            return "PRO LIFETIME"
        case .trial:
            guard let end = status.expiresAt else { return "TRIAL" }
            return "TRIAL \u{00B7} ENDS \(Fmt.shortDate(end, year: false, timeZone: timeZone))"
        case .yearly, .monthly:
            let name = status.reason == .yearly ? "PRO YEARLY" : "PRO MONTHLY"
            if status.billingIssue { return "\(name) \u{00B7} BILLING ISSUE" }
            guard let end = status.expiresAt else { return name }
            let verb = status.willRenew == false ? "ENDS" : "RENEWS"
            return "\(name) \u{00B7} \(verb) \(Fmt.shortDate(end, year: true, timeZone: timeZone))"
        case .none:
            return "NOT ACTIVE"
        }
    }
}
