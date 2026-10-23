import Foundation

/// Which stack a `-demo` launch seeds (`-demo-stack us` or `-demo-stack neutral`). The App Store screenshots come in two
/// sets, one per storefront group (REDESIGN.md "Store screenshots for the 1.1 submission" and "App Store pack for 1.1"):
/// - `us`, for English (U.S.): the stack CI has always captured plus Semaglutide, weekly on Thursday. Generic names only.
/// - `neutral`, for every other localization and the primary language: a "Weekly shot" row, and no prescription-only
///   medicine at all (no Finasteride), since most countries ban promoting prescription medicines to the public.
/// Without the argument (`standard`), the stack every other capture uses, unchanged.
enum DemoStack: String, Sendable, CaseIterable {
    case standard, us, neutral

    /// Read only in Debug builds, which CI's screenshot job runs (ci.yml); a Release build, and so every App Store build,
    /// always seeds `standard` and never reads the argument (Guideline 2.5.19: nothing hidden or dormant ships).
    init(arguments: [String]) {
        #if DEBUG
        guard let index = arguments.firstIndex(of: "-demo-stack"), index + 1 < arguments.count,
              let stack = DemoStack(rawValue: arguments[index + 1]) else {
            self = .standard
            return
        }
        self = stack
        #else
        self = .standard
        #endif
    }

    /// The store sets show a Thursday, the day their weekly row is due, so it reads "Weekly · Thu" with its time.
    var isStoreSet: Bool { self != .standard }

    /// The weekly row's name in a store set.
    var weeklyName: String? {
        switch self {
        case .standard: return nil
        case .us: return "Semaglutide"
        case .neutral: return "Weekly shot"
        }
    }

    /// What the Add sheet's type-ahead capture (`-screen add-search`) has typed. "tum" finds Turmeric through its
    /// misspelling, but leaves room for the chip grid's Finasteride, Metformin, Semaglutide and Tirzepatide rows above
    /// the keyboard, so the neutral set types "mag": four Magnesium names and the typed row fill the room, and only
    /// supplement chips stay in view.
    var typedQuery: String { self == .neutral ? "mag" : "tum" }
}

/// A realistic stack with five weeks of history, for `-demo` launches (screenshots) and widget previews.
/// Lives in a temporary file, never the real store.
enum DemoData {
    /// Thursday in Calendar numbering (1 = Sunday ... 7 = Saturday): the store sets' day.
    static let storeWeekday = 5

    /// Today at 21:41 local time: the end-of-day moment Taken exists for. A store set moves back to the most recent
    /// Thursday, so its weekly row is due and taken that day.
    static func referenceNow(from real: Date = Date(), timeZone: TimeZone = .current,
                             stack: DemoStack = .standard) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let c = calendar.dateComponents([.year, .month, .day, .weekday], from: real)
        let evening = calendar.date(from: DateComponents(year: c.year, month: c.month, day: c.day, hour: 21, minute: 41))
            ?? real
        guard stack.isStoreSet, let weekday = c.weekday else { return evening }
        let back = (weekday - storeWeekday + 7) % 7
        return calendar.date(byAdding: .day, value: -back, to: evening) ?? evening
    }

    /// The demo's settings: the nudge on, waking at 07:00 (the default), so the day rolls over at 03:00.
    static let settings = StackSettings(reminderEnabled: true)

    /// `yesterdayPartial` leaves last night's Magnesium out, for the `-screen today-repair` capture. A store set's
    /// weekly row is due on today's weekday (Thursday, from `referenceNow`) and logged that morning, every week.
    static func state(now: Date, allTaken: Bool, yesterdayPartial: Bool = false,
                      timeZone: TimeZone = .current, stack: DemoStack = .standard) -> StackState {
        let clock = DayClock(dayStartHour: settings.dayStartHour, timeZone: timeZone)
        let today = clock.day(for: now)
        let created = clock.start(of: today.adding(-60))
        var random = SeededRandom(seed: 0x7A4E_2026)

        let vd3 = Item(name: "Vitamin D3", code: "VD3", frequency: .daily(times: 1), createdAt: created, sortIndex: 0)
        let fin = Item(name: "Finasteride", code: "FIN", frequency: .daily(times: 1), createdAt: created, sortIndex: 1)
        let fsh = Item(name: "Fish Oil", code: "FSH", frequency: .daily(times: 2), createdAt: created, sortIndex: 2)
        let cre = Item(name: "Creatine", code: "CRE", frequency: .daily(times: 1), createdAt: created, sortIndex: 3)
        let mag = Item(name: "Magnesium", code: "MAG", frequency: .daily(times: 1), createdAt: created, sortIndex: 4)
        let znc = Item(name: "Zinc", code: "ZNC", frequency: .alternateDays, createdAt: created, sortIndex: 5)
        // A weekly dose on its day (the Add sheet saves Weekly as a one-day Days set), right after the stack's first rows.
        let weekly = stack.weeklyName.map { name in
            Item(name: name, code: Catalog.code(for: name), frequency: .weekdays([today.weekday]), createdAt: created,
                 sortIndex: 1)
        }

        var doses: [Dose] = []
        func log(_ item: Item, _ day: DayKey, _ hour: Int, _ minute: Int) {
            doses.append(Dose(itemId: item.id, takenAt: clock.date(on: day, hour: hour, minute: minute)))
        }

        let takesFinasteride = stack != .neutral
        for offset in stride(from: 59, through: 1, by: -1) {
            let day = today.adding(-offset)
            let morning = 24 + Int(random.next() % 28)
            log(vd3, day, 7, morning)
            if takesFinasteride { log(fin, day, 7, morning) }
            log(fsh, day, 7, morning + 1)
            if offset != 27 { log(cre, day, 7, morning + 2) }
            if offset != 22 { log(fsh, day, 18 + Int(random.next() % 2), Int(random.next() % 55)) }
            if offset != 15 && offset != 27 && !(yesterdayPartial && offset == 1) {
                log(mag, day, 21, 2 + Int(random.next() % 40))
            }
            if offset % 2 == 1 { log(znc, day, 7, morning + 3) }
            // Its own minute, drawn from nothing, so the other rows' history is the same in every stack.
            if let weekly, offset % 7 == 0 { log(weekly, day, 7, morning + 4) }
        }

        log(vd3, today, 7, 42)
        if takesFinasteride { log(fin, today, 7, 42) }
        log(fsh, today, 7, 43)
        log(cre, today, 7, 44)
        if let weekly { log(weekly, today, 7, 45) }
        if allTaken {
            log(fsh, today, 19, 6)
            log(mag, today, 21, 12)
        }

        var items = takesFinasteride ? [vd3, fin, fsh, cre, mag, znc] : [vd3, fsh, cre, mag, znc]
        if let weekly { items.insert(weekly, at: takesFinasteride ? 2 : 1) }
        for index in items.indices { items[index].sortIndex = index }
        return StackState(items: items, doses: doses, settings: settings)
    }

    /// The partly taken day shown in the day-sheet screenshot.
    static func sheetDay(now: Date, timeZone: TimeZone = .current) -> DayKey {
        DayClock(dayStartHour: settings.dayStartHour, timeZone: timeZone).day(for: now).adding(-15)
    }
}

#if DEBUG
// The Weight tab's demo (SPEC 3.12, CI screenshots only), Debug only like `-demo` itself.
extension DemoData {
    /// About 26 weeks of morning weigh-ins, most days: a flat-to-gently-falling line from about 92.6 kg that levels off
    /// near 88.9 kg, with the day-to-day swings a scale shows, to the nearest 0.05 kg. Today's is at 07:xx; without
    /// `includeToday` the history ends yesterday at 07:xx, and yesterday is never skipped.
    static func weighIns(now: Date, includeToday: Bool = true, timeZone: TimeZone = .current) -> [WeighIn] {
        let clock = DayClock(dayStartHour: settings.dayStartHour, timeZone: timeZone)
        let today = clock.day(for: now)
        var random = SeededRandom(seed: 0x5CA1_2026)
        let span = 181
        var out: [WeighIn] = []
        for offset in stride(from: span, through: 0, by: -1) {
            // About one morning in seven goes without a weigh-in; the last one never does.
            let skipped = random.next() % 7 == 0 && offset != 0 && (includeToday || offset != 1)
            let swing = Double(random.next() % 90) / 100 - 0.45
            let minute = 5 + Int(random.next() % 45)
            guard !skipped, includeToday || offset != 0 else { continue }
            let progress = Double(span - offset) / Double(span)
            let level = 92.6 - 3.7 * (1 - pow(1 - progress, 1.6))
            let at = clock.date(on: today.adding(-offset), hour: 7, minute: minute)
            out.append(WeighIn(kg: ((level + swing) * 20).rounded() / 20, weighedAt: at,
                               utcOffset: timeZone.secondsFromGMT(for: at)))
        }
        return out
    }

    /// The goal screens' history (REDESIGN.md, "Goal and moments"): the first weigh-in exactly 97.8 kg, 231 days before the
    /// demo day, then about six mornings in seven, falling about 0.3 kg a week with a fixed swing of up to 0.45 kg, to a
    /// trend of 88.08 today: one point (5%) and "1.1 kg to 87.0" with the goal 87.0 and 180 cm. `extraWeeks` starts it
    /// that much earlier and carries on down 0.24 kg a week, to a trend of about 86.8 and all three points
    /// (`weight-goal-reached`). `momentKg` adds one more weigh-in today (`weight-goal-moment`: 87.1 takes the trend below
    /// 88.02, the 10% point). WeightGoalTests pins all three.
    static func goalWeighIns(now: Date, extraWeeks: Int = 0, momentKg: Double? = nil,
                             timeZone: TimeZone = .current) -> [WeighIn] {
        let clock = DayClock(dayStartHour: settings.dayStartHour, timeZone: timeZone)
        let today = clock.day(for: now)
        var random = SeededRandom(seed: 0x60A1_0701)
        let base = 231
        let span = base + 7 * extraWeeks
        var out: [WeighIn] = []
        for offset in stride(from: span, through: 0, by: -1) {
            let day = span - offset
            // About one morning in seven goes without a weigh-in; the first and today never do.
            let skipped = random.next() % 7 == 0 && offset != 0 && day != 0
            let swing = Double(random.next() % 91) / 100 - 0.45
            let minute = 5 + Int(random.next() % 45)
            guard !skipped else { continue }
            let level = day <= base
                ? 97.8 - 0.3 * Double(day) / 7
                : 97.8 - 0.3 * Double(base) / 7 - 0.24 * Double(day - base) / 7
            let kg = day == 0 ? 97.8 : ((level + swing) * 20).rounded() / 20
            let at = clock.date(on: today.adding(-offset), hour: 7, minute: minute)
            out.append(WeighIn(kg: kg, weighedAt: at, utcOffset: timeZone.secondsFromGMT(for: at)))
        }
        if let momentKg {
            let at = clock.date(on: today, hour: 7, minute: 58)
            out.append(WeighIn(kg: momentKg, weighedAt: at, utcOffset: timeZone.secondsFromGMT(for: at)))
        }
        return out
    }

    /// The stack with a weekly shot added: Semaglutide on today's weekday, logged at 08:00 every week for 26 weeks,
    /// today included, for the chart's dose ticks and Today's one-time weight offer.
    static func withWeeklyShot(_ state: StackState, now: Date, timeZone: TimeZone = .current) -> StackState {
        let clock = DayClock(dayStartHour: settings.dayStartHour, timeZone: timeZone)
        let today = clock.day(for: now)
        let shot = Item(name: "Semaglutide", code: "SEM", frequency: .weekdays([today.weekday]),
                        createdAt: clock.start(of: today.adding(-182)), sortIndex: state.items.count)
        var next = state
        next.items.append(shot)
        for week in 0...25 {
            next.doses.append(Dose(itemId: shot.id, takenAt: clock.date(on: today.adding(-7 * week), hour: 8, minute: 0)))
        }
        return next
    }
}
#endif

/// Small deterministic generator so demo history looks the same on every run.
struct SeededRandom: Sendable {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return state >> 33
    }
}
