import Foundation

/// Which stack a `-demo` launch seeds (`-demo-stack us` or `-demo-stack neutral`). The App Store screenshots come in two
/// sets, one per storefront group (REDESIGN.md "Store screenshots for the 1.1 submission" and "App Store pack for 1.1"):
/// - `us`, for English (U.S.): the stack CI has always captured plus Semaglutide, weekly on Thursday. Generic names only.
/// - `neutral`, for every other localization and the primary language: a "Weekly shot" row, and no prescription-only
///   medicine at all (no Finasteride), since most countries ban promoting prescription medicines to the public.
/// Without the argument (`standard`), the stack every other capture uses, unchanged.
enum DemoStack: String, Sendable, CaseIterable {
    case standard, us, neutral

    init(arguments: [String]) {
        guard let index = arguments.firstIndex(of: "-demo-stack"), index + 1 < arguments.count,
              let stack = DemoStack(rawValue: arguments[index + 1]) else {
            self = .standard
            return
        }
        self = stack
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

/// Small deterministic generator so demo history looks the same on every run.
struct SeededRandom: Sendable {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return state >> 33
    }
}
