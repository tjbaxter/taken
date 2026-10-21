import Foundation

/// A realistic stack with five weeks of history, for `-demo` launches (screenshots) and widget previews.
/// Lives in a temporary file, never the real store.
enum DemoData {
    /// Today at 21:41 local time: the end-of-day moment Taken exists for.
    static func referenceNow(from real: Date = Date(), timeZone: TimeZone = .current) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let c = calendar.dateComponents([.year, .month, .day], from: real)
        return calendar.date(from: DateComponents(year: c.year, month: c.month, day: c.day, hour: 21, minute: 41)) ?? real
    }

    /// The demo's settings: the nudge on, waking at 07:00 (the default), so the day rolls over at 03:00.
    static let settings = StackSettings(reminderEnabled: true)

    /// `yesterdayPartial` leaves last night's Magnesium out, for the `-screen today-repair` capture.
    static func state(now: Date, allTaken: Bool, yesterdayPartial: Bool = false,
                      timeZone: TimeZone = .current) -> StackState {
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

        var doses: [Dose] = []
        func log(_ item: Item, _ day: DayKey, _ hour: Int, _ minute: Int) {
            doses.append(Dose(itemId: item.id, takenAt: clock.date(on: day, hour: hour, minute: minute)))
        }

        for offset in stride(from: 59, through: 1, by: -1) {
            let day = today.adding(-offset)
            let morning = 24 + Int(random.next() % 28)
            log(vd3, day, 7, morning)
            log(fin, day, 7, morning)
            log(fsh, day, 7, morning + 1)
            if offset != 27 { log(cre, day, 7, morning + 2) }
            if offset != 22 { log(fsh, day, 18 + Int(random.next() % 2), Int(random.next() % 55)) }
            if offset != 15 && offset != 27 && !(yesterdayPartial && offset == 1) {
                log(mag, day, 21, 2 + Int(random.next() % 40))
            }
            if offset % 2 == 1 { log(znc, day, 7, morning + 3) }
        }

        log(vd3, today, 7, 42)
        log(fin, today, 7, 42)
        log(fsh, today, 7, 43)
        log(cre, today, 7, 44)
        if allTaken {
            log(fsh, today, 19, 6)
            log(mag, today, 21, 12)
        }

        return StackState(items: [vd3, fin, fsh, cre, mag, znc], doses: doses, settings: settings)
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
