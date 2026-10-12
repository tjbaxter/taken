import XCTest
@testable import Taken

final class ReminderPlanTests: XCTestCase {

    private func makeState(enabled: Bool) -> (StackState, Item, Item) {
        let created = at(2026, 10, 1, 8)
        let vd3 = makeItem("Vitamin D3", "VD3", created: created, sortIndex: 0)
        let fish = makeItem("Fish Oil", "FSH", created: created, sortIndex: 1)
        var state = StackState(items: [vd3, fish])
        state.settings.reminderEnabled = enabled
        state.settings.reminderMinutes = 21 * 60
        return (state, vd3, fish)
    }

    func testDisabledPlansNothing() {
        let (state, _, _) = makeState(enabled: false)
        XCTAssertTrue(Reminders.plan(state: state, now: at(2026, 10, 12, 9), timeZone: london).isEmpty)
    }

    func testFourteenDaysListingWhatIsPending() {
        var (state, vd3, _) = makeState(enabled: true)
        state.logDose(itemId: vd3.id, at: at(2026, 10, 12, 7, 42))
        let plans = Reminders.plan(state: state, now: at(2026, 10, 12, 9), timeZone: london)
        XCTAssertEqual(plans.count, 14)
        XCTAssertEqual(plans[0].body, "1 pending: FSH", "today lists only what is still pending")
        XCTAssertEqual(plans[1].body, "2 pending: VD3, FSH")
        XCTAssertEqual(plans[0].fireDate, at(2026, 10, 12, 21, 0))
        XCTAssertEqual(plans[0].components.hour, 21)
        XCTAssertEqual(Set(plans.map(\.identifier)).count, 14)
    }

    func testNoNudgeForAFinishedDay() {
        var (state, vd3, fish) = makeState(enabled: true)
        state.logDose(itemId: vd3.id, at: at(2026, 10, 12, 7, 42))
        state.logDose(itemId: fish.id, at: at(2026, 10, 12, 7, 42))
        let plans = Reminders.plan(state: state, now: at(2026, 10, 12, 9), timeZone: london)
        XCTAssertEqual(plans.count, 13, "today is done, so it has no nudge")
        XCTAssertEqual(plans.first?.day, DayKey(year: 2026, month: 10, day: 13))
    }

    func testPastNudgeTimeIsSkippedToday() {
        let (state, _, _) = makeState(enabled: true)
        let plans = Reminders.plan(state: state, now: at(2026, 10, 12, 22), timeZone: london)
        XCTAssertEqual(plans.first?.day, DayKey(year: 2026, month: 10, day: 13))
        XCTAssertEqual(plans.count, 13)
    }

    func testLongListIsTrimmed() {
        XCTAssertEqual(Reminders.body(for: ["A", "B", "C", "D", "E", "F"]), "6 pending: A, B, C, D +2")
    }
}
