import Foundation

/// The one local notification before an introductory trial ends (PRO.md): two days before, at the nudge time when the
/// nudge is on and 10:00 otherwise, saying when it ends and what was logged. Only while the trial is set to renew;
/// cancelling or converting withdraws it. RevenueCat: "Don't be the dark-UX company that hides the upcoming charge"
/// (https://www.revenuecat.com/blog/growth/first-renewal-churn.md); 39.8% of 7-day trial cancellations happen on day 0
/// (https://www.revenuecat.com/state-of-subscription-apps), so a reminder is what lets someone try it without fear.
enum TrialReminder {
    static let identifier = "taken.pro.trial-end"
    /// Before the end, in calendar days.
    static let daysBefore = 2
    /// When the nudge is off.
    static let defaultMinutes = 10 * 60

    struct Plan: Equatable, Sendable {
        let fireDate: Date
        let components: DateComponents
        let body: String
    }

    /// The reminder that should exist now, or nil: not on a trial, the trial set not to renew (cancelled), a billing
    /// issue, or the moment already past.
    static func plan(status: ProStatus?, state: StackState, now: Date, timeZone: TimeZone = .current) -> Plan? {
        guard let status, status.isPro, status.reason == .trial, status.willRenew != false, !status.billingIssue,
              let end = status.expiresAt, end > now else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let minutes = state.settings.reminderEnabled ? state.settings.reminderMinutes : defaultMinutes
        let endDay = calendar.startOfDay(for: end)
        guard let day = calendar.date(byAdding: .day, value: -daysBefore, to: endDay),
              let fire = calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: day),
              fire > now, fire < end else { return nil }
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
        components.timeZone = timeZone
        return Plan(fireDate: fire, components: components,
                    body: body(end: end, doses: state.doses.count, timeZone: timeZone))
    }

    /// "Your Taken trial ends Sunday. 12 doses logged so far." The weekday the trial really ends, where the iPhone is.
    static func body(end: Date, doses: Int, timeZone: TimeZone = .current) -> String {
        let weekday = Fmt.weekday(DayKey(calendarDateOf: end, in: timeZone))
        let lead = "Your Taken trial ends \(weekday)."
        switch doses {
        case 0: return lead
        case 1: return "\(lead) 1 dose logged so far."
        default: return "\(lead) \(doses) doses logged so far."
        }
    }
}
