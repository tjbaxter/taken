import Foundation

// The trial promise and its one reminder (2026-10-21, SPEC 3.9, PRO.md). The paywall promises the reminder under the
// yearly plan (`ProCopy.trialTimeline`); one notification ask follows a trial purchase (`TrialAsk`); and one local
// notification comes at least 3 days before the trial ends (`TrialReminder`). What converts is the promise on the
// paywall: Blinkist's "23% increase in conversion" (https://uxplanet.org/how-solving-our-biggest-customer-complaint-at-blinkist-led-to-a-23-increase-in-conversion-b60ad514134b),
// ShareFile's +16.4% sign-ups (https://marketingsherpa.com/article/case-study/simple-email-cancellation-reminder-lifts);
// 64% of 7-day trial cancellations happen on day 0 to 1 (https://www.revenuecat.com/blog/growth/7-day-trial-subscription-app).
// Utah asks for a notice "at least three days before the day on which" a trial ends, with its date, price and how to
// cancel (https://le.utah.gov/~2024/bills/hbillenr/HB0174.pdf). Copy rules: no em or en dash, never the word for no
// charge, no exclamation marks.

/// The one local notification before an introductory trial ends: at least 72 hours before StoreKit's end of the
/// trial, at the nudge time when the nudge is on and 10:00 when it is off, with the end date, the price it turns into,
/// what was logged and how to cancel. Only while the trial is set to renew; at most one, never Time Sensitive, and only
/// with notification permission (`Reminders.reschedule`).
enum TrialReminder {
    static let identifier = "taken.pro.trial-end"
    /// The paywall promises the reminder this many days before the trial ends (Utah's minimum).
    static let leadDays = 3
    /// At least this long before the end, measured from StoreKit's expiration date.
    static let lead: TimeInterval = TimeInterval(leadDays) * 24 * 60 * 60
    /// When the nudge is off: 10:00 (own choice, from the brief; no source tests a time of day).
    static let defaultMinutes = 10 * 60

    struct Plan: Equatable, Sendable {
        let fireDate: Date
        let components: DateComponents
        let body: String
    }

    /// An introductory trial that is still on and set to renew: not cancelled (`willRenew == false`), not in a billing
    /// issue, not converted (the reason becomes yearly or monthly) and not Pro for good (lifetime and founding beat it).
    static func isRenewingTrial(_ status: ProStatus?, now: Date) -> Bool {
        guard let status, status.isPro, status.reason == .trial, status.willRenew != false, !status.billingIssue,
              let end = status.expiresAt else { return false }
        return end > now
    }

    /// The reminder that should exist now, or nil: no renewing trial, or the moment already past. A trial of 3 days or
    /// less never gets one: 72 hours before its end is its start, which is already past.
    static func plan(status: ProStatus?, price: PlanPrice?, state: StackState, now: Date,
                     timeZone: TimeZone = .current) -> Plan? {
        guard isRenewingTrial(status, now: now), let end = status?.expiresAt else { return nil }
        let minutes = state.settings.reminderEnabled ? state.settings.reminderMinutes : defaultMinutes
        guard let fire = fireDate(end: end, minutes: minutes, timeZone: timeZone), fire > now else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
        components.timeZone = timeZone
        return Plan(fireDate: fire, components: components,
                    body: body(end: end, price: price, doses: state.doses.count, timeZone: timeZone))
    }

    /// The latest moment at `minutes` past midnight (where the iPhone is) that is at least 72 hours before `end`.
    static func fireDate(end: Date, minutes: Int, timeZone: TimeZone = .current) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let latest = end.addingTimeInterval(-lead)
        let hour = min(max(minutes, 0), 24 * 60 - 1) / 60
        let minute = min(max(minutes, 0), 24 * 60 - 1) % 60
        var day = calendar.startOfDay(for: latest)
        for _ in 0..<3 {
            if let fire = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day), fire <= latest {
                return fire
            }
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { return nil }
            day = previous
        }
        return nil
    }

    /// "Your Taken trial ends Sunday 1 Nov. Then $19.99 a year. 12 doses logged so far. Manage in Settings >
    /// Subscriptions." The day and date the trial really ends, where the iPhone is; the price as StoreKit last gave it
    /// (left out if it never has, never made up); no count with nothing logged. No sales copy and no offer.
    static func body(end: Date, price: PlanPrice?, doses: Int, timeZone: TimeZone = .current) -> String {
        let day = DayKey(calendarDateOf: end, in: timeZone)
        var parts = ["Your Taken trial ends \(Fmt.weekday(day)) \(Fmt.shortDate(end, year: false, timeZone: timeZone))."]
        if let price { parts.append("Then \(ProCopy.renewal(price)).") }
        switch doses {
        case 0: break
        case 1: parts.append("1 dose logged so far.")
        default: parts.append("\(doses) doses logged so far.")
        }
        parts.append(manage)
        return parts.joined(separator: " ")
    }

    /// How to cancel, as the reminder says it (Apple: https://support.apple.com/en-us/118428).
    static let manage = "Manage in Settings > Subscriptions."
}

/// Whether notifications may be sent, as iOS last said.
enum NotificationPermission: Equatable, Sendable {
    /// iOS has not asked yet.
    case notDetermined
    case denied
    case allowed
}

/// The one notification ask right after a trial starts: one short sheet with both reasons, a Continue button that
/// opens iOS's prompt (Apple's HIG: a pre-prompt button titled like Continue, never Allow,
/// https://developer.apple.com/design/human-interface-guidelines/privacy) and a quiet Not now. Never provisional.
enum TrialAsk {
    /// Show the sheet: a trial just started, iOS has not asked about notifications yet, and the sheet never showed.
    /// Once iOS has an answer, the reminder simply follows it (`Reminders.reschedule`).
    static func shows(trialStarted: Bool, permission: NotificationPermission, alreadyShown: Bool) -> Bool {
        trialStarted && permission == .notDetermined && !alreadyShown
    }

    /// The reminder is part of the ask while the trial is long enough to get one (more than 3 days left).
    static func mentionsReminder(status: ProStatus?, now: Date) -> Bool {
        guard let status, status.reason == .trial, let end = status.expiresAt else { return true }
        return end.timeIntervalSince(now) > TrialReminder.lead
    }

    static let title = "Your trial has started."
    static let body = "Get the evening nudge and a heads-up 3 days before your trial ends."
    /// For a trial too short for the reminder.
    static let bodyNudgeOnly = "Get the evening nudge if anything's left."
    static let allow = "Continue"
    static let notNow = "Not now"

    static func body(mentionsReminder: Bool) -> String { mentionsReminder ? body : bodyNudgeOnly }

    /// Every line, for the copy rules test.
    static var all: [String] { [title, body, bodyNudgeOnly, allow, notNow, TrialReminder.manage] }
}
