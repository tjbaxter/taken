import XCTest
@testable import Taken

/// The one list (SPEC 3.10; Tom 2026-10-20: "I wanted it all under one tab"): Personal and Work as headed sections in
/// the order the person chose, each with its open tasks then its tasks done today, the line under the title counted
/// across both, and a dropped heading swapping the two. Pure rows, no view.
final class TodoSectionsTests: XCTestCase {
    private let clock = londonClock()
    private let now = at(2026, 10, 20, 14)
    private var today: DayKey { clock.day(for: now) }

    /// Personal: two open (one due), one done at 10:00, one at 12:00, one done yesterday. Work: one open with a time,
    /// one open, one done at 11:00.
    private func twoLists() -> (state: TodoState, ids: [String: UUID]) {
        var state = TodoState()
        var ids: [String: UUID] = [:]
        func add(_ title: String, due: TodoDue? = nil, area: TodoArea = .personal, at moment: Date) -> UUID {
            let id = state.add([TodoDraft(title: title, due: due)], area: area, at: moment)[0].id
            ids[title] = id
            return id
        }
        _ = add("Buy milk", at: at(2026, 10, 20, 8))
        _ = add("Renew the passport", due: .day(DayKey(year: 2026, month: 10, day: 22)), at: at(2026, 10, 20, 8, 5))
        let mum = add("Ring Mum", at: at(2026, 10, 20, 7))
        let cleaner = add("Pay the cleaner", at: at(2026, 10, 20, 7, 5))
        let plants = add("Water the plants", at: at(2026, 10, 19, 7))
        _ = add("Send the deck", due: .time(at(2026, 10, 20, 16)), area: .work, at: at(2026, 10, 20, 9))
        _ = add("Book the room", area: .work, at: at(2026, 10, 20, 9, 30))
        let dan = add("Reply to Dan", area: .work, at: at(2026, 10, 20, 8))
        state.complete(mum, at: at(2026, 10, 20, 10))
        state.complete(cleaner, at: at(2026, 10, 20, 12))
        state.complete(plants, at: at(2026, 10, 19, 20))
        state.complete(dan, at: at(2026, 10, 20, 11))
        return (state, ids)
    }

    private func titles(_ rows: [TodoSectionRow]) -> [String] {
        rows.map { $0.task?.title ?? "# \($0.area.title)" }
    }

    // MARK: Rows

    func testEachListIsAHeadingThenItsOpenTasksThenItsDoneToday() {
        let state = twoLists().state
        let rows = TodoSections.rows(state: state, day: today, clock: clock)
        XCTAssertEqual(titles(rows), ["# Personal", "Renew the passport", "Buy milk", "Pay the cleaner", "Ring Mum",
                                      "# Work", "Send the deck", "Book the room", "Reply to Dan"],
                       "open in the open list's order (due first), then done today newest first; yesterday's left out")
        XCTAssertEqual(rows.first?.id, .header(.personal))
        XCTAssertEqual(rows.filter(\.isHeader).map(\.openCount), [2, 2])
        XCTAssertTrue(rows.allSatisfy { $0.task == nil || $0.task?.area == $0.area }, "every task under its own list")
        XCTAssertEqual(Set(rows.map(\.id)).count, rows.count, "every row has its own identity")
    }

    func testTheRowsFollowTheOrderOfTheLists() {
        var state = twoLists().state
        state.setAreaOrder([.work, .personal])
        let rows = TodoSections.rows(state: state, day: today, clock: clock)
        XCTAssertEqual(titles(rows), ["# Work", "Send the deck", "Book the room", "Reply to Dan",
                                      "# Personal", "Renew the passport", "Buy milk", "Pay the cleaner", "Ring Mum"])
    }

    func testANoteBeingSortedIsLeftOut() throws {
        let (state, ids) = twoLists()
        let hidden = try XCTUnwrap(ids["Book the room"])
        let rows = TodoSections.rows(state: state, day: today, clock: clock, hiding: [hidden])
        XCTAssertFalse(rows.contains { $0.id == .task(hidden) })
        XCTAssertEqual(rows.first { $0.id == .header(.work) }?.openCount, 1, "nor counted")
        XCTAssertEqual(TodoSections.summary(rows), "3 open, 3 done today")
    }

    func testAnEmptyListKeepsItsHeadingWithNothingOpen() {
        var state = TodoState()
        state.add([TodoDraft(title: "Buy milk"), TodoDraft(title: "Ring Mum"), TodoDraft(title: "Book the car in")],
                  at: at(2026, 10, 20, 8))
        let rows = TodoSections.rows(state: state, day: today, clock: clock)
        XCTAssertEqual(titles(rows), ["# Personal", "Buy milk", "Ring Mum", "Book the car in", "# Work"])
        let work = rows.last
        XCTAssertEqual(work?.isHeader, true)
        XCTAssertEqual(work?.isEmpty, true, "Work says Nothing open")
        XCTAssertEqual(work?.openCount, 0)
        XCTAssertEqual(rows.first?.isEmpty, false)

        // A list with only tasks done today is not empty: they show under its heading.
        let done = state.add([TodoDraft(title: "Reply to Dan")], area: .work, at: at(2026, 10, 20, 9))[0]
        state.complete(done.id, at: at(2026, 10, 20, 10))
        let withDone = TodoSections.rows(state: state, day: today, clock: clock)
        XCTAssertEqual(withDone.first { $0.id == .header(.work) }?.isEmpty, false)
        XCTAssertEqual(titles(withDone).suffix(2), ["# Work", "Reply to Dan"])
    }

    func testNothingListedShowsNoHeadings() {
        XCTAssertEqual(TodoSections.rows(state: TodoState(), day: today, clock: clock), [])
        var state = TodoState()
        let old = state.add([TodoDraft(title: "Water the plants")], at: at(2026, 10, 19, 7))[0]
        state.complete(old.id, at: at(2026, 10, 19, 20))
        XCTAssertEqual(TodoSections.rows(state: state, day: today, clock: clock), [],
                       "only yesterday's done tasks: the line that teaches it shows instead")
        let open = state.add([TodoDraft(title: "Buy milk")], at: at(2026, 10, 20, 8))[0]
        XCTAssertEqual(TodoSections.rows(state: state, day: today, clock: clock, hiding: [open.id]), [],
                       "nor while the only note is still being sorted")
    }

    // MARK: The line under the title

    func testTheSummaryCountsBothLists() {
        XCTAssertEqual(TodoSections.summary(TodoSections.rows(state: twoLists().state, day: today, clock: clock)),
                       "4 open, 3 done today")
        XCTAssertEqual(TodoListCopy.summary(open: 4, doneToday: 2), "4 open, 2 done today")
        XCTAssertEqual(TodoListCopy.summary(open: 4, doneToday: 0), "4 open")
        XCTAssertEqual(TodoListCopy.summary(open: 0, doneToday: 2), "Nothing open, 2 done today")
        XCTAssertNil(TodoListCopy.summary(open: 0, doneToday: 0))

        var onlyWork = TodoState()
        onlyWork.add([TodoDraft(title: "Send the deck")], area: .work, at: at(2026, 10, 20, 9))
        XCTAssertEqual(TodoSections.summary(TodoSections.rows(state: onlyWork, day: today, clock: clock)), "1 open",
                       "a list empty on top never drops the line")
        XCTAssertNil(TodoSections.summary([]))
    }

    /// The bounce Tom saw: switching to an empty Work list dropped "3 open" from under the title. Nothing in the rows
    /// or the line reads the old list in view now, so changing it changes neither.
    func testTheOldListInViewChangesNoRowAndNoLine() {
        var state = TodoState()
        state.add([TodoDraft(title: "Buy milk"), TodoDraft(title: "Ring Mum"), TodoDraft(title: "Book the car in")],
                  at: at(2026, 10, 20, 8))
        let before = TodoSections.rows(state: state, day: today, clock: clock)
        state.lastArea = .work
        let after = TodoSections.rows(state: state, day: today, clock: clock)
        XCTAssertEqual(before, after)
        XCTAssertEqual(TodoSections.summary(after), "3 open")
        XCTAssertEqual(TodoSections.summary(before), TodoSections.summary(after))
    }

    // MARK: Moving a list

    func testADroppedHeadingTakesTheOtherListsPlace() {
        let personalFirst: [TodoArea] = [.personal, .work]
        XCTAssertEqual(TodoSections.order(personalFirst, dropping: .work, on: .personal), [.work, .personal],
                       "Work dropped on Personal goes on top")
        XCTAssertEqual(TodoSections.order(personalFirst, dropping: .personal, on: .work), [.work, .personal],
                       "Personal dropped on Work goes below it")
        XCTAssertEqual(TodoSections.order([.work, .personal], dropping: .personal, on: .work), [.personal, .work])
        XCTAssertEqual(TodoSections.order(personalFirst, dropping: .work, on: .work), personalFirst,
                       "dropped on its own list: nothing changes")
        XCTAssertEqual(TodoSections.order(personalFirst, dropping: .personal, on: .personal), personalFirst)
        XCTAssertEqual(TodoSections.order([.work], dropping: .work, on: .personal), [.personal, .work],
                       "the order is made whole first (Work, Personal), then the two swap")
    }

    func testTheMenuMovesAListToTheTopOrTheBottom() {
        XCTAssertEqual(TodoSections.order([.personal, .work], moving: .work, toTop: true), [.work, .personal])
        XCTAssertEqual(TodoSections.order([.work, .personal], moving: .work, toTop: false), [.personal, .work])
        XCTAssertEqual(TodoSections.order([.personal, .work], moving: .personal, toTop: true), [.personal, .work],
                       "already there")
        XCTAssertEqual(TodoSections.order([.personal, .work], moving: .work, toTop: false), [.personal, .work])
    }

    func testADraggedHeadingCarriesItsList() throws {
        for area in TodoArea.allCases {
            let data = try JSONEncoder().encode(TodoSectionDrag(area: area))
            XCTAssertEqual(try JSONDecoder().decode(TodoSectionDrag.self, from: data).area, area)
        }
    }

    // MARK: Copy

    func testTheListCopyKeepsTheRules() {
        XCTAssertEqual(TodoListCopy.nothingOpen, "Nothing open")
        XCTAssertEqual(TodoListCopy.headerLabel(.work, open: 2), "Work, 2 open")
        XCTAssertEqual(TodoListCopy.headerLabel(.work, open: 0), "Work, nothing open")
        XCTAssertEqual(TodoListCopy.moveToTop(.work), "Move Work to top")
        XCTAssertEqual(TodoListCopy.moveToBottom(.personal), "Move Personal to bottom")
        XCTAssertEqual(TodoListCopy.movedToTop(.work), "Work moved to the top.")
        XCTAssertEqual(TodoListCopy.movedToBottom(.work), "Work moved to the bottom.")
        for text in [TodoListCopy.headerHint, TodoListCopy.movedToTop(.personal), "4 open, 2 done today",
                     "Nothing open, 2 done today"] {
            XCTAssertTrue(TodoListCopy.all.contains(text), "\(text) is checked below")
        }
        for text in TodoListCopy.all {
            XCTAssertNil(text.range(of: "free", options: .caseInsensitive), text)
            XCTAssertFalse(text.contains("\u{2014}") || text.contains("\u{2013}"), "no em or en dash: \(text)")
            XCTAssertFalse(text.contains("!"), text)
        }
    }
}
