import Foundation

// The paywall's and Settings' words, built from what StoreKit says about each product, never from numbers in the
// code (PRO.md). Pure, so every line Apple requires is unit tested. Copy rules: no em or en dashes, never the word
// for no charge, no exclamation marks.

/// A billing period as StoreKit gives it: 1 year, 1 month, 1 week (or 7 days). Codable, so the price a trial turns
/// into can be cached for the trial reminder (`ProLedger.prices`).
struct PlanPeriod: Codable, Hashable, Sendable {
    enum Unit: String, Codable, Hashable, Sendable {
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

    private enum CodingKeys: String, CodingKey { case value, unit }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(value: try c.decode(Int.self, forKey: .value), unit: try c.decode(Unit.self, forKey: .unit))
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

/// A plan's recurring price as StoreKit gives it: "$19.99" and 1 year. Cached in `pro.json` (`ProLedger.prices`) so the
/// trial reminder, which may be scheduled from a widget or an intent where StoreKit does not run, names the real price.
struct PlanPrice: Codable, Hashable, Sendable {
    var displayPrice: String
    var period: PlanPeriod

    init(displayPrice: String, period: PlanPeriod) {
        self.displayPrice = displayPrice
        self.period = period
    }

    /// The recurring price of a subscription offer; nil for one payment.
    init?(_ offer: PlanOffer) {
        guard let period = offer.period else { return nil }
        self.init(displayPrice: offer.displayPrice, period: period)
    }
}

/// One step of the paywall's trial timeline: "Today" and "full Pro".
struct TrialStep: Hashable, Sendable {
    let day: String
    let text: String

    /// "Day 4: we remind you", as VoiceOver reads it.
    var line: String { "\(day): \(text)" }
    /// The text as the timeline sets it, under its day: "We remind you".
    var displayText: String { text.prefix(1).uppercased() + text.dropFirst() }
}

enum ProCopy {
    static let termsOfUseURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    static let privacyURL = URL(string: "https://tjbaxter.github.io/taken/privacy.html")!

    static let headline = "Keep your record."
    static let subline = "Every dose, logged to the minute. Widgets, Lock Screen, Siri."
    /// The subline as the paywall sets it: one thought per line.
    static let sublineLines = "Every dose, logged to the minute.\nWidgets, Lock Screen, Siri."
    /// What Pro unlocks, and only that: the log, the history and CSV export stay open without it.
    static let features = ["One-tap logging and Take all", "Home Screen, Lock Screen and Control Center",
                           "Siri and the evening nudge", "Voice to-dos"]

    /// What Siri, Shortcuts and a nudge say when logging needs Pro.
    static let lockedDialog = "Logging needs Taken Pro. Open Taken to continue."
    /// Profile > Reminder without Pro: no nudge is scheduled.
    static let nudgeLocked = "The nudge needs Taken Pro"
    /// Restore found Pro.
    static let restored = "Restored. Taken Pro is on."
    /// Restore found nothing active: true for someone who never bought and for a plan that ended.
    static let nothingToRestore = "No active Taken Pro on this Apple Account."
    /// Profile > Taken Pro for a lifetime or founding member whose subscription still renews.
    static let renewingNextToProForGood = "Your subscription still renews. Taken Pro is yours for good, so you can cancel it."
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

    /// "7 days on us", for an introductory offer that costs nothing. Nil for any other kind.
    static func introTag(_ intro: IntroTerms?) -> String? {
        guard let intro, intro.mode == .onUs else { return nil }
        return "\(span(intro)) on us"
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

    /// The primary button: "Start 7 days on us" while the offer applies, "Continue" otherwise.
    static func cta(_ offer: PlanOffer?, eligible: Bool) -> String {
        if let tag = introTag(liveIntro(offer, eligible: eligible)) { return "Start \(tag)" }
        return "Continue"
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

    /// "a year", "every 3 months": how the trial timeline and the trial reminder say what follows the trial.
    static func perPlain(_ period: PlanPeriod) -> String {
        period.value == 1 ? "a \(period.unitWord)" : "every \(period.value) \(period.unitWord)s"
    }

    /// "$19.99 a year", from StoreKit's display price and period.
    static func renewal(_ price: PlanPrice) -> String {
        "\(price.displayPrice) \(perPlain(price.period))"
    }

    // MARK: The trial promise (2026-10-21)

    /// The whole introductory span in days: a day or week offer by count, a month or year one on the calendar from
    /// `now`, so "1 month" from 21 Oct is 31 days.
    static func trialDays(_ intro: IntroTerms, from now: Date, timeZone: TimeZone = .current) -> Int {
        if let days = intro.period.days { return days * intro.periodCount }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let component: Calendar.Component = intro.period.unit == .year ? .year : .month
        guard let end = calendar.date(byAdding: component, value: intro.period.value * intro.periodCount, to: now) else {
            return 0
        }
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: end)).day ?? 0
    }

    /// The three steps under the yearly plan while its introductory offer costs nothing and this Apple Account can still
    /// have it: "Today: full Pro", "Day 4: we remind you", "Day 7: $19.99 a year starts". Built from StoreKit's trial
    /// length, display price and period, never from numbers in the code; the reminder day is the trial length minus
    /// `TrialReminder.leadDays`, and a trial of 3 days or less has no reminder step (it gets no reminder). Nor does it
    /// when notifications are already turned off for Taken (`remindable` false): the paywall never promises a reminder
    /// it knows cannot come. Empty when there is no such offer.
    static func trialTimeline(_ offer: PlanOffer?, eligible: Bool, now: Date, timeZone: TimeZone = .current,
                              remindable: Bool = true) -> [TrialStep] {
        guard let offer, let price = PlanPrice(offer), let intro = liveIntro(offer, eligible: eligible),
              intro.mode == .onUs else { return [] }
        let days = trialDays(intro, from: now, timeZone: timeZone)
        guard days >= 1 else { return [] }
        var steps = [TrialStep(day: "Today", text: "full Pro")]
        if remindable && days > TrialReminder.leadDays {
            steps.append(TrialStep(day: "Day \(days - TrialReminder.leadDays)", text: "we remind you"))
        }
        steps.append(TrialStep(day: "Day \(days)", text: "\(renewal(price)) starts"))
        return steps
    }

    /// The slim bar under Today's progress line in locked mode.
    static func lockedBar(eligible: Bool?, intro: IntroTerms?) -> String {
        if eligible == true, let tag = introTag(intro) { return "Start \(tag)" }
        if eligible == false { return "Pro ended. Tap to continue" }
        return "Taken Pro. Tap to continue"
    }

    /// Profile > Taken Pro status line: "Founding member · Pro for life", "Pro yearly · renews 12 Oct 2027",
    /// "Pro lifetime", "Trial · ends 19 Oct", "Pro yearly · renewing" (the period ended and the renewal has not
    /// shown yet), "Not active".
    static func statusLine(_ status: ProStatus?, now: Date, timeZone: TimeZone = .current) -> String {
        guard let status, status.isActive(at: now) else { return "Not active" }
        switch status.reason {
        case .founding:
            return "Founding member \u{00B7} Pro for life"
        case .lifetime:
            return "Pro lifetime"
        case .trial:
            if status.awaitingRenewal(at: now) { return "Trial \u{00B7} renewing" }
            guard let end = status.expiresAt else { return "Trial" }
            return "Trial \u{00B7} ends \(Fmt.shortDate(end, year: false, timeZone: timeZone))"
        case .yearly, .monthly:
            let name = status.reason == .yearly ? "Pro yearly" : "Pro monthly"
            if status.billingIssue { return "\(name) \u{00B7} billing issue" }
            if status.awaitingRenewal(at: now) { return "\(name) \u{00B7} renewing" }
            guard let end = status.expiresAt else { return name }
            let verb = status.willRenew == false ? "ends" : "renews"
            return "\(name) \u{00B7} \(verb) \(Fmt.shortDate(end, year: true, timeZone: timeZone))"
        case .none:
            return "Not active"
        }
    }
}
