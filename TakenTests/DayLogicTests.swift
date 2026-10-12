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
        let c = clock(4)
        let monday = DayKey(year: 2026, month: 10, day: 12)
        XCTAssertEqual(c.day(for: at(2026, 10, 13, 1, 0)), monday, "01:00 Tuesday still belongs to Monday")
        XCTAssertEqual(c.day(for: at(2026, 10, 13, 3, 59)), monday)
        XCTAssertEqual(c.day(for: at(2026, 10, 13, 4, 0)), monday.adding(1), "04:00 starts Tuesday")
        XCTAssertEqual(c.day(for: at(2026, 10, 12, 23, 30)), monday)
    }

    func testMidnightRolloverWhenDayStartsAtZero() {
        let c = clock(0)
        XCTAssertEqual(c.day(for: at(2026, 10, 13, 0, 30)), DayKey(year: 2026, month: 10, day: 13))
    }

    func testRolloverAcrossDaylightSavingStart() {
        // UK clocks go forward at 01:00 GMT on 29 Mar 2026.
        let c = clock(4)
        let sunday = DayKey(year: 2026, month: 3, day: 29)
        XCTAssertEqual(c.day(for: at(2026, 3, 29, 3, 30)), sunday.adding(-1))
        XCTAssertEqual(c.day(for: at(2026, 3, 29, 4, 30)), sunday, "04:30 BST is after the rollover")
        let start = c.start(of: sunday)
        XCTAssertEqual(c.hourMinute(of: start).hour, 4)
        XCTAssertEqual(c.end(of: sunday), c.start(of: sunday.adding(1)))
    }

    func testDateOnDayMapsEarlyHoursToNextCalendarDate() {
        let c = clock(4)
        let monday = DayKey(year: 2026, month: 10, day: 12)
        let late = c.date(on: monday, hour: 1, minute: 15)
        XCTAssertEqual(late, at(2026, 10, 13, 1, 15))
        XCTAssertEqual(c.day(for: late), monday)
        XCTAssertEqual(c.date(on: monday, hour: 9, minute: 0), at(2026, 10, 12, 9, 0))
    }

    // MARK: Frequencies

    func testAlternateDaysDueLogic() {
        let c = clock()
        let created = at(2026, 10, 1, 8)
        let zinc = makeItem("Zinc", "ZNC", .alternateDays, created: created)
        let monday = DayKey(year: 2026, month: 10, day: 12)

        var state = StackState(items: [zinc])
        var engine = StackEngine(state: state, clock: c)
        XCTAssertTrue(engine.isDue(zinc, on: monday), "never taken: due")

        state.logDose(itemId: zinc.id, at: at(2026, 10, 11, 8))
        engine = StackEngine(state: state, clock: c)
        XCTAssertFalse(engine.isDue(zinc, on: monday), "taken yesterday: not due")
        XCTAssertEqual(engine.nextDueDay(for: zinc, after: monday), monday.adding(1), "NEXT: TOMORROW")
        XCTAssertEqual(Fmt.next(engine.nextDueDay(for: zinc, after: monday), today: monday), "NEXT: TOMORROW")
        XCTAssertTrue(engine.isDue(zinc, on: monday.adding(1)), "two days after the last dose: due")

        state = StackState(items: [zinc])
        state.logDose(itemId: zinc.id, at: at(2026, 10, 10, 8))
        engine = StackEngine(state: state, clock: c)
        XCTAssertTrue(engine.isDue(zinc, on: monday), "last dose two days ago: due")

        let summary = engine.todaySummary(now: at(2026, 10, 12, 21))
        XCTAssertEqual(summary.due.count, 1)
    }

    func testAlternateDayItemTakenYesterdayIsInNotDueGroup() {
        let c = clock()
        let created = at(2026, 10, 1, 8)
        let vd3 = makeItem("Vitamin D3", "VD3", created: created, sortIndex: 0)
        let zinc = makeItem("Zinc", "ZNC", .alternateDays, created: created, sortIndex: 1)
        var state = StackState(items: [vd3, zinc])
        state.logDose(itemId: zinc.id, at: at(2026, 10, 11, 8))
        let today = StackEngine(state: state, clock: c).todaySummary(now: at(2026, 10, 12, 10))
        XCTAssertEqual(today.due.map(\.item.id), [vd3.id])
        XCTAssertEqual(today.notDue.map(\.item.id), [zinc.id])
        XCTAssertEqual(today.dueDoses, 1)
    }

    func testWeekdayFrequency() {
        let c = clock()
        let mwf = makeItem("Minoxidil", "MIN", .weekdays([2, 4, 6]), created: at(2026, 10, 1, 8))
        let engine = StackEngine(state: StackState(items: [mwf]), clock: c)
        let monday = DayKey(year: 2026, month: 10, day: 12)
        XCTAssertTrue(engine.isDue(mwf, on: monday))
        XCTAssertFalse(engine.isDue(mwf, on: monday.adding(1)))
        XCTAssertTrue(engine.isDue(mwf, on: monday.adding(2)))
        XCTAssertFalse(engine.isDue(mwf, on: monday.adding(6)), "Sunday")
        XCTAssertEqual(engine.nextDueDay(for: mwf, after: monday.adding(4)), monday.adding(7), "Friday to next Monday")
        XCTAssertEqual(Fmt.frequency(.weekdays([2, 4, 6])), "MON WED FRI")
        XCTAssertEqual(Fmt.frequency(.weekdays([2, 3, 4, 5, 6])), "WEEKDAYS")
    }

    func testMultiDoseCompletion() {
        let c = clock()
        let fish = makeItem("Fish Oil", "FSH", .daily(times: 2), created: at(2026, 10, 1, 8))
        var state = StackState(items: [fish])
        let now = at(2026, 10, 12, 8)

        var row = StackEngine(state: state, clock: c).todaySummary(now: now).items[0]
        XCTAssertEqual(row.pendingCount, 2)
        XCTAssertFalse(row.isDone)

        state.logDose(itemId: fish.id, at: now)
        row = StackEngine(state: state, clock: c).todaySummary(now: now).items[0]
        XCTAssertEqual(row.pendingCount, 1)
        XCTAssertFalse(row.isDone)

        state.logDose(itemId: fish.id, at: at(2026, 10, 12, 19))
        let summary = StackEngine(state: state, clock: c).todaySummary(now: at(2026, 10, 12, 20))
        XCTAssertTrue(summary.items[0].isDone)
        XCTAssertTrue(summary.allTaken)
        XCTAssertEqual(summary.takenDueDoses, 2)
    }

    // MARK: Take all

    func testTakeAllOnlyTouchesPendingDueDoses() {
        let c = clock()
        let created = at(2026, 10, 1, 8)
        let vd3 = makeItem("Vitamin D3", "VD3", created: created, sortIndex: 0)
        let fin = makeItem("Finasteride", "FIN", created: created, sortIndex: 1)
        let fish = makeItem("Fish Oil", "FSH", .daily(times: 2), created: created, sortIndex: 2)
        let zinc = makeItem("Zinc", "ZNC", .alternateDays, created: created, sortIndex: 3)
        var state = StackState(items: [vd3, fin, fish, zinc])
        state.logDose(itemId: vd3.id, at: at(2026, 10, 12, 7, 42))
        state.logDose(itemId: zinc.id, at: at(2026, 10, 11, 8))

        let now = at(2026, 10, 12, 21)
        let logged = state.takeAllPending(now: now, clock: c)
        XCTAssertEqual(Set(logged.map(\.itemId)), [fin.id, fish.id], "one dose each for pending items only")
        XCTAssertTrue(logged.allSatisfy { $0.takenAt == now })
        XCTAssertEqual(state.doses.filter { $0.itemId == vd3.id }.count, 1, "already taken: untouched")
        XCTAssertEqual(state.doses.filter { $0.itemId == zinc.id }.count, 1, "not due: untouched")

        let again = state.takeAllPending(now: now, clock: c)
        XCTAssertEqual(again.map(\.itemId), [fish.id], "second dose of the 2x item")
        XCTAssertTrue(state.takeAllPending(now: now, clock: c).isEmpty, "nothing left")
        XCTAssertTrue(StackEngine(state: state, clock: c).todaySummary(now: now).allTaken)
    }

    func testWidgetLogNeverDoubleLogs() {
        let c = clock()
        let vd3 = makeItem("Vitamin D3", "VD3", created: at(2026, 10, 1, 8))
        var state = StackState(items: [vd3])
        let now = at(2026, 10, 12, 9)
        XCTAssertNotNil(state.logNextDoseIfPending(itemId: vd3.id, now: now, clock: c))
        XCTAssertNil(state.logNextDoseIfPending(itemId: vd3.id, now: now, clock: c))
        XCTAssertEqual(state.doses.count, 1)
    }

    // MARK: Undo and backfill

    func testUndoRemovesOnlyThatDose() {
        let c = clock()
        let vd3 = makeItem("Vitamin D3", "VD3", created: at(2026, 10, 1, 8))
        var state = StackState(items: [vd3])
        let yesterday = state.logDose(itemId: vd3.id, at: at(2026, 10, 11, 8))!
        let today = state.logDose(itemId: vd3.id, at: at(2026, 10, 12, 8))!
        state.removeDoses([today.id])
        XCTAssertEqual(state.doses.map(\.id), [yesterday.id])

        let again = state.logDose(itemId: vd3.id, at: at(2026, 10, 12, 9))!
        let removed = state.undoLastDose(itemId: vd3.id, on: DayKey(year: 2026, month: 10, day: 12), clock: c)
        XCTAssertEqual(removed?.id, again.id)
        XCTAssertEqual(state.doses.map(\.id), [yesterday.id], "undo never reaches into another day")
        XCTAssertNil(state.undoLastDose(itemId: vd3.id, on: DayKey(year: 2026, month: 10, day: 12), clock: c))
    }

    func testBackfillOnPastDay() {
        let c = clock()
        let vd3 = makeItem("Vitamin D3", "VD3", created: at(2026, 10, 1, 8))
        var state = StackState(items: [vd3])
        let saturday = DayKey(year: 2026, month: 10, day: 10)
        XCTAssertEqual(StackEngine(state: state, clock: c).summary(for: saturday).status, .missed)

        state.logDose(itemId: vd3.id, at: c.date(on: saturday, hour: 9, minute: 0))
        let engine = StackEngine(state: state, clock: c)
        XCTAssertEqual(engine.summary(for: saturday).status, .complete)
        XCTAssertEqual(engine.doses(of: vd3.id, on: saturday).first?.takenAt, at(2026, 10, 10, 9, 0))
    }

    func testBackfillBeforeItemWasAddedExtendsHistory() {
        let c = clock()
        let vd3 = makeItem("Vitamin D3", "VD3", created: at(2026, 10, 12, 8))
        var state = StackState(items: [vd3])
        let sunday = DayKey(year: 2026, month: 10, day: 11)
        XCTAssertEqual(StackEngine(state: state, clock: c).summary(for: sunday).status, .nothingDue)
        state.logDose(itemId: vd3.id, at: c.date(on: sunday, hour: 9, minute: 0))
        XCTAssertEqual(StackEngine(state: state, clock: c).summary(for: sunday).status, .complete)
    }

    func testSetDoseTime() {
        let vd3 = makeItem("Vitamin D3", "VD3", created: at(2026, 10, 1, 8))
        var state = StackState(items: [vd3])
        let dose = state.logDose(itemId: vd3.id, at: at(2026, 10, 12, 21))!
        state.setDoseTime(doseId: dose.id, to: at(2026, 10, 12, 7))
        XCTAssertEqual(state.doses.first?.takenAt, at(2026, 10, 12, 7))
    }

    // MARK: Stats

    func testStreakSkipsNothingDueDaysAndIgnoresUnfinishedToday() {
        let c = clock()
        let created = at(2026, 10, 1, 8)
        let mwf = makeItem("Minoxidil", "MIN", .weekdays([2, 4, 6]), created: created)
        var state = StackState(items: [mwf])
        // Mon 5, Wed 7, Fri 9 Oct taken; Mon 12 is today and not yet taken.
        for day in [5, 7, 9] { state.logDose(itemId: mwf.id, at: at(2026, 10, day, 8)) }
        var engine = StackEngine(state: state, clock: c)
        let monday = DayKey(year: 2026, month: 10, day: 12)
        XCTAssertEqual(engine.streak(today: monday), 3, "weekends and off days do not break it; today pending does not either")

        state.logDose(itemId: mwf.id, at: at(2026, 10, 12, 8))
        engine = StackEngine(state: state, clock: c)
        XCTAssertEqual(engine.streak(today: monday), 4, "today counts once complete")
    }

    func testStreakBreaksOnMissedDay() {
        let c = clock()
        let vd3 = makeItem("Vitamin D3", "VD3", created: at(2026, 10, 1, 8))
        var state = StackState(items: [vd3])
        for day in [8, 9, 11] { state.logDose(itemId: vd3.id, at: at(2026, 10, day, 8)) }
        let engine = StackEngine(state: state, clock: c)
        XCTAssertEqual(engine.streak(today: DayKey(year: 2026, month: 10, day: 12)), 1, "10 Oct was missed")
    }

    func testThirtyDayAdherence() {
        let c = clock()
        let vd3 = makeItem("Vitamin D3", "VD3", created: at(2026, 9, 1, 8))
        var state = StackState(items: [vd3])
        let today = DayKey(year: 2026, month: 10, day: 12)
        for offset in 1...29 where offset != 5 && offset != 9 {
            state.logDose(itemId: vd3.id, at: c.date(on: today.adding(-offset), hour: 8, minute: 0))
        }
        let engine = StackEngine(state: state, clock: c)
        let pending = engine.adherence(today: today)
        XCTAssertEqual(pending.due, 29, "today's untaken dose is not counted yet")
        XCTAssertEqual(pending.taken, 27)
        XCTAssertEqual(pending.percent, 93)

        state.logDose(itemId: vd3.id, at: c.date(on: today, hour: 8, minute: 0))
        let done = StackEngine(state: state, clock: c).adherence(today: today)
        XCTAssertEqual(done.due, 30)
        XCTAssertEqual(done.taken, 28)
        XCTAssertEqual(done.percent, 93)
        XCTAssertNil(Adherence(taken: 0, due: 0).percent)
        XCTAssertEqual(Adherence(taken: 199, due: 200).percent, 99, "never rounds up to 100")
    }

    func testHistoryGridShape() {
        let c = clock()
        let vd3 = makeItem("Vitamin D3", "VD3", created: at(2026, 9, 1, 8))
        var state = StackState(items: [vd3])
        state.logDose(itemId: vd3.id, at: at(2026, 10, 11, 8))
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
        let c = clock()
        let vd3 = makeItem("Vitamin D3", "VD3", created: at(2026, 10, 1, 8), sortIndex: 0)
        let mag = makeItem("Magnesium", "MAG", created: at(2026, 10, 1, 8), sortIndex: 1)
        var state = StackState(items: [vd3, mag])
        state.logDose(itemId: mag.id, at: at(2026, 10, 5, 21))
        state.setArchived(id: mag.id, archived: true, now: at(2026, 10, 10, 12))
        let engine = StackEngine(state: state, clock: c)
        XCTAssertEqual(engine.todaySummary(now: at(2026, 10, 12, 9)).items.map(\.item.id), [vd3.id])
        XCTAssertEqual(engine.summary(for: DayKey(year: 2026, month: 10, day: 5)).items.count, 2)
    }

    func testDeleteRemovesItemAndItsDoses() {
        let vd3 = makeItem("Vitamin D3", "VD3", created: at(2026, 10, 1, 8), sortIndex: 0)
        let mag = makeItem("Magnesium", "MAG", created: at(2026, 10, 1, 8), sortIndex: 1)
        var state = StackState(items: [vd3, mag])
        state.logDose(itemId: mag.id, at: at(2026, 10, 5, 21))
        state.logDose(itemId: vd3.id, at: at(2026, 10, 5, 8))
        state.deleteItem(id: mag.id)
        XCTAssertEqual(state.items.map(\.id), [vd3.id])
        XCTAssertEqual(state.doses.count, 1)
        let summary = StackEngine(state: state, clock: clock()).summary(for: DayKey(year: 2026, month: 10, day: 5))
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
        state.logDose(itemId: zinc.id, at: at(2026, 10, 11, 8))
        state.logDose(itemId: vd3.id, at: at(2026, 10, 12, 7, 42))
        let pending = SiriAnswers.status(state: state, now: at(2026, 10, 12, 21), timeZone: london)
        XCTAssertTrue(pending.hasPrefix("Not yet: Fish Oil is pending."), pending)
        XCTAssertTrue(pending.contains("Zinc is not due today."), pending)

        state.logDose(itemId: fish.id, at: at(2026, 10, 12, 7, 42))
        let done = SiriAnswers.status(state: state, now: at(2026, 10, 12, 21), timeZone: london)
        XCTAssertTrue(done.hasPrefix("Yes. Vitamin D3 at "), done)
    }
}
