import Foundation
import UserNotifications

/// One global nudge. Individual, non-repeating requests for the next 14 days, rebuilt after every
/// change, so a finished day never gets a notification.
enum Reminders {
    static let categoryID = "taken.nudge"
    static let takeAllActionID = "taken.nudge.take-all"
    static let openActionID = "taken.nudge.open"
    static let requestPrefix = "taken.nudge.day."
    static let horizonDays = 14

    struct Plan: Equatable, Sendable {
        let identifier: String
        let day: DayKey
        let fireDate: Date
        let components: DateComponents
        let body: String
    }

    /// Pure planning, unit tested: which nudges should exist right now.
    static func plan(state: StackState, now: Date, timeZone: TimeZone = .current) -> [Plan] {
        guard state.settings.reminderEnabled, !state.items.isEmpty else { return [] }
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

    /// Replace every pending nudge with a fresh plan.
    static func reschedule(state: StackState, now: Date) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let ours = pending.map(\.identifier).filter { $0.hasPrefix(requestPrefix) }
        if !ours.isEmpty { center.removePendingNotificationRequests(withIdentifiers: ours) }

        let plans = plan(state: state, now: now)
        // A day that is now done drops its already-delivered nudge too.
        let today = DayClock(dayStartHour: state.settings.dayStartHour).day(for: now)
        if !plans.contains(where: { $0.day == today }) {
            center.removeDeliveredNotifications(withIdentifiers: [requestPrefix + String(today.ordinal)])
        }
        guard !plans.isEmpty, await isAuthorized() else { return }

        for plan in plans {
            let content = UNMutableNotificationContent()
            content.body = plan.body
            content.sound = .default
            content.categoryIdentifier = categoryID
            content.threadIdentifier = "taken.nudge"
            let trigger = UNCalendarNotificationTrigger(dateMatching: plan.components, repeats: false)
            let request = UNNotificationRequest(identifier: plan.identifier, content: content, trigger: trigger)
            try? await center.add(request)
        }
    }
}
