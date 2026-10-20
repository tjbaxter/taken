import XCTest
@testable import Taken

/// The To-do tab's model wired together (TodoModel, SPEC 3.10): Keep as one comes only after a note the model split and
/// goes on any change, a note goes to the list in view at the tap, the switch holds while a note is sorted, a tapped
/// due-time notification shows its task's list, the chip changes where one note goes, and the note being sorted stays
/// out of the list. A temporary file and canned model answers stand in for todos.json and the on-device model.
final class TodoModelTests: XCTestCase {
    /// Sorts every note with canned answers through the real validation, as the on-device model's answer is.
    private struct Canned: TaskExtractor {
        let raw: [RawTodo]
        var delay: Duration = .zero

        func prepare() async {}

        func extract(transcript: String, context: TodoContext) async -> TodoExtraction {
            if delay > .zero { try? await Task.sleep(for: delay) }
            return TodoExtraction(drafts: TodoValidation.validate(raw, transcript: transcript, context: context), sorting: .model)
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
                         makeExtractor: { Canned(raw: raw, delay: delay) })
    }

    @MainActor
    private func demoApp() -> AppModel {
        AppModel.fromLaunchArguments(["Taken", "-demo", "-screen", "today"])
    }

    /// Waits for the note being sorted to be saved.
    @MainActor
    private func settle(_ model: TodoModel) async {
        let deadline = Date().addingTimeInterval(5)
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

        let switched = try model(split)
        _ = try await offered(switched, app)
        switched.select(.work)
        XCTAssertNil(switched.keepOffer, "the other list came into view")

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

    @MainActor
    func testANoteGoesToTheListInViewAndTheSwitchHoldsWhileItIsSorted() async throws {
        let model = try model(split, delay: .milliseconds(300))
        let app = demoApp()
        model.select(.work)
        XCTAssertEqual(model.area, .work)
        model.submitTyped(note, app: app)
        XCTAssertEqual(model.phase, .sorting)
        model.select(.personal)
        XCTAssertEqual(model.area, .work, "fixed while the note is sorted: it goes to the list the card names")
        await settle(model)
        XCTAssertEqual(Set(model.openTasks(in: .work).map(\.title)), ["Call the dentist", "Buy milk"])
        XCTAssertTrue(model.openTasks(in: .personal).isEmpty)
        model.select(.personal)
        XCTAssertEqual(model.area, .personal, "and free again once it is saved")
    }

    @MainActor
    func testATappedNotificationShowsTheListThatHoldsItsTask() throws {
        var seed = TodoState()
        let work = seed.add([TodoDraft(title: "Send Priya the deck", due: .time(at(2026, 10, 20, 10)))], area: .work,
                            at: at(2026, 10, 19, 9))[0]
        let personal = seed.add([TodoDraft(title: "Call mum")], at: at(2026, 10, 19, 9))[0]
        seed.lastArea = .personal
        let model = try model([], seed: seed)
        XCTAssertEqual(TodoNotifications.taskID(TodoNotifications.identifier(work.id)), work.id)
        XCTAssertNil(TodoNotifications.taskID("taken.nudge.2026-10-19"))

        model.reveal(work.id)
        XCTAssertEqual(model.area, .work, "a Work reminder lands on Work")
        XCTAssertEqual(model.store.load().lastArea, .work, "so Taken reopens on it and the widget shows it")
        model.reveal(UUID())
        XCTAssertEqual(model.area, .work, "a to-do that has gone changes nothing")
        model.reveal(personal.id)
        XCTAssertEqual(model.area, .personal)
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
    }

    @MainActor
    func testTheNoteBeingSortedIsHiddenUntilItsTasksReplaceIt() async throws {
        let model = try model(split, delay: .milliseconds(300))
        XCTAssertTrue(model.hiddenTaskIDs.isEmpty)
        model.submitTyped(note, app: demoApp())
        let deadline = Date().addingTimeInterval(5)
        while model.hiddenTaskIDs.isEmpty && model.phase == .sorting && Date() < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        let whole = try XCTUnwrap(model.hiddenTaskIDs.first, "the note is saved whole at once")
        XCTAssertEqual(model.hiddenTaskIDs.count, 1)
        XCTAssertNotNil(model.store.load().task(whole), "in the file already, so nothing said is lost")
        XCTAssertTrue(model.openTasks(in: .personal).isEmpty, "and out of the list while it is sorted")
        await settle(model)
        XCTAssertTrue(model.hiddenTaskIDs.isEmpty)
        XCTAssertEqual(Set(model.openTasks.map(\.title)), ["Call the dentist", "Buy milk"])

        let first = try XCTUnwrap(model.openTasks.first)
        model.scrollTarget = first.id
        XCTAssertEqual(model.scrollTarget, first.id, "the list can be asked to bring a task into view")
        model.scrollTarget = nil
        XCTAssertNil(model.scrollTarget)
    }
}
