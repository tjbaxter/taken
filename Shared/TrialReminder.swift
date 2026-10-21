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

/// The one local notification before an introductory trial ends: on the day the paywall promised (the trial's length
/// minus 3), at least 72 hours before StoreKit's end of the trial, at the nudge time when the nudge is on and 10:00 when
/// it is off, with the end date, the price it turns into, what was logged and how to cancel. Only while the trial is
/// set to renew and Profile's Trial reminder is on; at most one, never Time Sensitive, and only with notification
/// permission (`Reminders.reschedule`).
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

    /// The reminder that should exist now, or nil: no renewing trial, Profile's Trial reminder off, the moment already
    /// past, or this trial's reminder already gone out (`sent`, so it never comes twice, even when a later nudge time or
    /// a flight west would put the moment in the future again). A trial of 3 days or less never gets one: 72 hours
    /// before its end is its start, which is already past.
    static func plan(status: ProStatus?, price: PlanPrice?, state: StackState, now: Date,
                     timeZone: TimeZone = .current, sent: TrialReminderMark? = nil) -> Plan? {
        guard state.settings.trialReminderEnabled, isRenewingTrial(status, now: now), let end = status?.expiresAt
        else { return nil }
        if let sent, sent.trialEnd == end, sent.fireAt <= now { return nil }
        guard let fire = fireDate(end: end, settings: state.settings, timeZone: timeZone), fire > now else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
        components.timeZone = timeZone
        return Plan(fireDate: fire, components: components,
                    body: body(end: end, price: price, doses: state.doses.count, timeZone: timeZone))
    }

    /// What `ProLedger.trialReminder` says after a reschedule: the reminder just handed to iOS; else the earlier one
    /// once its moment has passed (it has gone out, so it never comes again for that trial); else nothing (a pending
    /// one was removed without a replacement).
    static func nextMark(trial: Plan?, end: Date?, previous: TrialReminderMark?, now: Date) -> TrialReminderMark? {
        if let trial, let end { return TrialReminderMark(trialEnd: end, fireAt: trial.fireDate) }
        if let previous, previous.fireAt <= now { return previous }
        return nil
    }

    /// The fire moment for these settings: the nudge time while the nudge is on, 10:00 while it is off, and the
    /// wake-up time as the end of the night.
    static func fireDate(end: Date, settings: StackSettings, timeZone: TimeZone = .current) -> Date? {
        fireDate(end: end, minutes: settings.reminderEnabled ? settings.reminderMinutes : defaultMinutes,
                 wakeMinutes: settings.wakeMinutes, timeZone: timeZone)
    }

    /// On the day the paywall promised: the calendar day, where the iPhone is, of the moment 72 hours before `end`
    /// (day 4 of a 7-day trial). At `minutes` past midnight when that is at least 72 hours before the end; otherwise at
    /// that 72-hour moment itself, to the minute, which is the time of day the trial began. Only when that moment falls
    /// before the person's wake-up time does it move to the day before at `minutes` (own choice: never in the night,
    /// and earlier than the promise, never later).
    static func fireDate(end: Date, minutes: Int, wakeMinutes: Int = StackSettings.defaultWakeMinutes,
                         timeZone: TimeZone = .current) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        // Down to the minute, so a trigger set to the minute is never under 72 hours.
        guard let latest = calendar.dateInterval(of: .minute, for: end.addingTimeInterval(-lead))?.start else {
            return nil
        }
        let chosen = StackSettings.clampMinutes(minutes)
        let day = calendar.startOfDay(for: latest)
        guard let onDay = calendar.date(bySettingHour: chosen / 60, minute: chosen % 60, second: 0, of: day) else {
            return nil
        }
        if onDay <= latest { return onDay }
        let parts = calendar.dateComponents([.hour, .minute], from: latest)
        let latestMinutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        if latestMinutes >= StackSettings.clampMinutes(wakeMinutes) { return latest }
        guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { return nil }
        return calendar.date(bySettingHour: chosen / 60, minute: chosen % 60, second: 0, of: previous)
    }

    /// "Your Taken trial ends Sunday 1 Nov. Unless cancelled, it then renews at $19.99 a year. 12 doses logged so far.
    /// Cancel at least 24 hours before in Settings > your name > Subscriptions." The day and date the trial really ends,
    /// where the iPhone is; the price as StoreKit last gave it for the plan that renews (left out if it never has, never
    /// made up); no count with nothing logged. Worded to stay true when the trial was cancelled where Taken has not seen
    /// it yet. No sales copy and no offer.
    static func body(end: Date, price: PlanPrice?, doses: Int, timeZone: TimeZone = .current) -> String {
        let day = DayKey(calendarDateOf: end, in: timeZone)
        var parts = ["Your Taken trial ends \(Fmt.weekday(day)) \(Fmt.shortDate(end, year: false, timeZone: timeZone))."]
        if let price {
            parts.append("Unless cancelled, it then renews at \(ProCopy.renewal(price)).")
        } else {
            parts.append("Unless cancelled, it then renews.")
        }
        switch doses {
        case 0: break
        case 1: parts.append("1 dose logged so far.")
        default: parts.append("\(doses) doses logged so far.")
        }
        parts.append(howToCancel)
        return parts.joined(separator: " ")
    }

    /// How to cancel, as the reminder says it. Apple: "In Settings, tap your name." then "Tap Subscriptions.", and
    /// "cancel it at least 24 hours before the trial ends" (https://support.apple.com/en-us/118428).
    static let howToCancel = "Cancel at least 24 hours before in Settings > your name > Subscriptions."

    /// Profile > Reminder's footnote while the Trial reminder switch shows.
    static let settingFootnote = "The trial reminder comes once, 3 days before your trial ends."

    /// The same notice as a line on Today while notifications cannot carry it (not allowed in iOS Settings): from the
    /// moment the reminder would have come until the trial ends, under the same rules (a renewing trial, Profile's Trial
    /// reminder on), so the paywall's "we remind you" holds without notification permission. Nil otherwise.
    static func notice(status: ProStatus?, price: PlanPrice?, state: StackState, now: Date,
                       timeZone: TimeZone = .current) -> String? {
        guard state.settings.trialReminderEnabled, isRenewingTrial(status, now: now), let end = status?.expiresAt
        else { return nil }
        let from = fireDate(end: end, settings: state.settings, timeZone: timeZone) ?? end.addingTimeInterval(-lead)
        guard now >= from else { return nil }
        return body(end: end, price: price, doses: state.doses.count, timeZone: timeZone)
    }
}

/// The trial reminder as handed to iOS (`ProLedger.trialReminder`): the trial end it is for and the moment it fires.
struct TrialReminderMark: Codable, Hashable, Sendable {
    var trialEnd: Date
    var fireAt: Date

    init(trialEnd: Date, fireAt: Date) {
        self.trialEnd = trialEnd
        self.fireAt = fireAt
    }
}

/// Whether notifications may be sent, as iOS last said.
enum NotificationPermission: Equatable, Sendable {
    /// iOS has not asked yet.
    case notDetermined
    case denied
    case allowed
}

/// The one notification ask right after a trial starts: one short sheet with both reasons and a single Continue
/// button that opens iOS's prompt. Apple's HIG for a screen before a permission alert: "Include only one button and
/// make it clear that it opens the system alert", titled like "Continue", never "Allow", and no way "to leave the
/// screen or window without viewing the system alert, like offering an option to close or cancel"
/// (https://developer.apple.com/design/human-interface-guidelines/privacy). iOS's own alert carries the no. Never
/// provisional.
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
    /// The one button: iOS's prompt follows.
    static let allow = "Continue"

    static func body(mentionsReminder: Bool) -> String { mentionsReminder ? body : bodyNudgeOnly }

    /// Every line, for the copy rules test.
    static var all: [String] { [title, body, bodyNudgeOnly, allow, TrialReminder.howToCancel, TrialReminder.settingFootnote] }
}
