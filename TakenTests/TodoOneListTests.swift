import XCTest
@testable import Taken

/// One list again (SPEC 3.10, Tom 2026-10-21: "just having one list as we originally did is best"): every task is on one
/// list, whatever list a 1.1 internal build put it on; the list values those builds wrote (`area` on each task,
/// `lastArea`, `areaOrder`) still decode and round-trip unchanged, and nothing reads them; new tasks are Personal; the
/// Lock Screen widget and the demo are the one list.
final class TodoOneListTests: XCTestCase {
    private let clock = londonClock()

    private func temporaryTodoStore() -> TodoStore {
        TodoStore(fileURL: temporaryStoreURL().deletingLastPathComponent().appendingPathComponent(TodoStore.fileName))
    }

    /// todos.json as a 1.1 internal build with Personal and Work wrote it (`TodoStore.encode` sorts the keys): Work on
    /// top and in view, Tom's "LinkedIn ICP" on Work, a dentist call on Personal, and a Work task done.
    private let listBuildFile = """
        {"areaOrder":["work","personal"],"firstNoteAt":1790000000,"lastArea":"work","schemaVersion":1,"tasks":[
        {"area":"work","createdAt":1791000000,"id":"6F1C2D3E-4A5B-4C6D-8E9F-0A1B2C3D4E5F",\
        "noteId":"6F1C2D3E-4A5B-4C6D-8E9F-0A1B2C3D4E5F","order":0,"title":"LinkedIn ICP"},
        {"area":"personal","createdAt":1791000100,"dueAt":1791100000,"id":"7A1C2D3E-4A5B-4C6D-8E9F-0A1B2C3D4E5F",\
        "noteId":"7A1C2D3E-4A5B-4C6D-8E9F-0A1B2C3D4E5F","order":0,"title":"Call the dentist"},
        {"area":"work","completedAt":1791050000,"createdAt":1790990000,"dueDay":"2026-10-21",\
        "id":"8A1C2D3E-4A5B-4C6D-8E9F-0A1B2C3D4E5F","noteId":"8A1C2D3E-4A5B-4C6D-8E9F-0A1B2C3D4E5F","order":0,\
        "title":"Send Priya the deck"}
        ]}
        """

    // MARK: The file

    func testAFileTheListBuildsWroteDecodesAndRoundTripsUnchanged() throws {
        let data = Data(listBuildFile.utf8)
        let state = try TodoStore.decode(data)
        XCTAssertEqual(state.tasks.map(\.title), ["LinkedIn ICP", "Call the dentist", "Send Priya the deck"])
        XCTAssertEqual(state.tasks.map(\.area), [.work, .personal, .work], "each task's list is kept as it was")
        XCTAssertEqual(state.lastArea, .work)
        XCTAssertEqual(state.areaOrder, [.work, .personal])
        XCTAssertEqual(state.schemaVersion, 1)

        let written = try TodoStore.encode(state)
        XCTAssertEqual(try TodoStore.decode(written), state)
        let before = try JSONSerialization.jsonObject(with: data) as? NSDictionary
        let after = try JSONSerialization.jsonObject(with: written) as? NSDictionary
        XCTAssertNotNil(before)
        XCTAssertEqual(before, after, "every key and value as the list builds wrote them, so builds 9 to 20 read it the same")

        // A change made in this build keeps them too.
        let store = temporaryTodoStore()
        try store.replace(with: state)
        let dentist = try XCTUnwrap(state.tasks.first { $0.title == "Call the dentist" })
        try store.update { $0.complete(dentist.id, at: at(2026, 10, 21, 9)) }
        try store.update { $0.add([TodoDraft(title: "Buy milk")], at: at(2026, 10, 21, 9, 5)) }
        let changed = store.load()
        XCTAssertEqual(changed.lastArea, .work)
        XCTAssertEqual(changed.areaOrder, [.work, .personal])
        XCTAssertEqual(changed.tasks.map(\.area), [.work, .personal, .work, .personal], "a new task is Personal")
        let text = String(decoding: try TodoStore.encode(changed), as: UTF8.self)
        XCTAssertTrue(text.contains(#""areaOrder":["work","personal"]"#), text)
        XCTAssertTrue(text.contains(#""lastArea":"work""#), text)
        XCTAssertTrue(text.contains(#""area":"work""#), text)
    }

    func testAFileFromBeforeListsLoadsWithEveryTaskPersonal() throws {
        let json = """
            {"schemaVersion":1,"tasks":[
              {"id":"6F1C2D3E-4A5B-4C6D-8E9F-0A1B2C3D4E5F","title":"Call the dentist","createdAt":1791000000},
              {"id":"7A1C2D3E-4A5B-4C6D-8E9F-0A1B2C3D4E5F","title":"Buy milk","createdAt":1791000000,"completedAt":1791050000}
            ],"firstNoteAt":1790000000}
            """
        let state = try TodoStore.decode(Data(json.utf8))
        XCTAssertEqual(state.tasks.map(\.area), [.personal, .personal])
        XCTAssertEqual(state.lastArea, .personal)
        XCTAssertEqual(state.areaOrder, [.personal, .work])
        let text = String(decoding: try TodoStore.encode(state), as: UTF8.self)
        XCTAssertTrue(text.contains(#""areaOrder":["personal","work"]"#), "written as the list builds wrote it: \(text)")

        let later = """
            {"tasks":[{"id":"8A1C2D3E-4A5B-4C6D-8E9F-0A1B2C3D4E5F","title":"Plan the party","createdAt":1791000000,
              "area":"family"}],"lastArea":"family","areaOrder":["family","work","work"]}
            """
        let unknown = try TodoStore.decode(Data(later.utf8))
        XCTAssertEqual(unknown.tasks.map(\.title), ["Plan the party"], "a list this build does not know never loses a task")
        XCTAssertEqual(unknown.tasks.first?.area, .personal)
        XCTAssertEqual(unknown.lastArea, .personal)
        XCTAssertEqual(unknown.areaOrder, [.work, .personal], "every list once, as the list builds read it")
    }

    func testAnUnreadableOrderStillLoadsEveryTask() throws {
        for order in [#""work""#, "3", "true", #"{"top":"work"}"#, #"["work",3]"#, "null"] {
            let json = #"{"tasks":[{"id":"6F1C2D3E-4A5B-4C6D-8E9F-0A1B2C3D4E5F","title":"Call the dentist","createdAt":1791000000,"area":"work"}],"areaOrder":\#(order)}"#
            let state = try TodoStore.decode(Data(json.utf8))
            XCTAssertEqual(state.tasks.map(\.title), ["Call the dentist"], order)
            XCTAssertEqual(state.tasks.first?.area, .work, order)
            XCTAssertEqual(state.areaOrder, [.personal, .work], order)
        }
    }

    // MARK: One list

    /// Tasks Tom has on Work ("LinkedIn ICP") are on the one list with the rest, in the open list's order: due first,
    /// then the newest note first. Neither the old order nor the old list in view changes anything.
    func testFormerWorkTasksShowOnTheOneListInItsOrder() {
        var state = TodoState(lastArea: .work, areaOrder: [.work, .personal])
        state.add([TodoDraft(title: "Buy milk")], at: at(2026, 10, 21, 8))
        state.tasks.append(TodoTask(title: "LinkedIn ICP", createdAt: at(2026, 10, 20, 17, 18), noteId: UUID(), area: .work))
        state.tasks.append(TodoTask(title: "Send the deck", due: .time(at(2026, 10, 21, 16)), createdAt: at(2026, 10, 21, 7),
                                    noteId: UUID(), area: .work))
        let done = TodoTask(title: "Reply to Dan", createdAt: at(2026, 10, 21, 7), completedAt: at(2026, 10, 21, 11),
                            noteId: UUID(), area: .work)
        state.tasks.append(done)
        let ring = state.add([TodoDraft(title: "Ring Mum")], at: at(2026, 10, 21, 8, 30))[0]
        state.complete(ring.id, at: at(2026, 10, 21, 12))
        let today = clock.day(for: at(2026, 10, 21, 14))

        XCTAssertEqual(state.openTasks(clock: clock).map(\.title), ["Send the deck", "Buy milk", "LinkedIn ICP"])
        XCTAssertEqual(state.doneTasks(on: today, clock: clock).map(\.title), ["Ring Mum", "Reply to Dan"])
        XCTAssertEqual(TodoCopy.summary(open: state.openTasks(clock: clock).count,
                                        doneToday: state.doneTasks(on: today, clock: clock).count),
                       "3 open, 2 done today")

        var other = state
        other.lastArea = .personal
        XCTAssertEqual(other.openTasks(clock: clock), state.openTasks(clock: clock), "the old list in view changes nothing")
        let reordered = TodoState(tasks: state.tasks, lastArea: .personal, areaOrder: [.personal, .work])
        XCTAssertEqual(reordered.openTasks(clock: clock), state.openTasks(clock: clock), "nor the old order")
        XCTAssertEqual(TodoNotifications.plan(tasks: state.tasks, now: at(2026, 10, 21, 14), clock: clock).map(\.title),
                       ["Send the deck"], "a former Work task with a time still gets its notification")
    }

    func testANewTaskIsPersonalAndKeepAsOneKeepsTheFirstTask() throws {
        var state = TodoState(lastArea: .work, areaOrder: [.work, .personal])
        let added = state.add([TodoDraft(title: "Email Sam"), TodoDraft(title: "Call the bank")], at: at(2026, 10, 21, 10))
        XCTAssertEqual(added.map(\.area), [.personal, .personal], "never the old list in view or the one on top")
        let merged = try XCTUnwrap(state.mergeNote(ids: added.map(\.id), title: "Email Sam and call the bank", due: nil))
        XCTAssertEqual(merged.id, added[0].id)
        XCTAssertEqual(state.openTasks(clock: clock).map(\.title), ["Email Sam and call the bank"])
    }

    func testEraseAllPutsTheStoredListValuesBack() {
        var state = TodoState(lastArea: .work, areaOrder: [.work, .personal])
        state.add([TodoDraft(title: "Send the deck")], at: at(2026, 10, 21, 9))
        state.eraseAll()
        XCTAssertTrue(state.tasks.isEmpty)
        XCTAssertEqual(state.lastArea, .personal)
        XCTAssertEqual(state.areaOrder, TodoState.defaultAreaOrder)
        XCTAssertEqual(state.firstNoteAt, at(2026, 10, 21, 9), "erasing never opens the first note again")
    }

    // MARK: The Lock Screen widget

    /// Replaces testTheWidgetShowsBothListsInTheAppsOrder: the widget is the one list, due first, with one count.
    func testTheWidgetIsTheOneList() {
        let now = at(2026, 10, 21, 14)
        var state = TodoState(lastArea: .work, areaOrder: [.work, .personal])
        state.add([TodoDraft(title: "Buy milk")], at: at(2026, 10, 21, 8))
        state.tasks.append(TodoTask(title: "Send the deck", due: .time(at(2026, 10, 21, 16)), createdAt: at(2026, 10, 21, 9),
                                    noteId: UUID(), area: .work))
        state.tasks.append(TodoTask(title: "Book the room", createdAt: at(2026, 10, 21, 9), noteId: UUID(), area: .work))

        let entry = TodoEntry(date: now, state: state, clock: clock)
        XCTAssertEqual(entry.open, ["Send the deck", "Book the room", "Buy milk"], "the To-do tab's order")
        XCTAssertEqual(entry.openCount, 3)
        XCTAssertEqual(entry.header, "To-do \u{00B7} 3")
        let personalFirst = TodoState(tasks: state.tasks, lastArea: .personal, areaOrder: [.personal, .work])
        XCTAssertEqual(TodoEntry(date: now, state: personalFirst, clock: clock).open, entry.open, "no list decides anything")

        state.add((1...5).map { TodoDraft(title: "Task \($0)") }, at: at(2026, 10, 21, 10))
        XCTAssertEqual(TodoEntry(date: now, state: state, clock: clock).open.count, 3, "at most three titles")
        XCTAssertEqual(TodoEntry(date: now, state: state, clock: clock).openCount, 8)
        XCTAssertEqual(TodoEntry(date: now, state: TodoState(), clock: clock).header, "To-do")
    }

    // MARK: Copy and the demo

    func testTheLineUnderTheTitleAndDoneTodayAreAsBefore() {
        XCTAssertEqual(TodoCopy.summary(open: 3, doneToday: 2), "3 open, 2 done today")
        XCTAssertEqual(TodoCopy.summary(open: 3, doneToday: 0), "3 open")
        XCTAssertEqual(TodoCopy.summary(open: 0, doneToday: 2), "0 open, 2 done today")
        XCTAssertNil(TodoCopy.summary(open: 0, doneToday: 0), "nothing listed: the line that teaches it instead")
        XCTAssertEqual(TodoCopy.doneToday, "Done today")
        XCTAssertEqual(TodoCopy.empty, "Tap the mic and say what you need to do")
        for text in [TodoCopy.doneToday, "3 open, 2 done today", "0 open, 2 done today", TodoCopy.keepAsOne] {
            XCTAssertTrue(TodoCopy.all.contains(text), "\(text) is checked by the copy test")
        }
        XCTAssertFalse(TodoCopy.all.contains { $0.contains("Personal") || $0.contains("Work") }, "no list in any line")
    }

    /// One list with a Done today group, in every listening screen too.
    func testTheDemoSeedsOneListWithDoneToday() {
        let now = at(2026, 10, 19, 21, 41)
        let clock = londonClock(4)
        let state = TodoDemo.state(now: now, recording: false, timeZone: london)
        XCTAssertTrue(state.tasks.allSatisfy { $0.area == .personal })
        XCTAssertEqual(state.areaOrder, TodoState.defaultAreaOrder)
        XCTAssertEqual(state.openTasks(clock: clock).map(\.title),
                       ["Take the bins out", "Call the dentist", "Pick up the dry cleaning", "Email Sam the deck",
                        "Renew the car insurance", "Book flights for March", "Send Mum the photos"])
        XCTAssertEqual(state.doneTasks(on: clock.day(for: now), clock: clock).map(\.title),
                       ["Buy milk", "Pay the window cleaner"])
        let recording = TodoDemo.state(now: now, recording: true, timeZone: london)
        XCTAssertEqual(recording.openTasks(clock: clock).count, 3, "the note being said is not on the list yet")
        for screen in ["todo", "todo-recording", "todo-cap", "todo-empty"] {
            XCTAssertTrue(TodoModel.opensOnTodo(screen), screen)
        }
    }
}
