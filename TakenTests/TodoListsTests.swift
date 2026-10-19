import XCTest
@testable import Taken

/// Personal and Work to-do lists (REDESIGN.md, SPEC 3.10): kept apart, one in view at a time, the file stays readable
/// by every build, a note lands in the list in view, and the Lock Screen widget shows that list.
final class TodoListsTests: XCTestCase {

    // MARK: The file

    func testAFileFromBeforeListsLoadsWithEveryTaskPersonal() throws {
        let json = """
            {"schemaVersion":1,"tasks":[
              {"id":"6F1C2D3E-4A5B-4C6D-8E9F-0A1B2C3D4E5F","title":"Call the dentist","createdAt":1791000000},
              {"id":"7A1C2D3E-4A5B-4C6D-8E9F-0A1B2C3D4E5F","title":"Buy milk","createdAt":1791000000,"completedAt":1791050000}
            ],"firstNoteAt":1790000000}
            """
        let state = try TodoStore.decode(Data(json.utf8))
        XCTAssertEqual(state.tasks.map(\.area), [.personal, .personal], "every task saved before lists is Personal")
        XCTAssertEqual(state.lastArea, .personal, "and Personal is in view")
        XCTAssertEqual(state.firstNoteAt, Date(timeIntervalSince1970: 1790000000))
        XCTAssertEqual(state.schemaVersion, 1)

        let later = """
            {"tasks":[{"id":"8A1C2D3E-4A5B-4C6D-8E9F-0A1B2C3D4E5F","title":"Plan the party","createdAt":1791000000,
              "area":"family"}],"lastArea":"family"}
            """
        let unknown = try TodoStore.decode(Data(later.utf8))
        XCTAssertEqual(unknown.tasks.map(\.title), ["Plan the party"], "a list this build does not know never loses a task")
        XCTAssertEqual(unknown.tasks.first?.area, .personal)
        XCTAssertEqual(unknown.lastArea, .personal)
    }

    func testTheListAndTheListInViewRoundTrip() throws {
        let store = TodoStore(fileURL: temporaryStoreURL().deletingLastPathComponent().appendingPathComponent(TodoStore.fileName))
        var state = TodoState()
        state.add([TodoDraft(title: "Buy milk")], at: at(2026, 10, 19, 9))
        state.add([TodoDraft(title: "Send Priya the deck", due: .time(at(2026, 10, 20, 10)))], area: .work,
                  at: at(2026, 10, 19, 9, 30))
        state.lastArea = .work
        try store.replace(with: state)
        XCTAssertEqual(store.load(), state)
        XCTAssertEqual(store.load().tasks.map(\.area), [.personal, .work])
        XCTAssertEqual(store.load().lastArea, .work, "Taken reopens on the list last in view")

        let text = String(decoding: try TodoStore.encode(state), as: UTF8.self)
        XCTAssertTrue(text.contains(#""area":"personal""#), "the list is always written, Personal too: \(text)")
        XCTAssertTrue(text.contains(#""area":"work""#), text)
        XCTAssertTrue(text.contains(#""lastArea":"work""#), text)
        XCTAssertTrue(text.contains(#""schemaVersion":1"#), "an additive change: the schema stays 1: \(text)")
    }

    // MARK: Adding, sorting and moving

    func testANoteGoesToItsListAndItsSortedTasksStayThere() {
        var state = TodoState()
        let now = at(2026, 10, 19, 10)
        let whole = state.add(TodoValidation.wholeNote("email Sam the invoice and call the bank"), area: .work, at: now)[0]
        XCTAssertEqual(whole.area, .work)
        let sorted = state.replaceNote(whole.id, with: [TodoDraft(title: "Email Sam the invoice"),
                                                        TodoDraft(title: "Call the bank")], at: now)
        XCTAssertEqual(sorted.map(\.title), ["Email Sam the invoice", "Call the bank"])
        XCTAssertEqual(sorted.map(\.area), [.work, .work], "the model's tasks stay on the note's list")
        XCTAssertEqual(state.tasks.map(\.area), [.work, .work])

        let personal = state.add([TodoDraft(title: "Buy milk")], at: now)[0]
        XCTAssertEqual(personal.area, .personal, "no list given is Personal, as before lists")
    }

    func testMoveChangesOnlyTheListAndReportsWhetherItMoved() throws {
        var state = TodoState()
        let task = state.add([TodoDraft(title: "Reply to Dan", due: .day(DayKey(year: 2026, month: 10, day: 21)))],
                             at: at(2026, 10, 19, 10))[0]
        XCTAssertTrue(state.move(task.id, to: .work))
        let moved = try XCTUnwrap(state.task(task.id))
        XCTAssertEqual(moved.area, .work)
        XCTAssertEqual(moved.title, task.title)
        XCTAssertEqual(moved.due, task.due)
        XCTAssertEqual(moved.noteId, task.noteId)
        XCTAssertFalse(state.move(task.id, to: .work), "already there")
        XCTAssertFalse(state.move(UUID(), to: .personal), "a task that is gone")
        XCTAssertTrue(state.move(task.id, to: .personal))
        XCTAssertEqual(state.task(task.id)?.area, .personal)
    }

    func testEachListHasItsOwnOpenTasksAndDoneTodayAndNotificationsCoverBoth() {
        let clock = londonClock()
        var state = TodoState()
        let personal = state.add([TodoDraft(title: "Buy milk"), TodoDraft(title: "Ring Mum")], at: at(2026, 10, 19, 8))
        let work = state.add([TodoDraft(title: "Send the deck", due: .time(at(2026, 10, 19, 16))),
                              TodoDraft(title: "Book the room")], area: .work, at: at(2026, 10, 19, 9))
        state.complete(personal[1].id, at: at(2026, 10, 19, 12))
        state.complete(work[1].id, at: at(2026, 10, 19, 13))
        let today = clock.day(for: at(2026, 10, 19, 14))

        XCTAssertEqual(state.openTasks(in: .personal, clock: clock).map(\.title), ["Buy milk"])
        XCTAssertEqual(state.openTasks(in: .work, clock: clock).map(\.title), ["Send the deck"])
        XCTAssertEqual(state.doneTasks(on: today, in: .personal, clock: clock).map(\.title), ["Ring Mum"])
        XCTAssertEqual(state.doneTasks(on: today, in: .work, clock: clock).map(\.title), ["Book the room"])
        XCTAssertEqual(Set(state.openTasks(clock: clock).map(\.title)), ["Buy milk", "Send the deck"],
                       "every list, for the due-time notifications")
        XCTAssertEqual(TodoNotifications.plan(tasks: state.tasks, now: at(2026, 10, 19, 14), clock: clock).map(\.title),
                       ["Send the deck"], "a Work task with a time still gets its notification")
    }

    func testKeepAsOneKeepsTheNotesList() throws {
        var state = TodoState()
        let note = state.add([TodoDraft(title: "Email Sam"), TodoDraft(title: "Call the bank")], area: .work,
                             at: at(2026, 10, 19, 10))
        let merged = try XCTUnwrap(state.mergeNote(ids: note.map(\.id), title: "Email Sam and call the bank", due: nil))
        XCTAssertEqual(merged.area, .work)
        XCTAssertEqual(state.openTasks(in: .work, clock: londonClock()).map(\.title), ["Email Sam and call the bank"])
    }

    func testEraseAllBringsPersonalBackIntoView() {
        var state = TodoState(lastArea: .work)
        state.add([TodoDraft(title: "Send the deck")], area: .work, at: at(2026, 10, 19, 9))
        state.eraseAll()
        XCTAssertTrue(state.tasks.isEmpty)
        XCTAssertEqual(state.lastArea, .personal)
        XCTAssertEqual(state.firstNoteAt, at(2026, 10, 19, 9), "erasing never opens the first note again")
    }

    // MARK: The Lock Screen widget

    func testTheWidgetShowsTheListLastInView() {
        let clock = londonClock()
        let now = at(2026, 10, 19, 14)
        var state = TodoState()
        state.add([TodoDraft(title: "Buy milk")], at: at(2026, 10, 19, 8))
        state.add([TodoDraft(title: "Send the deck", due: .time(at(2026, 10, 19, 16))), TodoDraft(title: "Book the room")],
                  area: .work, at: at(2026, 10, 19, 9))

        let personal = TodoEntry(date: now, state: state, clock: clock)
        XCTAssertEqual(personal.area, .personal)
        XCTAssertEqual(personal.open, ["Buy milk"], "never a Work task on the Personal list")
        XCTAssertEqual(personal.openCount, 1)
        XCTAssertEqual(personal.header, "To-do \u{00B7} 1", "Personal reads as it did before lists")

        state.lastArea = .work
        let work = TodoEntry(date: now, state: state, clock: clock)
        XCTAssertEqual(work.area, .work)
        XCTAssertEqual(work.open, ["Send the deck", "Book the room"])
        XCTAssertEqual(work.openCount, 2)
        XCTAssertEqual(work.header, "Work \u{00B7} 2")

        XCTAssertEqual(TodoEntry(date: now, open: [], openCount: 0, area: .work).header, "Work")
        XCTAssertEqual(TodoEntry(date: now, open: [], openCount: 0).header, "To-do")
    }

    // MARK: Copy and the demo

    func testTheListCopyKeepsTheRules() {
        XCTAssertEqual(TodoArea.allCases.map(\.title), ["Personal", "Work"])
        XCTAssertEqual(TodoCopy.listeningLine(into: .work), "Listening \u{00B7} Work", "the destination shows before a word")
        XCTAssertEqual(TodoCopy.listeningLine(into: .personal), "Listening \u{00B7} Personal")
        XCTAssertEqual(TodoCopy.moveAction(to: .work), "Move to Work")
        XCTAssertEqual(TodoCopy.emptyLine(for: .personal), TodoCopy.empty, "Personal keeps today's line")
        XCTAssertEqual(TodoCopy.emptyLine(for: .work), "Tap the mic and say what needs doing for work")
        for text in [TodoCopy.emptyWork, TodoCopy.list, TodoCopy.keepAsOne, TodoCopy.keptAsOne, TodoCopy.fromYourNote(3)] {
            XCTAssertTrue(TodoCopy.all.contains(text), "\(text) is checked by the copy test")
        }
        XCTAssertEqual(TodoArea.personal.other, .work)
        XCTAssertEqual(TodoArea.work.other, .personal)
    }

    @MainActor
    func testTheDemoHasWorkTasksAndOpensOnTheListAsked() {
        let now = at(2026, 10, 19, 21, 41)
        let personal = TodoDemo.state(now: now, recording: false, timeZone: london)
        XCTAssertEqual(personal.lastArea, .personal)
        XCTAssertEqual(personal.tasks.filter { $0.area == .work }.count, 3)
        XCTAssertEqual(TodoDemo.state(now: now, recording: false, inView: .work, timeZone: london).lastArea, .work)
        XCTAssertTrue(TodoModel.opensOnTodo("todo-work"))
    }
}
