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

    /// "9h 12m ago", and "1d 2h ago" from a day on (a weekly dose logged on an earlier day).
    static func agoDetailed(_ date: Date, now: Date) -> String {
        let minutes = Int(now.timeIntervalSince(date) / 60)
        if minutes < 1 { return "just now" }
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        if hours >= 24 {
            let rest = hours % 24
            return rest == 0 ? "\(hours / 24)d ago" : "\(hours / 24)d \(rest)h ago"
        }
        let rest = minutes % 60
        return rest == 0 ? "\(hours)h ago" : "\(hours)h \(rest)m ago"
    }

    /// A dose's time as a row or a chip shows it: "08:12" when it was logged on the day being viewed, otherwise with the
    /// day it was logged, "Fri 08:12" (a weekly dose that counts for its due day, SPEC 3.3). The logged day is the one
    /// the engine reads (`DayClock.day(of:)`, at the dose's own UTC offset), so a dose logged abroad keeps its day.
    static func doseClock(_ dose: Dose, viewing day: DayKey, _ clock: DayClock) -> String {
        let logged = clock.day(of: dose)
        let time = self.clock(dose.takenAt, clock)
        return logged == day ? time : "\(weekdaysShort[logged.mondayIndex]) \(time)"
    }

    /// The same for VoiceOver and Siri, in the clock's zone and the locale's own short time: "at 8:12 AM", or
    /// "Friday at 8:12 AM" when it was logged on another day.
    static func spokenDose(_ dose: Dose, viewing day: DayKey, _ clock: DayClock, locale: Locale = .current) -> String {
        let logged = clock.day(of: dose)
        let time = spokenTime(dose.takenAt, clock, locale: locale)
        return logged == day ? "at \(time)" : "\(weekday(logged)) at \(time)"
    }

    /// A row's doses for VoiceOver and Siri: "at 7:42 AM and 9:00 AM" when all were logged on the day being viewed, as
    /// before; otherwise each with its day, "Tuesday at 8:12 AM" (an early weekly dose on its due day, SPEC 3.3).
    static func spokenDoses(_ doses: [Dose], viewing day: DayKey, _ clock: DayClock, locale: Locale = .current) -> String {
        if doses.allSatisfy({ clock.day(of: $0) == day }) {
            return "at " + list(doses.map { spokenTime($0.takenAt, clock, locale: locale) })
        }
        return list(doses.map { spokenDose($0, viewing: day, clock, locale: locale) })
    }

    /// "8:12 AM" or "08:12", in the clock's zone and the locale's own short time.
    private static func spokenTime(_ date: Date, _ clock: DayClock, locale: Locale) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .shortened)
        style.timeZone = clock.calendar.timeZone
        style.locale = locale
        // Newer releases put a narrow no-break space before AM; a plain space reads the same and compares the same.
        return date.formatted(style).replacingOccurrences(of: "\u{202F}", with: " ")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
    }

    /// "Thursday"
    static func weekday(_ day: DayKey) -> String {
        weekdaysLong[day.mondayIndex]
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

    /// "Daily", "2x daily", "Every other day", "Weekly · Thu", "Weekdays", "Mon Wed Fri".
    static func frequency(_ frequency: Frequency) -> String {
        switch frequency {
        case .daily(let times):
            return times <= 1 ? "Daily" : "\(min(times, 3))x daily"
        case .alternateDays:
            return "Every other day"
        case .weekdays(let set):
            if set.isEmpty { return "No days set" }
            if set.count == 7 { return "Daily" }
            // One day is Weekly: a weekly shot on its day.
            if set.count == 1, let day = set.first { return "Weekly \u{00B7} \(weekdaysShort[(day + 5) % 7])" }
            if set == [2, 3, 4, 5, 6] { return "Weekdays" }
            if set == [1, 7] { return "Weekends" }
            // Monday-first order.
            let order = [2, 3, 4, 5, 6, 7, 1]
            return order.filter { set.contains($0) }.map { weekdaysShort[($0 + 5) % 7] }.joined(separator: " ")
        }
    }

    /// Under an item in Not today: "Every other day · Next: Thursday". A weekly item names its day once, "Weekly · Next:
    /// Thursday", not "Weekly · Thu · Next: Thursday".
    static func notDue(_ frequency: Frequency, next: String) -> String {
        if case .weekdays(let set) = frequency, set.count == 1 { return "Weekly \u{00B7} \(next)" }
        return "\(self.frequency(frequency)) \u{00B7} \(next)"
    }

    /// The item sheet's one fixed line under a Weekly schedule (App Review Guideline 1.4.1). Taken only records doses: it
    /// never says when, whether or how much to take.
    static let missedDoseNote = "Missed a dose? Follow your medicine's leaflet, or ask your pharmacist or doctor."

    /// Under a weekly item in Not today, from the week today is in (`StackEngine.weekRow`): "Weekly · Thu · Not logged"
    /// while the week is open, "Weekly · Next: Thursday" once it is logged, "Weekly · Counts for Thursday" for an early
    /// dose. No countdown, and nothing about when to take it.
    static func weekNote(_ row: ItemDay, today: DayKey) -> String {
        if row.day > today { return "Weekly \u{00B7} Counts for \(weekday(row.day))" }
        if row.isOpen { return "\(frequency(row.frequency)) \u{00B7} Not logged" }
        return notDue(row.frequency, next: next(row.day.adding(7), today: today))
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

    /// The day sheet's status line. Today is still running, so what is not taken yet is pending, not missed. A weekly
    /// item whose week is still open is "not logged", never missed: "1 of 2 taken · 1 not logged".
    static func daySheetStatus(_ summary: DaySummary, isToday: Bool) -> String {
        let open = summary.openCount
        if open > 0 {
            var parts = ["\(summary.takenDueDoses) of \(summary.dueDoses + open) taken"]
            if summary.pendingDoses > 0 { parts.append("\(summary.pendingDoses) \(isToday ? "pending" : "missed")") }
            parts.append("\(open) not logged")
            return parts.joined(separator: " \u{00B7} ")
        }
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

    /// A day sheet row: "Daily · taken", "2x daily · 1 of 2", "Daily · missed" (pending today), "Weekly · Thu · not
    /// logged" (its week still open), with the frequency the item had on that day.
    static func dayItemStatus(_ row: ItemDay, isToday: Bool) -> String {
        let schedule = frequency(row.frequency)
        if !row.isActive && row.doses.isEmpty { return "\(schedule) \u{00B7} \(row.isPaused ? "archived" : "added later")" }
        if row.isOpen { return "\(schedule) \u{00B7} not logged" }
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
