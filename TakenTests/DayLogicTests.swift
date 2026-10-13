import XCTest
@testable import Taken

final class DayLogicTests: XCTestCase {

    // MARK: Day keys

    func testDayKeyRoundTripAndWeekday() {
        let key = DayKey(year: 2026, month: 10, day: 12)
        XCTAssertEqual(key.ymd.year, 2026)
        XCTAssertEqual(key.ymd.month, 10)
        XCTAssertEqual(key.ymd.day, 12)
        XCTAssertEqual(key.mondayIndex, 0, "12 Oct 2026 is a Monday")
        XCTAssertEqual(key.weekday, 2, "Calendar weekday for Monday is 2")
        XCTAssertEqual(key.adding(6).weekday, 1, "Sunday is 1")
        XCTAssertEqual(DayKey(year: 2024, month: 3, day: 1).adding(-1).ymd.day, 29, "leap day")
        XCTAssertEqual(DayKey(year: 1970, month: 1, day: 1).ordinal, 0)
    }

    // MARK: Rollover

    func testDayRolloverAtFourAM() {
        let c = londonClock(4)
        let monday = DayKey(year: 2026, month: 10, day: 12)
        XCTAssertEqual(c.day(for: at(2026, 10, 13, 1, 0)), monday, "01:00 Tuesday still belongs to Monday")
        XCTAssertEqual(c.day(for: at(2026, 10, 13, 3, 59)), monday)
        XCTAssertEqual(c.day(for: at(2026, 10, 13, 4, 0)), monday.adding(1), "04:00 starts Tuesday")
        XCTAssertEqual(c.day(for: at(2026, 10, 12, 23, 30)), monday)
    }

    func testMidnightRolloverWhenDayStartsAtZero() {
        let c = londonClock(0)
        XCTAssertEqual(c.day(for: at(2026, 10, 13, 0, 30)), DayKey(year: 2026, month: 10, day: 13))
    }

    func testRolloverAcrossDaylightSavingStart() {
        // UK clocks go forward at 01:00 GMT on 29 Mar 2026.
        let c = londonClock(4)
        let sunday = DayKey(year: 2026, month: 3, day: 29)
        XCTAssertEqual(c.day(for: at(2026, 3, 29, 3, 30)), sunday.adding(-1))
        XCTAssertEqual(c.day(for: at(2026, 3, 29, 4, 30)), sunday, "04:30 BST is after the rollover")
        let start = c.start(of: sunday)
        XCTAssertEqual(c.hourMinute(of: start).hour, 4)
        XCTAssertEqual(c.end(of: sunday), c.start(of: sunday.adding(1)))
    }

    func testDateOnDayMapsEarlyHoursToNextCalendarDate() {
        let c = londonClock(4)
        let monday = DayKey(year: 2026, month: 10, day: 12)
        let late = c.date(on: monday, hour: 1, minute: 15)
        XCTAssertEqual(late, at(2026, 10, 13, 1, 15))
        XCTAssertEqual(c.day(for: late), monday)
        XCTAssertEqual(c.date(on: monday, hour: 9, minute: 0), at(2026, 10, 12, 9, 0))
    }

    // MARK: Frequencies

    func testAlternateDaysDueLogic() {
        let c = londonClock()
        let created = at(2026, 10, 1, 8)
        let zinc = makeItem("Zinc", "ZNC", .alternateDays, created: created)
        let monday = DayKey(year: 2026, month: 10, day: 12)

        var state = StackState(items: [zinc])
        var engine = StackEngine(state: state, clock: c)
        XCTAssertTrue(engine.isDue(zinc, on: monday), "never taken: due")

        state.logDose(itemId: zinc.id, at: at(2026, 10, 11, 8), timeZone: london)
        engine = StackEngine(state: state, clock: c)
        XCTAssertFalse(engine.isDue(zinc, on: monday), "taken yesterday: not due")
        XCTAssertEqual(engine.nextDueDay(for: zinc, after: monday), monday.adding(1), "next due tomorrow")
        XCTAssertEqual(Fmt.next(engine.nextDueDay(for: zinc, after: monday), today: monday), "Next: tomorrow")
        XCTAssertEqual(Fmt.next(monday.adding(3), today: monday), "Next: Thursday", "the Not today group names the day")
        XCTAssertEqual(Fmt.next(monday.adding(9), today: monday), "Next: 21 Oct")
        XCTAssertTrue(engine.isDue(zinc, on: monday.adding(1)), "two days after the last dose: due")

        state = StackState(items: [zinc])
        state.logDose(itemId: zinc.id, at: at(2026, 10, 10, 8), timeZone: london)
        engine = StackEngine(state: state, clock: c)
        XCTAssertTrue(engine.isDue(zinc, on: monday), "last dose two days ago: due")

        let summary = engine.todaySummary(now: at(2026, 10, 12, 21))
        XCTAssertEqual(summary.due.count, 1)
    }

    func testAlternateDayItemTakenYesterdayIsInNotDueGroup() {
        let c = londonClock()
        let created = at(2026, 10, 1, 8)
        let vd3 = makeItem("Vitamin D3", "VD3", created: created, sortIndex: 0)
        let zinc = makeItem("Zinc", "ZNC", .alternateDays, created: created, sortIndex: 1)
        var state = StackState(items: [vd3, zinc])
        state.logDose(itemId: zinc.id, at: at(2026, 10, 11, 8), timeZone: london)
        let today = StackEngine(state: state, clock: c).todaySummary(now: at(2026, 10, 12, 10))
        XCTAssertEqual(today.due.map(\.item.id), [vd3.id])
        XCTAssertEqual(today.notDue.map(\.item.id), [zinc.id])
        XCTAssertEqual(today.dueDoses, 1)
    }

    func testWeekdayFrequency() {
        let c = londonClock()
        let mwf = makeItem("Minoxidil", "MIN", .weekdays([2, 4, 6]), created: at(2026, 10, 1, 8))
        let engine = StackEngine(state: StackState(items: [mwf]), clock: c)
        let monday = DayKey(year: 2026, month: 10, day: 12)
        XCTAssertTrue(engine.isDue(mwf, on: monday))
        XCTAssertFalse(engine.isDue(mwf, on: monday.adding(1)))
        XCTAssertTrue(engine.isDue(mwf, on: monday.adding(2)))
        XCTAssertFalse(engine.isDue(mwf, on: monday.adding(6)), "Sunday")
        XCTAssertEqual(engine.nextDueDay(for: mwf, after: monday.adding(4)), monday.adding(7), "Friday to next Monday")
        XCTAssertEqual(Fmt.frequency(.weekdays([2, 4, 6])), "Mon Wed Fri")
        XCTAssertEqual(Fmt.frequency(.weekdays([2, 3, 4, 5, 6])), "Weekdays")
        XCTAssertEqual(Fmt.frequency(.alternateDays), "Every other day")
        XCTAssertEqual(Fmt.frequency(.daily(times: 2)), "2x daily")
    }

    func testMultiDoseCompletion() {
        let c = londonClock()
        let fish = makeItem("Fish Oil", "FSH", .daily(times: 2), created: at(2026, 10, 1, 8))
        var state = StackState(items: [fish])
        let now = at(2026, 10, 12, 8)

        var row = StackEngine(state: state, clock: c).todaySummary(now: now).items[0]
        XCTAssertEqual(row.pendingCount, 2)
        XCTAssertFalse(row.isDone)

        state.logDose(itemId: fish.id, at: now, timeZone: london)
        row = StackEngine(state: state, clock: c).todaySummary(now: now).items[0]
        XCTAssertEqual(row.pendingCount, 1)
        XCTAssertFalse(row.isDone)

        state.logDose(itemId: fish.id, at: at(2026, 10, 12, 19), timeZone: london)
        let summary = StackEngine(state: state, clock: c).todaySummary(now: at(2026, 10, 12, 20))
        XCTAssertTrue(summary.items[0].isDone)
        XCTAssertTrue(summary.allTaken)
        XCTAssertEqual(summary.takenDueDoses, 2)
    }

    // MARK: Take all

    func testTakeAllOnlyTouchesPendingDueDoses() {
        let c = londonClock()
        let created = at(2026, 10, 1, 8)
        let vd3 = makeItem("Vitamin D3", "VD3", created: created, sortIndex: 0)
        let fin = makeItem("Finasteride", "FIN", created: created, sortIndex: 1)
        let fish = makeItem("Fish Oil", "FSH", .daily(times: 2), created: created, sortIndex: 2)
        let zinc = makeItem("Zinc", "ZNC", .alternateDays, created: created, sortIndex: 3)
        var state = StackState(items: [vd3, fin, fish, zinc])
        state.logDose(itemId: vd3.id, at: at(2026, 10, 12, 7, 42), timeZone: london)
        state.logDose(itemId: zinc.id, at: at(2026, 10, 11, 8), timeZone: london)

        let now = at(2026, 10, 12, 21)
        let logged = state.takeAllPending(now: now, clock: c)
        XCTAssertEqual(Set(logged.map(\.itemId)), [fin.id, fish.id], "one dose each for pending items only")
        XCTAssertTrue(logged.allSatisfy { $0.takenAt == now })
        XCTAssertEqual(state.doses.filter { $0.itemId == vd3.id }.count, 1, "already taken: untouched")
        XCTAssertEqual(state.doses.filter { $0.itemId == zinc.id }.count, 1, "not due: untouched")

        XCTAssertTrue(state.takeAllPending(now: now, clock: c).isEmpty,
                      "a second TAKE ALL at once never logs the 2x item's next dose")
        XCTAssertTrue(state.takeAllPending(now: now.addingTimeInterval(59 * 60), clock: c).isEmpty,
                      "nor does one within the hour")
        let later = now.addingTimeInterval(61 * 60)
        let again = state.takeAllPending(now: later, clock: c)
        XCTAssertEqual(again.map(\.itemId), [fish.id], "an hour on, the second dose of the 2x item")
        XCTAssertTrue(state.takeAllPending(now: later, clock: c).isEmpty, "nothing left")
        XCTAssertTrue(StackEngine(state: state, clock: c).todaySummary(now: later).allTaken)
    }

    func testRepeatedTakeAllNeverStacksDosesOfMultiDoseItems() {
        // The widget, the control and Siri can all fire TAKE ALL twice in a row.
        let c = londonClock()
        let created = at(2026, 10, 1, 8)
        let met = makeItem("Metformin", "MET", .daily(times: 2), created: created, sortIndex: 0)
        let fish = makeItem("Fish Oil", "FSH", .daily(times: 3), created: created, sortIndex: 1)
        let vd3 = makeItem("Vitamin D3", "VD3", created: created, sortIndex: 2)
        var state = StackState(items: [met, fish, vd3])
        let morning = at(2026, 10, 12, 8)
        XCTAssertEqual(state.takeAllPending(now: morning, clock: c).count, 3)
        XCTAssertTrue(state.takeAllPending(now: morning.addingTimeInterval(5), clock: c).isEmpty)
        let engine = StackEngine(state: state, clock: c)
        let today = engine.todaySummary(now: morning.addingTimeInterval(5))
        XCTAssertEqual(today.pendingItems.map(\.item.id), [met.id, fish.id], "their next doses stay pending")
        XCTAssertTrue(engine.quickLogRows(today, now: morning.addingTimeInterval(5)).isEmpty)
        XCTAssertEqual(engine.quickLogResumes(today.pendingItems[0], now: morning.addingTimeInterval(5)),
                       morning.addingTimeInterval(StackEngine.repeatGuard))

        // The row in the app is a deliberate tap: never held back.
        XCTAssertNotNil(state.logDose(itemId: met.id, at: morning.addingTimeInterval(10), timeZone: london))
    }

    func testWidgetLogNeverDoubleLogs() {
        let c = londonClock()
        let vd3 = makeItem("Vitamin D3", "VD3", created: at(2026, 10, 1, 8))
        var state = StackState(items: [vd3])
        let now = at(2026, 10, 12, 9)
        XCTAssertNotNil(state.logNextDoseIfPending(itemId: vd3.id, now: now, clock: c))
        XCTAssertNil(state.logNextDoseIfPending(itemId: vd3.id, now: now, clock: c))
        XCTAssertEqual(state.doses.count, 1)
    }

    func testWidgetRowNeverLogsTheNextDoseWithinTheHour() {
        let c = londonClock()
        let fish = makeItem("Fish Oil", "FSH", .daily(times: 2), created: at(2026, 10, 1, 8))
        var state = StackState(items: [fish])
        let morning = at(2026, 10, 12, 8)
        XCTAssertNotNil(state.logNextDoseIfPending(itemId: fish.id, now: morning, clock: c))
        XCTAssertNil(state.logNextDoseIfPending(itemId: fish.id, now: morning.addingTimeInterval(20), clock: c),
                     "a second tap seconds later")
        XCTAssertNil(state.logNextDoseIfPending(itemId: fish.id, now: morning.addingTimeInterval(59 * 60), clock: c))
        XCTAssertNotNil(state.logNextDoseIfPending(itemId: fish.id, now: at(2026, 10, 12, 19), clock: c), "the evening dose")
        XCTAssertNil(state.logNextDoseIfPending(itemId: fish.id, now: at(2026, 10, 12, 21), clock: c), "done for the day")
        XCTAssertEqual(state.doses.count, 2)
    }

    func testWidgetSnapshotHoldsTakeAllBackUntilTheHourIsUp() {
        let fish = makeItem("Fish Oil", "FSH", .daily(times: 2), created: at(2026, 10, 1, 8), sortIndex: 0)
        let vd3 = makeItem("Vitamin D3", "VD3", created: at(2026, 10, 1, 8), sortIndex: 1)
        var state = StackState(items: [fish, vd3])
        let morning = at(2026, 10, 12, 8)
        state.logDose(itemId: fish.id, at: morning, timeZone: london)
        state.logDose(itemId: vd3.id, at: morning, timeZone: london)

        let soon = WidgetSnapshot(state: state, now: morning.addingTimeInterval(600), timeZone: london)
        XCTAssertEqual(soon.pendingItems, 1)
        XCTAssertEqual(soon.readyItems, 0, "no TAKE ALL while the only pending item was logged ten minutes ago")
        XCTAssertEqual(soon.rows.first?.id, fish.id)
        XCTAssertEqual(soon.rows.first?.ready, false)
        XCTAssertEqual(soon.nextReady, morning.addingTimeInterval(StackEngine.repeatGuard))

        let evening = WidgetSnapshot(state: state, now: at(2026, 10, 12, 19), timeZone: london)
        XCTAssertEqual(evening.readyItems, 1)
        XCTAssertEqual(evening.rows.first?.ready, true)
        XCTAssertNil(evening.nextReady)
    }

    func testTakeAllExplainsAHeldBackItem() {
        let fish = makeItem("Fish Oil", "FSH", .daily(times: 2), created: at(2026, 10, 1, 8))
        var state = StackState(items: [fish])
        let morning = at(2026, 10, 12, 8)
        state.logDose(itemId: fish.id, at: morning, timeZone: london)
        let answer = SiriAnswers.nothingPending(state: state, now: morning.addingTimeInterval(60), timeZone: london)
        XCTAssertTrue(answer.hasPrefix("Nothing logged. Fish Oil was logged in the last hour."), answer)
    }

    // MARK: Undo and backfill

    func testUndoRemovesOnlyThatDose() {
        let c = londonClock()
        let vd3 = makeItem("Vitamin D3", "VD3", created: at(2026, 10, 1, 8))
        var state = StackState(items: [vd3])
        let yesterday = state.logDose(itemId: vd3.id, at: at(2026, 10, 11, 8), timeZone: london)!
        let today = state.logDose(itemId: vd3.id, at: at(2026, 10, 12, 8), timeZone: london)!
        state.removeDoses([today.id])
        XCTAssertEqual(state.doses.map(\.id), [yesterday.id])

        let again = state.logDose(itemId: vd3.id, at: at(2026, 10, 12, 9), timeZone: london)!
        let removed = state.undoLastDose(itemId: vd3.id, on: DayKey(year: 2026, month: 10, day: 12), clock: c)
        XCTAssertEqual(removed?.id, again.id)
        XCTAssertEqual(state.doses.map(\.id), [yesterday.id], "undo never reaches into another day")
        XCTAssertNil(state.undoLastDose(itemId: vd3.id, on: DayKey(year: 2026, month: 10, day: 12), clock: c))
    }

    func testBackfillOnPastDay() {
        let c = londonClock()
        let vd3 = makeItem("Vitamin D3", "VD3", created: at(2026, 10, 1, 8))
        var state = StackState(items: [vd3])
        let saturday = DayKey(year: 2026, month: 10, day: 10)
        XCTAssertEqual(StackEngine(state: state, clock: c).summary(for: saturday).status, .missed)

        state.logDose(itemId: vd3.id, at: c.date(on: saturday, hour: 9, minute: 0), timeZone: london)
        let engine = StackEngine(state: state, clock: c)
        XCTAssertEqual(engine.summary(for: saturday).status, .complete)
        XCTAssertEqual(engine.doses(of: vd3.id, on: saturday).first?.takenAt, at(2026, 10, 10, 9, 0))
    }

    func testBackfillBeforeItemWasAddedExtendsHistory() {
        let c = londonClock()
        let vd3 = makeItem("Vitamin D3", "VD3", created: at(2026, 10, 12, 8))
        var state = StackState(items: [vd3])
        let sunday = DayKey(year: 2026, month: 10, day: 11)
        XCTAssertEqual(StackEngine(state: state, clock: c).summary(for: sunday).status, .nothingDue)
        state.logDose(itemId: vd3.id, at: c.date(on: sunday, hour: 9, minute: 0), timeZone: london)
        XCTAssertEqual(StackEngine(state: state, clock: c).summary(for: sunday).status, .complete)
    }

    func testSetDoseTime() {
        let vd3 = makeItem("Vitamin D3", "VD3", created: at(2026, 10, 1, 8))
        var state = StackState(items: [vd3])
        let dose = state.logDose(itemId: vd3.id, at: at(2026, 10, 12, 21), timeZone: london)!
        state.setDoseTime(doseId: dose.id, to: at(2026, 10, 12, 7), timeZone: london)
        XCTAssertEqual(state.doses.first?.takenAt, at(2026, 10, 12, 7))
    }

    func testUndoPutsADoseBackExactlyAsItWas() {
        let c = londonClock()
        let vd3 = makeItem("Vitamin D3", "VD3", created: at(2026, 10, 1, 8))
        var state = StackState(items: [vd3])
        let monday = DayKey(year: 2026, month: 10, day: 12)
        let dose = state.logDose(itemId: vd3.id, at: at(2026, 10, 12, 7, 42), timeZone: london)!

        // Undo last dose by mistake, then UNDO on its toast.
        let removed = state.undoLastDose(itemId: vd3.id, on: monday, clock: c)!
        XCTAssertTrue(state.doses.isEmpty)
        state.restore(removed)
        XCTAssertEqual(state.doses, [dose], "same id, same 07:42")
        state.restore(removed)
        XCTAssertEqual(state.doses.count, 1, "restoring twice never duplicates")

        // Set time, then UNDO on its toast.
        state.setDoseTime(doseId: dose.id, to: at(2026, 10, 12, 7, 0), timeZone: london)
        XCTAssertEqual(state.doses.first?.takenAt, at(2026, 10, 12, 7, 0))
        state.restore(dose)
        XCTAssertEqual(state.doses, [dose], "the replaced time comes back")

        state.deleteItem(id: vd3.id)
        state.restore(dose)
        XCTAssertTrue(state.doses.isEmpty, "never restores a dose of a deleted item")
    }

    func testDayStatusWordsForTodayAndEarlierDays() {
        let c = londonClock()
        let created = at(2026, 10, 1, 8)
        let vd3 = makeItem("Vitamin D3", "VD3", created: created, sortIndex: 0)
        let mag = makeItem("Magnesium", "MAG", created: created, sortIndex: 1)
        var state = StackState(items: [vd3, mag])
        state.logDose(itemId: vd3.id, at: at(2026, 10, 11, 8), timeZone: london)
        state.logDose(itemId: vd3.id, at: at(2026, 10, 12, 8), timeZone: london)
        let engine = StackEngine(state: state, clock: c)
        let today = engine.sheetSummary(for: DayKey(year: 2026, month: 10, day: 12))
        let sunday = engine.sheetSummary(for: DayKey(year: 2026, month: 10, day: 11))

        XCTAssertEqual(Fmt.daySheetStatus(today, isToday: true), "1 of 2 taken \u{00B7} 1 pending")
        XCTAssertEqual(Fmt.daySheetStatus(sunday, isToday: false), "1 of 2 taken \u{00B7} 1 missed")
        XCTAssertEqual(Fmt.dayItemStatus(today.items[1], isToday: true), "Daily \u{00B7} pending")
        XCTAssertEqual(Fmt.dayItemStatus(sunday.items[1], isToday: false), "Daily \u{00B7} missed")
        XCTAssertEqual(Fmt.dayItemStatus(today.items[0], isToday: true), "Daily \u{00B7} taken")
    }

    func testTodaysProgressLineCountsDosesAsTheWidgetsDo() {
        let c = londonClock()
        let created = at(2026, 10, 1, 8)
        let vd3 = makeItem("Vitamin D3", "VD3", created: created, sortIndex: 0)
        let fish = makeItem("Fish Oil", "FSH", .daily(times: 2), created: created, sortIndex: 1)
        let zinc = makeItem("Zinc", "ZNC", .alternateDays, created: created, sortIndex: 2)
        var state = StackState(items: [vd3, fish, zinc])
        state.logDose(itemId: zinc.id, at: at(2026, 10, 11, 8), timeZone: london)
        state.logDose(itemId: vd3.id, at: at(2026, 10, 12, 8), timeZone: london)
        state.logDose(itemId: fish.id, at: at(2026, 10, 12, 8), timeZone: london)
        let now = at(2026, 10, 12, 21)
        let partly = StackEngine(state: state, clock: c).todaySummary(now: now)
        XCTAssertEqual(Fmt.progress(partly), "2 of 3 taken", "doses: Fish Oil is 1 of 2, the not-due item is not counted")
        XCTAssertEqual(WidgetSnapshot(state: state, now: now, timeZone: london).takenDue, 2, "the widget says 2/3 too")
        state.logDose(itemId: fish.id, at: at(2026, 10, 12, 19), timeZone: london)
        XCTAssertEqual(Fmt.progress(StackEngine(state: state, clock: c).todaySummary(now: now)), "All taken")
        var onlyZinc = StackState(items: [zinc])
        onlyZinc.logDose(itemId: zinc.id, at: at(2026, 10, 11, 8), timeZone: london)
        XCTAssertNil(Fmt.progress(StackEngine(state: onlyZinc, clock: c).todaySummary(now: now)), "nothing due today")
    }

    // MARK: Stats

    func testStreakSkipsNothingDueDaysAndIgnoresUnfinishedToday() {
        let c = londonClock()
        let created = at(2026, 10, 1, 8)
        let mwf = makeItem("Minoxidil", "MIN", .weekdays([2, 4, 6]), created: created)
        var state = StackState(items: [mwf])
        // Mon 5, Wed 7, Fri 9 Oct taken; Mon 12 is today and not yet taken.
        for day in [5, 7, 9] { state.logDose(itemId: mwf.id, at: at(2026, 10, day, 8), timeZone: london) }
        var engine = StackEngine(state: state, clock: c)
        let monday = DayKey(year: 2026, month: 10, day: 12)
        XCTAssertEqual(engine.streak(today: monday), 3, "weekends and off days do not break it; today pending does not either")

        state.logDose(itemId: mwf.id, at: at(2026, 10, 12, 8), timeZone: london)
        engine = StackEngine(state: state, clock: c)
        XCTAssertEqual(engine.streak(today: monday), 4, "today counts once complete")
    }

    func testStreakBreaksOnMissedDay() {
        let c = londonClock()
        let vd3 = makeItem("Vitamin D3", "VD3", created: at(2026, 10, 1, 8))
        var state = StackState(items: [vd3])
        for day in [8, 9, 11] { state.logDose(itemId: vd3.id, at: at(2026, 10, day, 8), timeZone: london) }
        let engine = StackEngine(state: state, clock: c)
        XCTAssertEqual(engine.streak(today: DayKey(year: 2026, month: 10, day: 12)), 1, "10 Oct was missed")
    }

    func testThirtyDayAdherence() {
        let c = londonClock()
        let vd3 = makeItem("Vitamin D3", "VD3", created: at(2026, 9, 1, 8))
        var state = StackState(items: [vd3])
        let today = DayKey(year: 2026, month: 10, day: 12)
        for offset in 1...29 where offset != 5 && offset != 9 {
            state.logDose(itemId: vd3.id, at: c.date(on: today.adding(-offset), hour: 8, minute: 0), timeZone: london)
        }
        let engine = StackEngine(state: state, clock: c)
        let pending = engine.adherence(today: today)
        XCTAssertEqual(pending.due, 29, "today's untaken dose is not counted yet")
        XCTAssertEqual(pending.taken, 27)
        XCTAssertEqual(pending.percent, 93)

        state.logDose(itemId: vd3.id, at: c.date(on: today, hour: 8, minute: 0), timeZone: london)
        let done = StackEngine(state: state, clock: c).adherence(today: today)
        XCTAssertEqual(done.due, 30)
        XCTAssertEqual(done.taken, 28)
        XCTAssertEqual(done.percent, 93)
        XCTAssertNil(Adherence(taken: 0, due: 0).percent)
        XCTAssertEqual(Adherence(taken: 199, due: 200).percent, 99, "never rounds up to 100")
    }

    func testHistoryGridShape() {
        let c = londonClock()
        let vd3 = makeItem("Vitamin D3", "VD3", created: at(2026, 9, 1, 8))
        var state = StackState(items: [vd3])
        state.logDose(itemId: vd3.id, at: at(2026, 10, 11, 8), timeZone: london)
        let wednesday = DayKey(year: 2026, month: 10, day: 14)
        let grid = StackEngine(state: state, clock: c).history(today: wednesday)
        XCTAssertEqual(grid.count, 5)
        XCTAssertTrue(grid.allSatisfy { $0.count == 7 })
        XCTAssertEqual(grid[4][0].day, DayKey(year: 2026, month: 10, day: 12), "last row starts on this Monday")
        XCTAssertTrue(grid[4][2].isToday)
        XCTAssertEqual(grid[4][3].status, .future)
        XCTAssertEqual(grid[3][6].status, .complete, "Sunday 11 Oct was taken")
        XCTAssertEqual(grid[3][5].status, .missed)
    }

    func testArchivedItemKeepsHistoryButLeavesToday() {
        let c = londonClock()
        let vd3 = makeItem("Vitamin D3", "VD3", created: at(2026, 10, 1, 8), sortIndex: 0)
        let mag = makeItem("Magnesium", "MAG", created: at(2026, 10, 1, 8), sortIndex: 1)
        var state = StackState(items: [vd3, mag])
        state.logDose(itemId: mag.id, at: at(2026, 10, 5, 21), timeZone: london)
        state.setArchived(id: mag.id, archived: true, now: at(2026, 10, 10, 12))
        let engine = StackEngine(state: state, clock: c)
        XCTAssertEqual(engine.todaySummary(now: at(2026, 10, 12, 9)).items.map(\.item.id), [vd3.id])
        XCTAssertEqual(engine.summary(for: DayKey(year: 2026, month: 10, day: 5)).items.count, 2)
    }

    func testFrequencyChangeNeverRewritesPastDays() {
        let c = londonClock()
        let fin = makeItem("Finasteride", "FIN", .alternateDays, created: at(2026, 9, 1, 8))
        var state = StackState(items: [fin])
        let monday = DayKey(year: 2026, month: 10, day: 12)
        // Every other day for three weeks, the last one yesterday.
        for offset in stride(from: 21, through: 1, by: -2) {
            state.logDose(itemId: fin.id, at: c.date(on: monday.adding(-offset), hour: 8, minute: 0), timeZone: london)
        }
        let before = StackEngine(state: state, clock: c)
        let offDay = monday.adding(-2)
        XCTAssertEqual(before.summary(for: offDay).status, .nothingDue)

        state.updateItem(id: fin.id, name: "Finasteride", code: "FIN", frequency: .onceDaily, now: at(2026, 10, 12, 9))
        let after = StackEngine(state: state, clock: c)
        XCTAssertEqual(after.summary(for: offDay).status, .nothingDue, "an off day stays off")
        XCTAssertEqual(after.history(today: monday).flatMap { $0 }.filter { $0.day < monday }.map(\.status),
                       before.history(today: monday).flatMap { $0 }.filter { $0.day < monday }.map(\.status),
                       "every earlier day in the grid is unchanged")
        XCTAssertEqual(after.streak(today: monday), before.streak(today: monday))
        XCTAssertEqual(after.adherence(today: monday), before.adherence(today: monday))
        let today = after.todaySummary(now: at(2026, 10, 12, 10)).items[0]
        XCTAssertTrue(today.isDue, "the new frequency applies from today")
        XCTAssertEqual(today.frequency, .onceDaily)
        XCTAssertEqual(after.summary(for: offDay).items[0].frequency, .alternateDays)

        // 1x to 2x: earlier days stay complete at 1/1.
        let fish = makeItem("Fish Oil", "FSH", created: at(2026, 9, 1, 8))
        var oil = StackState(items: [fish])
        for offset in 1...5 {
            oil.logDose(itemId: fish.id, at: c.date(on: monday.adding(-offset), hour: 8, minute: 0), timeZone: london)
        }
        oil.updateItem(id: fish.id, name: "Fish Oil", code: "FSH", frequency: .daily(times: 2), now: at(2026, 10, 12, 9))
        oil.updateItem(id: fish.id, name: "Fish Oil", code: "FSH", frequency: .daily(times: 3), now: at(2026, 10, 12, 9, 5))
        let oilEngine = StackEngine(state: oil, clock: c)
        XCTAssertEqual(oilEngine.summary(for: monday.adding(-1)).status, .complete)
        XCTAssertEqual(oilEngine.todaySummary(now: at(2026, 10, 12, 10)).dueDoses, 3, "two changes on one day: the last wins today")
        XCTAssertEqual(oilEngine.summary(for: monday.adding(-1)).dueDoses, 1, "and the first frequency still holds before it")
    }

    func testUnarchiveKeepsTheArchivedDaysOutOfHistory() {
        let c = londonClock()
        let vd3 = makeItem("Vitamin D3", "VD3", created: at(2026, 9, 1, 8), sortIndex: 0)
        let mag = makeItem("Magnesium", "MAG", created: at(2026, 9, 1, 8), sortIndex: 1)
        var state = StackState(items: [vd3, mag])
        for day in 1...11 { state.logDose(itemId: vd3.id, at: at(2026, 10, day, 8), timeZone: london) }
        for day in 1...4 { state.logDose(itemId: mag.id, at: at(2026, 10, day, 21), timeZone: london) }
        state.setArchived(id: mag.id, archived: true, now: at(2026, 10, 5, 7))
        let monday = DayKey(year: 2026, month: 10, day: 12)
        let before = StackEngine(state: state, clock: c)

        state.setArchived(id: mag.id, archived: false, now: at(2026, 10, 12, 9))
        let after = StackEngine(state: state, clock: c)
        let thursday = DayKey(year: 2026, month: 10, day: 8)
        XCTAssertEqual(after.summary(for: thursday).status, .complete, "an archived day is not a missed day")
        XCTAssertEqual(after.history(today: monday).flatMap { $0 }.map(\.status),
                       before.history(today: monday).flatMap { $0 }.map(\.status))
        XCTAssertEqual(after.streak(today: monday), before.streak(today: monday))
        XCTAssertEqual(after.adherence(today: monday), before.adherence(today: monday))
        XCTAssertTrue(after.todaySummary(now: at(2026, 10, 12, 10)).pendingItems.contains { $0.item.id == mag.id },
                      "back in today's stack")

        // The day sheet still offers the archived days, and a dose logged there counts.
        let row = after.sheetSummary(for: thursday).items.first { $0.item.id == mag.id }
        XCTAssertEqual(row.map { Fmt.dayItemStatus($0, isToday: false) }, "Daily \u{00B7} archived")
        state.logDose(itemId: mag.id, at: at(2026, 10, 8, 21), timeZone: london)
        XCTAssertEqual(StackEngine(state: state, clock: c).summary(for: thursday).dueDoses, 2)
    }

    func testDosesKeepTheirDayAfterATimeZoneChange() {
        let newYork = TimeZone(identifier: "America/New_York")!
        let vd3 = makeItem("Vitamin D3", "VD3", created: at(2026, 10, 1, 8))
        let monday = DayKey(year: 2026, month: 10, day: 12)

        // 07:42 BST on Monday in London is 02:42 EDT, before New York's 04:00 day start.
        var west = StackState(items: [vd3])
        west.logDose(itemId: vd3.id, at: at(2026, 10, 12, 7, 42), timeZone: london)
        let inNewYork = StackEngine(state: west, clock: londonClock(4, newYork))
        let today = inNewYork.todaySummary(now: at(2026, 10, 12, 13, 0, newYork))
        XCTAssertEqual(today.day, monday)
        XCTAssertTrue(today.allTaken, "this morning's dose still belongs to Monday")
        XCTAssertEqual(inNewYork.summary(for: monday.adding(-1)).status, .missed, "and not to Sunday")
        XCTAssertNotNil(west.undoLastDose(itemId: vd3.id, on: monday, clock: londonClock(4, newYork)))

        // 23:30 EDT on Monday is 04:30 BST on Tuesday: it stays Monday's, and Tuesday is still to take.
        var east = StackState(items: [vd3])
        east.logDose(itemId: vd3.id, at: at(2026, 10, 12, 23, 30, newYork), timeZone: newYork)
        let inLondon = StackEngine(state: east, clock: londonClock())
        XCTAssertEqual(inLondon.summary(for: monday).status, .complete)
        let tuesday = inLondon.todaySummary(now: at(2026, 10, 13, 10))
        XCTAssertEqual(tuesday.day, monday.adding(1))
        XCTAssertEqual(tuesday.pendingItems.count, 1)

        // A dose saved before offsets were recorded reads in the current zone, as it always did.
        var legacy = StackState(items: [vd3])
        legacy.doses.append(Dose(itemId: vd3.id, takenAt: at(2026, 10, 12, 7, 42)))
        XCTAssertEqual(StackEngine(state: legacy, clock: londonClock(4, newYork)).summary(for: monday.adding(-1)).status,
                       .complete)
    }

    func testLogItemNeverLogsToAnArchivedItem() {
        let cre = makeItem("Creatine", "CRE", created: at(2026, 10, 1, 8))
        var state = StackState(items: [cre])
        state.setArchived(id: cre.id, archived: true, now: at(2026, 10, 10, 9))
        XCTAssertNil(state.logActiveDose(itemId: cre.id, at: at(2026, 10, 12, 18, 5), timeZone: london))
        XCTAssertTrue(state.doses.isEmpty)
        state.setArchived(id: cre.id, archived: false, now: at(2026, 10, 12, 18))
        XCTAssertNotNil(state.logActiveDose(itemId: cre.id, at: at(2026, 10, 12, 18, 5), timeZone: london))
        XCTAssertNil(state.logActiveDose(itemId: UUID(), at: at(2026, 10, 12, 18, 5), timeZone: london))
    }

    func testDeleteRemovesItemAndItsDoses() {
        let vd3 = makeItem("Vitamin D3", "VD3", created: at(2026, 10, 1, 8), sortIndex: 0)
        let mag = makeItem("Magnesium", "MAG", created: at(2026, 10, 1, 8), sortIndex: 1)
        var state = StackState(items: [vd3, mag])
        state.logDose(itemId: mag.id, at: at(2026, 10, 5, 21), timeZone: london)
        state.logDose(itemId: vd3.id, at: at(2026, 10, 5, 8), timeZone: london)
        state.deleteItem(id: mag.id)
        XCTAssertEqual(state.items.map(\.id), [vd3.id])
        XCTAssertEqual(state.doses.count, 1)
        let summary = StackEngine(state: state, clock: londonClock()).summary(for: DayKey(year: 2026, month: 10, day: 5))
        XCTAssertEqual(summary.status, .complete)
    }

    func testReorder() {
        let created = at(2026, 10, 1, 8)
        var state = StackState(items: [
            makeItem("A", "AAA", created: created, sortIndex: 0),
            makeItem("B", "BBB", created: created, sortIndex: 1),
            makeItem("C", "CCC", created: created, sortIndex: 2),
        ])
        state.moveActiveItems(fromOffsets: IndexSet(integer: 0), toOffset: 3)
        XCTAssertEqual(state.orderedItems.map(\.code), ["BBB", "CCC", "AAA"])
        state.moveActiveItems(fromOffsets: IndexSet(integer: 2), toOffset: 0)
        XCTAssertEqual(state.orderedItems.map(\.code), ["AAA", "BBB", "CCC"])
    }

    func testAddItemsUsesPresetCodesAndDerivesOthers() {
        var state = StackState()
        let added = state.addItems([
            ItemDraft(name: "Vitamin D3"),
            ItemDraft(name: "  Lion's Mane "),
            ItemDraft(name: "   "),
        ], now: at(2026, 10, 12, 9))
        XCTAssertEqual(added.count, 2)
        XCTAssertEqual(added[0].code, "VD3")
        XCTAssertEqual(added[1].name, "Lion's Mane")
        XCTAssertEqual(added[1].code, "LMN")
        XCTAssertEqual(added.map(\.sortIndex), [0, 1])
        XCTAssertEqual(Catalog.code(for: "Ashwagandha"), "ASH")
        XCTAssertEqual(Catalog.code(for: "Berberine"), "BRB")
        XCTAssertEqual(Catalog.sanitizeCode("vd-3 extra"), "VD3E")
    }

    // MARK: Siri

    func testSiriAnswer() {
        let created = at(2026, 10, 1, 8)
        let vd3 = makeItem("Vitamin D3", "VD3", created: created, sortIndex: 0)
        let fish = makeItem("Fish Oil", "FSH", created: created, sortIndex: 1)
        let zinc = makeItem("Zinc", "ZNC", .alternateDays, created: created, sortIndex: 2)
        var state = StackState(items: [vd3, fish, zinc])
        state.logDose(itemId: zinc.id, at: at(2026, 10, 11, 8), timeZone: london)
        state.logDose(itemId: vd3.id, at: at(2026, 10, 12, 7, 42), timeZone: london)
        let pending = SiriAnswers.status(state: state, now: at(2026, 10, 12, 21), timeZone: london)
        XCTAssertTrue(pending.hasPrefix("Not yet: Fish Oil is pending."), pending)
        XCTAssertTrue(pending.contains("Zinc is not due today."), pending)

        state.logDose(itemId: fish.id, at: at(2026, 10, 12, 7, 42), timeZone: london)
        let done = SiriAnswers.status(state: state, now: at(2026, 10, 12, 21), timeZone: london)
        XCTAssertTrue(done.hasPrefix("Yes. Vitamin D3 at "), done)
    }
}
