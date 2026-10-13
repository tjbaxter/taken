import Foundation

/// Text formatting. Words in sentence case, times on the 24-hour clock.
enum Fmt {
    private static let weekdaysCaps = ["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"]
    private static let monthsCaps = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]
    private static let weekdaysShort = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    private static let weekdaysLong = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
    private static let monthsShort = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    private static let monthsLong = ["January", "February", "March", "April", "May", "June", "July", "August", "September",
                                     "October", "November", "December"]
    static let weekdayLetters = ["M", "T", "W", "T", "F", "S", "S"]

    private static func month(_ list: [String], _ month: Int) -> String { list[max(0, min(11, month - 1))] }

    /// "07:42"
    static func clock(_ date: Date, _ clock: DayClock) -> String {
        let hm = clock.hourMinute(of: date)
        return String(format: "%02d:%02d", hm.hour, hm.minute)
    }

    /// "04:00" for an hour.
    static func hour(_ hour: Int) -> String {
        String(format: "%02d:00", hour)
    }

    /// "21:00" for minutes after midnight.
    static func minutes(_ minutes: Int) -> String {
        String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }

    /// "9h ago", "12m ago", "now".
    static func ago(_ date: Date, now: Date) -> String {
        let minutes = Int(now.timeIntervalSince(date) / 60)
        if minutes < 1 { return "now" }
        if minutes < 60 { return "\(minutes)m ago" }
        return "\(minutes / 60)h ago"
    }

    /// "9h 12m ago"
    static func agoDetailed(_ date: Date, now: Date) -> String {
        let minutes = Int(now.timeIntervalSince(date) / 60)
        if minutes < 1 { return "just now" }
        if minutes < 60 { return "\(minutes)m ago" }
        let rest = minutes % 60
        return rest == 0 ? "\(minutes / 60)h ago" : "\(minutes / 60)h \(rest)m ago"
    }

    /// "MON 12 OCT", the short day the nudge's notifications name.
    static func dayHeader(_ day: DayKey) -> String {
        let (_, month, dayOfMonth) = day.ymd
        return "\(weekdaysCaps[day.mondayIndex]) \(dayOfMonth) \(self.month(monthsCaps, month))"
    }

    /// "Tuesday 13 October", under the Today title and on the day sheet.
    static func longDay(_ day: DayKey) -> String {
        let (_, month, dayOfMonth) = day.ymd
        return "\(weekdaysLong[day.mondayIndex]) \(dayOfMonth) \(self.month(monthsLong, month))"
    }

    /// "19 Oct", or "12 Oct 2027" with the year, for a moment in a time zone.
    static func shortDate(_ date: Date, year: Bool, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        let dayMonth = "\(c.day ?? 1) \(month(monthsShort, c.month ?? 1))"
        return year ? "\(dayMonth) \(c.year ?? 1970)" : dayMonth
    }

    /// "Daily", "2x daily", "Every other day", "Weekdays", "Mon Wed Fri".
    static func frequency(_ frequency: Frequency) -> String {
        switch frequency {
        case .daily(let times):
            return times <= 1 ? "Daily" : "\(min(times, 3))x daily"
        case .alternateDays:
            return "Every other day"
        case .weekdays(let set):
            if set.isEmpty { return "No days set" }
            if set.count == 7 { return "Daily" }
            if set == [2, 3, 4, 5, 6] { return "Weekdays" }
            if set == [1, 7] { return "Weekends" }
            // Monday-first order.
            let order = [2, 3, 4, 5, 6, 7, 1]
            return order.filter { set.contains($0) }.map { weekdaysShort[($0 + 5) % 7] }.joined(separator: " ")
        }
    }

    /// "Next: tomorrow", "Next: Thursday", "Next: 14 Oct"
    static func next(_ next: DayKey?, today: DayKey) -> String {
        guard let next else { return "Not scheduled" }
        let gap = today.distance(to: next)
        if gap <= 1 { return "Next: tomorrow" }
        if gap < 7 { return "Next: \(weekdaysLong[next.mondayIndex])" }
        let (_, month, dayOfMonth) = next.ymd
        return "Next: \(dayOfMonth) \(self.month(monthsShort, month))"
    }

    /// Today's progress line, in doses as the widgets count them: "4 of 6 taken", or "All taken". Nil when nothing is
    /// due.
    static func progress(_ summary: DaySummary) -> String? {
        guard summary.dueDoses > 0 else { return nil }
        if summary.allTaken { return "All taken" }
        return "\(summary.takenDueDoses) of \(summary.dueDoses) taken"
    }

    /// The day sheet's status line. Today is still running, so what is not taken yet is pending, not missed.
    static func daySheetStatus(_ summary: DaySummary, isToday: Bool) -> String {
        switch summary.status {
        case .nothingDue:
            return summary.allDoses.isEmpty ? "Nothing due" : "\(summary.allDoses.count) logged \u{00B7} nothing due"
        case .complete:
            return "All taken"
        case .partial:
            return "\(summary.takenDueDoses) of \(summary.dueDoses) taken \u{00B7} \(summary.pendingDoses) \(isToday ? "pending" : "missed")"
        case .missed:
            return isToday ? "\(summary.dueDoses) pending" : "Nothing logged"
        case .future:
            return ""
        }
    }

    /// A day sheet row: "Daily · taken", "2x daily · 1 of 2", "Daily · missed" (pending today), with the frequency the
    /// item had on that day.
    static func dayItemStatus(_ row: ItemDay, isToday: Bool) -> String {
        let schedule = frequency(row.frequency)
        if !row.isActive && row.doses.isEmpty { return "\(schedule) \u{00B7} \(row.isPaused ? "archived" : "added later")" }
        if !row.isDue { return "\(schedule) \u{00B7} not due" }
        if row.isDone { return "\(schedule) \u{00B7} taken" }
        if row.doses.isEmpty { return "\(schedule) \u{00B7} \(isToday ? "pending" : "missed")" }
        return "\(schedule) \u{00B7} \(row.takenCount) of \(row.dosesPerDay)"
    }

    /// Locale aware short time for VoiceOver and Siri: "7:42 AM" or "07:42".
    static func spoken(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    /// "Vitamin D3, Fish Oil and Zinc"
    static func list(_ parts: [String]) -> String {
        switch parts.count {
        case 0: return ""
        case 1: return parts[0]
        default: return parts.dropLast().joined(separator: ", ") + " and " + (parts.last ?? "")
        }
    }
}
