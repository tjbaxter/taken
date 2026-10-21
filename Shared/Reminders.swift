import Foundation
import UserNotifications

/// One global nudge. Individual, non-repeating requests for the next 14 days, rebuilt after every
/// change, so a finished day never gets a notification.
enum Reminders {
    static let categoryID = "taken.nudge"
    static let takeAllActionID = "taken.nudge.take-all"
    static let openActionID = "taken.nudge.open"
    static let requestPrefix = "taken.nudge.day."
    /// The one-off note that a TAKE ALL on an earlier day's nudge logged nothing.
    static let staleIdentifier = "taken.nudge.stale"
    /// The one-off note that a nudge's TAKE ALL logged nothing because logging needs Taken Pro.
    static let lockedIdentifier = "taken.pro.locked"
    /// userInfo key holding the logical day (DayKey ordinal) a nudge is for.
    static let dayKey = "day"
    static let horizonDays = 14

    struct Plan: Equatable, Sendable {
        let identifier: String
        let day: DayKey
        let fireDate: Date
        let components: DateComponents
        let body: String
    }

    /// Pure planning, unit tested: which nudges should exist right now. Without Taken Pro there are none, and a
    /// plan set not to renew is nudged only until it ends (PRO.md). A weekly item is nudged on its due day only: never
    /// on the six days after it while its week is open (how late a dose may still be taken differs by medicine, so a
    /// later prompt would be dosing advice), and never on a due day an early dose already counts for (SPEC 3.3, R4).
    static func plan(state: StackState, now: Date, timeZone: TimeZone = .current, window: NudgeWindow = .open) -> [Plan] {
        guard window != .closed, state.settings.reminderEnabled, !state.items.isEmpty else { return [] }
        let clock = DayClock(dayStartHour: state.settings.dayStartHour, timeZone: timeZone)
        let engine = StackEngine(state: state, clock: clock)
        let today = clock.day(for: now)
        let hour = state.settings.reminderMinutes / 60
        let minute = state.settings.reminderMinutes % 60
        var plans: [Plan] = []
        for offset in 0..<horizonDays {
            let day = today.adding(offset)
            let fire = clock.date(on: day, hour: hour, minute: minute)
            guard fire > now else { continue }
            if case .until(let end) = window, fire >= end { break }
            let summary = offset == 0 ? engine.todaySummary(now: now) : engine.summary(for: day)
            let pending = summary.items.filter { $0.isPending && !$0.item.archived }
            guard !pending.isEmpty else { continue }
            var components = clock.calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
            components.timeZone = timeZone
            plans.append(Plan(identifier: requestPrefix + String(day.ordinal), day: day, fireDate: fire,
                              components: components, body: body(for: pending.map { $0.item.code })))
        }
        return plans
    }

    /// The logical day a nudge was for: from its userInfo, else from its identifier ("taken.nudge.day.20738").
    static func nudgeDay(identifier: String, userInfo: [AnyHashable: Any] = [:]) -> DayKey? {
        if let ordinal = userInfo[dayKey] as? Int { return DayKey(ordinal: ordinal) }
        guard identifier.hasPrefix(requestPrefix), let ordinal = Int(identifier.dropFirst(requestPrefix.count)) else {
            return nil
        }
        return DayKey(ordinal: ordinal)
    }

    /// A nudge's TAKE ALL logs only on the day the nudge was for, so last night's nudge tapped this
    /// morning never logs today's doses. A nudge with no day (none are scheduled that way) counts as today's.
    static func isCurrent(nudgeDay: DayKey?, state: StackState, now: Date, timeZone: TimeZone = .current) -> Bool {
        guard let nudgeDay else { return true }
        return nudgeDay == DayClock(dayStartHour: state.settings.dayStartHour, timeZone: timeZone).day(for: now)
    }

    /// Delivered nudges to withdraw from Notification Center: every earlier day's, and today's once nothing
    /// is pending. Today's stays while something is still pending, so its TAKE ALL keeps working.
    static func staleDelivered(_ identifiers: [String], state: StackState, now: Date,
                               timeZone: TimeZone = .current) -> [String] {
        let clock = DayClock(dayStartHour: state.settings.dayStartHour, timeZone: timeZone)
        let today = clock.day(for: now)
        let todayDone = StackEngine(state: state, clock: clock).todaySummary(now: now).pendingItems.isEmpty
        return identifiers.filter { identifier in
            guard let day = nudgeDay(identifier: identifier) else {
                return identifier == staleIdentifier || identifier == lockedIdentifier
            }
            return day < today || (day == today && todayDone)
        }
    }

    /// "Nothing logged. That nudge was for MON 12 OCT. Tap to open that day."
    static func staleBody(day: DayKey) -> String {
        "Nothing logged. That nudge was for \(Fmt.dayHeader(day)). Tap to open that day."
    }

    /// "2 pending: VD3, FSH"
    static func body(for codes: [String]) -> String {
        let shown = codes.prefix(4).joined(separator: ", ")
        let extra = codes.count > 4 ? " +\(codes.count - 4)" : ""
        return "\(codes.count) pending: \(shown)\(extra)"
    }

    static func registerCategories() {
        let takeAll = UNNotificationAction(identifier: takeAllActionID, title: "TAKE ALL", options: [])
        let open = UNNotificationAction(identifier: openActionID, title: "OPEN", options: [.foreground])
        let category = UNNotificationCategory(identifier: categoryID, actions: [takeAll, open],
                                              intentIdentifiers: [], options: [])
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    static func requestPermission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        return granted
    }

    static func isAuthorized() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return true
        default: return false
        }
    }

    static func isDenied() async -> Bool {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .denied
    }

    /// Replace every pending nudge with a fresh plan, and withdraw delivered nudges that no longer apply. The trial
    /// reminder (`TrialReminder`) is rebuilt with them, so its count stays current and a cancelled or converted trial
    /// never gets one. Neither asks for permission: only Turn on does.
    static func reschedule(state: StackState, now: Date) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let ours = pending.map(\.identifier).filter { $0.hasPrefix(requestPrefix) || $0 == TrialReminder.identifier }
        if !ours.isEmpty { center.removePendingNotificationRequests(withIdentifiers: ours) }

        let delivered = await center.deliveredNotifications().map(\.request.identifier)
        let stale = staleDelivered(delivered, state: state, now: now)
        if !stale.isEmpty { center.removeDeliveredNotifications(withIdentifiers: stale) }

        let ledger = ProLedgerStore.shared.load()
        let window = ProGate.nudgeWindow(access: ProGate.access(ledger: ledger, state: state, now: now), status: ledger?.status)
        let plans = plan(state: state, now: now, window: window)
        let trial = TrialReminder.plan(status: ledger?.status, state: state, now: now)
        guard !plans.isEmpty || trial != nil, await isAuthorized() else { return }

        if let trial {
            let content = UNMutableNotificationContent()
            content.body = trial.body
            content.sound = .default
            content.threadIdentifier = "taken.pro"
            let trigger = UNCalendarNotificationTrigger(dateMatching: trial.components, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: TrialReminder.identifier, content: content,
                                                        trigger: trigger))
        }

        for plan in plans {
            let content = UNMutableNotificationContent()
            content.body = plan.body
            content.sound = .default
            content.categoryIdentifier = categoryID
            content.threadIdentifier = "taken.nudge"
            content.userInfo = [dayKey: plan.day.ordinal]
            let trigger = UNCalendarNotificationTrigger(dateMatching: plan.components, repeats: false)
            let request = UNNotificationRequest(identifier: plan.identifier, content: content, trigger: trigger)
            try? await center.add(request)
        }
    }

    /// TAKE ALL on a nudge logs nothing while logging needs Taken Pro. Say so; a tap opens Taken, which offers the
    /// same TAKE ALL with the paywall.
    static func explainLocked() async {
        guard await isAuthorized() else { return }
        let content = UNMutableNotificationContent()
        content.body = ProCopy.lockedDialog
        content.threadIdentifier = "taken.nudge"
        let request = UNNotificationRequest(identifier: lockedIdentifier, content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }

    /// TAKE ALL on an earlier day's nudge logs nothing. Say so quietly, and let a tap open that day.
    static func explainStale(day: DayKey) async {
        guard await isAuthorized() else { return }
        let content = UNMutableNotificationContent()
        content.body = staleBody(day: day)
        content.threadIdentifier = "taken.nudge"
        content.userInfo = [dayKey: day.ordinal]
        let request = UNNotificationRequest(identifier: staleIdentifier, content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }
}
