import Foundation

/// A calendar day as a plain number: days since 1970-01-01 (proleptic Gregorian).
/// Pure integer arithmetic, so adding days never trips over DST or time zones.
struct DayKey: Hashable, Comparable, Codable, Sendable {
    let ordinal: Int

    init(ordinal: Int) { self.ordinal = ordinal }

    init(year: Int, month: Int, day: Int) {
        // Howard Hinnant's days_from_civil.
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let mp = (month + 9) % 12
        let doy = (153 * mp + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        ordinal = era * 146097 + doe - 719468
    }

    /// (year, month, day) of this key.
    var ymd: (year: Int, month: Int, day: Int) {
        let z = ordinal + 719468
        let era = (z >= 0 ? z : z - 146096) / 146097
        let doe = z - era * 146097
        let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
        let y = yoe + era * 400
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp < 10 ? mp + 3 : mp - 9
        return (m <= 2 ? y + 1 : y, m, d)
    }

    var dayOfMonth: Int { ymd.day }

    /// 0 = Monday ... 6 = Sunday. 1970-01-01 was a Thursday.
    var mondayIndex: Int { ((ordinal + 3) % 7 + 7) % 7 }

    /// Calendar weekday numbering: 1 = Sunday ... 7 = Saturday.
    var weekday: Int { mondayIndex == 6 ? 1 : mondayIndex + 2 }

    func adding(_ days: Int) -> DayKey { DayKey(ordinal: ordinal + days) }

    /// Whole days from self to other (positive when other is later).
    func distance(to other: DayKey) -> Int { other.ordinal - ordinal }

    static func < (lhs: DayKey, rhs: DayKey) -> Bool { lhs.ordinal < rhs.ordinal }
}

/// Maps absolute moments to the day the user was living, using the day-start hour.
/// A 01:00 dose with a 04:00 rollover belongs to the previous day.
struct DayClock: Sendable {
    let calendar: Calendar
    let dayStartHour: Int

    init(dayStartHour: Int, timeZone: TimeZone = .current) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.locale = Locale(identifier: "en_US_POSIX")
        self.calendar = calendar
        self.dayStartHour = min(max(dayStartHour, 0), 23)
    }

    /// The logical day a moment belongs to (wall clock based, so DST safe).
    func day(for date: Date) -> DayKey {
        let c = calendar.dateComponents([.year, .month, .day, .hour], from: date)
        let key = DayKey(year: c.year ?? 1970, month: c.month ?? 1, day: c.day ?? 1)
        return (c.hour ?? 0) < dayStartHour ? key.adding(-1) : key
    }

    /// The moment a logical day starts: its calendar date at the day-start hour.
    func start(of day: DayKey) -> Date {
        let (y, m, d) = day.ymd
        if let date = calendar.date(from: DateComponents(year: y, month: m, day: d, hour: dayStartHour, minute: 0)) {
            return date
        }
        return Date(timeIntervalSince1970: TimeInterval(day.ordinal) * 86_400)
    }

    func end(of day: DayKey) -> Date { start(of: day.adding(1)) }

    /// A wall-clock time on a logical day. Hours before the rollover fall on the next calendar date.
    func date(on day: DayKey, hour: Int, minute: Int) -> Date {
        let calendarDay = hour < dayStartHour ? day.adding(1) : day
        let (y, m, d) = calendarDay.ymd
        if let date = calendar.date(from: DateComponents(year: y, month: m, day: d, hour: hour, minute: minute)) {
            return date
        }
        return start(of: day)
    }

    func nextRollover(after date: Date) -> Date { start(of: day(for: date).adding(1)) }

    func hourMinute(of date: Date) -> (hour: Int, minute: Int) {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0, c.minute ?? 0)
    }

    /// Minutes since local midnight.
    func minutesOfDay(_ date: Date) -> Int {
        let hm = hourMinute(of: date)
        return hm.hour * 60 + hm.minute
    }
}
