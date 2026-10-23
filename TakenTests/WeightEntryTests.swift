import XCTest
@testable import Taken

/// The Weight tab's page, entry first (REDESIGN.md, "Weight tab page: entry first"): what the big number shows, when the
/// range hint shows, which small line wins, where a scroll comes to rest, the digits box's sizing, and the visit line's
/// copy. London clock, the day starting at 04:00.
final class WeightEntryTests: XCTestCase {

    private let enGB = Locale(identifier: "en_GB")
    private let deDE = Locale(identifier: "de_DE")

    private func weighIn(_ kg: Double, _ dayOfMonth: Int, _ hour: Int = 7, _ minute: Int = 0) -> WeighIn {
        let date = at(2026, 10, dayOfMonth, hour, minute)
        return WeighIn(kg: kg, weighedAt: date, utcOffset: london.secondsFromGMT(for: date))
    }

    // MARK: 1. The big number

    func testTheNumberAlwaysShowsAWeighIn() {
        let clock = londonClock()
        let today = DayKey(year: 2026, month: 10, day: 22)
        func figure(_ last: WeighIn?, draft: String = "", focused: Bool = false) -> WeightFigure {
            WeightEntry.figure(last: last, today: today, clock: clock, draft: draft, focused: focused)
        }
        XCTAssertEqual(figure(nil), .empty, "never weighed in")
        XCTAssertEqual(figure(weighIn(88.35, 21)), .ghost(kg: 88.35), "last weigh-in yesterday: grey")
        XCTAssertEqual(figure(weighIn(89.3, 22, 7, 6)), .today(kg: 89.3), "today's: in ink")
        XCTAssertEqual(figure(weighIn(89.3, 22), focused: true), .ghost(kg: 89.3), "typing nothing yet: today's included, grey")
        XCTAssertEqual(figure(weighIn(88.35, 21), focused: true), .ghost(kg: 88.35))
        XCTAssertEqual(figure(nil, focused: true), .empty)
        XCTAssertEqual(figure(weighIn(88.35, 21), draft: "88.1", focused: true), .typing("88.1"))
        XCTAssertEqual(figure(weighIn(88.35, 21), draft: "88.1", focused: false), .ghost(kg: 88.35),
                       "a draft never shows once the keypad is down")
        XCTAssertEqual(figure(weighIn(88.35, 22, 2, 30)), .ghost(kg: 88.35), "02:30 counts for the day before, as a dose does")
        XCTAssertEqual(WeightFigure.typing("8").kind, "typing")
    }

    // MARK: 2. The range hint

    func testTheRangeHintWaitsUntilTheNumberLooksFinished() {
        for draft in ["8", "19", "88.1", "", "350", "20"] {
            XCTAssertFalse(WeightEntry.showsRangeHint(draft, unit: .kg, locale: enGB), "kg \(draft)")
        }
        for draft in ["19.5", "883", "1000", "350.5", "19.", "883."] where draft != "19." {
            XCTAssertTrue(WeightEntry.showsRangeHint(draft, unit: .kg, locale: enGB), "kg \(draft)")
        }
        XCTAssertFalse(WeightEntry.showsRangeHint("19.", unit: .kg, locale: enGB), "a separator with no digit after it")
        for draft in ["40", "195.5"] {
            XCTAssertFalse(WeightEntry.showsRangeHint(draft, unit: .lb, locale: enGB), "lb \(draft)")
        }
        for draft in ["40.5", "800"] {
            XCTAssertTrue(WeightEntry.showsRangeHint(draft, unit: .lb, locale: enGB), "lb \(draft)")
        }
        XCTAssertTrue(WeightEntry.showsRangeHint("19,5", unit: .kg, locale: deDE))
        XCTAssertEqual(WeightCopy.rangeHint(.kg), "Between 20 and 350 kg")
        XCTAssertEqual(WeightCopy.rangeHint(.lb), "Between 44 and 770 lb")
        XCTAssertEqual(WeightCopy.spokenRangeHint(.kg), "Between 20 and 350 kilograms")
    }

    // MARK: 3. The small line

    func testTheSmallLinesPriority() {
        let moment = WeightMoment(kind: .percent(10), day: DayKey(year: 2026, month: 10, day: 22), trendKg: 88.0)
        func line(focused: Bool = false, draft: String = "", goal: Bool = true, saved: Bool = true,
                  reached: WeightMoment? = nil, readout: GoalReadout? = .toGo(1.1)) -> WeightLine {
            WeightEntry.line(focused: focused, draft: draft, unit: .kg, locale: enGB, hasGoal: goal, justSaved: saved,
                             justReached: reached, readout: readout)
        }
        XCTAssertEqual(line(focused: true, draft: "883", reached: moment), .range, "while typing the hint beats everything")
        XCTAssertEqual(line(focused: true, draft: "88.1", reached: moment), .last, "otherwise typing shows the last weigh-in")
        XCTAssertEqual(line(reached: moment), .moment(moment), "the moment beats the closing-in line")
        XCTAssertEqual(line(), .closing(.toGo(1.1)))
        XCTAssertEqual(line(saved: false), .last, "closing needs a save on this visit")
        XCTAssertEqual(line(goal: false), .last, "and a goal")
        XCTAssertEqual(line(readout: .goalOnly), .last, "and a reading other than Goal 87.0")
        XCTAssertEqual(line(readout: nil), .last)
        XCTAssertEqual(line(readout: .holding), .closing(.holding))
        XCTAssertEqual(WeightLine.closing(.holding).kind, "closing")
    }

    // MARK: 4. The fold

    func testTheFoldSnapsOnlyBetweenTheNumberAndTheTrend() {
        XCTAssertEqual(WeightFold.snap(0, fold: 700), 0)
        XCTAssertEqual(WeightFold.snap(-20, fold: 700), -20, "a bounce at the top is left alone")
        XCTAssertEqual(WeightFold.snap(700, fold: 700), 700)
        XCTAssertEqual(WeightFold.snap(900, fold: 700), 900, "below the fold, scrolling is free")
        XCTAssertEqual(WeightFold.snap(200, fold: 700), 0, "nearer the number")
        XCTAssertEqual(WeightFold.snap(349, fold: 700), 0)
        XCTAssertEqual(WeightFold.snap(350, fold: 700), 700, "half way goes on to the trend")
        XCTAssertEqual(WeightFold.snap(600, fold: 700), 700)
        XCTAssertEqual(WeightFold.snap(300, fold: 0), 300, "no fold measured yet")
    }

    // MARK: 5. Sizing

    func testTheBoxKeepsTheLongerOfTheGreyValueAndTheDraft() {
        XCTAssertEqual(WeightEntry.sizing(ghost: "88.35", draft: ""), "88.35")
        XCTAssertEqual(WeightEntry.sizing(ghost: "88.35", draft: "88.1"), "88.35", "nothing re-centres while typing")
        XCTAssertEqual(WeightEntry.sizing(ghost: "88.35", draft: "100.55"), "100.55")
        XCTAssertEqual(WeightEntry.sizing(ghost: "", draft: "88"), "88")
    }

    // MARK: 6. The visit line

    func testTheVisitLinePutsTrendInFront() {
        func visit(_ readout: GoalReadout, unit: WeightUnit = .kg, goal: Double = 87) -> String? {
            WeightGoalCopy.visit(readout, goalKg: goal, unit: unit, locale: enGB).map(WeightGoalCopy.text)
        }
        XCTAssertEqual(visit(.closer(4.2)), "Trend 4.2 kg closer to 87.0")
        XCTAssertEqual(visit(.toGo(1.1)), "Trend 1.1 kg to 87.0")
        XCTAssertEqual(visit(.holding), "Trend holding near 87.0")
        XCTAssertEqual(visit(.from(0.9)), "Trend 0.9 kg from 87.0")
        XCTAssertNil(visit(.goalOnly))
        // 191.8 lb is 87.0 kg; 2.4 lb to go.
        XCTAssertEqual(visit(.toGo(2.35 * 0.45359237), unit: .lb, goal: 191.8 * 0.45359237), "Trend 2.4 lb to 191.8")
        XCTAssertEqual(WeightGoalCopy.spokenVisit(.closer(4.2), goalKg: 87, unit: .kg, locale: enGB),
                       "Trend 4.2 kilograms closer to your goal, 87.0")
        XCTAssertEqual(WeightGoalCopy.spokenVisit(.toGo(1.1), goalKg: 87, unit: .kg, locale: enGB),
                       "Trend 1.1 kilograms to your goal, 87.0")
        XCTAssertEqual(WeightGoalCopy.spokenVisit(.holding, goalKg: 87, unit: .kg, locale: enGB),
                       "Trend holding near your goal, 87.0")
        XCTAssertEqual(WeightGoalCopy.spokenVisit(.from(0.9), goalKg: 87, unit: .kg, locale: enGB),
                       "Trend 0.9 kilograms from your goal, 87.0")
        XCTAssertNil(WeightGoalCopy.spokenVisit(.goalOnly, goalKg: 87, unit: .kg, locale: enGB))
        for text in WeightCopy.all {
            XCTAssertNil(text.range(of: "goal", options: .caseInsensitive), "every goal string lives in WeightGoalCopy: \(text)")
        }
        XCTAssertTrue(WeightCopy.all.contains("Weigh in"))
        XCTAssertTrue(WeightCopy.all.contains("Your trend starts here."))
        XCTAssertTrue(WeightCopy.all.contains("Show trend"))
        XCTAssertTrue(WeightGoalCopy.all.contains("Trend 1.1 kg to 87.0"))
    }
}
