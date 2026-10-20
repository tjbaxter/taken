import XCTest
@testable import Taken

/// The To-do tab's model wired together (TodoModel, SPEC 3.10): Keep as one comes only after a short note the model
/// split and goes on any change; a note goes to the top list unless its chip sends it to the other, never to where
/// `lastArea` points; a note is saved at once as said and hidden until its tasks replace it, then brought into view; a
/// tapped due-time notification scrolls to its task; a long note is sorted in parts; the demo's listening screens hold a
/// fixed time; the internal voice note log records each note. A temporary file and canned model answers stand in for
/// todos.json and the on-device model.
final class TodoModelTests: XCTestCase {
    /// Sorts every part with canned answers, as the on-device model would, through the real checks.
    private struct Canned: ChunkSorting {
        let raw: [RawTodo]
        var delay: Duration = .zero

        var unavailable: TodoSorting? { nil }

        func prepare() async {}

        func answer(chunk: TodoChunk, prompt: String) async throws -> [RawTodo] {
            if delay > .zero { try? await Task.sleep(for: delay) }
            // Only the tasks said in this part.
            return raw.filter { chunk.text.lowercased().contains(($0.spoken ?? $0.title).lowercased()) }
        }
    }

    private let split = [RawTodo(spoken: "call the dentist", title: "Call the dentist"),
                         RawTodo(spoken: "buy milk", title: "Buy milk")]
    private let note = "call the dentist and buy milk"

    @MainActor
    private func model(_ raw: [RawTodo], delay: Duration = .zero, seed: TodoState = TodoState()) throws -> TodoModel {
        let url = temporaryStoreURL().deletingLastPathComponent().appendingPathComponent(TodoStore.fileName)
        let store = TodoStore(fileURL: url)
        try store.replace(with: seed)
        // Real time, so the demo's Taken Pro (a year from today) is active after the first note.
        return TodoModel(store: store, isDemo: true, launchScreen: nil, clockNow: { Date() },
                         makeSorter: { Canned(raw: raw, delay: delay) })
    }

    @MainActor
    private func demoApp() -> AppModel {
        AppModel.fromLaunchArguments(["Taken", "-demo", "-screen", "today"])
    }

    /// Waits for the note being sorted to be saved.
    @MainActor
    private func settle(_ model: TodoModel) async {
        let deadline = Date().addingTimeInterval(8)
        while model.phase != .idle && Date() < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    /// A typed note the canned model splits in two, saved: Keep as one is offered.
    @MainActor
    private func offered(_ model: TodoModel, _ app: AppModel) async throws -> TodoModel.KeepOffer {
        model.submitTyped(note, app: app)
        await settle(model)
        return try XCTUnwrap(model.keepOffer, "two to-dos from one note: Keep as one is offered")
    }

    @MainActor
    func testKeepAsOneIsOfferedForASplitNoteAndPutsItBack() async throws {
        let model = try model(split)
        let app = demoApp()
        let offer = try await offered(model, app)
        XCTAssertEqual(offer.ids.count, 2)
        XCTAssertEqual(offer.transcript, note)
        XCTAssertEqual(Set(model.openTasks(in: .personal).map(\.title)), ["Call the dentist", "Buy milk"])

        model.keepAsOne()
        XCTAssertNil(model.keepOffer, "once only")
        XCTAssertEqual(model.openTasks(in: .personal).map(\.title), ["Call the dentist and buy milk"])
        XCTAssertEqual(model.store.load().tasks.map(\.title), ["Call the dentist and buy milk"], "and saved")
    }

    @MainActor
    func testKeepAsOneIsNotOfferedForANoteOfOneToDo() async throws {
        let model = try model([RawTodo(spoken: "call the dentist", title: "Call the dentist")])
        model.submitTyped("call the dentist", app: demoApp())
        await settle(model)
        XCTAssertEqual(model.openTasks(in: .personal).map(\.title), ["Call the dentist"])
        XCTAssertNil(model.keepOffer)
    }

    @MainActor
    func testKeepAsOneGoesOnAnyChangeAMicTapOrLeavingTheTab() async throws {
        let app = demoApp()

        let reordered = try model(split)
        _ = try await offered(reordered, app)
        reordered.write { $0.setAreaOrder([.work, .personal]) }
        XCTAssertNil(reordered.keepOffer, "the lists were reordered")

        let edited = try model(split)
        let offer = try await offered(edited, app)
        edited.edit(offer.ids[0], title: "Call the dentist about the filling", due: nil)
        XCTAssertNil(edited.keepOffer, "a write")

        let ticked = try model(split)
        let ticking = try await offered(ticked, app)
        let task = try XCTUnwrap(ticked.state.task(ticking.ids[0]))
        ticked.toggle(task)
        try await Task.sleep(for: .milliseconds(700))
        XCTAssertTrue(ticked.state.task(task.id)?.isDone ?? false)
        XCTAssertNil(ticked.keepOffer, "a task done")

        let elsewhere = try model(split)
        _ = try await offered(elsewhere, app)
        _ = try elsewhere.store.update { $0.add([TodoDraft(title: "From a shortcut")], at: Date()) }
        elsewhere.refresh()
        XCTAssertNil(elsewhere.keepOffer, "the file changed elsewhere")

        let tapped = try model(split)
        _ = try await offered(tapped, app)
        tapped.micTapped(app)
        XCTAssertNil(tapped.keepOffer, "the mic")

        let left = try model(split)
        _ = try await offered(left, app)
        left.dismissKeepOffer()
        XCTAssertNil(left.keepOffer, "the tab was left")
        left.keepAsOne()
        XCTAssertEqual(left.openTasks(in: .personal).count, 2, "nothing to keep once it has gone")
    }

    // Replaces testANoteGoesToTheListInViewAndTheSwitchHoldsWhileItIsSorted: a note now goes to the top list (Tom: "I
    // should have work selected and it should go in work"), and lastArea, the old list in view, decides nothing.
    @MainActor
    func testANoteGoesToTheTopListWhereverLastAreaPoints() async throws {
        let seed = TodoState(lastArea: .personal, areaOrder: [.work, .personal])
        let model = try model(split, delay: .milliseconds(300), seed: seed)
        XCTAssertEqual(model.destination, .work)
        model.submitTyped(note, app: demoApp())
        XCTAssertEqual(model.phase, .sorting)
        XCTAssertEqual(model.captureArea, .work)
        await settle(model)
        XCTAssertEqual(Set(model.openTasks(in: .work).map(\.title)), ["Call the dentist", "Buy milk"])
        XCTAssertTrue(model.openTasks(in: .personal).isEmpty)
        XCTAssertEqual(model.store.load().lastArea, .personal, "never read, never written for a note")
    }

    @MainActor
    func testATypedNoteGoesWhereTheTypeSheetsChipSentIt() async throws {
        let model = try model(split)
        XCTAssertEqual(model.destination, .personal)
        model.setDestination(.work)
        model.submitTyped(note, app: demoApp())
        await settle(model)
        XCTAssertEqual(Set(model.openTasks(in: .work).map(\.title)), ["Call the dentist", "Buy milk"])
        XCTAssertEqual(model.destination, .personal, "for that note only")

        model.setDestination(.work)
        model.resetDestination()
        XCTAssertEqual(model.destination, .personal, "a sheet closed without a note forgets its chip")
        model.setDestination(.work)
        model.micTapped(demoApp())
        let deadline = Date().addingTimeInterval(5)
        while model.phase != .listening && Date() < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(model.phase, .listening)
        XCTAssertEqual(model.captureArea, .personal, "a new voice note starts on the top list")
    }

    // Replaces testATappedNotificationShowsTheListThatHoldsItsTask: both lists are in one scroll, so the list comes to
    // the task instead of switching to its list.
    @MainActor
    func testATappedNotificationScrollsToItsTaskAndWashesIt() throws {
        var seed = TodoState()
        let work = seed.add([TodoDraft(title: "Send Priya the deck", due: .time(at(2026, 10, 20, 10)))], area: .work,
                            at: at(2026, 10, 19, 9))[0]
        seed.lastArea = .personal
        let model = try model([], seed: seed)
        XCTAssertEqual(TodoNotifications.taskID(TodoNotifications.identifier(work.id)), work.id)
        XCTAssertNil(TodoNotifications.taskID("taken.nudge.2026-10-19"))

        model.reveal(work.id)
        XCTAssertEqual(model.scrollTarget, work.id, "the list brings it into view")
        XCTAssertEqual(model.arrived, [work.id], "and washes it for a moment")
        XCTAssertEqual(model.store.load().lastArea, .personal, "where notes go never changes")
        model.scrollTarget = nil
        model.reveal(UUID())
        XCTAssertNil(model.scrollTarget, "a to-do that has gone changes nothing")
    }

    @MainActor
    func testANoteIsSavedAsSaidAtOnceHiddenWhileSortedThenBroughtIntoView() async throws {
        let model = try model(split, delay: .milliseconds(300))
        XCTAssertTrue(model.hiddenTaskIDs.isEmpty)
        model.submitTyped("Call the dentist. Buy milk.", app: demoApp())
        let deadline = Date().addingTimeInterval(5)
        while model.hiddenTaskIDs.isEmpty && model.phase == .sorting && Date() < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(model.hiddenTaskIDs.count, 2, "one line per sentence, saved at once")
        let lines = model.store.load().tasks.map(\.title)
        XCTAssertEqual(lines, ["Call the dentist", "Buy milk"], "in the file already, so nothing said is lost")
        XCTAssertTrue(model.openTasks(in: .personal).isEmpty, "and out of the list while it is sorted")
        await settle(model)
        XCTAssertTrue(model.hiddenTaskIDs.isEmpty)
        let open = model.openTasks(in: .personal)
        XCTAssertEqual(Set(open.map(\.title)), ["Call the dentist", "Buy milk"])
        let first = try XCTUnwrap(model.store.load().tasks.first { $0.title == "Call the dentist" })
        XCTAssertEqual(model.scrollTarget, first.id, "the list scrolls to the note's first task")
    }

    @MainActor
    func testALongTypedNoteIsSortedInPartsAndNotOfferedAsOne() async throws {
        let actions = (0..<6).map { "call person\($0)" }
        let raw = actions.map { RawTodo(spoken: $0, title: $0.capitalized) }
        let long = (0..<6).map { "Please \(actions[$0]) about the thing number \($0) today, and then there are a few more words." }
            .joined(separator: " ")
        let model = try model(raw)
        model.submitTyped(long, app: demoApp())
        await settle(model)
        XCTAssertEqual(model.openTasks(in: .personal).count, 6, "\(model.openTasks(in: .personal).map(\.title))")
        XCTAssertNil(model.keepOffer, "a long note's tasks are not one thought")
        XCTAssertNil(model.notice, "every part was sorted")
    }

    @MainActor
    func testNoModelSavesTheNoteOneLinePerSentenceAndSaysSo() async throws {
        let url = temporaryStoreURL().deletingLastPathComponent().appendingPathComponent(TodoStore.fileName)
        let model = TodoModel(store: TodoStore(fileURL: url), isDemo: true, launchScreen: nil, clockNow: { Date() },
                              makeSorter: { FallbackSorter(reason: .needsAppleIntelligence) })
        model.submitTyped("Call the dentist. Buy milk.", app: demoApp())
        await settle(model)
        XCTAssertEqual(Set(model.openTasks(in: .personal).map(\.title)), ["Call the dentist", "Buy milk"])
        XCTAssertEqual(model.notice, TodoCopy.needsAppleIntelligence)
    }

    // MARK: Where a note goes, and what the list hides

    @MainActor
    func testTheDestinationIsTheTopListUnlessTheChipChangesItForOneNote() async throws {
        let model = try model(split, delay: .milliseconds(300), seed: TodoState(areaOrder: [.work, .personal]))
        XCTAssertEqual(model.destination, .work, "the top list")
        let file = try Data(contentsOf: model.store.fileURL)
        model.setDestination(.personal)
        XCTAssertEqual(model.destination, .personal)
        XCTAssertEqual(try Data(contentsOf: model.store.fileURL), file, "never saved: it is for this note only")

        model.submitTyped(note, app: demoApp())
        XCTAssertEqual(model.phase, .sorting)
        model.setDestination(.work)
        XCTAssertEqual(model.destination, .personal, "fixed while the note is sorted")
        await settle(model)
        XCTAssertEqual(model.destination, .work, "once the note is saved, the next one starts on the top list again")

        model.write { $0.setAreaOrder([.personal, .work]) }
        XCTAssertEqual(model.destination, .personal, "and follows the order")
        XCTAssertEqual(model.store.load().areaOrder, [.personal, .work])
    }

    @MainActor
    func testTheChipMovesTheNoteBeingHeard() async throws {
        let model = try model(split)
        let app = demoApp()
        model.micTapped(app)
        let deadline = Date().addingTimeInterval(5)
        while model.phase != .listening && Date() < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(model.phase, .listening, "the demo listens without a microphone")
        XCTAssertEqual(model.hapticsOn, app.hapticsOn, "the model follows the app's haptics setting")
        XCTAssertEqual(model.captureArea, .personal)
        model.setDestination(.work)
        XCTAssertEqual(model.captureArea, .work, "the note being heard now goes to Work")
        XCTAssertEqual(model.destination, .work)
        model.setDestination(.personal)
        XCTAssertEqual(model.captureArea, .personal, "and back")
        XCTAssertEqual(model.store.load().lastArea, .personal, "the list in view never changes with it")
        XCTAssertEqual(model.demoElapsed, TodoModel.demoRecordingElapsed, "a fixed time on the demo's card")
    }

    // MARK: The demo's listening screens

    @MainActor
    func testTheDemoListeningScreensHoldAFixedTime() async {
        let recording = TodoModel.fromLaunchArguments(["Taken", "-demo", "-screen", "todo-recording"])
        XCTAssertEqual(recording.phase, .listening)
        XCTAssertEqual(recording.demoElapsed, 12)
        XCTAssertEqual(TodoCopy.noteTime(elapsed: recording.demoElapsed ?? 0).text, "0:12")
        XCTAssertEqual(recording.captureArea, .personal, "the chip reads Into Personal")

        let cap = TodoModel.fromLaunchArguments(["Taken", "-demo", "-screen", "todo-cap"])
        XCTAssertEqual(cap.phase, .listening)
        XCTAssertEqual(TodoCopy.noteTime(elapsed: cap.demoElapsed ?? 0).text, "0:40 left", "4:20 heard")
        XCTAssertTrue(TodoModel.opensOnTodo("todo-cap"))
        XCTAssertTrue(TodoModel.opensOnTodo("todo-type"))

        let typing = AppModel.fromLaunchArguments(["Taken", "-demo", "-screen", "todo-type"])
        XCTAssertEqual(typing.tab, .todo)
        await typing.applyLaunchScreen()
        XCTAssertEqual(typing.sheet, .todoType, "the type sheet with its chip")
    }

    // MARK: The voice note log (internal builds only)

    @MainActor
    func testATypedNoteIsRecordedInTheVoiceNoteLogAndEraseAllClearsIt() async throws {
        let model = try model(split)
        let log = VoiceNoteLogStore(fileURL: temporaryStoreURL().deletingLastPathComponent()
            .appendingPathComponent("voice-notes.json"))
        model.voiceLog = log
        model.setDestination(.work)
        model.submitTyped(note, app: demoApp())
        await settle(model)
        log.flush()
        let trace = try XCTUnwrap(log.load().first)
        XCTAssertEqual(trace.input, .typed)
        XCTAssertEqual(trace.list, "work")
        XCTAssertTrue(trace.chipChanged, "the chip sent it to Work")
        XCTAssertEqual(trace.finalTranscript, note)
        XCTAssertEqual(trace.saved.map(\.title), ["Call the dentist", "Buy milk"])
        XCTAssertEqual(trace.parts.count, 1)
        XCTAssertEqual(trace.parts.first?.outcome, "model")
        XCTAssertNotNil(trace.marks.first { $0.label == "saved" })

        model.eraseAll()
        XCTAssertFalse(FileManager.default.fileExists(atPath: log.fileURL.path), "Erase all data takes the log too")
    }

    @MainActor
    func testEraseAllDataWhileANoteIsSortedLeavesNoLog() async throws {
        let model = try model(split, delay: .milliseconds(400))
        let log = VoiceNoteLogStore(fileURL: temporaryStoreURL().deletingLastPathComponent()
            .appendingPathComponent("voice-notes.json"))
        model.voiceLog = log
        model.submitTyped(note, app: demoApp())
        let deadline = Date().addingTimeInterval(5)
        while model.hiddenTaskIDs.isEmpty && model.phase == .sorting && Date() < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        log.flush()
        XCTAssertEqual(log.load().count, 1, "recorded at the stop")
        XCTAssertEqual(model.phase, .sorting)
        model.eraseAll()
        await settle(model)
        log.flush()
        XCTAssertTrue(log.load().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: log.fileURL.path), "the note's save never writes it back")
    }

    // MARK: The chip after a reorder, and after a 5-minute stop

    @MainActor
    func testTheChipStillMovesTheNoteWhenTheListsAreReorderedMidNote() async throws {
        let model = try model(split)
        model.micTapped(demoApp())
        let deadline = Date().addingTimeInterval(5)
        while model.phase != .listening && Date() < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(model.captureArea, .personal)
        XCTAssertTrue(model.moveSection(.work, toTop: true))
        XCTAssertEqual(model.state.topArea, .work)
        XCTAssertEqual(model.captureArea, .personal, "moving the lists never moves the note being heard")
        // The card reads "Into Personal"; its chip sends the note to Work.
        model.setDestination(.work)
        XCTAssertEqual(model.captureArea, .work)
        model.setDestination(.personal)
        XCTAssertEqual(model.captureArea, .personal, "and back")
    }

    @MainActor
    func testAfterAFiveMinuteStopTheNextTapKeepsGoingOnTheSameList() async throws {
        let model = try model(split)
        let app = demoApp()
        // A note the chip sent to Work, stopped at 5 minutes (the stop itself needs a microphone).
        await model.save(note: note, area: .work, stoppedAtCap: true)
        XCTAssertEqual(model.notice, TodoCopy.stoppedAtCap)
        XCTAssertEqual(model.destination, .personal, "the chip is for one note")
        model.micTapped(app)
        let deadline = Date().addingTimeInterval(5)
        while model.phase != .listening && Date() < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(model.phase, .listening)
        XCTAssertEqual(model.captureArea, .work, "Tap the mic to keep going: the monologue stays on Work")

        let other = try self.model(split)
        await other.save(note: note, area: .work, stoppedAtCap: false)
        XCTAssertNotEqual(other.notice, TodoCopy.stoppedAtCap)
        other.micTapped(app)
        let later = Date().addingTimeInterval(5)
        while other.phase != .listening && Date() < later {
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(other.captureArea, .personal, "any other note: the next one starts on the top list")
    }
}
