import XCTest
@testable import Taken

/// The Weight tab (SPEC 3.12): the trend with worked numbers, units per locale, the Pro rule, the offer on Today, the dose
/// ticks, the chart's window, the CSV both ways, the copy, and the tab's visibility with the selection it resets.
/// London clock, the day starting at 04:00; Monday 19 October 2026.
final class WeightTests: XCTestCase {

    private let enUS = Locale(identifier: "en_US")
    private let enGB = Locale(identifier: "en_GB")
    private let deDE = Locale(identifier: "de_DE")

    private func weighIn(_ kg: Double, _ day: Int, _ hour: Int = 7, _ minute: Int = 0, month: Int = 10) -> WeighIn {
        let date = at(2026, month, day, hour, minute)
        return WeighIn(kg: kg, weighedAt: date, utcOffset: london.secondsFromGMT(for: date))
    }

    private func day(_ dayOfMonth: Int, month: Int = 10) -> DayKey {
        DayKey(year: 2026, month: month, day: dayOfMonth)
    }

    // MARK: The trend

    /// Fourmilab's pencil-and-paper example, by the calculator formula: T(n) = T(n-1) + 0.1 x (W(n) - T(n-1)), starting at
    /// the first weigh-in. Rounded to a tenth it is their table: 173.5, 173.3, 173.2, 173.0.
    func testTheTrendIsTheHackersDietOnEachDaysLowestWeighIn() {
        let weighIns = [
            weighIn(173.6, 1), weighIn(174.2, 1, 19), // the day's lowest counts, whenever it was
            weighIn(172.5, 2), weighIn(171.5, 3), weighIn(172.0, 4), weighIn(171.5, 5, 6, 30),
        ]
        let trend = WeightTrend.trend(weighIns, clock: londonClock())
        XCTAssertEqual(trend.map(\.day), (1...5).map { day($0) })
        let expected = [173.6, 173.49, 173.291, 173.1619, 172.99571]
        for (point, value) in zip(trend, expected) {
            XCTAssertEqual(point.kg, value, accuracy: 1e-9, "\(point.day.iso)")
        }
        XCTAssertEqual(trend.dropFirst().map { ($0.kg * 10).rounded() / 10 }, [173.5, 173.3, 173.2, 173.0],
                       "Fourmilab's hand-worked trend column")
        XCTAssertEqual(WeightTrend.daily(weighIns, clock: londonClock()).first?.kg, 173.6, "the lowest of the day")
    }

    /// MacroFactor: 151 on Monday and 150 on Wednesday give 150.5 on Tuesday. The trend runs through the filled day.
    func testDaysBetweenWeighInsAreFilledOnAStraightLine() {
        let monday = weighIn(151, 19)
        let wednesday = weighIn(150, 21)
        let filled = WeightTrend.filled(WeightTrend.daily([wednesday, monday], clock: londonClock()))
        XCTAssertEqual(filled.map(\.day), [day(19), day(20), day(21)])
        XCTAssertEqual(filled[1].kg, 150.5, accuracy: 1e-9)

        let longer = WeightTrend.filled([WeightPoint(day: day(1), kg: 90), WeightPoint(day: day(5), kg: 88)])
        XCTAssertEqual(longer.map(\.kg), [90, 89.5, 89, 88.5, 88])

        let trend = WeightTrend.trend([monday, wednesday], clock: londonClock())
        XCTAssertEqual(trend.map(\.kg)[1], 150.95, accuracy: 1e-9)
        XCTAssertEqual(trend.map(\.kg)[2], 150.855, accuracy: 1e-9)
    }

    /// No line past the last weigh-in and no forecast; a weigh-in before the day starts at 04:00 counts for the day before,
    /// as a dose does, and one logged in New York keeps its New York day.
    func testTheTrendStopsAtTheLastWeighInAndDaysAreDayClocks() {
        let trend = WeightTrend.trend([weighIn(90, 1), weighIn(89, 4)], clock: londonClock())
        XCTAssertEqual(trend.last?.day, day(4), "nothing after the last weigh-in")
        XCTAssertEqual(trend.count, 4)

        let lateNight = weighIn(88, 20, 2, 30)
        XCTAssertEqual(londonClock().day(of: lateNight), day(19), "02:30 counts for the day being lived")

        let newYork = TimeZone(identifier: "America/New_York")!
        let evening = at(2026, 10, 20, 23, 30, newYork)
        let abroad = WeighIn(kg: 88, weighedAt: evening, utcOffset: newYork.secondsFromGMT(for: evening))
        XCTAssertEqual(londonClock().day(for: evening), day(21), "04:30 on the 21st in London")
        XCTAssertEqual(londonClock().day(of: abroad), day(20), "but 23:30 on the 20th where it was logged")
        XCTAssertTrue(WeightTrend.trend([], clock: londonClock()).isEmpty)
    }

    /// After a 1 kg drop the trend is 89 + 0.9^n, so the 7-day change is 0.9^7 - 1. Each change shows once that much
    /// history exists.
    func testChangesAreReadOffTheTrendOnceThereIsThatMuchHistory() {
        let eight = [weighIn(90, 1)] + (2...8).map { weighIn(89, $0) }
        let trend = WeightTrend.trend(eight, clock: londonClock())
        XCTAssertEqual(trend.last?.kg ?? 0, 89 + pow(0.9, 7), accuracy: 1e-9)
        XCTAssertEqual(WeightTrend.change(trend, days: 7) ?? 0, pow(0.9, 7) - 1, accuracy: 1e-9)
        XCTAssertNil(WeightTrend.change(trend, days: 30), "8 days of history: no 30-day change yet")
        XCTAssertEqual(WeightTrend.changes(trend).map(\.days), [7])

        let month = [weighIn(90, 1, month: 9)] + (2...30).map { weighIn(89, $0, month: 9) } + [weighIn(89, 1)]
        let monthTrend = WeightTrend.trend(month, clock: londonClock())
        XCTAssertEqual(WeightTrend.change(monthTrend, days: 30) ?? 0, pow(0.9, 30) - 1, accuracy: 1e-9)
        XCTAssertEqual(WeightTrend.changes(monthTrend).map(\.days), [7, 30])

        let down = WeightChange(days: 30, kg: -1.21)
        XCTAssertEqual(down.direction(unit: .kg), .down)
        XCTAssertEqual(down.symbol(unit: .kg), "arrow.down")
        XCTAssertEqual(down.amount(unit: .kg, locale: enGB), "1.2 kg", "the arrow carries the sign")
        XCTAssertEqual(down.spoken(unit: .kg, locale: enGB), "Down 1.2 kilograms over 30 days")
        XCTAssertEqual(WeightChange(days: 7, kg: 0.04).direction(unit: .kg), .flat, "0.0 at one decimal is flat")
        XCTAssertEqual(WeightChange(days: 7, kg: 0.5).symbol(unit: .lb), "arrow.up")
        XCTAssertEqual(WeightCopy.chartSummary(trendKg: 88.1, changes: [down], unit: .kg, locale: enGB),
                       "Trend 88.1 kilograms, down 1.2 over 30 days")
    }

    // MARK: Units

    /// UnitMass's person-weight unit: pounds for en_US and es_US, kilograms everywhere else, en_GB's stones included.
    func testTheUnitFollowsTheLocaleUntilTheMoreMenuPicksOne() {
        XCTAssertEqual(WeightUnit.preferred(for: enUS), .lb)
        XCTAssertEqual(WeightUnit.preferred(for: Locale(identifier: "es_US")), .lb)
        for id in ["en_GB", "en_IE", "en_AU", "en_CA", "de_DE", "fr_FR", "ja_JP", "en_IN"] {
            XCTAssertEqual(WeightUnit.preferred(for: Locale(identifier: id)), .kg, id)
        }
        XCTAssertEqual(WeightUnit.lb.kilograms(from: 194.6), 194.6 * 0.45359237, accuracy: 1e-12)
        XCTAssertEqual(WeightUnit.lb.value(fromKilograms: WeightUnit.lb.kilograms(from: 194.6)), 194.6, accuracy: 1e-9)
        XCTAssertEqual(WeightUnit.kg.value(fromKilograms: 88.35), 88.35)
    }

    func testWhatIsTypedParsesInTheLocaleWithinTheBounds() {
        XCTAssertEqual(WeightFormat.parse("88,35", locale: deDE), 88.35)
        XCTAssertEqual(WeightFormat.parse("88.35", locale: deDE), 88.35, "a point reads as the decimal point too")
        XCTAssertEqual(WeightFormat.parse("88.35", locale: enGB), 88.35)
        XCTAssertEqual(WeightFormat.parse("88,35", locale: enUS), 88.35, "a weight never needs a thousands separator")
        XCTAssertEqual(WeightFormat.parse(" 88 ", locale: enGB), 88)
        XCTAssertEqual(WeightFormat.parse("88.", locale: enGB), 88)
        XCTAssertEqual(WeightFormat.parse("\u{0668}\u{0668}\u{066B}\u{0663}", locale: Locale(identifier: "ar_SA")), 88.3,
                       "any script's digits, the locale's own separator")
        for bad in ["", "88.356", "88..3", "8,8.3", "abc", "-88", "1,234.5", ".5", "88 kg"] {
            XCTAssertNil(WeightFormat.parse(bad, locale: enGB), bad)
        }
        XCTAssertNil(WeightFormat.kilograms("19.9", unit: .kg, locale: enGB))
        XCTAssertEqual(WeightFormat.kilograms("20", unit: .kg, locale: enGB), 20)
        XCTAssertEqual(WeightFormat.kilograms("350", unit: .kg, locale: enGB), 350)
        XCTAssertNil(WeightFormat.kilograms("350.1", unit: .kg, locale: enGB))
        XCTAssertNil(WeightFormat.kilograms("43.9", unit: .lb, locale: enUS))
        XCTAssertEqual(WeightFormat.kilograms("44", unit: .lb, locale: enUS) ?? 0, 44 * 0.45359237, accuracy: 1e-9)
        XCTAssertNotNil(WeightFormat.kilograms("770", unit: .lb, locale: enUS))
        XCTAssertNil(WeightFormat.kilograms("771", unit: .lb, locale: enUS))

        XCTAssertEqual(WeightFormat.sanitize("88.356", locale: enGB), "88.35", "two decimals at most")
        XCTAssertEqual(WeightFormat.sanitize("8a8,3,5", locale: deDE), "88,35")
        XCTAssertEqual(WeightFormat.sanitize(".5", locale: enGB), "5", "no leading separator")
        XCTAssertEqual(WeightFormat.sanitize("12345", locale: enGB), "1234")
    }

    /// Kilograms as typed with up to two decimals, pounds with one, the trend with one, in the locale's own numbers.
    func testWeightsShowInTheLocale() {
        XCTAssertEqual(WeightFormat.value(88.35, unit: .kg, locale: deDE), "88,35")
        XCTAssertEqual(WeightFormat.value(88.35, unit: .kg, locale: enGB), "88.35")
        XCTAssertEqual(WeightFormat.value(88, unit: .kg, locale: enGB), "88.0")
        XCTAssertEqual(WeightFormat.value(88.3, unit: .kg, locale: enGB), "88.3")
        XCTAssertEqual(WeightFormat.value(194.6 * 0.45359237, unit: .lb, locale: enUS), "194.6")
        XCTAssertEqual(WeightFormat.value(1000 * 0.45359237, unit: .lb, locale: enUS), "1000.0", "no grouping")
        XCTAssertEqual(WeightFormat.trend(88.123, unit: .kg, locale: enGB), "88.1")
        XCTAssertEqual(WeightFormat.withUnit(88.35, unit: .kg, locale: enGB), "88.35 kg")
        XCTAssertEqual(WeightFormat.spoken(88.35, unit: .kg, locale: enGB), "88.35 kilograms")
    }

    // MARK: Taken Pro

    /// The first weigh-in needs no Pro; after it, logging needs it, as doses and voice to-dos do.
    func testTheFirstWeighInNeedsNoProAfterThatLoggingDoes() {
        let now = at(2026, 10, 22, 9)
        XCTAssertEqual(WeightGate.access(firstWeighInAt: nil, status: nil, settled: true, legacyLog: false, now: now),
                       .firstSession)
        XCTAssertEqual(WeightGate.access(firstWeighInAt: nil, status: .notPro(checkedAt: now), settled: true,
                                         legacyLog: false, now: now), .firstSession)
        XCTAssertEqual(WeightGate.access(firstWeighInAt: now, status: nil, settled: true, legacyLog: false, now: now), .locked)
        let yearly = ProStatus(isPro: true, reason: .yearly, checkedAt: now, expiresAt: at(2027, 10, 22, 9), willRenew: true)
        XCTAssertEqual(WeightGate.access(firstWeighInAt: now, status: yearly, settled: true, legacyLog: false, now: now), .pro)
        XCTAssertEqual(WeightGate.access(firstWeighInAt: now, status: nil, settled: false, legacyLog: false, now: now),
                       .checking, "never locked before StoreKit's first answer")
        XCTAssertEqual(WeightGate.access(firstWeighInAt: now, status: nil, settled: true, legacyLog: true, now: now),
                       .pending, "a 1.0 log is never locked out on a guess")

        var state = WeightState()
        state.log(kg: 88.35, at: now, timeZone: london)
        XCTAssertEqual(state.firstWeighInAt, now)
        let first = state.weighIns[0]
        state.delete(first.id)
        state.eraseAll()
        XCTAssertEqual(state.firstWeighInAt, now, "deleting or erasing never gives the first weigh-in back")
    }

    // MARK: The offer on Today

    private struct OfferCase {
        var state: StackState
        var now: Date
        var summary: DaySummary { StackEngine(state: state, clock: londonClock()).todaySummary(now: now) }
    }

    /// A Thursday 22 October with Vitamin D3 daily and Semaglutide on Thursdays, both logged today and last week, and the
    /// widget invite shown on Tuesday.
    private func glp1Day(code: String = "SEM") -> OfferCase {
        let created = at(2026, 10, 1, 8)
        let vd3 = makeItem("Vitamin D3", "VD3", created: created, sortIndex: 0)
        let shot = makeItem(code == "OSM" ? "Oral Semaglutide" : "Semaglutide", code,
                            code == "OSM" ? .daily(times: 1) : .weekdays([5]), created: created, sortIndex: 1)
        var state = StackState(items: [vd3, shot])
        for dayOfMonth in 15...22 {
            state.logDose(itemId: vd3.id, at: at(2026, 10, dayOfMonth, 8), timeZone: london)
            if code == "OSM" { state.logDose(itemId: shot.id, at: at(2026, 10, dayOfMonth, 8, 5), timeZone: london) }
        }
        if code != "OSM" {
            state.logDose(itemId: shot.id, at: at(2026, 10, 15, 8, 5), timeZone: london)
            state.logDose(itemId: shot.id, at: at(2026, 10, 22, 8, 5), timeZone: london)
        }
        state.settings.nudgeOfferDone = true
        state.settings.widgetInviteDay = day(20).ordinal
        return OfferCase(state: state, now: at(2026, 10, 22, 20))
    }

    private func shows(_ c: OfferCase, weight: WeightState = WeightState()) -> Bool {
        WeightOffer.shows(weight: weight, state: c.state, today: c.summary, clock: londonClock())
    }

    func testTheOfferGoesOnlyToAGLP1StackOnALaterAllTakenDay() {
        let base = glp1Day()
        XCTAssertTrue(base.summary.allTaken)
        XCTAssertTrue(shows(base), "Semaglutide logged, everything taken, a later day than the first dose and the invite")
        XCTAssertTrue(shows(glp1Day(code: "TRZ")), "Tirzepatide")
        XCTAssertTrue(shows(glp1Day(code: "OSM")), "Oral Semaglutide")

        XCTAssertFalse(shows(base, weight: WeightState(showsTab: true)), "the tab is on already")
        XCTAssertFalse(shows(base, weight: WeightState(showsTab: false)), "hidden on purpose: an answer")
        XCTAssertFalse(shows(base, weight: WeightState(offerAnswered: true)), "either answer is final")

        var pending = base
        pending.now = at(2026, 10, 22, 7)
        pending.state.doses.removeAll { $0.takenAt >= at(2026, 10, 22, 4) }
        XCTAssertFalse(shows(pending), "never while anything is pending")

        var supplements = base
        supplements.state.items[1].code = "VD3X"
        XCTAssertFalse(shows(supplements), "no GLP-1 medicine, no offer")

        var archived = base
        archived.state.items[1].archived = true
        XCTAssertFalse(shows(archived), "an archived medicine is not in the stack")

        var neverLogged = base
        let shotID = neverLogged.state.items[1].id
        neverLogged.state.items[1].frequency = .weekdays([2])
        neverLogged.state.doses.removeAll { $0.itemId == shotID }
        XCTAssertTrue(neverLogged.summary.allTaken)
        XCTAssertFalse(shows(neverLogged), "only once that medicine's dose is logged")

        var firstDay = base
        firstDay.state.doses.removeAll { $0.takenAt < at(2026, 10, 22, 4) }
        XCTAssertFalse(shows(firstDay), "never in the first session: not on the first dose's day")

        var inviteToday = base
        inviteToday.state.settings.widgetInviteDay = day(22).ordinal
        inviteToday.state.settings.widgetInviteDone = true
        XCTAssertFalse(shows(inviteToday), "never on the widget invite's day")

        var inviteToCome = base
        inviteToCome.state.settings.widgetInviteDay = nil
        XCTAssertFalse(shows(inviteToCome), "the widget invite has its day first")
        inviteToCome.state.settings.widgetInviteDone = true
        XCTAssertTrue(shows(inviteToCome), "a Lock Screen widget already there answered the invite without a day")
    }

    /// After the trial notice, the nudge offer, the repair and the widget invite; never while locked.
    func testTheOfferComesAfterEveryOtherRowAndNeverWhileLocked() {
        let c = glp1Day()
        let settings = c.state.settings
        func pick(_ settings: StackSettings, repair: DayKey? = nil, locked: Bool = false, notice: String? = nil) -> TodayPrompt? {
            TodayPrompts.pick(settings: settings, hasStack: true, today: c.summary, repairDay: repair, locked: locked,
                              lockScreenWidget: true, trialNotice: notice, weightOffer: true)
        }
        XCTAssertEqual(pick(settings), .weightOffer)
        XCTAssertNil(pick(settings, locked: true), "none while locked: the Pro bar sits there")
        XCTAssertEqual(pick(settings, notice: "Your Taken trial ends Sunday 1 Nov."), .trialEnds("Your Taken trial ends Sunday 1 Nov."))
        var unanswered = settings
        unanswered.nudgeOfferDone = false
        XCTAssertEqual(pick(unanswered), .nudgeOffer(minutes: 20 * 60))
        XCTAssertEqual(pick(settings, repair: day(21)), .repair(day(21)))
        XCTAssertNil(TodayPrompts.pick(settings: settings, hasStack: true, today: c.summary, repairDay: nil, locked: false,
                                       lockScreenWidget: true, trialNotice: nil, weightOffer: false))
    }

    // MARK: Dose ticks

    /// A tick for each day a dose of a Weekly item was logged, on the day it was logged; never a daily item, and never a
    /// day the item was on another schedule.
    func testDoseTicksAreTheDaysAWeeklyDoseWasLogged() {
        let created = at(2026, 9, 1, 8)
        let vd3 = makeItem("Vitamin D3", "VD3", created: created, sortIndex: 0)
        let sem = makeItem("Semaglutide", "SEM", .weekdays([5]), created: created, sortIndex: 1)
        var state = StackState(items: [vd3, sem])
        for dayOfMonth in [1, 8, 15, 16, 22] {
            state.logDose(itemId: sem.id, at: at(2026, 10, dayOfMonth, 8), timeZone: london)
        }
        for dayOfMonth in 1...22 { state.logDose(itemId: vd3.id, at: at(2026, 10, dayOfMonth, 8), timeZone: london) }
        let engine = StackEngine(state: state, clock: londonClock())
        XCTAssertEqual(WeightTicks.days(engine: engine), [day(1), day(8), day(15), day(16), day(22)],
                       "each logged day once, a late dose on its own day")

        // Daily until 10 October, Weekly from then: only the doses logged on Weekly days tick.
        var changed = StackState(items: [vd3, sem])
        changed.items[1].frequency = .weekdays([5])
        changed.items[1].pastFrequencies = [FrequencyEra(until: at(2026, 10, 10, 12), frequency: .daily(times: 1))]
        for dayOfMonth in [2, 3, 15] { changed.logDose(itemId: sem.id, at: at(2026, 10, dayOfMonth, 8), timeZone: london) }
        XCTAssertEqual(WeightTicks.days(engine: StackEngine(state: changed, clock: londonClock())), [day(15)])
        XCTAssertTrue(WeightTicks.days(engine: StackEngine(state: StackState(), clock: londonClock())).isEmpty)
    }

    // MARK: The chart's window

    func testTheWindowFitsWhatIsInViewAndNeverStartsAtZero() {
        let weighIns = [weighIn(92, 1, month: 9), weighIn(88, 21), weighIn(89, 22)]
        let trend = WeightTrend.trend(weighIns, clock: londonClock())
        let ticks = [day(1, month: 9), day(17), day(22)]
        let week = WeightWindow.make(weighIns: weighIns, trend: trend, ticks: ticks, range: .week, today: day(22),
                                     clock: londonClock())
        XCTAssertEqual(week.firstDay, day(16))
        XCTAssertEqual(week.lastDay, day(22))
        XCTAssertEqual(week.dots.map(\.kg), [88, 89])
        XCTAssertEqual(week.ticks, [day(17), day(22)])
        let values = week.dots.map(\.kg) + week.trend.map(\.kg)
        let low = values.min() ?? 0
        let high = values.max() ?? 0
        let padding = max(WeightWindow.minimumPadding, (high - low) * 0.15)
        XCTAssertEqual(week.lower, low - padding, accuracy: 1e-9)
        XCTAssertEqual(week.upper, high + padding, accuracy: 1e-9)
        XCTAssertGreaterThan(week.lower, 80, "fitted to the data, never from zero")

        let all = WeightWindow.make(weighIns: weighIns, trend: trend, ticks: ticks, range: .all, today: day(22),
                                    clock: londonClock())
        XCTAssertEqual(all.firstDay, day(1, month: 9))
        XCTAssertEqual(all.dots.count, 3)
        XCTAssertEqual(all.trend.count, trend.count)
        XCTAssertGreaterThanOrEqual(all.upper, 92)

        let single = WeightWindow.make(weighIns: [weighIn(88, 22)], trend: WeightTrend.trend([weighIn(88, 22)], clock: londonClock()),
                                       ticks: [], range: .all, today: day(22), clock: londonClock())
        XCTAssertEqual(single.firstDay, day(16), "at least a week across")
        XCTAssertEqual(single.lower, 88 - WeightWindow.minimumPadding, accuracy: 1e-9)

        let stale = WeightWindow.make(weighIns: weighIns, trend: trend, ticks: ticks, range: .week, today: day(31),
                                      clock: londonClock())
        XCTAssertTrue(stale.isEmpty, "a week with no weigh-ins draws no line past the last one")
        XCTAssertEqual(WeightRange.allCases.map(\.label), ["W", "30D", "90D", "Y", "All"])
    }

    // MARK: CSV

    func testExportIsDateTimeAndKilogramsOldestFirst() {
        let pounds = WeighIn(kg: 194.6 * 0.45359237, weighedAt: at(2026, 10, 20, 7, 5))
        let csv = WeightCSV.make([weighIn(88.35, 21, 7, 42), pounds, weighIn(88, 19, 6, 58)], timeZone: london)
        XCTAssertEqual(csv.split(separator: "\n").map(String.init), [
            "date,time,kg",
            "2026-10-19,06:58,88.0",
            "2026-10-20,07:05,88.269",
            "2026-10-21,07:42,88.35",
        ])
        XCTAssertEqual(WeightCSV.fileName, "taken-weight.csv")
    }

    private func parse(_ text: String, unit: WeightUnit = .kg, locale: Locale? = nil) -> WeightImport.Parsed? {
        try? WeightImport.parse(text, fallbackUnit: unit, locale: locale ?? enGB, timeZone: london,
                                now: at(2026, 10, 22, 9)).get()
    }

    /// Taken's own file comes back as it went out, and a second import adds nothing.
    func testImportReadsTakensOwnExportAndDedupesByTheMinute() throws {
        let original = [weighIn(88.35, 21, 7, 42), WeighIn(kg: 194.6 * 0.45359237, weighedAt: at(2026, 10, 20, 7, 5))]
        let parsed = try XCTUnwrap(parse(WeightCSV.make(original, timeZone: london), unit: .lb))
        XCTAssertEqual(parsed.unit, .kg, "the header says kg")
        XCTAssertEqual(parsed.unreadable, 0)
        XCTAssertEqual(parsed.weighIns.map(\.weighedAt), [at(2026, 10, 20, 7, 5), at(2026, 10, 21, 7, 42)])
        XCTAssertEqual(parsed.weighIns.map(\.kg), [88.269, 88.35])
        XCTAssertEqual(WeightFormat.value(parsed.weighIns[0].kg, unit: .lb, locale: enUS), "194.6", "a pound figure round-trips")

        var state = WeightState(weighIns: original)
        XCTAssertNil(WeightState().firstWeighInAt)
        let merged = state.merge(parsed.weighIns, at: at(2026, 10, 22, 9))
        XCTAssertEqual(merged.added, 0)
        XCTAssertEqual(merged.already, 2)
        XCTAssertEqual(state.weighIns.count, 2)

        var fresh = WeightState()
        XCTAssertEqual(fresh.merge(parsed.weighIns, at: at(2026, 10, 22, 9)).added, 2)
        XCTAssertEqual(fresh.firstWeighInAt, at(2026, 10, 22, 9), "an import is a first weigh-in for the Pro rule")
        XCTAssertEqual(fresh.merge(parsed.weighIns, at: at(2026, 10, 22, 10)).added, 0, "the same file twice adds nothing")
        XCTAssertEqual(WeightCopy.imported(added: 2, already: 0, unreadable: 0, unit: .kg), "Added 2 weigh-ins, read in kg.")
        XCTAssertEqual(WeightCopy.imported(added: 0, already: 2, unreadable: 1, unit: .kg),
                       "Nothing new: those 2 weigh-ins are already in Taken. 1 row could not be read.")
        XCTAssertEqual(WeightCopy.imported(added: 1, already: 1, unreadable: 0, unit: .lb),
                       "Added 1 weigh-in, read in lb. 1 was already in Taken.")
    }

    /// The common layouts: a US file in pounds with month-first dates and another column, a German Excel file with
    /// semicolons and decimal commas, and an export with a title, quoted month names and a trend column.
    func testImportReadsTheCommonLayouts() throws {
        let us = try XCTUnwrap(parse("""
            Date,Weight (lbs),Body Fat (%)
            10/21/2026,194.6,22.1
            10/20/2026,195.0,22.3
            "10/19/2026","195.4 lbs",22.0
            """, unit: .kg, locale: enGB))
        XCTAssertEqual(us.unit, .lb)
        XCTAssertEqual(us.weighIns.map(\.weighedAt), [at(2026, 10, 19, 12), at(2026, 10, 20, 12), at(2026, 10, 21, 12)],
                       "a second number over 12 means month first; a date alone is noon")
        XCTAssertEqual(us.weighIns.last?.kg ?? 0, 194.6 * 0.45359237, accuracy: 1e-9)

        let german = try XCTUnwrap(parse("Datum;Gewicht (kg)\n21.10.2026;88,35\n20.10.2026;88,6\n", unit: .lb))
        XCTAssertEqual(german.unit, .kg)
        XCTAssertEqual(german.weighIns.map(\.kg), [88.6, 88.35])
        XCTAssertEqual(german.weighIns.first?.weighedAt, at(2026, 10, 20, 12))

        let export = try XCTUnwrap(parse("""
            MyNetDiary Data Export

            "Date","Weight, kg","Trending Weight, kg"
            "Oct 21, 2026","88.35","88.1"
            "Oct 20, 2026","88.6","88.2"
            "Oct 19, 2026","",""
            "Sunday, October 18, 2026","88.9","88.3"
            """))
        XCTAssertEqual(export.weighIns.map(\.kg), [88.9, 88.6, 88.35], "the weight, never the trend column")
        XCTAssertEqual(export.unreadable, 1, "a day with no weight")

        let noUnit = try XCTUnwrap(parse("date,weight\n2026-10-21,88.35\n", unit: .kg))
        XCTAssertEqual(noUnit.unit, .kg, "no unit anywhere: the person's own")
        XCTAssertEqual(try XCTUnwrap(parse("date,weight\n2026-10-21,194.6\n", unit: .lb)).weighIns.first?.kg ?? 0,
                       194.6 * 0.45359237, accuracy: 1e-9)

        let timed = try XCTUnwrap(parse("""
            Date,Time,Weight (kg),Notes
            2026-10-21,7:42 AM,88.35,after the gym
            2026-10-20T06:05:00Z,,88.5,
            21/10/2026 19:05,,88.9,
            """))
        XCTAssertEqual(timed.weighIns.map(\.weighedAt),
                       [at(2026, 10, 20, 7, 5), at(2026, 10, 21, 7, 42), at(2026, 10, 21, 19, 5)])
        XCTAssertEqual(timed.weighIns.first?.utcOffset, 0, "the zone the cell names")
        XCTAssertEqual(londonClock().day(of: timed.weighIns[0]), day(20))

        let tabs = try XCTUnwrap(parse("date\tkg\n2026-10-21\t88.35\n"))
        XCTAssertEqual(tabs.weighIns.count, 1)
        let headerless = try XCTUnwrap(parse("2026-10-21,88.35\n2026-10-20,88.6\n", unit: .kg))
        XCTAssertEqual(headerless.weighIns.count, 2, "two columns, a date and a number")
    }

    func testImportSkipsWhatItCannotReadAndSaysSo() throws {
        let mixed = try XCTUnwrap(parse("""
            date,kg
            2026-10-23,88.0
            2026-10-21,12.0
            2026-10-21,abc
            2026-02-31,88.0
            2026-10-20,88.4
            2026-10-19,88.6
            2026-10-19,88.5

            """))
        XCTAssertEqual(mixed.weighIns.map(\.kg), [88.5, 88.4], "the 19th twice at noon: the lower stays")
        XCTAssertEqual(mixed.unreadable, 4, "a day to come, below the bounds, not a number, not a date")

        let ambiguous = "date,kg\n03/04/2026,88.0\n"
        XCTAssertEqual(try XCTUnwrap(parse(ambiguous, locale: enUS)).weighIns.first?.weighedAt, at(2026, 3, 4, 12))
        XCTAssertEqual(try XCTUnwrap(parse(ambiguous, locale: enGB)).weighIns.first?.weighedAt, at(2026, 4, 3, 12),
                       "neither number over 12: the locale's own order")

        XCTAssertEqual(WeightImport.parse("hello,world\n1,2\n", fallbackUnit: .kg), .failure(.noColumns))
        XCTAssertEqual(WeightImport.parse("", fallbackUnit: .kg), .failure(.noColumns))
        XCTAssertEqual(WeightImport.parse("date,kg\nfoo,bar\n", fallbackUnit: .kg), .failure(.nothingReadable))
        XCTAssertEqual(WeightImport.text(from: Data("\u{FEFF}date,kg".utf8)).map { $0.replacingOccurrences(of: "\u{FEFF}", with: "") },
                       "date,kg")
        XCTAssertEqual(WeightImport.text(from: "date,kg".data(using: .utf16)!), "date,kg")
    }

    // MARK: Copy

    func testTheCopyIsCalmAndNeutral() {
        for text in WeightCopy.all {
            XCTAssertFalse(text.contains("\u{2014}") || text.contains("\u{2013}"), "no em or en dash: \(text)")
            XCTAssertNil(text.range(of: "free", options: .caseInsensitive), text)
            XCTAssertFalse(text.contains("!"), text)
            for word in ["lose", "loss", "ideal", "goal"] {
                XCTAssertNil(text.range(of: word, options: .caseInsensitive), "\(word) in \(text)")
            }
        }
        let clock = londonClock()
        let now = at(2026, 10, 22, 9)
        XCTAssertEqual(WeightCopy.lastLine(nil, now: now, clock: clock), "No weigh-ins yet")
        XCTAssertEqual(WeightCopy.lastLine(weighIn(88, 22, 7, 42), now: now, clock: clock), "Last weigh-in today, 07:42")
        XCTAssertEqual(WeightCopy.lastLine(weighIn(88, 21, 7, 42), now: now, clock: clock), "Last weigh-in yesterday, 07:42")
        XCTAssertEqual(WeightCopy.lastLine(weighIn(88, 19, 7, 42), now: now, clock: clock), "Last weigh-in Monday, 07:42")
        XCTAssertEqual(WeightCopy.lastLine(weighIn(88, 14, 7, 42), now: now, clock: clock), "Last weigh-in 14 Oct, 07:42")
        XCTAssertEqual(WeightCopy.listDay(day(20), today: day(22)), "Tue 20 Oct")
        XCTAssertEqual(WeightCopy.listDay(DayKey(year: 2025, month: 3, day: 3), today: day(22)), "Mon 3 Mar 2025")
    }

    // MARK: The tab

    @MainActor
    func testHidingTheTabBringsTodayForwardFirstAndUndoBringsItBack() throws {
        let model = AppModel.fromLaunchArguments(["Taken", "-demo", "-screen", "weight"])
        XCTAssertEqual(AppModel.tab(forScreen: "weight"), .weight)
        XCTAssertEqual(model.tab, .weight)
        XCTAssertTrue(model.weight.showsTab)
        XCTAssertFalse(model.weight.isEmpty)

        model.hideWeightTab()
        XCTAssertEqual(model.tab, .today, "a hidden tab never stays selected")
        XCTAssertFalse(model.weight.showsTab)
        XCTAssertEqual(WeightStore(fileURL: model.weight.store.fileURL).load().showsTab, false, "kept in weights.json")
        let toast = try XCTUnwrap(model.toast)
        XCTAssertEqual(toast.message, "Weight tab hidden. Profile brings it back.")
        XCTAssertEqual(toast.undo, .showWeightTab)
        XCTAssertFalse(model.weight.isEmpty, "hiding deletes nothing")

        model.undo(toast)
        XCTAssertTrue(model.weight.showsTab)
        XCTAssertEqual(model.tab, .weight)

        model.setWeightTab(false)
        XCTAssertEqual(model.tab, .today, "Profile's switch off while the tab is in front")
        model.setWeightTab(true)
        XCTAssertEqual(model.tab, .today, "on never switches tabs")
        XCTAssertEqual(WeightStore(fileURL: model.weight.store.fileURL).load().showsTab, true)

        model.openWeightTab()
        XCTAssertEqual(model.tab, .weight, "taken://weight")
        model.setWeightTab(false)
        model.openWeightTab()
        XCTAssertEqual(model.tab, .today, "taken://weight with the tab off lands on Today")

        let others = AppModel.fromLaunchArguments(["Taken", "-demo", "-screen", "today"])
        XCTAssertFalse(others.weight.showsTab, "every other screen shows the default app")
        XCTAssertNil(WeightState().showsTab, "off by default: nil until the person chooses")
    }

    @MainActor
    func testTheOfferAddsTheTabWithoutSwitchingAndNeverComesBack() {
        let model = AppModel.fromLaunchArguments(["Taken", "-demo", "-screen", "today-weight-offer"])
        XCTAssertEqual(model.todayPrompt, .weightOffer)
        XCTAssertTrue(model.today.allTaken)
        XCTAssertTrue(model.activeItems.contains { $0.code == "SEM" }, "a stack with a weekly shot")
        XCTAssertFalse(model.weight.showsTab)

        model.answerWeightOffer(addTab: true)
        XCTAssertNil(model.todayPrompt)
        XCTAssertTrue(model.weight.showsTab)
        XCTAssertTrue(model.weight.state.offerAnswered)
        XCTAssertEqual(model.tab, .today, "Add tab does not switch to it")

        let declined = AppModel.fromLaunchArguments(["Taken", "-demo", "-screen", "today-weight-offer"])
        declined.answerWeightOffer(addTab: false)
        XCTAssertFalse(declined.weight.showsTab)
        XCTAssertTrue(declined.weight.state.offerAnswered)
        XCTAssertNil(AppModel.demoRow(forScreen: "today", settings: StackSettings(), today: DayKey(ordinal: 0)))
    }

    /// The first weigh-in opens the sheet without Pro; the next opens the paywall. Save shows the weight with UNDO.
    @MainActor
    func testLoggingFollowsTheWeighInRuleAndUndoRemovesIt() throws {
        let model = AppModel.fromLaunchArguments(["Taken", "-demo", "-screen", "locked"])
        XCTAssertEqual(model.weightAccess, .firstSession)
        model.openWeighIn()
        XCTAssertEqual(model.sheet, .weighIn)
        XCTAssertEqual(SheetRoute.weighIn.id, "weigh-in")
        model.sheet = nil

        model.saveWeighIn(kg: 88.35)
        let toast = try XCTUnwrap(model.toast)
        XCTAssertEqual(toast.message, "Weighed in")
        XCTAssertEqual(toast.time, WeightFormat.withUnit(88.35, unit: model.weight.unit))
        XCTAssertEqual(model.weight.state.weighIns.count, 1)
        XCTAssertNotNil(model.weight.state.firstWeighInAt)
        XCTAssertEqual(model.weightAccess, .locked, "after the first weigh-in, logging needs Pro")

        model.undo(toast)
        XCTAssertTrue(model.weight.isEmpty, "UNDO removes it")
        XCTAssertEqual(model.weightAccess, .locked, "and the first weigh-in stays used")

        model.openWeighIn()
        XCTAssertNil(model.sheet)
        XCTAssertNotNil(model.paywall, "the paywall instead of the sheet")
        XCTAssertNotEqual(model.access, .firstSession)
    }

    /// Erase all data takes the weigh-ins and keeps the tab setting, the unit, the offer's answer and the first
    /// weigh-in's date; the dialog says so.
    @MainActor
    func testEraseTakesTheWeighInsAndKeepsTheChoices() throws {
        XCTAssertTrue(ProfileView.eraseMessage.contains("your weigh-ins"))
        XCTAssertTrue(ProfileView.eraseMessage.contains("to-dos"))
        let model = AppModel.fromLaunchArguments(["Taken", "-demo", "-screen", "weight"])
        model.weight.setUnit(.lb)
        model.weight.answerOffer(addTab: true)
        model.setWeightRange(.month)
        let first = model.weight.state.firstWeighInAt
        XCTAssertNotNil(first)
        model.eraseAll()
        let kept = WeightStore(fileURL: model.weight.store.fileURL).load()
        XCTAssertTrue(kept.weighIns.isEmpty)
        XCTAssertEqual(kept.showsTab, true)
        XCTAssertEqual(kept.unit, .lb)
        XCTAssertTrue(kept.offerAnswered)
        XCTAssertEqual(kept.firstWeighInAt, first)
        XCTAssertNil(kept.range, "the chart's range goes back to All")
    }
}
