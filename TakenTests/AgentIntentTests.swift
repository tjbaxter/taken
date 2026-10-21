import XCTest
@testable import Taken

/// The agent read surface (REDESIGN.md, SPEC 3.7): "Did I take it?" and "Get to-dos" hand their answers on to other
/// shortcuts, and "Add to-do" is gated exactly like a typed note. Every test runs on temporary files or plain values,
/// never the App Group.
final class AgentIntentTests: XCTestCase {

    private let now = at(2026, 10, 19, 12)
    private let clock = londonClock()

    private var pro: ProStatus { ProStatus(isPro: true, reason: .yearly, checkedAt: now, expiresAt: at(2027, 10, 19, 9), willRenew: true) }
    private var notPro: ProStatus { .notPro(checkedAt: now) }

    private func temporaryTodoStore() -> TodoStore {
        TodoStore(fileURL: temporaryStoreURL().deletingLastPathComponent().appendingPathComponent(TodoStore.fileName))
    }

    private func temporaryLedger(_ status: ProStatus?) -> ProLedgerStore {
        let store = ProLedgerStore(fileURL: temporaryStoreURL().deletingLastPathComponent().appendingPathComponent(ProLedgerStore.fileName))
        _ = store.loadOrCreate { ProLedger(status: status, firstSeenAt: at(2026, 10, 1, 8), legacyLog: false) }
        return store
    }

    /// The one list, as a file a list build wrote it (Work on top): three open, one a former Work task, two done today
    /// (one on Work), and one done before the day rolled over (02:30 is still yesterday with a 04:00 day start).
    private func oneList() -> TodoState {
        var state = TodoState(lastArea: .work, areaOrder: [.work, .personal])
        state.add([TodoDraft(title: "Buy milk")], at: at(2026, 10, 19, 9))
        state.add([TodoDraft(title: "Call the dentist", due: .time(at(2026, 10, 19, 16)))], at: at(2026, 10, 19, 9, 5))
        state.tasks.append(TodoTask(title: "Send the deck", due: .day(DayKey(year: 2026, month: 10, day: 20)),
                                    createdAt: at(2026, 10, 19, 9, 10), noteId: UUID(), area: .work))
        let car = state.add([TodoDraft(title: "Book the car in")], at: at(2026, 10, 19, 8))[0]
        state.complete(car.id, at: at(2026, 10, 19, 10))
        state.tasks.append(TodoTask(title: "Reply to Dan", createdAt: at(2026, 10, 19, 8), completedAt: at(2026, 10, 19, 11),
                                    noteId: UUID(), area: .work))
        let cleaner = state.add([TodoDraft(title: "Pay the window cleaner")], at: at(2026, 10, 18, 19))[0]
        state.complete(cleaner.id, at: at(2026, 10, 19, 2, 30))
        return state
    }

    // MARK: Did I take it?

    func testDidITakeItHandsOnTheSentenceSiriSays() {
        let created = at(2026, 10, 1, 8)
        let vd3 = makeItem("Vitamin D3", "VD3", created: created, sortIndex: 0)
        let fish = makeItem("Fish Oil", "FSH", created: created, sortIndex: 1)
        var state = StackState(items: [vd3, fish])
        state.logDose(itemId: vd3.id, at: at(2026, 10, 19, 7, 42), timeZone: london)
        let pending = SiriAnswers.status(state: state, now: now, timeZone: london)
        XCTAssertTrue(pending.hasPrefix("Not yet: Fish Oil is pending."), pending)
        XCTAssertEqual(CheckStackIntent.answer(state: state, now: now, timeZone: london).value, pending,
                       "the value a shortcut gets is the sentence Siri says")

        state.logDose(itemId: fish.id, at: at(2026, 10, 19, 8), timeZone: london)
        let done = SiriAnswers.status(state: state, now: now, timeZone: london)
        XCTAssertTrue(done.hasPrefix("Yes. Vitamin D3 at "), done)
        XCTAssertEqual(CheckStackIntent.answer(state: state, now: now, timeZone: london).value, done)

        XCTAssertEqual(CheckStackIntent.answer(state: StackState(), now: now, timeZone: london).value,
                       "Your stack is empty. Open Taken to add what you take.")
    }

    // MARK: Get to-dos

    /// Replaces testGetTodosFiltersOpenDoneTodayAndAllByList: no List parameter, the one list in the To-do tab's order.
    func testGetTodosFiltersOpenDoneTodayAndAll() {
        let state = oneList()
        func titles(_ show: TodoShowOption) -> [String] {
            TodoAgent.tasks(in: state, show: show, now: now, clock: clock).map(\.title)
        }
        XCTAssertEqual(titles(.open), ["Call the dentist", "Send the deck", "Buy milk"],
                       "the one list as the To-do tab shows it, due first, a former Work task among the rest")
        XCTAssertEqual(titles(.doneToday), ["Reply to Dan", "Book the car in"],
                       "newest first; 02:30 belongs to yesterday with a 04:00 day start")
        XCTAssertEqual(titles(.all), ["Call the dentist", "Send the deck", "Buy milk", "Reply to Dan", "Book the car in",
                                      "Pay the window cleaner"], "open first, then done, newest first")

        let personalFirst = TodoState(tasks: state.tasks, lastArea: .personal, areaOrder: [.personal, .work])
        for show in TodoShowOption.allCases {
            XCTAssertEqual(TodoAgent.tasks(in: personalFirst, show: show, now: now, clock: clock).map(\.title), titles(show),
                           "no old list value changes what a shortcut gets")
        }

        let answer = GetTodosIntent.answer(todos: state, show: .open, now: now, clock: clock)
        XCTAssertEqual(answer.value?.map(\.title), titles(.open), "the value is the to-dos themselves")
        XCTAssertEqual(GetTodosIntent.answer(todos: TodoState(), show: .all, now: now, clock: clock).value?.count, 0)
    }

    func testGetTodosDefaultsToOpen() {
        XCTAssertEqual(GetTodosIntent().show, .open)
        XCTAssertEqual(GetTodosIntent(show: .doneToday).show, .doneToday)
    }

    func testTheDialogCountsAndNamesTheFirstThree() {
        XCTAssertEqual(TodoAgentCopy.summary(["Call the dentist", "Send the deck", "Buy milk"], show: .open),
                       "3 open to-dos: Call the dentist, Send the deck and Buy milk.")
        XCTAssertEqual(TodoAgentCopy.summary(["A", "B", "C", "D", "E"], show: .open), "5 open to-dos: A, B, C and 2 more.")
        XCTAssertEqual(TodoAgentCopy.summary(["Send the deck"], show: .open), "1 open to-do: Send the deck.")
        XCTAssertEqual(TodoAgentCopy.summary(["Reply to Dan"], show: .doneToday), "1 to-do done today: Reply to Dan.")
        XCTAssertEqual(TodoAgentCopy.summary(["Buy milk", "Book the car in"], show: .all),
                       "2 to-dos: Buy milk and Book the car in.")
        XCTAssertEqual(TodoAgentCopy.summary([], show: .open), "No open to-dos.")
        XCTAssertEqual(TodoAgentCopy.summary([], show: .doneToday), "No to-dos done today.")
        XCTAssertEqual(TodoAgentCopy.summary([], show: .all), "No to-dos.")
        XCTAssertEqual(TodoAgentCopy.summary(["Ask Sam about Friday?"], show: .open),
                       "1 open to-do: Ask Sam about Friday?", "a title that ends the sentence gets no extra full stop")
    }

    func testATodoCarriesWhatAShortcutOrAModelNeeds() throws {
        let state = oneList()
        let open = TodoAgent.tasks(in: state, show: .all, now: now, clock: clock)
        let entities = open.map { TodoEntity($0, now: now, clock: clock) }
        XCTAssertEqual(entities.map(\.id), open.map(\.id), "the to-do's own id, so Shortcuts finds it again")

        let dentist = try XCTUnwrap(entities.first { $0.title == "Call the dentist" })
        XCTAssertEqual(dentist.due, at(2026, 10, 19, 16), "a clock time is the moment it is due")
        XCTAssertEqual(dentist.dueLabel, "16:00")
        XCTAssertFalse(dentist.isDone)
        XCTAssertNil(dentist.completedAt)
        let subtitle = try XCTUnwrap(dentist.displayRepresentation.subtitle)
        XCTAssertEqual(String(localized: subtitle), "16:00", "the due label shows under the title")

        let deck = try XCTUnwrap(entities.first { $0.title == "Send the deck" })
        XCTAssertEqual(deck.due, at(2026, 10, 21, 0).addingTimeInterval(-1), "a day alone is due by its end, as the list orders it")
        XCTAssertEqual(deck.dueLabel, "Tomorrow")

        let dan = try XCTUnwrap(entities.first { $0.title == "Reply to Dan" })
        XCTAssertTrue(dan.isDone)
        XCTAssertEqual(dan.completedAt, at(2026, 10, 19, 11))
        XCTAssertNil(dan.due)
        XCTAssertNil(dan.dueLabel)
        XCTAssertNil(dan.displayRepresentation.subtitle)
        XCTAssertEqual(String(localized: dan.displayRepresentation.title), "Reply to Dan")
    }

    // MARK: Add to-do

    /// Replaces testAddTodoWithNoListGoesToTheListOnTopWithItsDue: no List parameter; a shortcut adds to the one list,
    /// as a new Personal task, whatever the file's old list values say.
    func testAddTodoAddsToTheOneListWithItsDue() async throws {
        let store = temporaryTodoStore()
        try store.replace(with: TodoState(firstNoteAt: at(2026, 10, 12, 9), lastArea: .work, areaOrder: [.work, .personal]))
        let ledger = temporaryLedger(pro)
        let due = at(2026, 10, 20, 9)

        let added = try await TodoAgent.add(title: "  send priya the deck. ", due: due, store: store, ledgerStore: ledger,
                                            now: now)
        XCTAssertEqual(added.task.title, "Send priya the deck", "cleaned like every title")
        XCTAssertEqual(added.task.area, .personal, "a new task, never the old list on top or in view")
        XCTAssertEqual(added.task.due, TodoDue.time(due), "a due date is saved as a moment")
        XCTAssertEqual(added.task.createdAt, now)
        XCTAssertEqual(store.load().tasks, [added.task], "written to the file")
        XCTAssertEqual(added.state, store.load(), "the state handed back is the one written, for the notifications")
        XCTAssertEqual(store.load().areaOrder, [.work, .personal], "the file's old values are kept as they were")
        XCTAssertEqual(store.load().lastArea, .work)

        let plain = try await TodoAgent.add(title: "Buy milk", due: nil, store: store, ledgerStore: ledger, now: now)
        XCTAssertNil(plain.task.due)
        XCTAssertEqual(store.load().tasks.count, 2)
        XCTAssertEqual(TodoAgent.tasks(in: store.load(), show: .open, now: now, clock: clock).map(\.title),
                       ["Send priya the deck", "Buy milk"], "both on the one list")

        let long = String(repeating: "word ", count: 60)
        let short = try await TodoAgent.add(title: long, due: nil, store: store, ledgerStore: ledger, now: now)
        XCTAssertLessThanOrEqual(short.task.title.count, TodoText.maxTitleLength, "short lines, never paragraphs")
    }

    func testAddTodoWritesNothingWhenLocked() async throws {
        let store = temporaryTodoStore()
        var before = TodoState(firstNoteAt: at(2026, 10, 12, 9))
        before.add([TodoDraft(title: "Buy milk")], at: at(2026, 10, 12, 9))
        try store.replace(with: before)
        let ledger = temporaryLedger(notPro)

        do {
            _ = try await TodoAgent.add(title: "Call the bank", due: nil, store: store, ledgerStore: ledger, now: now)
            XCTFail("locked: nothing may be added")
        } catch {
            XCTAssertEqual(error as? TodoAgentError, .needsPro)
        }
        XCTAssertEqual(store.load(), before, "nothing written")
        XCTAssertEqual(TodoAgentError.needsPro.message, "To-dos need Taken Pro. Open Taken to continue.")
    }

    func testTheFirstNoteFromAShortcutIsOnTheHouseLikeATypedOne() async throws {
        let store = temporaryTodoStore()
        let ledger = temporaryLedger(notPro)
        let first = try await TodoAgent.add(title: "Call the bank", due: nil, store: store, ledgerStore: ledger, now: now)
        XCTAssertEqual(first.task.title, "Call the bank")
        XCTAssertEqual(store.load().firstNoteAt, now, "it uses up the first note, as a typed one does")
        do {
            _ = try await TodoAgent.add(title: "Buy milk", due: nil, store: store, ledgerStore: ledger, now: now)
            XCTFail("after the first note, adding needs Pro")
        } catch {
            XCTAssertEqual(error as? TodoAgentError, .needsPro)
        }
        XCTAssertEqual(store.load().tasks.map(\.title), ["Call the bank"])
    }

    func testAnEmptyTitleAsksAgainAndWritesNothing() async throws {
        let store = temporaryTodoStore()
        let ledger = temporaryLedger(pro)
        do {
            _ = try await TodoAgent.add(title: "  . ", due: nil, store: store, ledgerStore: ledger, now: now)
            XCTFail("nothing left of the title")
        } catch {
            XCTAssertEqual(error as? TodoAgentError, .needsTitle)
        }
        XCTAssertTrue(store.load().tasks.isEmpty)
        XCTAssertNil(store.load().firstNoteAt, "an empty title never uses up the first note")
    }

    func testTheGateReadsTheLedgerAsWidgetsAndIntentsDo() {
        let used = TodoState(firstNoteAt: at(2026, 10, 12, 9))
        let ledger = ProLedger(status: notPro, firstSeenAt: at(2026, 10, 1, 8), legacyLog: false)
        XCTAssertEqual(TodoGate.access(ledger: ledger, todos: TodoState(), now: now), .firstSession)
        XCTAssertEqual(TodoGate.access(ledger: ledger, todos: used, now: now), .locked)
        XCTAssertEqual(TodoGate.access(ledger: ProLedger(status: pro, firstSeenAt: at(2026, 10, 1, 8), legacyLog: false),
                                       todos: used, now: now), .pro)
        XCTAssertEqual(TodoGate.access(ledger: nil, todos: used, now: now), .pending,
                       "no ledger yet is someone updated from 1.0, as for doses: never locked on a guess")
        XCTAssertEqual(TodoGate.access(ledger: ledger, todos: used, now: now),
                       TodoGate.access(firstNoteAt: used.firstNoteAt, status: notPro, settled: true, legacyLog: false, now: now),
                       "the same rule the To-do tab uses")
    }

    func testALapsedRenewalIsCheckedWithTheAppStoreBeforeLocking() async {
        let used = TodoState(firstNoteAt: at(2026, 10, 12, 9))
        let lapsed = ProStatus(isPro: true, reason: .monthly, checkedAt: at(2026, 9, 1, 9),
                               expiresAt: now.addingTimeInterval(-ProStatus.renewalMargin - 60), willRenew: true)
        XCTAssertTrue(lapsed.lapsedRenewal(at: now))

        let renewed = ProStatus(isPro: true, reason: .monthly, checkedAt: now, expiresAt: at(2026, 11, 19, 9), willRenew: true)
        let ledger = temporaryLedger(lapsed)
        let mayAdd = await TodoGate.mayAdd(todos: used, now: now, ledgerStore: ledger, recheck: {
            ledger.update { $0?.status = renewed }
        })
        XCTAssertTrue(mayAdd, "the App Store found the renewal")

        let stillLapsed = temporaryLedger(lapsed)
        let refused = await TodoGate.mayAdd(todos: used, now: now, ledgerStore: stillLapsed, recheck: {})
        XCTAssertFalse(refused, "no renewal found: locked")

        let cancelled = temporaryLedger(notPro)
        let neverAsked = await TodoGate.mayAdd(todos: used, now: now, ledgerStore: cancelled, recheck: {
            XCTFail("only a plan set to renew is checked again")
        })
        XCTAssertFalse(neverAsked)
    }

    // MARK: Copy and metadata

    func testTheNewCopyKeepsTheRules() {
        var lines = TodoAgentCopy.all
        let titles = ["Call the dentist", "Send the deck", "Buy milk", "Book the car in", "Reply to Dan"]
        for show in TodoShowOption.allCases {
            for count in [0, 1, 2, 5] {
                lines.append(TodoAgentCopy.summary(Array(titles.prefix(count)), show: show))
            }
        }
        var state = TodoState()
        let timed = state.add([TodoDraft(title: "Send the deck", due: .time(at(2026, 10, 20, 9)))], at: now)[0]
        let day = state.add([TodoDraft(title: "Buy milk", due: .day(DayKey(year: 2026, month: 10, day: 22)))], at: now)[0]
        let plain = state.add([TodoDraft(title: "Call the bank")], at: now)[0]
        for task in [timed, day, plain] {
            lines.append(TodoAgentCopy.added(task, now: now, clock: clock))
        }
        XCTAssertEqual(TodoAgentCopy.added(plain, now: now, clock: clock), "Added to your to-dos: Call the bank.")
        XCTAssertTrue(TodoAgentCopy.added(timed, now: now, clock: clock)
            .hasPrefix("Added to your to-dos: Send the deck, due tomorrow at "))
        XCTAssertFalse(lines.contains { $0.contains("Personal") || $0.contains("Work") }, "no list in any line")
        for representation in TodoShowOption.caseDisplayRepresentations.values {
            lines.append(String(localized: representation.title))
            if let subtitle = representation.subtitle { lines.append(String(localized: subtitle)) }
        }
        lines += [GetTodosIntent.title, AddTodoIntent.title, CheckStackIntent.title].map { String(localized: $0) }
        for text in lines {
            XCTAssertNil(text.range(of: "free", options: .caseInsensitive), text)
            XCTAssertFalse(text.contains("\u{2014}") || text.contains("\u{2013}"), "no em or en dash: \(text)")
            XCTAssertFalse(text.contains("!"), text)
        }
    }

    /// Siri reads the to-dos aloud, and Add to-do writes: on a locked iPhone both ask for Face ID or the passcode first.
    func testTheToDoActionsAskALockedIPhoneToUnlock() {
        for policy in [GetTodosIntent.authenticationPolicy, AddTodoIntent.authenticationPolicy] {
            guard case .requiresAuthentication = policy else { return XCTFail("\(policy)") }
        }
    }

    /// "Did I take it?" says the stack's names (Birth Control, Finasteride): a locked iPhone asks to unlock first, so
    /// Siri never reads them to whoever holds it.
    func testDidITakeItAsksALockedIPhoneToUnlock() {
        guard case .requiresAuthentication = CheckStackIntent.authenticationPolicy else {
            return XCTFail("\(CheckStackIntent.authenticationPolicy)")
        }
    }

    /// The App Intents metadata the build extracts is what Siri and Shortcuts read. The Release device build checks the
    /// file is there; this checks the new actions and types made it in.
    func testTheActionsAreInTheAppIntentsMetadata() throws {
        guard let url = Bundle.main.url(forResource: "extract", withExtension: "actionsdata", subdirectory: "Metadata.appintents"),
              let data = try? Data(contentsOf: url) else {
            throw XCTSkip("This build carries no App Intents metadata; the Release device build checks for it.")
        }
        let text = String(decoding: data, as: UTF8.self)
        guard text.contains("CheckStackIntent") else { throw XCTSkip("The metadata is not readable as text in this build.") }
        for name in ["GetTodosIntent", "AddTodoIntent", "TodoEntity", "TodoShowOption"] {
            XCTAssertTrue(text.contains(name), "\(name) is in the metadata, so Shortcuts and Siri can see it")
        }
        if text.contains("Did I take my pills") {
            XCTAssertTrue(text.contains("on my to-do list"), "the Get to-dos phrase is extracted with the others")
        }
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            print("App Intents metadata keys: \(json.keys.sorted())")
            if let actions = json["actions"] as? [String: Any], let check = actions["CheckStackIntent"] as? [String: Any] {
                print("CheckStackIntent metadata keys: \(check.keys.sorted())")
            }
        }
    }
}
