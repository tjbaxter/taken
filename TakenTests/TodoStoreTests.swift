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
        let added = state.add([TodoDraft(title: "Call the dentist", due: .time(at(2026, 10, 13, 16))),
                               TodoDraft(title: "Renew the passport", due: .day(DayKey(year: 2026, month: 10, day: 16))),
                               TodoDraft(title: "Buy milk")], at: now)
        state.complete(added[2].id, at: at(2026, 10, 13, 10))
        XCTAssertEqual(state.firstNoteAt, now, "the first note is remembered")
        XCTAssertEqual(added.map(\.order), [0, 1, 2], "a note keeps the order it was said in")
        XCTAssertEqual(Set(added.map(\.noteId)).count, 1, "one note, one id")

        try store.replace(with: state)
        XCTAssertEqual(store.load(), state)
        XCTAssertEqual(TodoStore(fileURL: store.fileURL).load(), state, "a second process sees the same tasks")
        let text = String(decoding: try TodoStore.encode(state), as: UTF8.self)
        XCTAssertTrue(text.contains(#""dueDay":"2026-10-16""#), "a day alone is stored as that date: \(text)")
        XCTAssertFalse(text.contains("hasTime"), text)
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
        XCTAssertNil(first.due)
        XCTAssertFalse(first.hasTime)
        XCTAssertNil(first.completedAt)
        XCTAssertEqual(first.noteId, first.id, "a task saved without a note is its own note")
        XCTAssertEqual(first.order, 0)
        XCTAssertTrue(state.tasks[1].hasTime, "a file from before 1.1 shipped: dueDate with hasTime is a time")
        XCTAssertEqual(state.tasks[1].due, .time(Date(timeIntervalSince1970: 1791100000)))
        XCTAssertEqual(state.tasks[1].order, 1)
        XCTAssertNotNil(state.tasks[1].completedAt)
        XCTAssertFalse(state.tasks[2].hasTime, "no due date, no time")
        XCTAssertNil(state.firstNoteAt)
        XCTAssertEqual(state.schemaVersion, 1)
        XCTAssertEqual(try TodoStore.decode(Data("{}".utf8)), TodoState())

        let current = """
            {"tasks":[
              {"id":"6F1C2D3E-4A5B-4C6D-8E9F-0A1B2C3D4E5F","title":"Call Sam","dueAt":1791100000,"createdAt":1791000000},
              {"id":"7A1C2D3E-4A5B-4C6D-8E9F-0A1B2C3D4E5F","title":"Renew the passport","dueDay":"2026-10-16","createdAt":1791000000},
              {"id":"8A1C2D3E-4A5B-4C6D-8E9F-0A1B2C3D4E5F","title":"Bad day","dueDay":"2026-02-31","createdAt":1791000000}
            ]}
            """
        let tasks = try TodoStore.decode(Data(current.utf8)).tasks
        XCTAssertEqual(tasks[0].due, .time(Date(timeIntervalSince1970: 1791100000)))
        XCTAssertEqual(tasks[1].due, .day(DayKey(year: 2026, month: 10, day: 16)))
        XCTAssertNil(tasks[2].due, "a day that does not exist is no due date, and the task stays")
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
            TodoTask(title: "Tomorrow, any time", due: .day(DayKey(year: 2026, month: 10, day: 14)), createdAt: early,
                     noteId: morning, order: 2),
            TodoTask(title: "Tomorrow 09:00", due: .time(at(2026, 10, 14, 9)), createdAt: late,
                     noteId: evening, order: 0),
            TodoTask(title: "Today 16:00", due: .time(at(2026, 10, 13, 16)), createdAt: late,
                     noteId: evening, order: 1),
            TodoTask(title: "Evening, no time", createdAt: late, noteId: evening, order: 2),
            TodoTask(title: "Tomorrow 23:00", due: .time(at(2026, 10, 14, 23)), createdAt: late,
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

        state.update(id, title: "  call the dentist about the filling. ", due: .time(at(2026, 10, 14, 9)))
        XCTAssertEqual(state.task(id)?.title, "Call the dentist about the filling")
        XCTAssertEqual(state.task(id)?.due, .time(at(2026, 10, 14, 9)))
        XCTAssertEqual(state.task(id)?.hasTime, true)
        state.update(id, title: "   ", due: nil)
        XCTAssertEqual(state.task(id)?.title, "Call the dentist about the filling", "an empty title keeps the old one")
        XCTAssertNil(state.task(id)?.due)
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
            TodoText.dueLabel(TodoTask(title: "x", due: due.map { make($0, hasTime) }, createdAt: now, noteId: UUID()),
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
            TodoText.isOverdue(TodoTask(title: "x", due: make(due, hasTime), createdAt: now, noteId: UUID()),
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
            TodoTask(title: "Call the dentist", due: .time(at(2026, 10, 13, 16)), createdAt: now, noteId: UUID()),
            TodoTask(title: "Already past", due: .time(at(2026, 10, 13, 9)), createdAt: now, noteId: UUID()),
            TodoTask(title: "Any time tomorrow", due: .day(DayKey(year: 2026, month: 10, day: 14)), createdAt: now,
                     noteId: UUID()),
            TodoTask(title: "Done", due: .time(at(2026, 10, 13, 18)), createdAt: now, completedAt: now, noteId: UUID()),
            TodoTask(title: "Tomorrow at nine", due: .time(at(2026, 10, 14, 9)), createdAt: now, noteId: UUID()),
        ]
        let plans = TodoNotifications.plan(tasks: tasks, now: now, clock: londonClock())
        XCTAssertEqual(plans.map(\.title), ["Call the dentist", "Tomorrow at nine"])
        XCTAssertEqual(plans.first?.fireDate, at(2026, 10, 13, 16))
        XCTAssertEqual(plans.first?.body, "Due 16:00")
        XCTAssertTrue(plans.allSatisfy { TodoNotifications.isTodo($0.identifier) })
        XCTAssertFalse(TodoNotifications.isTodo(Reminders.requestPrefix + "20738"), "never the nudge's")
    }

    // Replaces testListeningStopsAfterAPauseOrWhenNothingIsSaid: a pause no longer ends a note (Tom, 20 Oct 2026: cut
    // off at his first pause). A tap finishes it; 30 s of quiet or 5 minutes stop it.
    func testATapFinishesANoteAndOnlyThirtySecondsOfQuietOrFiveMinutesStopIt() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        func stop(_ now: TimeInterval, lastVoice: TimeInterval) -> TodoStopReason? {
            TodoModel.shouldStop(now: start + now, startedAt: start, lastVoiceAt: start + lastVoice)
        }
        XCTAssertNil(stop(12, lastVoice: 10), "2 s of quiet after words: still listening")
        XCTAssertNil(stop(20, lastVoice: 10), "10 s")
        XCTAssertNil(stop(39.9, lastVoice: 10), "29.9 s")
        XCTAssertNil(stop(29.9, lastVoice: 0), "29.9 s with nothing said")
        XCTAssertEqual(stop(30, lastVoice: 0), .quiet, "30 s with nothing said")
        XCTAssertEqual(stop(70, lastVoice: 40), .quiet, "30 s of quiet after words")
        XCTAssertNil(stop(299, lastVoice: 298.9), "talking at 4:59")
        XCTAssertEqual(stop(300, lastVoice: 299.9), .cap, "5 minutes at most, even mid-sentence")
        XCTAssertFalse(TodoModel.capWarning(elapsed: 239.9))
        XCTAssertTrue(TodoModel.capWarning(elapsed: 240), "the countdown from 4:00")
        XCTAssertEqual(TodoModel.silenceToStop, 30)
        XCTAssertEqual(TodoModel.longestNote, 300)
    }

    func testTheListeningCardTimeAndTheScreenStayingOn() {
        XCTAssertEqual(TodoCopy.elapsed(12), "0:12")
        XCTAssertEqual(TodoCopy.elapsed(102), "1:42")
        XCTAssertEqual(TodoCopy.timeLeft(60), "1:00 left")
        XCTAssertEqual(TodoCopy.timeLeft(1), "0:01 left")
        XCTAssertEqual(TodoCopy.spokenElapsed(130), "2 minutes 10 seconds")
        XCTAssertEqual(TodoCopy.spokenElapsed(60), "1 minute")
        XCTAssertEqual(TodoCopy.spokenTimeLeft(45), "45 seconds left")
        XCTAssertEqual(TodoCopy.noteTime(elapsed: 102.4).text, "1:42")
        XCTAssertFalse(TodoCopy.noteTime(elapsed: 102.4).countdown)
        XCTAssertEqual(TodoCopy.noteTime(elapsed: 260).text, "0:40 left", "the todo-cap screenshot")
        XCTAssertTrue(TodoCopy.noteTime(elapsed: 260).countdown)
        XCTAssertEqual(TodoCopy.noteTime(elapsed: 299.5).text, "0:01 left")
        for text in [TodoCopy.timeLeft(60), TodoCopy.stoppedAtCap, TodoCopy.spokenElapsed(130), TodoCopy.part(2, of: 5)] {
            XCTAssertTrue(TodoCopy.all.contains(text), "\(text) is checked by the copy test")
        }
        XCTAssertEqual(TodoCopy.stoppedAtCap, "Stopped at 5 minutes. Tap the mic to keep going.")

        XCTAssertTrue(TodoModel.keepsScreenOn(phase: .starting, isDemo: false))
        XCTAssertTrue(TodoModel.keepsScreenOn(phase: .listening, isDemo: false))
        XCTAssertFalse(TodoModel.keepsScreenOn(phase: .sorting, isDemo: false), "never once the note is heard")
        XCTAssertFalse(TodoModel.keepsScreenOn(phase: .idle, isDemo: false))
        XCTAssertFalse(TodoModel.keepsScreenOn(phase: .listening, isDemo: true), "never in the demo")
        XCTAssertEqual(TodoListeningCard.tail("short"), "short")
        let long = (1...100).map { "word\($0)" }.joined(separator: " ")
        let tail = TodoListeningCard.tail(long)
        XCTAssertTrue(tail.hasPrefix("\u{2026} word"), tail)
        XCTAssertTrue(tail.hasSuffix("word100"))
        XCTAssertLessThanOrEqual(tail.count, TodoListeningCard.shownCharacters + 2, "only the end of a long note")
    }

    /// A due as the old tests wrote it: a moment with a time, or the London calendar date of a day-only one.
    private func make(_ date: Date, _ hasTime: Bool) -> TodoDue {
        hasTime ? .time(date) : .day(DayKey(calendarDateOf: date, in: london))
    }

    // MARK: Days stay days

    @MainActor
    func testADayOnlyDueDateIsTheSameDateInEveryTimeZone() {
        // "Renew the passport on Friday", said in Sydney: Friday wherever the iPhone is later.
        let friday = DayKey(year: 2026, month: 10, day: 16)
        let task = TodoTask(title: "Renew the passport", due: .day(friday), createdAt: at(2026, 10, 13, 9), noteId: UUID())
        let sydney = TimeZone(identifier: "Australia/Sydney")!
        let losAngeles = TimeZone(identifier: "America/Los_Angeles")!
        for zone in [sydney, losAngeles, london] {
            let clock = DayClock(dayStartHour: 4, timeZone: zone)
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = zone
            let thursday = calendar.date(from: DateComponents(year: 2026, month: 10, day: 15, hour: 10))!
            XCTAssertEqual(TodoText.dueLabel(task, now: thursday, clock: clock), "Tomorrow", zone.identifier)
            let fridayEvening = calendar.date(from: DateComponents(year: 2026, month: 10, day: 16, hour: 20))!
            XCTAssertFalse(TodoText.isOverdue(task, now: fridayEvening, clock: clock), "\(zone.identifier): due all Friday")
            let saturday = calendar.date(from: DateComponents(year: 2026, month: 10, day: 17, hour: 10))!
            XCTAssertTrue(TodoText.isOverdue(task, now: saturday, clock: clock), zone.identifier)
            let sorted = TodoOrdering.sortDate(task, clock: clock)
            XCTAssertEqual(sorted.map { DayKey(calendarDateOf: $0, in: zone) }, friday, "sorted by the end of Friday there")
        }
        let edited = TodoEditSheet.savedDue(hasDue: true, hasTime: false,
                                            picked: TodoEditSheet.pickerDate(.day(friday), clock: DayClock(dayStartHour: 4, timeZone: losAngeles)),
                                            clock: DayClock(dayStartHour: 4, timeZone: losAngeles))
        XCTAssertEqual(edited, .day(friday), "editing keeps the date")
        XCTAssertNil(TodoEditSheet.savedDue(hasDue: false, hasTime: true, picked: Date(), clock: londonClock()))
    }

    // MARK: Saved whole, then sorted

    func testANoteSavedWholeIsReplacedByItsTasks() {
        var state = TodoState()
        let now = at(2026, 10, 13, 9)
        let whole = state.add(TodoValidation.wholeNote("call the dentist and buy milk"), at: now)[0]
        XCTAssertEqual(state.firstNoteAt, now, "the whole note is the first note")
        let sorted = state.replaceNote(whole.id, with: [TodoDraft(title: "Call the dentist", due: .time(at(2026, 10, 14, 9))),
                                                        TodoDraft(title: "Buy milk")], at: now)
        XCTAssertEqual(sorted.map(\.title), ["Call the dentist", "Buy milk"])
        XCTAssertNil(state.task(whole.id), "the whole note goes")
        XCTAssertEqual(state.tasks.map(\.title), ["Call the dentist", "Buy milk"])
        XCTAssertEqual(Set(state.tasks.map(\.noteId)), [whole.noteId], "the same note")
        XCTAssertEqual(state.tasks.map(\.createdAt), [now, now])
        XCTAssertEqual(state.tasks.map(\.order), [0, 1])

        var same = TodoState()
        let note = same.add([TodoDraft(title: "Sort out the garage")], at: now)[0]
        XCTAssertEqual(same.replaceNote(note.id, with: [TodoDraft(title: "Sort out the garage")], at: now), [note],
                       "a note the model kept whole stays as it is")
        XCTAssertEqual(same.tasks, [note])

        var gone = TodoState()
        let erased = gone.add([TodoDraft(title: "Call Sam")], at: now)[0]
        gone.eraseAll()
        XCTAssertTrue(gone.replaceNote(erased.id, with: [TodoDraft(title: "Call Sam")], at: now).isEmpty,
                      "erased meanwhile: nothing comes back")
        XCTAssertTrue(gone.tasks.isEmpty)

        var changed = TodoState()
        let done = changed.add([TodoDraft(title: "Call Sam and Kim")], at: now)[0]
        changed.complete(done.id, at: now)
        XCTAssertEqual(changed.replaceNote(done.id, with: [TodoDraft(title: "Call Sam"), TodoDraft(title: "Call Kim")],
                                           at: now).map(\.id), [done.id], "a note already done stays as it is")
    }

    func testANoteSavedAsSaidIsReplacedByItsTasksOnlyWhileItsLinesAreUntouched() {
        let now = at(2026, 10, 20, 9)
        var state = TodoState()
        let note = UUID()
        let lines = state.add(TodoValidation.lines("Call the dentist. Buy milk and bread."), area: .work, noteId: note,
                              at: now)
        XCTAssertEqual(lines.map(\.title), ["Call the dentist", "Buy milk and bread"], "every sentence saved at once")
        let sorted = state.replaceNote(noteId: note, saved: lines, with: [TodoDraft(title: "Call the dentist"),
                                                                         TodoDraft(title: "Buy milk"),
                                                                         TodoDraft(title: "Buy bread")], at: now)
        XCTAssertEqual(sorted.map(\.title), ["Call the dentist", "Buy milk", "Buy bread"])
        XCTAssertEqual(sorted.map(\.area), [.work, .work, .work], "on the note's list")
        XCTAssertEqual(Set(sorted.map(\.noteId)), [note])
        XCTAssertEqual(sorted.map(\.order), [0, 1, 2])
        XCTAssertEqual(state.tasks.count, 3, "the lines are gone")

        var edited = TodoState()
        let second = UUID()
        let saved = edited.add([TodoDraft(title: "Call the dentist"), TodoDraft(title: "Buy milk")], noteId: second, at: now)
        edited.update(saved[1].id, title: "Buy oat milk", due: nil)
        XCTAssertEqual(edited.replaceNote(noteId: second, saved: saved, with: [TodoDraft(title: "Call")], at: now)
                        .map(\.title), ["Call the dentist", "Buy oat milk"], "someone edited a line: the note stays")

        var done = TodoState()
        let third = UUID()
        let doneLines = done.add([TodoDraft(title: "Call the dentist")], noteId: third, at: now)
        done.complete(doneLines[0].id, at: now)
        XCTAssertEqual(done.replaceNote(noteId: third, saved: doneLines, with: [TodoDraft(title: "Call")], at: now)
                        .map(\.id), [doneLines[0].id], "a line done meanwhile: the note stays")

        var erased = TodoState()
        let fourth = UUID()
        let gone = erased.add([TodoDraft(title: "Call Sam")], noteId: fourth, at: now)
        erased.eraseAll()
        XCTAssertTrue(erased.replaceNote(noteId: fourth, saved: gone, with: [TodoDraft(title: "Call Sam")], at: now).isEmpty,
                      "erased meanwhile: nothing comes back")
        XCTAssertTrue(erased.tasks.isEmpty)

        var same = TodoState()
        let fifth = UUID()
        let kept = same.add([TodoDraft(title: "Sort out the garage")], noteId: fifth, at: now)
        XCTAssertEqual(same.replaceNote(noteId: fifth, saved: kept, with: [TodoDraft(title: "Sort out the garage")], at: now),
                       kept, "the model kept it as said")
    }

    // MARK: Keep as one

    func testKeepAsOneMergesOnlyTheGivenOpenTasksAndKeepsTheNoteAndTheEarliestDue() throws {
        let clock = londonClock()
        let now = at(2026, 10, 19, 10)
        var state = TodoState()
        let other = state.add([TodoDraft(title: "Ring Jo about the lease")], at: at(2026, 10, 19, 8))[0]
        let note = state.add([TodoDraft(title: "Reach toothbrushes", due: .day(DayKey(year: 2026, month: 10, day: 21))),
                              TodoDraft(title: "Order toothbrushes", due: .time(at(2026, 10, 20, 9))),
                              TodoDraft(title: "Buy floss")], at: now)
        let due = TodoMerge.earliestDue(note.map(\.due), clock: clock)
        XCTAssertEqual(due, .time(at(2026, 10, 20, 9)), "Tuesday 09:00 comes before any time on Wednesday")
        let title = try XCTUnwrap(TodoMerge.title(transcript: "order Reach toothbrushes on Amazon",
                                                  titles: note.map(\.title), hasDue: due != nil))
        XCTAssertEqual(title, "Order Reach toothbrushes on Amazon", "a short note reads as it was said")

        let merged = try XCTUnwrap(state.mergeNote(ids: note.map(\.id), title: title, due: due))
        XCTAssertEqual(state.tasks.count, 2, "three became one; the other note is untouched")
        XCTAssertEqual(state.task(other.id), other)
        XCTAssertEqual(merged.title, "Order Reach toothbrushes on Amazon")
        XCTAssertEqual(merged.due, .time(at(2026, 10, 20, 9)))
        XCTAssertEqual(merged.noteId, note[0].noteId, "the same note")
        XCTAssertEqual(merged.createdAt, now, "said when the note was said")
        XCTAssertEqual(merged.order, 0)
        XCTAssertEqual(merged.id, note[0].id, "the first task's row stays where it was")
        XCTAssertNil(state.task(note[1].id))
        XCTAssertNil(state.task(note[2].id))
        XCTAssertFalse(merged.isDone)
        XCTAssertNil(state.mergeNote(ids: note.map(\.id), title: title, due: due), "once only")
    }

    func testKeepAsOneLeavesTheListAloneWhenATaskWasDoneOrDeleted() {
        let now = at(2026, 10, 19, 10)
        var done = TodoState()
        let first = done.add([TodoDraft(title: "Call the dentist"), TodoDraft(title: "Email Priya the deck")], at: now)
        done.complete(first[1].id, at: now)
        let before = done
        XCTAssertNil(done.mergeNote(ids: first.map(\.id), title: "Call the dentist and email Priya", due: nil))
        XCTAssertEqual(done, before, "one was done meanwhile: nothing changes")

        var deleted = TodoState()
        let second = deleted.add([TodoDraft(title: "Call the dentist"), TodoDraft(title: "Email Priya the deck")], at: now)
        deleted.delete(second[0].id)
        let left = deleted
        XCTAssertNil(deleted.mergeNote(ids: second.map(\.id), title: "Call the dentist and email Priya", due: nil))
        XCTAssertEqual(deleted, left, "one was deleted meanwhile: nothing changes")

        var mixed = TodoState()
        let a = mixed.add([TodoDraft(title: "Call the dentist")], at: now)[0]
        let b = mixed.add([TodoDraft(title: "Buy milk")], at: now)[0]
        XCTAssertNil(mixed.mergeNote(ids: [a.id, b.id], title: "Call the dentist, Buy milk", due: nil),
                     "two notes are never merged")
        XCTAssertNil(mixed.mergeNote(ids: [a.id], title: "Call the dentist", due: nil), "one task is already one")
        XCTAssertEqual(mixed.tasks.count, 2)
    }

    func testKeepAsOneTitleIsTheWordsSaidForAShortNoteOtherwiseTheTitlesJoined() {
        XCTAssertEqual(TodoMerge.title(transcript: "  um order Reach toothbrushes on Amazon. ", titles: ["A", "B"], hasDue: false),
                       "Order Reach toothbrushes on Amazon", "leading filler goes, as in a rebuilt title")
        XCTAssertEqual(TodoMerge.title(transcript: "Um so I need to order Reach toothbrushes and floss", titles: ["A", "B"],
                                       hasDue: false), "Order Reach toothbrushes and floss")
        XCTAssertEqual(TodoMerge.title(transcript: "Order. Reach toothbrushes on Amazon.", titles: ["A", "B"], hasDue: false),
                       "Order Reach toothbrushes on Amazon", "a pause inside the note is not kept")
        XCTAssertEqual(TodoMerge.title(transcript: "buy milk, eggs and bread", titles: ["A", "B"], hasDue: false),
                       "Buy milk, eggs and bread", "a list keeps its commas")
        XCTAssertEqual(TodoMerge.title(transcript: "Tomorrow at 9 call the dentist and buy milk", titles: ["A", "B"], hasDue: true),
                       "Call the dentist and buy milk", "the due date carries the day and time")
        XCTAssertEqual(TodoMerge.title(transcript: "Tomorrow at 9 call the dentist and buy milk", titles: ["A", "B"], hasDue: false),
                       "Tomorrow at 9 call the dentist and buy milk", "with no due date, the day stays in the words")
        let long = "so I need to call the dentist and also email Priya the deck and then buy milk eggs and bread"
        XCTAssertEqual(TodoMerge.title(transcript: long, titles: ["Call the dentist", "Email Priya the deck", "Buy milk"],
                                       hasDue: false),
                       "Call the dentist, Email Priya the deck, Buy milk", "past 12 words: the titles, joined")
        let titles = Array(repeating: "Pick up the parcel from the post office on the high street", count: 4)
        let joined = TodoMerge.title(transcript: long, titles: titles, hasDue: false) ?? ""
        XCTAssertLessThanOrEqual(joined.count, TodoText.maxTitleLength, "never a paragraph")
        XCTAssertNil(TodoMerge.earliestDue([nil, nil], clock: londonClock()))
        XCTAssertEqual(TodoMerge.earliestDue([nil, .day(DayKey(year: 2026, month: 10, day: 22)),
                                              .day(DayKey(year: 2026, month: 10, day: 20))], clock: londonClock()),
                       .day(DayKey(year: 2026, month: 10, day: 20)))
    }

    // MARK: Notifications

    func testDeliveredNotificationsForFinishedOrDeletedTasksAreWithdrawn() {
        let now = at(2026, 10, 13, 9)
        let open = TodoTask(title: "Open", due: .time(at(2026, 10, 13, 8)), createdAt: now, noteId: UUID())
        let done = TodoTask(title: "Done", due: .time(at(2026, 10, 13, 8)), createdAt: now, completedAt: now, noteId: UUID())
        let deleted = UUID()
        let delivered = [TodoNotifications.identifier(open.id), TodoNotifications.identifier(done.id),
                         TodoNotifications.identifier(deleted), Reminders.requestPrefix + "20738"]
        XCTAssertEqual(TodoNotifications.staleDelivered(delivered, tasks: [open, done]),
                       [TodoNotifications.identifier(done.id), TodoNotifications.identifier(deleted)],
                       "an open task's stays; the nudge's is never touched")
    }

    func testRebuildsRunOneAtATimeAndTheNewestWins() async throws {
        // Two checks a moment apart used to interleave (remove, remove, add, add) and leave a done task's notification
        // scheduled. Now a rebuild never overlaps another, and a request made while one runs replaces any waiting one.
        let log = RebuildLog()
        // Each rebuild takes 600 ms here, far longer than the two requests below need, even on a slow runner.
        let scheduler = TodoNotificationScheduler { tasks in
            await log.begin(tasks.count)
            try? await Task.sleep(for: .milliseconds(600))
            await log.end()
        }
        let call = TodoTask(title: "Call Sam", due: .time(at(2026, 10, 13, 16)), createdAt: at(2026, 10, 13, 9), noteId: UUID())
        let milk = TodoTask(title: "Buy milk", createdAt: at(2026, 10, 13, 9), noteId: UUID())
        let first = Task { await scheduler.reschedule([call]) }
        while await log.runs.isEmpty { try await Task.sleep(for: .milliseconds(5)) }
        await scheduler.reschedule([call, milk])
        await scheduler.reschedule([])
        await first.value
        let runs = await log.runs
        let most = await log.mostAtOnce
        XCTAssertEqual(runs, [1, 0], "the waiting request was replaced by the newest one")
        XCTAssertEqual(most, 1, "never two rebuilds at once")
    }
}

/// What a test scheduler ran, and how many at once.
private actor RebuildLog {
    private(set) var runs: [Int] = []
    private(set) var mostAtOnce = 0
    private var running = 0

    func begin(_ count: Int) {
        running += 1
        mostAtOnce = max(mostAtOnce, running)
        runs.append(count)
    }

    func end() {
        running -= 1
    }
}
