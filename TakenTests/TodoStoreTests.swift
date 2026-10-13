import XCTest
@testable import Taken

/// Voice to-dos: the store, the order of the list, carry-over, completion and the Pro rule (SPEC 3.10).
final class TodoStoreTests: XCTestCase {

    private func temporaryTodoStore() -> TodoStore {
        TodoStore(fileURL: temporaryStoreURL().deletingLastPathComponent().appendingPathComponent(TodoStore.fileName))
    }

    // MARK: Store

    func testRoundTrip() throws {
        let store = temporaryTodoStore()
        XCTAssertEqual(store.load(), TodoState(), "a missing file reads as no tasks")

        let now = at(2026, 10, 13, 9, 41)
        var state = TodoState()
        let added = state.add([TodoDraft(title: "Call the dentist", dueDate: at(2026, 10, 13, 16), hasTime: true),
                               TodoDraft(title: "Buy milk")], at: now)
        state.complete(added[1].id, at: at(2026, 10, 13, 10))
        XCTAssertEqual(state.firstNoteAt, now, "the first note is remembered")
        XCTAssertEqual(added.map(\.order), [0, 1], "a note keeps the order it was said in")
        XCTAssertEqual(Set(added.map(\.noteId)).count, 1, "one note, one id")

        try store.replace(with: state)
        XCTAssertEqual(store.load(), state)
        XCTAssertEqual(TodoStore(fileURL: store.fileURL).load(), state, "a second process sees the same tasks")
    }

    func testUpdateIsCoordinatedAndReturnsItsValue() throws {
        let store = temporaryTodoStore()
        let result = try store.update { state in
            state.add([TodoDraft(title: "Email Sam the deck")], at: at(2026, 10, 13, 9))
        }
        XCTAssertEqual(result.value.first?.title, "Email Sam the deck")
        XCTAssertEqual(store.load().tasks.count, 1)
    }

    func testDecodesOlderAndNewerFiles() throws {
        // Fields missing (an earlier version) or unknown (a later one) never cost a task; one unreadable task never
        // costs the others.
        let json = """
            {"tasks":[
              {"id":"6F1C2D3E-4A5B-4C6D-8E9F-0A1B2C3D4E5F","title":"Call the dentist","createdAt":1791000000},
              {"id":"7A1C2D3E-4A5B-4C6D-8E9F-0A1B2C3D4E5F","title":"Buy milk","dueDate":1791100000,"hasTime":true,
               "createdAt":1791000000,"completedAt":1791050000,"noteId":"8A1C2D3E-4A5B-4C6D-8E9F-0A1B2C3D4E5F",
               "order":1,"colour":"red"},
              {"id":"9A1C2D3E-4A5B-4C6D-8E9F-0A1B2C3D4E5F","title":"No due date","hasTime":true,"createdAt":1791000000},
              {"title":"","createdAt":1791000000},
              {"id":12,"title":"Broken id"}
            ],"futureKey":true}
            """
        let state = try TodoStore.decode(Data(json.utf8))
        XCTAssertEqual(state.tasks.map(\.title), ["Call the dentist", "Buy milk", "No due date"])
        let first = state.tasks[0]
        XCTAssertNil(first.dueDate)
        XCTAssertFalse(first.hasTime)
        XCTAssertNil(first.completedAt)
        XCTAssertEqual(first.noteId, first.id, "a task saved without a note is its own note")
        XCTAssertEqual(first.order, 0)
        XCTAssertTrue(state.tasks[1].hasTime)
        XCTAssertEqual(state.tasks[1].order, 1)
        XCTAssertNotNil(state.tasks[1].completedAt)
        XCTAssertFalse(state.tasks[2].hasTime, "no due date, no time")
        XCTAssertNil(state.firstNoteAt)
        XCTAssertEqual(state.schemaVersion, 1)
        XCTAssertEqual(try TodoStore.decode(Data("{}".utf8)), TodoState())
    }

    func testUnreadableFileIsKeptAsideNotOverwritten() throws {
        let store = temporaryTodoStore()
        try FileManager.default.createDirectory(at: store.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: store.fileURL)
        XCTAssertEqual(store.load(), TodoState())
        try store.update { $0.add([TodoDraft(title: "Buy milk")], at: Date()) }
        let siblings = try FileManager.default.contentsOfDirectory(atPath: store.fileURL.deletingLastPathComponent().path)
        XCTAssertTrue(siblings.contains { $0.hasPrefix("todos-unreadable-") }, "\(siblings)")
        XCTAssertEqual(store.load().tasks.count, 1)
    }

    // MARK: Order

    func testDueFirstSoonestFirstThenTheNewestNoteInTheOrderSaid() {
        let clock = londonClock()
        let morning = UUID()
        let evening = UUID()
        let early = at(2026, 10, 13, 8)
        let late = at(2026, 10, 13, 18)
        let tasks = [
            TodoTask(title: "Morning first", createdAt: early, noteId: morning, order: 0),
            TodoTask(title: "Morning second", createdAt: early, noteId: morning, order: 1),
            TodoTask(title: "Tomorrow, any time", dueDate: at(2026, 10, 14, 12), hasTime: false, createdAt: early,
                     noteId: morning, order: 2),
            TodoTask(title: "Tomorrow 09:00", dueDate: at(2026, 10, 14, 9), hasTime: true, createdAt: late,
                     noteId: evening, order: 0),
            TodoTask(title: "Today 16:00", dueDate: at(2026, 10, 13, 16), hasTime: true, createdAt: late,
                     noteId: evening, order: 1),
            TodoTask(title: "Evening, no time", createdAt: late, noteId: evening, order: 2),
            TodoTask(title: "Tomorrow 23:00", dueDate: at(2026, 10, 14, 23), hasTime: true, createdAt: late,
                     noteId: evening, order: 3),
        ]
        XCTAssertEqual(TodoState(tasks: tasks).openTasks(clock: clock).map(\.title), [
            "Today 16:00",
            "Tomorrow 09:00",
            "Tomorrow 23:00",
            "Tomorrow, any time",
            "Evening, no time",
            "Morning first",
            "Morning second",
        ])
    }

    // MARK: Carry-over and completion

    func testOpenTasksCarryOverAndDoneTodayIsTheDayBeingLived() {
        let clock = londonClock()
        var state = TodoState()
        let yesterday = state.add([TodoDraft(title: "Yesterday, still open"), TodoDraft(title: "Yesterday, done")],
                                  at: at(2026, 10, 12, 9))
        state.complete(yesterday[1].id, at: at(2026, 10, 12, 20))
        let today = state.add([TodoDraft(title: "Done this morning"), TodoDraft(title: "Done after midnight")],
                              at: at(2026, 10, 13, 9))
        state.complete(today[0].id, at: at(2026, 10, 13, 10))
        // 01:30 on the 14th is still the 13th with the day starting at 04:00, as it is for doses.
        state.complete(today[1].id, at: at(2026, 10, 14, 1, 30))

        let day = clock.day(for: at(2026, 10, 13, 21))
        XCTAssertEqual(state.openTasks(clock: clock).map(\.title), ["Yesterday, still open"],
                       "yesterday's open tasks stay until they are done")
        XCTAssertEqual(state.doneTasks(on: day, clock: clock).map(\.title), ["Done after midnight", "Done this morning"],
                       "Done today: newest first, nothing from yesterday")
        XCTAssertEqual(state.doneTasks(on: day.adding(-1), clock: clock).map(\.title), ["Yesterday, done"])
    }

    func testCompleteReopenEditDeleteAndRestore() throws {
        var state = TodoState()
        let id = state.add([TodoDraft(title: "Call the dentist")], at: at(2026, 10, 13, 9))[0].id

        state.complete(id, at: at(2026, 10, 13, 10))
        state.complete(id, at: at(2026, 10, 13, 11))
        XCTAssertEqual(state.task(id)?.completedAt, at(2026, 10, 13, 10), "done twice keeps the first time")
        state.reopen(id)
        XCTAssertNil(state.task(id)?.completedAt, "a tap on the check opens it again")

        state.update(id, title: "  call the dentist about the filling. ", dueDate: at(2026, 10, 14, 9), hasTime: true)
        XCTAssertEqual(state.task(id)?.title, "Call the dentist about the filling")
        XCTAssertEqual(state.task(id)?.dueDate, at(2026, 10, 14, 9))
        XCTAssertEqual(state.task(id)?.hasTime, true)
        state.update(id, title: "   ", dueDate: nil, hasTime: true)
        XCTAssertEqual(state.task(id)?.title, "Call the dentist about the filling", "an empty title keeps the old one")
        XCTAssertNil(state.task(id)?.dueDate)
        XCTAssertEqual(state.task(id)?.hasTime, false, "no due date, no time")

        let removed = try XCTUnwrap(state.delete(id))
        XCTAssertNil(state.task(id))
        state.restore(removed)
        state.restore(removed)
        XCTAssertEqual(state.tasks.filter { $0.id == id }.count, 1, "UNDO puts it back once")
    }

    func testOldDoneTasksArePrunedAndEraseNeverGivesTheFirstNoteBack() {
        var state = TodoState()
        let september = state.add([TodoDraft(title: "Old and done"), TodoDraft(title: "Old and open")],
                                  at: at(2026, 9, 1, 9))
        state.complete(september[0].id, at: at(2026, 9, 1, 10))
        state.add([TodoDraft(title: "New")], at: at(2026, 10, 13, 9))
        XCTAssertEqual(state.tasks.map(\.title), ["Old and open", "New"],
                       "done more than 30 days ago is dropped; an open task never is")
        XCTAssertEqual(state.firstNoteAt, at(2026, 9, 1, 9), "the first note, not the latest")

        state.eraseAll()
        XCTAssertTrue(state.tasks.isEmpty)
        XCTAssertEqual(state.firstNoteAt, at(2026, 9, 1, 9), "erasing never opens the first note again")
    }

    func testAnEmptyNoteIsNotTheFirstNote() {
        var state = TodoState()
        XCTAssertTrue(state.add([], at: at(2026, 10, 13, 9)).isEmpty)
        XCTAssertNil(state.firstNoteAt)
    }

    // MARK: Taken Pro

    func testTheFirstVoiceNoteNeedsNoProAfterThatTheMicDoes() {
        let now = at(2026, 10, 13, 9)
        XCTAssertEqual(TodoGate.access(firstNoteAt: nil, status: nil, settled: true, legacyLog: false, now: now),
                       .firstSession, "the first note is on the house")
        XCTAssertEqual(TodoGate.access(firstNoteAt: now, status: nil, settled: true, legacyLog: false, now: now), .locked)
        XCTAssertEqual(TodoGate.access(firstNoteAt: now, status: .notPro(checkedAt: now), settled: true,
                                       legacyLog: false, now: now), .locked)
        let lifetime = ProStatus(isPro: true, reason: .lifetime, checkedAt: now)
        XCTAssertEqual(TodoGate.access(firstNoteAt: now, status: lifetime, settled: true, legacyLog: false, now: now), .pro)
        let ended = ProStatus(isPro: true, reason: .monthly, checkedAt: now, expiresAt: at(2026, 10, 1, 9), willRenew: false)
        XCTAssertEqual(TodoGate.access(firstNoteAt: now, status: ended, settled: true, legacyLog: false, now: now), .locked)
        XCTAssertEqual(TodoGate.access(firstNoteAt: now, status: nil, settled: false, legacyLog: false, now: now),
                       .checking, "never locked before StoreKit's first answer")
        XCTAssertEqual(TodoGate.access(firstNoteAt: now, status: nil, settled: true, legacyLog: true, now: now),
                       .pending, "a log from 1.0 (a founding member) is never locked out on a guess")
    }

    // MARK: Reading

    func testDueLabels() {
        let clock = londonClock()
        let now = at(2026, 10, 13, 9, 41) // Tuesday
        func label(_ due: Date?, _ hasTime: Bool, now: Date = at(2026, 10, 13, 9, 41)) -> String? {
            TodoText.dueLabel(TodoTask(title: "x", dueDate: due, hasTime: hasTime, createdAt: now, noteId: UUID()),
                              now: now, clock: clock)
        }
        XCTAssertNil(label(nil, false))
        XCTAssertEqual(label(at(2026, 10, 13, 16), true), "16:00")
        XCTAssertEqual(label(at(2026, 10, 13, 12), false), "Today")
        XCTAssertEqual(label(at(2026, 10, 14, 9), true), "Tomorrow 09:00")
        XCTAssertEqual(label(at(2026, 10, 14, 12), false), "Tomorrow")
        XCTAssertEqual(label(at(2026, 10, 16, 12), false), "Fri")
        XCTAssertEqual(label(at(2026, 10, 16, 14, 30), true), "Fri 14:30")
        XCTAssertEqual(label(at(2026, 10, 25, 12), false), "25 Oct")
        XCTAssertEqual(label(at(2026, 10, 12, 12), false), "Yesterday")
        // 01:30 on Wednesday is still Tuesday's day: Wednesday 09:00 is tomorrow, Wednesday 02:00 is today.
        let late = at(2026, 10, 14, 1, 30)
        XCTAssertEqual(label(at(2026, 10, 14, 9), true, now: late), "Tomorrow 09:00")
        XCTAssertEqual(label(at(2026, 10, 14, 2), true, now: late), "02:00")

        func overdue(_ due: Date, _ hasTime: Bool) -> Bool {
            TodoText.isOverdue(TodoTask(title: "x", dueDate: due, hasTime: hasTime, createdAt: now, noteId: UUID()),
                               now: now, clock: clock)
        }
        XCTAssertTrue(overdue(at(2026, 10, 13, 9), true))
        XCTAssertFalse(overdue(at(2026, 10, 13, 10), true))
        XCTAssertFalse(overdue(at(2026, 10, 13, 12), false), "today, any time, is not late yet")
        XCTAssertTrue(overdue(at(2026, 10, 12, 12), false))
    }

    func testDueTimeRemindersOnlyForOpenTasksWithATimeStillToCome() {
        let now = at(2026, 10, 13, 9, 41)
        let tasks = [
            TodoTask(title: "Call the dentist", dueDate: at(2026, 10, 13, 16), hasTime: true, createdAt: now, noteId: UUID()),
            TodoTask(title: "Already past", dueDate: at(2026, 10, 13, 9), hasTime: true, createdAt: now, noteId: UUID()),
            TodoTask(title: "Any time tomorrow", dueDate: at(2026, 10, 14, 12), hasTime: false, createdAt: now, noteId: UUID()),
            TodoTask(title: "Done", dueDate: at(2026, 10, 13, 18), hasTime: true, createdAt: now, completedAt: now,
                     noteId: UUID()),
            TodoTask(title: "Tomorrow at nine", dueDate: at(2026, 10, 14, 9), hasTime: true, createdAt: now, noteId: UUID()),
        ]
        let plans = TodoNotifications.plan(tasks: tasks, now: now, clock: londonClock())
        XCTAssertEqual(plans.map(\.title), ["Call the dentist", "Tomorrow at nine"])
        XCTAssertEqual(plans.first?.fireDate, at(2026, 10, 13, 16))
        XCTAssertEqual(plans.first?.body, "Due 16:00")
        XCTAssertTrue(plans.allSatisfy { TodoNotifications.isTodo($0.identifier) })
        XCTAssertFalse(TodoNotifications.isTodo(Reminders.requestPrefix + "20738"), "never the nudge's")
    }

    func testListeningStopsAfterAPauseOrWhenNothingIsSaid() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertFalse(TodoModel.shouldStop(now: start + 1.0, startedAt: start, lastVoiceAt: start + 0.5, heardWords: true))
        XCTAssertTrue(TodoModel.shouldStop(now: start + 2.1, startedAt: start, lastVoiceAt: start + 0.5, heardWords: true),
                      "about 1.5 s of quiet after speech")
        XCTAssertFalse(TodoModel.shouldStop(now: start + 5, startedAt: start, lastVoiceAt: start, heardWords: false),
                       "waits for the first words")
        XCTAssertTrue(TodoModel.shouldStop(now: start + 8.5, startedAt: start, lastVoiceAt: start, heardWords: false))
        XCTAssertTrue(TodoModel.shouldStop(now: start + 121, startedAt: start, lastVoiceAt: start + 120.9, heardWords: true),
                      "two minutes at most")
    }
}
