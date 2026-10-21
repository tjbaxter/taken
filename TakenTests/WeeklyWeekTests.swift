import XCTest
@testable import Taken

/// A weekly dose counts for its week (SPEC 3.3, R1 to R5). London clock, the day starting at 04:00. Semaglutide (SEM) is
/// Weekly on Thursday; Vitamin D3 (VD3) is daily and logged on every past day. Thu 15 Oct 2026, Fri 16, Sat 17, Tue 20,
/// Thu 22. Sources: the labels' missed-dose windows (https://www.novo-pi.com/ozempic.pdf,
/// https://pi.lilly.com/us/zepbound-uspi.pdf) and why a broken streak costs use
/// (https://www.colorado.edu/business/faculty-research/2023/04/19/or-track-how-broken-streaks-affect-consumer-decisions).
final class WeeklyWeekTests: XCTestCase {

    private let thu15 = DayKey(year: 2026, month: 10, day: 15)
    private let fri16 = DayKey(year: 2026, month: 10, day: 16)
    private let sat17 = DayKey(year: 2026, month: 10, day: 17)
    private let sun18 = DayKey(year: 2026, month: 10, day: 18)
    private let tue20 = DayKey(year: 2026, month: 10, day: 20)
    private let wed21 = DayKey(year: 2026, month: 10, day: 21)
    private let thu22 = DayKey(year: 2026, month: 10, day: 22)
    private let enUS = Locale(identifier: "en_US")

    private struct Stack {
        var state: StackState
        let vd3: Item
        let sem: Item
        var engine: StackEngine { StackEngine(state: state, clock: londonClock()) }
        /// The same Vitamin D3 log without Semaglutide.
        var vd3Only: StackEngine {
            StackEngine(state: StackState(items: [vd3], doses: state.doses.filter { $0.itemId == vd3.id }),
                        clock: londonClock())
        }
    }

    /// Both items added on Thu 1 Oct, Semaglutide logged on Thu 1 and Thu 8 at 08:00, Vitamin D3 at 08:00 from 1 Oct
    /// through `vd3Through`.
    private func stack(vd3Through last: Int, reminder: Bool = false) -> Stack {
        let created = at(2026, 10, 1, 7)
        let vd3 = makeItem("Vitamin D3", "VD3", created: created, sortIndex: 0)
        let sem = makeItem("Semaglutide", "SEM", .weekdays([5]), created: created, sortIndex: 1)
        var state = StackState(items: [vd3, sem])
        for day in 1...last { state.logDose(itemId: vd3.id, at: at(2026, 10, day, 8), timeZone: london) }
        state.logDose(itemId: sem.id, at: at(2026, 10, 1, 8), timeZone: london)
        state.logDose(itemId: sem.id, at: at(2026, 10, 8, 8), timeZone: london)
        if reminder {
            state.settings.reminderEnabled = true
            state.settings.reminderMinutes = 21 * 60
        }
        return Stack(state: state, vd3: vd3, sem: sem)
    }

    // MARK: R1 credit

    func testALateDoseCountsForItsDayAtItsRealTime() {
        var s = stack(vd3Through: 21)
        let without = s.engine
        s.state.logDose(itemId: s.sem.id, at: at(2026, 10, 16, 8, 12), timeZone: london)
        let engine = s.engine

        XCTAssertEqual(engine.summary(for: thu15).status, .complete)
        XCTAssertEqual(engine.summary(for: thu15, asOf: sat17).status, .complete)
        XCTAssertEqual(engine.doses(of: s.sem.id, on: thu15).map(\.takenAt), [at(2026, 10, 16, 8, 12)],
                       "it counts for Thursday at its real time")
        XCTAssertTrue(engine.doses(of: s.sem.id, on: fri16).isEmpty, "Friday holds no Semaglutide dose")
        XCTAssertFalse(engine.itemDay(s.sem, on: thu15, asOf: sat17).isOpen)
        XCTAssertEqual(engine.streak(today: sat17), 17, "Thu 15 counts: every day from 1 Oct")
        XCTAssertEqual(engine.streak(today: thu22), 21, "and still does once the week has closed")
        XCTAssertEqual(without.streak(today: thu22), 6, "without it Thursday is missed and the streak starts on Friday")

        let csv = CSVExport.make(state: s.state, timeZone: london)
        XCTAssertTrue(csv.contains("\n2026-10-16,08:12,Semaglutide,SEM\n"), "CSV keeps the real date and time: \(csv)")
    }

    // MARK: R2 open week

    func testAnOpenWeekNeitherBreaksNorGrowsTheStreak() {
        let s = stack(vd3Through: 21)
        let engine = s.engine
        for offset in 1...6 {
            let today = thu15.adding(offset)
            XCTAssertEqual(engine.streak(today: today), s.vd3Only.streak(today: today), "on \(Fmt.longDay(today))")
            XCTAssertTrue(engine.itemDay(s.sem, on: thu15, asOf: today).isOpen, "open on \(Fmt.longDay(today))")
            XCTAssertEqual(engine.itemDay(s.sem, on: thu15, asOf: today).dueCount, 0)
            let cell = engine.history(today: today).flatMap { $0 }.first { $0.day == thu15 }
            XCTAssertEqual(cell?.status, .complete, "the grid cell for Thu 15 on \(Fmt.longDay(today))")
            XCTAssertEqual(engine.adherence(today: today).percent, 100, "the 30-day % neither gains nor loses")
        }
        XCTAssertFalse(engine.itemDay(s.sem, on: thu15, asOf: thu15).isOpen, "on its day it is due and pending")
        XCTAssertTrue(engine.itemDay(s.sem, on: thu15, asOf: nil).isPending, "nil turns the rule off")
    }

    func testTheWeekClosesOnTheNextDueDay() {
        let s = stack(vd3Through: 21)
        let engine = s.engine
        XCTAssertFalse(engine.itemDay(s.sem, on: thu15, asOf: thu22).isOpen)
        XCTAssertEqual(engine.summary(for: thu15, asOf: thu22).status, .partial, "missed once the next due day comes")
        XCTAssertEqual(engine.streak(today: thu22), 6, "the streak counts from Fri 16 only")
        let row = engine.todaySummary(now: at(2026, 10, 22, 9)).items.first { $0.item.id == s.sem.id }
        XCTAssertEqual(row?.pendingCount, 1, "one ring and one pending dose, never 2")
        XCTAssertEqual(row?.dosesPerDay, 1)
    }

    func testAnEarlyDoseCountsForTheNextDueDayAndItsNudgeGoes() {
        var s = stack(vd3Through: 19, reminder: true)
        s.state.logDose(itemId: s.sem.id, at: at(2026, 10, 15, 8), timeZone: london)
        s.state.logDose(itemId: s.sem.id, at: at(2026, 10, 20, 8, 12), timeZone: london)
        let engine = s.engine

        XCTAssertEqual(engine.doses(of: s.sem.id, on: thu22).map(\.takenAt), [at(2026, 10, 20, 8, 12)])
        XCTAssertTrue(engine.doses(of: s.sem.id, on: tue20).isEmpty)
        let today = engine.todaySummary(now: at(2026, 10, 22, 9))
        let row = today.items.first { $0.item.id == s.sem.id }
        XCTAssertEqual(row?.isDone, true, "Thu 22's row is done, showing that dose")
        XCTAssertEqual(row?.isPending, false)
        XCTAssertEqual(row.flatMap(\.lastDose).map { Fmt.doseClock($0, viewing: thu22, londonClock()) }, "Tue 08:12")
        XCTAssertEqual(Fmt.progress(today), "1 of 2 taken", "it counts in today's progress")

        let plans = Reminders.plan(state: s.state, now: at(2026, 10, 20, 9), timeZone: london)
        XCTAssertEqual(plans.first { $0.day == thu22 }?.body, "1 pending: VD3", "no nudge that reads as take another")
    }

    func testAnExtraDoseStaysOnItsDay() {
        var s = stack(vd3Through: 16, reminder: true)
        s.state.logDose(itemId: s.sem.id, at: at(2026, 10, 15, 8), timeZone: london)
        s.state.logDose(itemId: s.sem.id, at: at(2026, 10, 15, 9), timeZone: london)
        XCTAssertEqual(s.engine.doses(of: s.sem.id, on: thu15).count, 2, "a second dose on the shot day stays there")

        s.state.logDose(itemId: s.sem.id, at: at(2026, 10, 16, 8), timeZone: london)
        let engine = s.engine
        XCTAssertEqual(engine.doses(of: s.sem.id, on: fri16).count, 1, "6 days before the next due day it stays put")
        XCTAssertEqual(engine.doses(of: s.sem.id, on: thu15).count, 2)
        XCTAssertTrue(engine.doses(of: s.sem.id, on: thu22).isEmpty)

        let plans = Reminders.plan(state: s.state, now: at(2026, 10, 16, 9), timeZone: london)
        XCTAssertEqual(plans.first { $0.day == thu22 }?.body, "2 pending: VD3, SEM", "Thu 22 is still due")
    }

    // MARK: R3 and R4

    func testNoNudgeAfterTheDueDay() {
        let s = stack(vd3Through: 15, reminder: true)
        let plans = Reminders.plan(state: s.state, now: at(2026, 10, 16, 9), timeZone: london)
        for offset in 0..<6 {
            let day = fri16.adding(offset)
            XCTAssertEqual(plans.first { $0.day == day }?.body, "1 pending: VD3", "no Semaglutide on \(Fmt.longDay(day))")
        }
        XCTAssertEqual(plans.first { $0.day == thu22 }?.body, "2 pending: VD3, SEM")
    }

    func testQuickPathsNeverLogAWeeklyItemOffItsDay() {
        let s = stack(vd3Through: 15)
        let now = at(2026, 10, 16, 9)
        var take = s.state
        XCTAssertEqual(take.takeAllPending(now: now, clock: londonClock()).map(\.itemId), [s.vd3.id], "Take all logs VD3 only")
        var widget = s.state
        XCTAssertNil(widget.logNextDoseIfPending(itemId: s.sem.id, now: now, clock: londonClock()))
        XCTAssertFalse(s.engine.todaySummary(now: now).due.contains { $0.item.id == s.sem.id })
        #if canImport(UIKit)
        let snapshot = WidgetSnapshot(state: s.state, now: now, timeZone: london)
        XCTAssertFalse(snapshot.rows.contains { $0.id == s.sem.id }, "the widget leaves the open week out")
        #endif
    }

    // MARK: Rows and copy

    func testWeekRowAndItsCopy() throws {
        var s = stack(vd3Through: 16)
        let open = try XCTUnwrap(s.engine.weekRow(for: s.sem, today: sat17))
        XCTAssertTrue(open.isOpen)
        XCTAssertEqual(open.day, thu15)
        XCTAssertEqual(Fmt.weekNote(open, today: sat17), "Weekly \u{00B7} Thu \u{00B7} Not logged")
        let sheet = s.engine.sheetSummary(for: thu15, asOf: sat17)
        let sheetRow = try XCTUnwrap(sheet.items.first { $0.item.id == s.sem.id })
        XCTAssertEqual(Fmt.dayItemStatus(sheetRow, isToday: false), "Weekly \u{00B7} Thu \u{00B7} not logged")
        XCTAssertEqual(Fmt.daySheetStatus(sheet, isToday: false), "1 of 2 taken \u{00B7} 1 not logged")

        let dose = try XCTUnwrap(s.state.logDose(itemId: s.sem.id, at: at(2026, 10, 17, 8, 12), timeZone: london))
        let logged = try XCTUnwrap(s.engine.weekRow(for: s.sem, today: sat17))
        XCTAssertFalse(logged.isOpen)
        XCTAssertEqual(logged.lastDose?.id, dose.id)
        XCTAssertEqual(Fmt.doseClock(dose, viewing: sat17, londonClock()), "08:12")
        XCTAssertEqual(Fmt.doseClock(dose, viewing: sun18, londonClock()), "Sat 08:12")
        XCTAssertEqual(Fmt.weekNote(logged, today: sat17), "Weekly \u{00B7} Next: Thursday")
        XCTAssertEqual(Fmt.weekNote(try XCTUnwrap(s.engine.weekRow(for: s.sem, today: sun18)), today: sun18),
                       "Weekly \u{00B7} Next: Thursday")
        XCTAssertEqual(Fmt.agoDetailed(at(2026, 10, 16, 8, 12), now: at(2026, 10, 17, 10, 12)), "1d 2h ago")
        XCTAssertEqual(Fmt.agoDetailed(at(2026, 10, 16, 8, 12), now: at(2026, 10, 17, 8, 40)), "1d ago")
        XCTAssertEqual(Fmt.agoDetailed(at(2026, 10, 17, 8, 12), now: at(2026, 10, 17, 17, 24)), "9h 12m ago", "unchanged")

        var early = stack(vd3Through: 19)
        early.state.logDose(itemId: early.sem.id, at: at(2026, 10, 15, 8), timeZone: london)
        early.state.logDose(itemId: early.sem.id, at: at(2026, 10, 20, 8, 12), timeZone: london)
        let waiting = try XCTUnwrap(early.engine.weekRow(for: early.sem, today: wed21))
        XCTAssertEqual(waiting.day, thu22)
        XCTAssertEqual(Fmt.weekNote(waiting, today: wed21), "Weekly \u{00B7} Counts for Thursday")
        XCTAssertEqual(waiting.lastDose.map { Fmt.doseClock($0, viewing: wed21, londonClock()) }, "Tue 08:12")
    }

    // MARK: The early dose (R1 b) on Today, its day and its sheet

    /// The 1 to 3 days before the next due day, with this week logged, Today's row is today's quiet ring, so an early
    /// dose is one tap. On the 3 days after the due day the lit ring stays and a tap never logs.
    func testAnEarlyDoseIsOneTapInTheDaysBeforeTheNextDueDay() {
        var s = stack(vd3Through: 21)
        s.state.logDose(itemId: s.sem.id, at: at(2026, 10, 15, 8), timeZone: london)
        for offset in 1...3 {
            XCTAssertFalse(s.engine.takesEarlyDose(s.sem, today: thu15.adding(offset)), "D+\(offset): the lit ring stays")
        }
        for offset in 4...6 {
            XCTAssertTrue(s.engine.takesEarlyDose(s.sem, today: thu15.adding(offset)), "D+\(offset): a tap logs")
        }
        let open = stack(vd3Through: 21)
        XCTAssertTrue(open.engine.weekRow(for: open.sem, today: tue20)?.isOpen ?? false)
        XCTAssertFalse(open.engine.takesEarlyDose(open.sem, today: tue20), "an open week logs from its own ring")
        s.state.logDose(itemId: s.sem.id, at: at(2026, 10, 20, 8, 12), timeZone: london)
        XCTAssertFalse(s.engine.takesEarlyDose(s.sem, today: wed21), "once it is logged the row is Thu 22's")
        XCTAssertEqual(s.engine.weekRow(for: s.sem, today: wed21)?.day, thu22)
    }

    /// Thu 15 logged, then a tap on Semaglutide's Not today ring on Tue 20 logs a dose that counts for Thu 22.
    @MainActor
    func testATapOnTheRingLogsAnEarlyDoseFromToday() throws {
        let zone = TimeZone.current
        func local(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date { at(2026, 10, day, hour, minute, zone) }
        let vd3 = makeItem("Vitamin D3", "VD3", created: local(1, 9), sortIndex: 0)
        let sem = makeItem("Semaglutide", "SEM", .weekdays([5]), created: local(1, 9), sortIndex: 1)
        var state = StackState(items: [vd3, sem])
        state.logDose(itemId: sem.id, at: local(8, 9), timeZone: zone)
        state.logDose(itemId: sem.id, at: local(15, 9), timeZone: zone)
        let store = TakenStore(fileURL: temporaryStoreURL(), postsChangeNotifications: false)
        try store.replace(with: state)
        let now = local(20, 10, 30)
        let profiles = ProfileStore(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent("taken-tests-profile-\(UUID().uuidString)"))
        let model = AppModel(store: store, pro: ProStore(demoLocked: false, now: now), profileStore: profiles,
                             isDemo: true, launchScreen: nil, clockNow: { now })

        let entry = try XCTUnwrap(model.today.notDue.first { $0.item.id == sem.id })
        let shown = model.notTodayRow(entry)
        XCTAssertEqual(shown.row.day, tue20, "today's row, not last Thursday's")
        XCTAssertTrue(shown.row.doses.isEmpty, "a quiet ring")
        XCTAssertEqual(shown.note, "Weekly \u{00B7} Next: Thursday")
        model.tap(shown.row)

        XCTAssertEqual(model.engine.doses(of: sem.id, on: thu22).map(\.takenAt), [now], "it counts for Thu 22")
        XCTAssertTrue(model.engine.doses(of: sem.id, on: tue20).isEmpty)
        let after = model.notTodayRow(try XCTUnwrap(model.today.notDue.first { $0.item.id == sem.id }))
        XCTAssertEqual(after.row.day, thu22)
        XCTAssertEqual(after.note, "Weekly \u{00B7} Counts for Thursday")
        XCTAssertTrue(model.offersSetTime(after.row), "logged today: Set time corrects it")
        XCTAssertEqual(model.toast?.message, "Semaglutide taken at")
    }

    /// On Thu 22 with the Tue 20 dose credited to it, the row, the progress line, VoiceOver and Siri all name Tuesday.
    func testAnEarlyDoseKeepsItsDayOnTheDueDay() throws {
        var s = stack(vd3Through: 21)
        s.state.logDose(itemId: s.sem.id, at: at(2026, 10, 15, 8), timeZone: london)
        s.state.logDose(itemId: s.sem.id, at: at(2026, 10, 20, 8, 12), timeZone: london)
        let now = at(2026, 10, 22, 7)
        let today = s.engine.todaySummary(now: now)
        let row = try XCTUnwrap(today.items.first { $0.item.id == s.sem.id })
        XCTAssertEqual(row.day, thu22)
        XCTAssertEqual(today.lastDose?.takenAt, at(2026, 10, 20, 8, 12), "the only dose counted for today")

        let siri = SiriAnswers.status(state: s.state, now: now, timeZone: london, locale: enUS)
        XCTAssertTrue(siri.contains("Semaglutide taken Tuesday at 8:12 AM."), siri)
        XCTAssertFalse(siri.contains("Semaglutide at 8:12 AM"), siri)
        let same = SiriAnswers.status(state: stack(vd3Through: 22).state, now: at(2026, 10, 22, 9), timeZone: london,
                                      locale: enUS)
        XCTAssertTrue(same.contains("Vitamin D3 at 8:00 AM"), "a dose logged today reads as before: \(same)")
        #if canImport(UIKit)
        XCTAssertEqual(ItemRowView.accessibilityLabel(row: row, today: thu22, clock: londonClock(), nextLabel: nil,
                                                      locale: enUS),
                       "Semaglutide, taken Tuesday at 8:12 AM.")
        XCTAssertEqual(ProgressSummary.lastTime(today, clock: londonClock()), "Tue 08:12", "Last Tue 08:12, never 08:12")
        let vd3Row = try XCTUnwrap(stack(vd3Through: 22).engine.todaySummary(now: at(2026, 10, 22, 9)).items.first)
        XCTAssertEqual(ItemRowView.accessibilityLabel(row: vd3Row, today: thu22, clock: londonClock(), nextLabel: nil,
                                                      locale: enUS),
                       "Vitamin D3, taken at 8:00 AM.", "unchanged for a dose logged that day")
        #endif
    }

    /// Long-press "Open Thursday" on the early row opens Thu 22 from Tue 20: a day still to come reads as pending, never
    /// missed, and its chip names the day the dose was logged.
    func testTheNextDueDaysSheetNeverSaysMissed() throws {
        var s = stack(vd3Through: 19)
        s.state.logDose(itemId: s.sem.id, at: at(2026, 10, 15, 8), timeZone: london)
        let dose = try XCTUnwrap(s.state.logDose(itemId: s.sem.id, at: at(2026, 10, 19, 8, 12), timeZone: london))
        let row = try XCTUnwrap(s.engine.weekRow(for: s.sem, today: tue20))
        XCTAssertEqual(row.day, thu22, "Mon 19 is 3 days before Thu 22: it counts for it")
        let sheet = s.engine.sheetSummary(for: thu22, asOf: tue20)
        #if canImport(UIKit)
        let live = DaySheet.isLive(thu22, today: tue20)
        XCTAssertTrue(live)
        XCTAssertFalse(DaySheet.isLive(thu15, today: tue20), "an earlier day is still past")
        let status = Fmt.daySheetStatus(sheet, isToday: live)
        XCTAssertEqual(status, "1 of 2 taken \u{00B7} 1 pending")
        for line in [status] + sheet.items.map({ Fmt.dayItemStatus($0, isToday: live) }) {
            XCTAssertNil(line.range(of: "missed", options: .caseInsensitive), line)
        }
        #endif
        XCTAssertEqual(Fmt.doseClock(dose, viewing: thu22, londonClock()), "Mon 08:12")
    }

    func testCreditRespectsTheStartAndScheduleChanges() throws {
        let vd3 = makeItem("Vitamin D3", "VD3", created: at(2026, 10, 1, 7), sortIndex: 0)
        let added = makeItem("Semaglutide", "SEM", .weekdays([5]), created: at(2026, 10, 17, 9), sortIndex: 1)
        var fresh = StackState(items: [vd3, added])
        fresh.logDose(itemId: added.id, at: at(2026, 10, 17, 10), timeZone: london)
        var engine = StackEngine(state: fresh, clock: londonClock())
        XCTAssertEqual(engine.doses(of: added.id, on: sat17).count, 1, "added on Saturday: the dose stays on Saturday")
        XCTAssertTrue(engine.doses(of: added.id, on: thu15).isEmpty, "never for a Thursday before it was added")
        XCTAssertNil(engine.weekRow(for: added, today: sat17), "the row reads as before")
        XCTAssertEqual(engine.todaySummary(now: at(2026, 10, 22, 9)).items.first { $0.item.id == added.id }?.isPending, true,
                       "Thu 22 is due")

        var s = stack(vd3Through: 17)
        s.state.updateItem(id: s.sem.id, name: "Semaglutide", code: "SEM", frequency: .weekdays([7]), now: at(2026, 10, 17, 9))
        s.state.logDose(itemId: s.sem.id, at: at(2026, 10, 17, 10), timeZone: london)
        engine = s.engine
        XCTAssertEqual(engine.doses(of: s.sem.id, on: sat17).count, 1, "moved to Saturday: a Saturday dose counts for it")
        XCTAssertTrue(engine.doses(of: s.sem.id, on: thu15).isEmpty, "never for Thu 15, on the old schedule")

        // Weekly to Every other day after a late dose: the dose still counts for Thu 15, and Every other day reads the
        // day it was really taken, Sat 17, so Sun 18 is not due and the nudge never asks for it a day after a dose.
        var switched = stack(vd3Through: 17, reminder: true)
        switched.state.logDose(itemId: switched.sem.id, at: at(2026, 10, 17, 10), timeZone: london)
        switched.state.updateItem(id: switched.sem.id, name: "Semaglutide", code: "SEM", frequency: .alternateDays,
                                  now: at(2026, 10, 18, 9))
        engine = switched.engine
        let sem = try XCTUnwrap(switched.state.item(switched.sem.id))
        XCTAssertEqual(engine.doses(of: sem.id, on: thu15).count, 1, "the late dose still counts for its week")
        XCTAssertEqual(engine.lastDoseDay(of: sem.id, before: sun18), sat17, "the day it was logged")
        XCTAssertFalse(engine.isDue(sem, on: sun18), "a day after a real dose")
        XCTAssertTrue(engine.isDue(sem, on: sun18.adding(1)))
        XCTAssertEqual(engine.nextDueDay(for: sem, after: sun18), sun18.adding(1))
        let plans = Reminders.plan(state: switched.state, now: at(2026, 10, 18, 9), timeZone: london)
        XCTAssertEqual(plans.first { $0.day == sun18 }?.body, "1 pending: VD3", "no Semaglutide on Sun 18")
        XCTAssertEqual(plans.first { $0.day == sun18.adding(1) }?.body, "2 pending: VD3, SEM")
    }

    func testOtherSchedulesAreUnchanged() {
        let mwf = makeItem("Minoxidil", "MIN", .weekdays([2, 4, 6]), created: at(2026, 10, 1, 8))
        var state = StackState(items: [mwf])
        state.logDose(itemId: mwf.id, at: at(2026, 10, 13, 8), timeZone: london)
        let engine = StackEngine(state: state, clock: londonClock())
        let monday = DayKey(year: 2026, month: 10, day: 12)
        XCTAssertEqual(engine.summary(for: monday, asOf: monday.adding(1)).status, .missed)
        XCTAssertEqual(engine.summary(for: monday, asOf: monday.adding(3)).status, .missed)
        XCTAssertEqual(engine.doses(of: mwf.id, on: monday.adding(1)).count, 1, "the dose stays on Tuesday")
        XCTAssertNil(engine.weekRow(for: mwf, today: monday.adding(1)))
        XCTAssertFalse(engine.itemDay(mwf, on: monday, asOf: monday.adding(1)).isOpen)
    }

    func testUndoReopensTheWeek() throws {
        var s = stack(vd3Through: 17)
        let late = try XCTUnwrap(s.state.logDose(itemId: s.sem.id, at: at(2026, 10, 16, 8, 12), timeZone: london))
        XCTAssertFalse(s.engine.itemDay(s.sem, on: thu15, asOf: sat17).isOpen)
        s.state.removeDoses([late.id])
        XCTAssertTrue(s.engine.itemDay(s.sem, on: thu15, asOf: sat17).isOpen, "Thu 15 is open again")
        s.state.restore(late)
        XCTAssertEqual(s.engine.doses(of: s.sem.id, on: thu15).map(\.id), [late.id], "and Undo puts it back")
    }

    func testADoseLoggedAbroadCreditsFromItsLoggedDay() throws {
        let newYork = TimeZone(identifier: "America/New_York")!
        var s = stack(vd3Through: 21)
        // 23:30 EDT on Wed 21 is 04:30 BST on Thu 22: logged on Wednesday where it was taken, so it counts for Thu 15.
        s.state.logDose(itemId: s.sem.id, at: at(2026, 10, 21, 23, 30, newYork), timeZone: newYork)
        let engine = s.engine
        XCTAssertEqual(engine.doses(of: s.sem.id, on: thu15).count, 1)
        XCTAssertTrue(engine.doses(of: s.sem.id, on: thu22).isEmpty)
        XCTAssertEqual(engine.todaySummary(now: at(2026, 10, 22, 9)).items.first { $0.item.id == s.sem.id }?.isPending, true)
        let late = try XCTUnwrap(engine.doses(of: s.sem.id, on: thu15).first)
        XCTAssertTrue(Fmt.doseClock(late, viewing: thu15, londonClock()).hasPrefix("Wed "),
                      "logged on Wednesday where it was taken: the chip names Wednesday, as the engine reads it")

        // On time abroad: 23:30 EDT on Thu 15 is 04:30 BST on Fri 16, after the 04:00 day start. Back in London it reads
        // as Thursday's dose on Thursday, with no day before the time, and Siri says it was taken on its day.
        var onTime = stack(vd3Through: 21)
        let dose = try XCTUnwrap(onTime.state.logDose(itemId: onTime.sem.id, at: at(2026, 10, 15, 23, 30, newYork),
                                                      timeZone: newYork))
        XCTAssertEqual(onTime.engine.doses(of: onTime.sem.id, on: thu15).map(\.id), [dose.id])
        XCTAssertEqual(Fmt.doseClock(dose, viewing: thu15, londonClock()), "04:30", "no Fri before an on-time dose")
        XCTAssertEqual(Fmt.doseClock(dose, viewing: sat17, londonClock()), "Thu 04:30")
        XCTAssertEqual(Fmt.spokenDose(dose, viewing: thu15, londonClock(), locale: enUS), "at 4:30 AM")
        let siri = SiriAnswers.status(state: onTime.state, now: at(2026, 10, 17, 10), timeZone: london, locale: enUS)
        XCTAssertTrue(siri.contains("Semaglutide was taken Thursday at 4:30 AM."), siri)
        XCTAssertFalse(siri.contains("for Thursday"), "never as taken on another day: \(siri)")

        // A daily dose logged abroad keeps its plain time on its own day, as before this build.
        var daily = stack(vd3Through: 14)
        let vd3 = try XCTUnwrap(daily.state.logDose(itemId: daily.vd3.id, at: at(2026, 10, 15, 23, 30, newYork),
                                                    timeZone: newYork))
        XCTAssertEqual(daily.engine.doses(of: daily.vd3.id, on: thu15).map(\.id), [vd3.id])
        XCTAssertEqual(Fmt.doseClock(vd3, viewing: thu15, londonClock()), "04:30")
    }

    func testSiriWeeklySentences() {
        var late = stack(vd3Through: 17)
        late.state.logDose(itemId: late.sem.id, at: at(2026, 10, 16, 8, 12), timeZone: london)
        let lateAnswer = SiriAnswers.status(state: late.state, now: at(2026, 10, 17, 10), timeZone: london, locale: enUS)
        XCTAssertTrue(lateAnswer.contains("Semaglutide was taken Friday at 8:12 AM, for Thursday."), lateAnswer)
        XCTAssertFalse(lateAnswer.contains("not due today"), lateAnswer)

        var onDay = stack(vd3Through: 17)
        onDay.state.logDose(itemId: onDay.sem.id, at: at(2026, 10, 15, 8, 12), timeZone: london)
        let onDayAnswer = SiriAnswers.status(state: onDay.state, now: at(2026, 10, 17, 10), timeZone: london, locale: enUS)
        XCTAssertTrue(onDayAnswer.contains("Semaglutide was taken Thursday at 8:12 AM."), onDayAnswer)

        let open = stack(vd3Through: 17)
        let openAnswer = SiriAnswers.status(state: open.state, now: at(2026, 10, 17, 10), timeZone: london, locale: enUS)
        XCTAssertTrue(openAnswer.contains("Semaglutide is not logged for Thursday."), openAnswer)

        let row = open.engine.weekRow(for: open.sem, today: sat17)!
        XCTAssertEqual(SiriAnswers.weekSentence(row, today: sat17, clock: londonClock(), locale: enUS),
                       "Semaglutide is not logged for Thursday.")
    }

    func testWeeklyCopyGivesNoDosingAdvice() throws {
        var s = stack(vd3Through: 19)
        let open = try XCTUnwrap(s.engine.weekRow(for: s.sem, today: sat17))
        let openSheet = s.engine.sheetSummary(for: thu15, asOf: sat17)
        var openLines = [Fmt.weekNote(open, today: sat17), Fmt.daySheetStatus(openSheet, isToday: false),
                         SiriAnswers.weekSentence(open, today: sat17, clock: londonClock(), locale: enUS)]
        openLines += openSheet.items.map { Fmt.dayItemStatus($0, isToday: false) }

        s.state.logDose(itemId: s.sem.id, at: at(2026, 10, 16, 8, 12), timeZone: london)
        let logged = try XCTUnwrap(s.engine.weekRow(for: s.sem, today: sat17))
        s.state.logDose(itemId: s.sem.id, at: at(2026, 10, 20, 8, 12), timeZone: london)
        let early = try XCTUnwrap(s.engine.weekRow(for: s.sem, today: tue20))
        var lines = openLines + [Fmt.weekNote(logged, today: sat17), Fmt.weekNote(early, today: tue20), Fmt.missedDoseNote,
                                 SiriAnswers.weekSentence(logged, today: sat17, clock: londonClock(), locale: enUS),
                                 SiriAnswers.weekSentence(early, today: wed21, clock: londonClock(), locale: enUS)]
        #if canImport(UIKit)
        let openLabel = ItemRowView.accessibilityLabel(row: open, today: sat17, clock: londonClock(), nextLabel: "Next: Thursday",
                                                       locale: enUS)
        XCTAssertEqual(openLabel, "Semaglutide, Thursday's dose not logged.")
        XCTAssertEqual(ItemRowView.accessibilityHint(row: open, quiet: true, locked: false), "Double tap to mark taken.")
        let loggedLabel = ItemRowView.accessibilityLabel(row: logged, today: sat17, clock: londonClock(),
                                                         nextLabel: "Next: Thursday", locale: enUS)
        XCTAssertEqual(loggedLabel, "Semaglutide, taken Friday at 8:12 AM.")
        openLines.append(openLabel)
        lines += [openLabel, loggedLabel,
                  ItemRowView.accessibilityLabel(row: early, today: wed21, clock: londonClock(), nextLabel: nil, locale: enUS)]
        #endif

        for line in lines {
            for word in ["late", "overdue", "left", "still", "take it", "skip"] {
                XCTAssertNil(line.range(of: word, options: .caseInsensitive), "\(word) in \(line)")
            }
            XCTAssertNil(line.range(of: "free", options: .caseInsensitive), line)
            XCTAssertFalse(line.contains("\u{2014}") || line.contains("\u{2013}") || line.contains("!"), line)
        }
        for line in openLines {
            XCTAssertNil(line.range(of: "missed", options: .caseInsensitive), "never missed while the week is open: \(line)")
        }
        XCTAssertEqual(Fmt.missedDoseNote,
                       "Missed a dose? Follow your medicine's leaflet, or ask your pharmacist or doctor.")
    }
}
