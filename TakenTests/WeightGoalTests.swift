import XCTest
@testable import Taken

/// The Weight tab's optional goal (REDESIGN.md, "Goal and moments, 2026-10-22"): the start, the direction, the floor, the
/// lit points, the slot's reading, which point a save just lit, the y axis and the goal in it, the change line, the copy,
/// storage, Clear with UNDO, the Goal sheet's start rule and the demo screens. London clock, the day starting at 04:00.
final class WeightGoalTests: XCTestCase {

    private let enGB = Locale(identifier: "en_GB")

    private func day(_ dayOfMonth: Int, month: Int = 10, year: Int = 2026) -> DayKey {
        DayKey(year: year, month: month, day: dayOfMonth)
    }

    /// A trend, one value a day from `start`.
    private func points(_ values: [Double], from start: DayKey = DayKey(year: 2026, month: 10, day: 1)) -> [WeightPoint] {
        values.enumerated().map { WeightPoint(day: start.adding($0.offset), kg: $0.element) }
    }

    private func everyDay(_ trend: [WeightPoint]) -> Set<DayKey> { Set(trend.map(\.day)) }

    private func weighIn(_ kg: Double, _ dayOfMonth: Int, _ hour: Int = 7, _ minute: Int = 0) -> WeighIn {
        let date = at(2026, 10, dayOfMonth, hour, minute)
        return WeighIn(kg: kg, weighedAt: date, utcOffset: london.secondsFromGMT(for: date))
    }

    private func slot(_ readout: GoalReadout, goal: Double, unit: WeightUnit = .kg) -> String {
        WeightGoalCopy.text(WeightGoalCopy.slot(readout, goalKg: goal, unit: unit, locale: enGB))
    }

    // MARK: 1. The start

    func testTheStartIsTheFirstWeighInUnlessTheTrendHasBeenAtTheGoal() {
        let trend = points([97.8, 97.0, 96.0, 95.0])
        XCTAssertEqual(WeightGoals.defaultStartDay(goalKg: 87, trend: trend), day(1), "outside the trend's range")
        XCTAssertEqual(WeightGoals.defaultStartDay(goalKg: 99, trend: trend), day(1))
        XCTAssertEqual(WeightGoals.defaultStartDay(goalKg: 96.5, trend: trend), day(4),
                       "the trend has been at 96.5 already: the last weigh-in day, so a regain is never a finished goal")
        XCTAssertNil(WeightGoals.defaultStartDay(goalKg: 87, trend: []))

        XCTAssertEqual(WeightGoals.start(of: WeightGoal(kg: 87, startDay: day(2)), trend: trend), WeightPoint(day: day(2), kg: 97))
        XCTAssertEqual(WeightGoals.start(of: WeightGoal(kg: 87, startDay: day(20, month: 9)), trend: trend)?.day, day(1),
                       "clamped to the first weigh-in day")
        XCTAssertEqual(WeightGoals.start(of: WeightGoal(kg: 87, startDay: day(9)), trend: trend)?.day, day(4),
                       "clamped to the last weigh-in day")
        XCTAssertNil(WeightGoals.start(of: WeightGoal(kg: 87, startDay: day(1)), trend: []), "it waits for a weigh-in")

        // Deleting the first weigh-in moves the start to the new first one.
        var state = WeightState(weighIns: [weighIn(97.8, 1), weighIn(97, 2), weighIn(96, 3)])
        state.goal = WeightGoal(kg: 87, startDay: day(1))
        state.delete(state.weighIns[0].id)
        let after = WeightTrend.trend(state.weighIns, clock: londonClock())
        XCTAssertEqual(WeightGoals.start(of: state.goal!, trend: after), WeightPoint(day: day(2), kg: 97))
    }

    // MARK: 2. Direction

    func testTheDirectionIsInferredWithAHoldBandOf068Kilograms() {
        XCTAssertEqual(WeightGoals.direction(startKg: 90, goalKg: 90), .near)
        XCTAssertEqual(WeightGoals.direction(startKg: 90, goalKg: 89.32), .near, "0.68 below is still near")
        XCTAssertEqual(WeightGoals.direction(startKg: 90, goalKg: 89.31), .lower)
        XCTAssertEqual(WeightGoals.direction(startKg: 90, goalKg: 90.68), .near, "0.68 above is still near")
        XCTAssertEqual(WeightGoals.direction(startKg: 90, goalKg: 90.69), .higher)
    }

    // MARK: 3. The floor

    func testTheFloorIsBMI185AndNeverBlocksAGainGoal() {
        XCTAssertEqual(WeightGoals.floorKg(heightCm: 180), 18.5 * 1.8 * 1.8, accuracy: 1e-9)
        XCTAssertEqual(WeightGoals.floorKg(heightCm: 180), 59.94, accuracy: 1e-9)
        XCTAssertEqual(HeightUnit.centimetres(feet: 6, inches: 0), 182.88, accuracy: 1e-9)
        XCTAssertEqual(HeightUnit.centimetres(feet: 5, inches: 7), 170.18, accuracy: 1e-9)
        XCTAssertEqual(HeightUnit.feetInches(centimetres: 180).feet, 5)
        XCTAssertEqual(HeightUnit.feetInches(centimetres: 180).inches, 11)
        XCTAssertEqual(HeightUnit.feetInches(centimetres: 182.88).feet, 6)
        XCTAssertEqual(HeightUnit.feetInches(centimetres: 182.88).inches, 0)
        XCTAssertEqual(HeightUnit.preferred(for: Locale(identifier: "en_US")), .feetInches)
        XCTAssertEqual(HeightUnit.preferred(for: enGB), .feetInches)
        XCTAssertEqual(HeightUnit.preferred(for: Locale(identifier: "de_DE")), .centimetres)
        XCTAssertEqual(HeightUnit.preferred(for: Locale(identifier: "fr_FR")), .centimetres, "metres show as centimetres")

        XCTAssertTrue(WeightGoals.floorBlocks(goalKg: 55, startKg: 97.8, heightCm: 180), "a lower goal below BMI 18.5")
        XCTAssertFalse(WeightGoals.floorBlocks(goalKg: 59.94, startKg: 97.8, heightCm: 180), "the floor itself is allowed")
        XCTAssertFalse(WeightGoals.floorBlocks(goalKg: 60, startKg: 97.8, heightCm: 180))
        XCTAssertTrue(WeightGoals.floorBlocks(goalKg: 59.5, startKg: 59.8, heightCm: 180), "a near goal below the floor")
        XCTAssertFalse(WeightGoals.floorBlocks(goalKg: 58, startKg: 50, heightCm: 180), "gaining towards a healthier weight")
        XCTAssertTrue(WeightGoals.floorBlocks(goalKg: 55, startKg: 97.8, heightCm: HeightUnit.centimetres(feet: 5, inches: 11)))
    }

    // MARK: 4. Points

    func testPointsLandOnTheFirstWeighInDayAtOrPastEachThresholdAndStay() {
        // Start 100: 5% is 95.0, 10% is 90.0. Day 4 (index 3) crosses 95 but is a day the trend filled in.
        let trend = points([100, 96, 95.5, 94.9, 94.0, 92, 89.9, 91, 92])
        var days = everyDay(trend)
        days.remove(day(4))
        let goal = WeightGoal(kg: 80, startDay: day(1))
        let moments = WeightGoals.moments(goal: goal, trend: trend, weighInDays: days, heightCm: 180)
        XCTAssertEqual(moments.map(\.id), ["pct5", "pct10"])
        XCTAssertEqual(moments[0].day, day(5), "a crossing inside a gap lands on the next weigh-in day")
        XCTAssertEqual(moments[0].trendKg, 94.0)
        XCTAssertEqual(moments[1].day, day(7))
        XCTAssertEqual(moments[1].trendKg, 89.9, "and it stays after the trend rises again")

        // Only between the start and the goal, and more than 0.05 kg from the goal.
        let fall = points([100, 96, 94.9, 93, 91])
        func ids(goal kg: Double) -> [String] {
            WeightGoals.moments(goal: WeightGoal(kg: kg, startDay: day(1)), trend: fall, weighInDays: everyDay(fall),
                                heightCm: 180).map(\.id)
        }
        XCTAssertEqual(ids(goal: 94.9), ["pct5", "goal"], "95.0 lies 0.1 above the goal: marked")
        XCTAssertEqual(ids(goal: 94.98), ["goal"], "95.0 lies within 0.05 of the goal: nothing past your own goal")
        XCTAssertEqual(ids(goal: 92), ["pct5", "goal"], "10% lies past the goal: never marked")

        // The start must be at BMI 25 or more for 5% and 10%: 100 kg at 2 m is 25.0, 99.6 kg is 24.9.
        let at25 = points([100, 94, 89, 80])
        XCTAssertEqual(WeightGoals.moments(goal: WeightGoal(kg: 80, startDay: day(1)), trend: at25, weighInDays: everyDay(at25),
                                           heightCm: 200).map(\.id), ["pct5", "pct10", "goal"])
        let at249 = points([99.6, 94, 89, 80])
        XCTAssertEqual(WeightGoals.moments(goal: WeightGoal(kg: 80, startDay: day(1)), trend: at249,
                                           weighInDays: everyDay(at249), heightCm: 200).map(\.id), ["goal"])
        XCTAssertEqual(WeightGoals.moments(goal: WeightGoal(kg: 80, startDay: day(1)), trend: at25, weighInDays: everyDay(at25),
                                           heightCm: nil).map(\.id), ["goal"], "no height, no percent points")

        // A near goal gets none; a higher goal only its own.
        let flat = points([90, 89.8, 89.6])
        XCTAssertTrue(WeightGoals.moments(goal: WeightGoal(kg: 89.5, startDay: day(1)), trend: flat, weighInDays: everyDay(flat),
                                          heightCm: 180).isEmpty)
        let rise = points([60, 62, 64.96, 63])
        XCTAssertEqual(WeightGoals.moments(goal: WeightGoal(kg: 65, startDay: day(1)), trend: rise, weighInDays: everyDay(rise),
                                           heightCm: 180).map(\.id), ["goal"], "within 0.05 of a higher goal")

        // The 0.05 kg reach tolerance.
        let near80 = points([100, 90, 80.04])
        XCTAssertEqual(WeightGoals.moments(goal: WeightGoal(kg: 80, startDay: day(1)), trend: near80,
                                           weighInDays: everyDay(near80), heightCm: nil).map(\.id), ["goal"])
        let short = points([100, 90, 80.06])
        XCTAssertTrue(WeightGoals.moments(goal: WeightGoal(kg: 80, startDay: day(1)), trend: short,
                                          weighInDays: everyDay(short), heightCm: nil).isEmpty)
    }

    // MARK: 5. The slot

    func testTheSlotSaysHowCloseTheTrendIsInTheUnitShown() {
        let goal = WeightGoal(kg: 90, startDay: day(1))
        func readout(_ values: [Double], unit: WeightUnit = .kg, goal: WeightGoal = goal) -> GoalReadout {
            let trend = points(values)
            let moments = WeightGoals.moments(goal: goal, trend: trend, weighInDays: everyDay(trend), heightCm: 180)
            return WeightGoals.readout(goal: goal, trend: trend, moments: moments, unit: unit)
        }
        XCTAssertEqual(readout([100, 99.95]), .goalOnly, "less than 0.1 covered")
        XCTAssertEqual(slot(readout([100, 99.95]), goal: 90), "Goal 90.0")
        XCTAssertEqual(readout([100, 100.5]), .goalOnly, "on the far side of the start: no number, no words")
        XCTAssertEqual(slot(readout([100, 97]), goal: 90), "3.0 kg closer to 90.0")
        XCTAssertEqual(slot(readout([100, 96.96]), goal: 90), "3.0 kg closer to 90.0", "closer rounds down")
        XCTAssertEqual(slot(readout([100, 95.01]), goal: 90), "4.9 kg closer to 90.0")
        XCTAssertEqual(readout([100, 95]), .toGo(5), "exactly half covered: to go")
        XCTAssertEqual(slot(readout([100, 95]), goal: 90), "5.0 kg to 90.0")
        XCTAssertEqual(slot(readout([100, 91.04]), goal: 90), "1.1 kg to 90.0", "to go rounds up")

        XCTAssertEqual(readout([100, 95, 90]), .holding, "reached")
        XCTAssertEqual(slot(readout([100, 95, 90, 90.6]), goal: 90), "Holding near 90.0", "within 0.68 kg")
        XCTAssertEqual(slot(readout([100, 95, 90, 90.9]), goal: 90), "0.9 kg from 90.0", "beyond it: a number only")
        let near = WeightGoal(kg: 89.5, startDay: day(1))
        XCTAssertEqual(slot(readout([90, 90], goal: near), goal: 89.5), "Holding near 89.5", "a near goal holds from day one")
        XCTAssertEqual(slot(readout([90, 91], goal: near), goal: 89.5), "1.5 kg from 89.5")

        // In pounds: 0.05 kg covered is 0.11 lb, past 0.1; 3 kg is 6.6 lb; the goal reads 198.4.
        XCTAssertEqual(slot(readout([100, 99.95], unit: .lb), goal: 90, unit: .lb), "0.1 lb closer to 198.4")
        XCTAssertEqual(slot(readout([100, 97], unit: .lb), goal: 90, unit: .lb), "6.6 lb closer to 198.4")
        XCTAssertEqual(WeightGoalCopy.spokenSlot(.toGo(1.04), goalKg: 87, unit: .kg, locale: enGB), "1.1 kilograms to your goal, 87.0")
        XCTAssertEqual(WeightGoalCopy.spokenSlot(.goalOnly, goalKg: 87, unit: .kg, locale: enGB), "Goal, 87.0 kilograms")
    }

    // MARK: 6. Fresh points

    func testOnlyASaveThatLightsAPointOnItsOwnDayAcknowledgesIt() {
        let goal = WeightGoal(kg: 80, startDay: day(1))
        func moments(_ values: [Double]) -> [WeightMoment] {
            let trend = points(values)
            return WeightGoals.moments(goal: goal, trend: trend, weighInDays: everyDay(trend), heightCm: 180)
        }
        let before = moments([100, 96])
        let after = moments([100, 96, 94.9])
        XCTAssertEqual(WeightGoals.fresh(before: before, after: after, savedDay: day(3))?.id, "pct5")
        XCTAssertNil(WeightGoals.fresh(before: after, after: after, savedDay: day(3)), "a second weigh-in the same day")
        XCTAssertEqual(WeightGoals.fresh(before: before, after: moments([100, 96, 89]), savedDay: day(3))?.id, "pct10",
                       "two at once: the higher rank")
        let withGoal = WeightGoal(kg: 89, startDay: day(1))
        let reached = WeightGoals.moments(goal: withGoal, trend: points([100, 96, 89]), weighInDays: everyDay(points([100, 96, 89])),
                                          heightCm: 180)
        XCTAssertEqual(reached.map(\.id), ["pct5", "pct10", "goal"])
        XCTAssertEqual(WeightGoals.fresh(before: [], after: reached, savedDay: day(3))?.id, "goal", "the goal outranks 10%")
        XCTAssertNil(WeightGoals.fresh(before: before, after: moments([100, 94.9, 95]), savedDay: day(3)),
                     "a point dated before the saved day: silent")
        XCTAssertEqual(WeightGoals.fresh(before: before, after: after, savedDay: day(3)),
                       WeightGoals.fresh(before: before, after: after, savedDay: day(3)), "UNDO, then the same number again")
    }

    /// Through the app model: the demo stack 0.06 above the 10% line; saving 87.1 lights 10%, UNDO takes it away, and
    /// saving it again lights it again.
    @MainActor
    func testSavingAWeighInThatCrossesLightsItOnceAndUndoTakesItBack() throws {
        let model = AppModel.fromLaunchArguments(["Taken", "-demo", "-screen", "weight-goal"])
        XCTAssertNil(model.weight.justReached)
        model.saveWeighIn(kg: 87.1)
        XCTAssertEqual(model.weight.justReached?.id, "pct10")
        let toast = try XCTUnwrap(model.toast)
        XCTAssertEqual(toast.message, "Weighed in")
        model.undo(toast)
        XCTAssertNil(model.weight.justReached, "UNDO removes the point and its sentence")
        XCTAssertEqual(model.weightPicture(range: .all).moments.map(\.id), ["pct5"])
        model.saveWeighIn(kg: 87.1)
        XCTAssertEqual(model.weight.justReached?.id, "pct10", "a typo cannot use up a moment")
        model.saveWeighIn(kg: 87.0)
        XCTAssertNil(model.weight.justReached, "the next weigh-in brings the closing-in line back")
    }

    // MARK: 7. The y domain

    func testTheGoalJoinsTheAxisOnlyIfTheDataKeepsHalfThePlot() {
        let weighIns = [weighIn(92, 20), weighIn(91, 21), weighIn(90, 22)]
        let trend = WeightTrend.trend(weighIns, clock: londonClock())
        func window(goal: Double?) -> WeightWindow {
            WeightWindow.make(weighIns: weighIns, trend: trend, ticks: [], range: .week, today: day(22), clock: londonClock(),
                              goalKg: goal)
        }
        let none = window(goal: nil)
        XCTAssertEqual(none.lower, 89.6, accuracy: 1e-9)
        XCTAssertEqual(none.upper, 92.4, accuracy: 1e-9)
        XCTAssertFalse(none.goalInDomain)
        let near = window(goal: 88)
        XCTAssertTrue(near.goalInDomain, "5.2 kg with it against 2.8 without: in")
        XCTAssertEqual(near.lower, 87.4, accuracy: 1e-9)
        XCTAssertEqual(near.upper, 92.6, accuracy: 1e-9)
        let far = window(goal: 87)
        XCTAssertFalse(far.goalInDomain, "6.5 kg against 2.8: pinned to the edge, the line keeps its height")
        XCTAssertEqual(far.lower, 89.6, accuracy: 1e-9)
        XCTAssertTrue(window(goal: 94).goalInDomain)
        XCTAssertFalse(window(goal: 95).goalInDomain)
        XCTAssertTrue(window(goal: 91).goalInDomain, "inside the data")
    }

    // MARK: 8. The axis

    func testTicksAreFourOrFewerAndGiveWayToTheGoal() {
        XCTAssertEqual(WeightAxis.ticks(lower: 89.6, upper: 92.4), [90, 91, 92])
        XCTAssertEqual(WeightAxis.decimals([90, 91, 92]), 0)
        XCTAssertEqual(WeightAxis.ticks(lower: 88.0, upper: 89.2), [88, 88.5, 89])
        XCTAssertEqual(WeightAxis.decimals([88, 88.5, 89]), 1, "one decimal only for half steps")
        XCTAssertEqual(WeightAxis.ticks(lower: 86.25, upper: 92.75), [88, 90, 92])
        XCTAssertEqual(WeightAxis.ticks(lower: 60, upper: 100), [60, 80, 100])
        for (lower, upper) in [(85.0, 98.0), (190.0, 216.0), (55.5, 56.1), (40.0, 300.0)] {
            XCTAssertLessThanOrEqual(WeightAxis.ticks(lower: lower, upper: upper).count, 4, "\(lower) to \(upper)")
        }
        // 196 pt over 6.5 kg is about 30 pt a kilogram: 88 sits 9 pt from a goal at 87.7 and gives way; 12 pt is clear.
        XCTAssertEqual(WeightAxis.clear([88, 90, 92], of: 87.7, lower: 86.25, upper: 92.75, plotHeight: 196), [90, 92])
        XCTAssertEqual(WeightAxis.clear([88, 90, 92], of: 87.6, lower: 86.25, upper: 92.75, plotHeight: 196), [88, 90, 92])
        // A goal pinned 8 pt inside the top: the top tick under it gives way.
        let inset = 8 / 196 * (92.05 - 90.0)
        XCTAssertEqual(WeightAxis.clear(WeightAxis.ticks(lower: 90, upper: 92.05), of: 92.05 - inset, lower: 90, upper: 92.05,
                                        plotHeight: 196), [90, 91])
    }

    // MARK: 9. The change line

    func testTheChangeLineFollowsTheRange() {
        let clock = londonClock()
        let weighIns = [weighIn(90, 1)] + (2...8).map { weighIn(89, $0) }
        let trend = WeightTrend.trend(weighIns, clock: clock)
        func line(_ range: WeightRange, today: Int = 8) -> (kg: Double, span: WeightChangeLine.Span)? {
            let window = WeightWindow.make(weighIns: weighIns, trend: trend, ticks: [], range: range, today: day(today), clock: clock)
            return WeightChangeLine.make(range: range, trend: trend, window: window)
        }
        XCTAssertEqual(line(.week)?.span, .days(7))
        XCTAssertEqual(line(.week)?.kg ?? 0, pow(0.9, 7) - 1, accuracy: 1e-9)
        XCTAssertEqual(line(.month)?.span, .since(day(1)), "a trend shorter than the range: since its first day")
        XCTAssertEqual(line(.month)?.kg ?? 0, trend.last!.kg - 90, accuracy: 1e-9)
        XCTAssertEqual(line(.all)?.span, .since(day(1)), "always since on All")
        XCTAssertNil(line(.week, today: 20), "fewer than two trend days in view: hidden")

        let today = day(22)
        func text(_ kg: Double, _ span: WeightChangeLine.Span) -> String {
            WeightGoalCopy.text(WeightGoalCopy.changeLine(kg, span: span, unit: .kg, today: today, locale: enGB))
        }
        XCTAssertEqual(text(-1.21, .days(30)), "\u{2212}1.2 kg over 30 days")
        XCTAssertEqual(text(0.5, .since(day(4, month: 3))), "+0.5 kg since 4 Mar")
        XCTAssertEqual(text(-9.72, .since(day(4, month: 3, year: 2025))), "\u{2212}9.7 kg since 4 Mar 2025")
        XCTAssertEqual(text(-0.4, .year), "\u{2212}0.4 kg over the year")
        XCTAssertEqual(text(0.04, .days(30)), "No change over 30 days")
        XCTAssertEqual(text(-0.04, .since(day(4, month: 3))), "No change since 4 Mar")
        XCTAssertEqual(WeightGoalCopy.text(WeightGoalCopy.changeLine(-1.0, span: .days(7), unit: .lb, today: today, locale: enGB)),
                       "\u{2212}2.2 lb over 7 days")
        XCTAssertEqual(WeightGoalCopy.spokenChange(-1.21, span: .days(30), unit: .kg, today: today, locale: enGB),
                       "Down 1.2 kilograms over 30 days")
        XCTAssertEqual(WeightGoalCopy.spokenChange(0.5, span: .since(day(4, month: 3)), unit: .kg, today: today, locale: enGB),
                       "Up 0.5 kilograms since 4 March")
        XCTAssertEqual(WeightGoalCopy.spokenChange(0.01, span: .days(30), unit: .kg, today: today, locale: enGB),
                       "No change over 30 days")
    }

    // MARK: 10. Copy

    func testTheGoalCopyIsPlainAndNeverJudges() throws {
        let banned = try NSRegularExpression(pattern: #"\b(lose|lost|loss|ideal|great|should|missed|behind)\b|off track"#,
                                             options: [.caseInsensitive])
        for text in WeightGoalCopy.all {
            XCTAssertFalse(text.isEmpty)
            XCTAssertFalse(text.contains("\u{2014}") || text.contains("\u{2013}"), "no em or en dash: \(text)")
            XCTAssertNil(text.range(of: "free", options: .caseInsensitive), text)
            XCTAssertFalse(text.contains("!"), text)
            XCTAssertNil(banned.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)), text)
        }
        XCTAssertTrue(WeightGoalCopy.all.contains { $0.contains("closer") }, "whole words: closer holds lose and is fine")
        for text in WeightCopy.all {
            XCTAssertNil(text.range(of: "goal", options: .caseInsensitive), "the core copy still never says goal: \(text)")
        }
        XCTAssertEqual(WeightGoalCopy.setGoal, "Set Goal\u{2026}")
        XCTAssertEqual(WeightGoalCopy.changeGoal, "Change Goal\u{2026}")
        XCTAssertEqual(WeightGoalCopy.setHeight(183, unit: .centimetres), "Set 183 cm")
        XCTAssertEqual(WeightGoalCopy.setHeight(182.88, unit: .feetInches), "Set 6 ft 0 in")
        let ten = WeightMoment(kind: .percent(10), day: day(3, month: 8), trendKg: 92.9)
        let goal = WeightMoment(kind: .goal, day: day(22), trendKg: 87)
        XCTAssertEqual(WeightGoalCopy.text(WeightGoalCopy.moment(ten, goalKg: 87, unit: .kg, locale: enGB)),
                       "Trend is now 10% below where you started.")
        XCTAssertEqual(WeightGoalCopy.text(WeightGoalCopy.moment(goal, goalKg: 87, unit: .kg, locale: enGB)), "Trend reached 87.0.")
        XCTAssertEqual(WeightGoalCopy.spokenMoment(goal, goalKg: 87, unit: .kg, locale: enGB),
                       "Trend reached your goal, 87.0 kilograms.")
        XCTAssertEqual(WeightGoalCopy.chartLabel(ten), "\u{2212}10%")
        XCTAssertNil(WeightGoalCopy.chartLabel(goal), "the goal point is never labelled")
        XCTAssertEqual(WeightGoalCopy.pointValue(ten, unit: .kg, locale: enGB), "3 August, trend 92.9 kilograms")
        XCTAssertEqual(WeightGoalCopy.marked([WeightMoment(kind: .percent(5), day: day(3, month: 8), trendKg: 92.9)]),
                       "Marked: 5 percent below where you started, 3 August.")
        XCTAssertEqual(WeightGoalCopy.goalSet(87, unit: .kg, locale: enGB), "Goal set, 87.0 kilograms.")
        XCTAssertTrue(ProfileView.eraseMessage.contains("your weight goal"))
    }

    // MARK: 11. Storage

    func testTheGoalAndHeightAreStoredReadLossilyAndErased() throws {
        let url = temporaryStoreURL().deletingLastPathComponent().appendingPathComponent("weights-goal-\(UUID().uuidString).json")
        let store = WeightStore(fileURL: url, postsChangeNotifications: false)
        var state = WeightState(weighIns: [weighIn(97.8, 1)], showsTab: true, unit: .lb)
        state.goal = WeightGoal(kg: 87, startDay: day(1), startPicked: true)
        state.heightCm = 180
        try store.replace(with: state)
        XCTAssertEqual(store.load().goal, WeightGoal(kg: 87, startDay: day(1), startPicked: true))
        XCTAssertEqual(store.load().heightCm, 180)

        let lossy = #"{"weighIns":[],"showsTab":true,"goal":{"startDay":{"ordinal":20000}},"heightCm":"tall"}"#
        let read = try WeightStore.decode(Data(lossy.utf8))
        XCTAssertNil(read.goal, "a goal that cannot be read is none")
        XCTAssertNil(read.heightCm)
        XCTAssertEqual(read.showsTab, true, "and the rest of the file still reads")
        let older = try WeightStore.decode(Data(#"{"weighIns":[],"unit":"kg"}"#.utf8))
        XCTAssertNil(older.goal)
        let noFlag = try WeightStore.decode(Data(#"{"goal":{"kg":87,"startDay":{"ordinal":20000}}}"#.utf8))
        XCTAssertEqual(noFlag.goal, WeightGoal(kg: 87, startDay: DayKey(ordinal: 20000), startPicked: false))

        state.eraseAll()
        XCTAssertNil(state.goal)
        XCTAssertNil(state.heightCm)
        XCTAssertEqual(state.showsTab, true)
        XCTAssertEqual(state.unit, .lb)
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: 12. Clear and UNDO

    @MainActor
    func testClearGoalActsAtOnceAndUndoBringsTheSameGoalBack() throws {
        let model = AppModel.fromLaunchArguments(["Taken", "-demo", "-screen", "weight-goal"])
        let goal = try XCTUnwrap(model.weight.goal)
        XCTAssertEqual(goal.kg, 87)
        model.clearWeightGoal()
        XCTAssertNil(model.weight.goal)
        XCTAssertFalse(model.weight.isEmpty, "clearing a goal deletes no weigh-in")
        let toast = try XCTUnwrap(model.toast)
        XCTAssertEqual(toast.message, "Goal cleared")
        XCTAssertEqual(toast.undo, .restoreWeightGoal(goal))
        model.undo(toast)
        XCTAssertEqual(model.weight.goal, goal, "the same goal, start included")
        XCTAssertEqual(SheetRoute.weightGoal.id, "weight-goal")

        model.hideWeightTab()
        XCTAssertEqual(model.weight.goal, goal, "hiding the tab keeps the goal")
        model.eraseAll()
        XCTAssertNil(model.weight.goal)
        XCTAssertNil(model.weight.state.heightCm)
    }

    // MARK: 13. The Goal sheet's start

    func testTheSheetKeepsTheStartUnlessTheValueChanges() {
        let trend = points([97.8, 97.0, 96.0, 95.0])
        XCTAssertEqual(WeightGoals.sheetStartDay(existing: nil, typedKg: nil, pickedDay: nil, trend: trend), day(1))
        XCTAssertEqual(WeightGoals.sheetStartDay(existing: nil, typedKg: 87, pickedDay: nil, trend: trend), day(1))
        XCTAssertEqual(WeightGoals.sheetStartDay(existing: nil, typedKg: 96.5, pickedDay: nil, trend: trend), day(4),
                       "Set Goal follows what is typed")
        XCTAssertEqual(WeightGoals.sheetStartDay(existing: nil, typedKg: 87, pickedDay: day(2), trend: trend), day(2),
                       "until the Start row is touched")
        let stored = WeightGoal(kg: 87, startDay: day(3))
        XCTAssertEqual(WeightGoals.sheetStartDay(existing: stored, typedKg: 87, pickedDay: nil, trend: trend), day(3),
                       "Change Goal with the same value keeps the start")
        XCTAssertEqual(WeightGoals.sheetStartDay(existing: stored, typedKg: 86, pickedDay: nil, trend: trend), day(1),
                       "a new value recomputes it")
        let picked = WeightGoal(kg: 87, startDay: day(3), startPicked: true)
        XCTAssertEqual(WeightGoals.sheetStartDay(existing: picked, typedKg: 86, pickedDay: nil, trend: trend), day(3),
                       "unless it was picked by hand")
        XCTAssertNil(WeightGoals.sheetStartDay(existing: stored, typedKg: 87, pickedDay: nil, trend: []))
    }

    // MARK: 14. The demo screens

    @MainActor
    func testTheDemoScreensShowOneTwoAndThreePoints() async throws {
        let goal = AppModel.fromLaunchArguments(["Taken", "-demo", "-screen", "weight-goal"])
        let picture = goal.weightPicture(range: .all)
        XCTAssertEqual(goal.tab, .weight)
        XCTAssertEqual(picture.moments.map(\.id), ["pct5"], "exactly one point")
        XCTAssertEqual(picture.trend.first?.kg, 97.8, "the first weigh-in is exactly 97.8 kg")
        let last = try XCTUnwrap(picture.trend.last?.kg)
        XCTAssertGreaterThanOrEqual(last, 88.05)
        XCTAssertLessThanOrEqual(last, 88.3)
        guard case .toGo(let left)? = picture.readout else { return XCTFail("to go, not \(String(describing: picture.readout))") }
        XCTAssertGreaterThanOrEqual(WeightGoalCopy.roundedUp(left), 1.1)
        XCTAssertLessThanOrEqual(WeightGoalCopy.roundedUp(left), 1.3)
        XCTAssertEqual(slot(picture.readout!, goal: 87), "1.1 kg to 87.0")
        XCTAssertEqual(goal.weight.state.heightCm, 180)

        let moment = AppModel.fromLaunchArguments(["Taken", "-demo", "-screen", "weight-goal-moment"])
        XCTAssertEqual(moment.weightPicture(range: .all).moments.map(\.id), ["pct5", "pct10"])
        XCTAssertEqual(moment.weight.justReached?.id, "pct10")

        let reached = AppModel.fromLaunchArguments(["Taken", "-demo", "-screen", "weight-goal-reached"])
        let held = reached.weightPicture(range: .all)
        XCTAssertEqual(held.moments.map(\.id), ["pct5", "pct10", "goal"])
        XCTAssertEqual(held.readout, .holding)
        XCTAssertEqual(held.trend.last?.kg ?? 0, 86.8, accuracy: 0.1)

        let sheet = AppModel.fromLaunchArguments(["Taken", "-demo", "-screen", "weight-goal-sheet"])
        await sheet.applyLaunchScreen()
        XCTAssertEqual(sheet.sheet, .weightGoal)
        let low = AppModel.fromLaunchArguments(["Taken", "-demo", "-screen", "weight-goal-low"])
        await low.applyLaunchScreen()
        XCTAssertEqual(low.sheet, .weightGoal)
        XCTAssertEqual(low.weight.demoTypedGoal, "55.0")
        XCTAssertTrue(WeightGoals.floorBlocks(goalKg: 55, startKg: 97.8, heightCm: 180))

        let plain = AppModel.fromLaunchArguments(["Taken", "-demo", "-screen", "weight"])
        XCTAssertNil(plain.weight.goal, "every other weight screen has no goal")
    }
}
