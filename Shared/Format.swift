import Foundation

/// Text formatting for the HUD. Mono, caps, 24-hour clock.
enum Fmt {
    private static let weekdays = ["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"]
    private static let months = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]
    static let weekdayLetters = ["M", "T", "W", "T", "F", "S", "S"]

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

    /// "9H AGO", "12M AGO", "NOW".
    static func ago(_ date: Date, now: Date) -> String {
        let minutes = Int(now.timeIntervalSince(date) / 60)
        if minutes < 1 { return "NOW" }
        if minutes < 60 { return "\(minutes)M AGO" }
        return "\(minutes / 60)H AGO"
    }

    /// "9H 12M AGO"
    static func agoDetailed(_ date: Date, now: Date) -> String {
        let minutes = Int(now.timeIntervalSince(date) / 60)
        if minutes < 1 { return "JUST NOW" }
        if minutes < 60 { return "\(minutes)M AGO" }
        let rest = minutes % 60
        return rest == 0 ? "\(minutes / 60)H AGO" : "\(minutes / 60)H \(rest)M AGO"
    }

    /// "MON 12 OCT"
    static func dayHeader(_ day: DayKey) -> String {
        let (_, month, dayOfMonth) = day.ymd
        return "\(weekdays[day.mondayIndex]) \(dayOfMonth) \(months[max(0, min(11, month - 1))])"
    }

    static func weekdayShort(_ day: DayKey) -> String { weekdays[day.mondayIndex] }

    /// "DAILY", "2X DAILY", "ALT DAYS", "MON WED FRI".
    static func frequency(_ frequency: Frequency) -> String {
        switch frequency {
        case .daily(let times):
            return times <= 1 ? "DAILY" : "\(min(times, 3))X DAILY"
        case .alternateDays:
            return "ALT DAYS"
        case .weekdays(let set):
            if set.isEmpty { return "NO DAYS SET" }
            if set.count == 7 { return "DAILY" }
            if set == [2, 3, 4, 5, 6] { return "WEEKDAYS" }
            if set == [1, 7] { return "WEEKENDS" }
            // Monday-first order.
            let order = [2, 3, 4, 5, 6, 7, 1]
            return order.filter { set.contains($0) }.map { weekdays[(($0 + 5) % 7)] }.joined(separator: " ")
        }
    }

    /// "NEXT: TOMORROW", "NEXT: THU", "NEXT: 14 OCT"
    static func next(_ next: DayKey?, today: DayKey) -> String {
        guard let next else { return "NOT SCHEDULED" }
        let gap = today.distance(to: next)
        if gap <= 1 { return "NEXT: TOMORROW" }
        if gap < 7 { return "NEXT: \(weekdayShort(next))" }
        let (_, month, dayOfMonth) = next.ymd
        return "NEXT: \(dayOfMonth) \(months[max(0, min(11, month - 1))])"
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
