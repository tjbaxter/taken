import XCTest
@testable import Taken

/// The To-do tab's model wired together (TodoModel, SPEC 3.10): Keep as one comes only after a short note the model
/// split and goes on any change; every note, typed to-do and quick capture lands on the one list, whatever the file's
/// old list values say; a note is saved at once as said and hidden until its tasks replace it, then brought into view; a
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
        XCTAssertEqual(Set(model.openTasks.map(\.title)), ["Call the dentist", "Buy milk"])

        model.keepAsOne()
        XCTAssertNil(model.keepOffer, "once only")
        XCTAssertEqual(model.openTasks.map(\.title), ["Call the dentist and buy milk"])
        XCTAssertEqual(model.store.load().tasks.map(\.title), ["Call the dentist and buy milk"], "and saved")
    }

    @MainActor
    func testKeepAsOneIsNotOfferedForANoteOfOneToDo() async throws {
        let model = try model([RawTodo(spoken: "call the dentist", title: "Call the dentist")])
        model.submitTyped("call the dentist", app: demoApp())
        await settle(model)
        XCTAssertEqual(model.openTasks.map(\.title), ["Call the dentist"])
        XCTAssertNil(model.keepOffer)
    }

    @MainActor
    func testKeepAsOneGoesOnAnyChangeAMicTapOrLeavingTheTab() async throws {
        let app = demoApp()

        let deleted = try model(split)
        let deleting = try await offered(deleted, app)
        deleted.delete(try XCTUnwrap(deleted.state.task(deleting.ids[1])))
        XCTAssertNil(deleted.keepOffer, "a task deleted")

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
        XCTAssertEqual(left.openTasks.count, 2, "nothing to keep once it has gone")
    }

    // Replaces testANoteGoesToTheTopListWhereverLastAreaPoints and testATypedNoteGoesWhereTheTypeSheetsChipSentIt: with
    // one list there is nowhere else to go (Tom 2026-10-21: "voice note mode, it should just literally go into one
    // table"). A file a list build wrote, Work on top and in view, with Tom's "LinkedIn ICP" on Work.
    @MainActor
    private func listBuildSeed() -> TodoState {
        var seed = TodoState(lastArea: .work, areaOrder: [.work, .personal])
        seed.tasks.append(TodoTask(title: "LinkedIn ICP", createdAt: Date().addingTimeInterval(-3_600), noteId: UUID(),
                                   area: .work))
        return seed
    }

    @MainActor
    func testATypedToDoLandsOnTheOneListBesideFormerWorkTasks() async throws {
        let model = try model(split, delay: .milliseconds(300), seed: listBuildSeed())
        XCTAssertEqual(model.openTasks.map(\.title), ["LinkedIn ICP"], "a former Work task is on the one list")
        model.submitTyped(note, app: demoApp())
        XCTAssertEqual(model.phase, .sorting)
        await settle(model)
        XCTAssertEqual(Set(model.openTasks.map(\.title)), ["Call the dentist", "Buy milk", "LinkedIn ICP"])
        let saved = model.store.load()
        XCTAssertEqual(saved.tasks.filter { $0.title != "LinkedIn ICP" }.map(\.area), [.personal, .personal],
                       "new tasks are Personal, never the list on top or in view")
        XCTAssertEqual(saved.areaOrder, [.work, .personal], "the file's old order is kept as it was")
        XCTAssertEqual(saved.lastArea, .work)
        XCTAssertEqual(saved.tasks.first { $0.title == "LinkedIn ICP" }?.area, .work)
    }

    @MainActor
    func testAVoiceNoteAndAQuickCaptureLandOnTheOneList() async throws {
        let app = demoApp()
        let voice = try model(split, seed: listBuildSeed())
        voice.micTapped(app)
        try await waitForListening(voice)
        XCTAssertEqual(voice.phase, .listening, "the demo listens without a microphone")
        // The stop itself needs a microphone: the save it ends in stands in for it.
        await voice.save(note: note, stoppedAtCap: false)
        XCTAssertEqual(voice.phase, .idle)
        XCTAssertEqual(Set(voice.openTasks.map(\.title)), ["Call the dentist", "Buy milk", "LinkedIn ICP"])

        let quick = try model(split, seed: listBuildSeed())
        quick.startFromRequest(app)
        try await waitForListening(quick)
        XCTAssertEqual(quick.phase, .listening)
        await quick.save(note: "call the dentist", stoppedAtCap: false)
        XCTAssertEqual(Set(quick.openTasks.map(\.title)), ["Call the dentist", "LinkedIn ICP"])
        XCTAssertEqual(quick.store.load().tasks.filter { $0.title == "Call the dentist" }.map(\.area), [.personal])
    }

    @MainActor
    private func waitForListening(_ model: TodoModel) async throws {
        let deadline = Date().addingTimeInterval(5)
        while model.phase != .listening && Date() < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    // Replaces testATappedNotificationShowsTheListThatHoldsItsTask: one list, so the list comes to the task, a former
    // Work one too.
    @MainActor
    func testATappedNotificationScrollsToItsTaskAndWashesIt() throws {
        var seed = TodoState()
        let work = TodoTask(title: "Send Priya the deck", due: .time(at(2026, 10, 20, 10)), createdAt: at(2026, 10, 19, 9),
                            noteId: UUID(), area: .work)
        seed.tasks.append(work)
        let model = try model([], seed: seed)
        XCTAssertEqual(TodoNotifications.taskID(TodoNotifications.identifier(work.id)), work.id)
        XCTAssertNil(TodoNotifications.taskID("taken.nudge.2026-10-19"))

        model.reveal(work.id)
        XCTAssertEqual(model.scrollTarget, work.id, "the list brings it into view")
        XCTAssertEqual(model.arrived, [work.id], "and washes it for a moment")
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
        XCTAssertTrue(model.openTasks.isEmpty, "and out of the list while it is sorted")
        XCTAssertTrue(model.isEmpty, "so the list shows nothing of it yet")
        await settle(model)
        XCTAssertTrue(model.hiddenTaskIDs.isEmpty)
        let open = model.openTasks
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
        XCTAssertEqual(model.openTasks.count, 6, "\(model.openTasks.map(\.title))")
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
        XCTAssertEqual(Set(model.openTasks.map(\.title)), ["Call the dentist", "Buy milk"])
        XCTAssertEqual(model.notice, TodoCopy.needsAppleIntelligence)
    }

    // MARK: The demo's listening screens

    /// The original card (Tom 2026-10-21): no time while a note is young, one static "1 minute left" past 4:00, and the
    /// ring at a fixed level.
    @MainActor
    func testTheDemoListeningScreensShowTheOriginalCard() async throws {
        let recording = TodoModel.fromLaunchArguments(["Taken", "-demo", "-screen", "todo-recording"])
        XCTAssertEqual(recording.phase, .listening)
        XCTAssertFalse(recording.inLastMinute, "no time on the card before 4:00")
        XCTAssertEqual(recording.level, TodoDemo.level)
        XCTAssertEqual(recording.transcript, TodoDemo.transcript)

        let cap = TodoModel.fromLaunchArguments(["Taken", "-demo", "-screen", "todo-cap"])
        XCTAssertEqual(cap.phase, .listening)
        XCTAssertTrue(cap.inLastMinute, "a note past 4:00 says 1 minute left")
        XCTAssertTrue(TodoModel.opensOnTodo("todo-cap"))

        // A tap in the demo listens on the same card, and the model follows the app's haptics setting.
        let app = demoApp()
        let tapped = try model(split)
        tapped.micTapped(app)
        try await waitForListening(tapped)
        XCTAssertEqual(tapped.phase, .listening)
        XCTAssertEqual(tapped.hapticsOn, app.hapticsOn)
        XCTAssertFalse(tapped.inLastMinute)
    }

    // MARK: The voice note log (internal builds only)

    @MainActor
    func testATypedNoteIsRecordedInTheVoiceNoteLogAndEraseAllClearsIt() async throws {
        let model = try model(split)
        let log = VoiceNoteLogStore(fileURL: temporaryStoreURL().deletingLastPathComponent()
            .appendingPathComponent("voice-notes.json"))
        model.voiceLog = log
        model.submitTyped(note, app: demoApp())
        await settle(model)
        log.flush()
        let trace = try XCTUnwrap(log.load().first)
        XCTAssertEqual(trace.input, .typed)
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

    // MARK: After a 5-minute stop

    /// Replaces testAfterAFiveMinuteStopTheNextTapKeepsGoingOnTheSameList: one list, so the next tap simply keeps going.
    @MainActor
    func testAfterAFiveMinuteStopTheLineSaysSoAndTheNextTapKeepsGoing() async throws {
        let model = try model(split)
        let app = demoApp()
        // A note stopped at 5 minutes (the stop itself needs a microphone).
        await model.save(note: note, stoppedAtCap: true)
        XCTAssertEqual(model.notice, TodoCopy.stoppedAtCap)
        XCTAssertNil(model.keepOffer, "the 5-minute line comes first")
        XCTAssertEqual(Set(model.openTasks.map(\.title)), ["Call the dentist", "Buy milk"])
        model.micTapped(app)
        try await waitForListening(model)
        XCTAssertEqual(model.phase, .listening, "Tap the mic to keep going")

        let other = try self.model(split)
        await other.save(note: note, stoppedAtCap: false)
        XCTAssertNotEqual(other.notice, TodoCopy.stoppedAtCap)
        XCTAssertNotNil(other.keepOffer, "a short note split in two offers Keep as one")
    }
}
