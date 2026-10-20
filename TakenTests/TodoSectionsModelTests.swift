import XCTest
@testable import Taken

/// The one list wired to the model (SPEC 3.10): a heading dropped on the other list, or moved from its menu or by
/// VoiceOver, writes the new order to todos.json, where the widget and Shortcuts read it, and the next note goes to the
/// list on top. A drop on its own list writes nothing. A temporary file stands in for todos.json.
final class TodoSectionsModelTests: XCTestCase {
    @MainActor
    private func model(_ seed: TodoState) throws -> TodoModel {
        let url = temporaryStoreURL().deletingLastPathComponent().appendingPathComponent(TodoStore.fileName)
        let store = TodoStore(fileURL: url)
        try store.replace(with: seed)
        return TodoModel(store: store, isDemo: true, launchScreen: nil, clockNow: { Date() })
    }

    /// Two open on Personal and one done today, one open on Work.
    private func seed() -> TodoState {
        let now = Date()
        var state = TodoState()
        state.add([TodoDraft(title: "Buy milk"), TodoDraft(title: "Ring Mum")], at: now.addingTimeInterval(-60))
        let done = state.add([TodoDraft(title: "Pay the cleaner")], at: now.addingTimeInterval(-50))[0]
        state.complete(done.id, at: now.addingTimeInterval(-40))
        state.add([TodoDraft(title: "Send the deck")], area: .work, at: now.addingTimeInterval(-30))
        return state
    }

    @MainActor
    func testDroppingWorkOnPersonalPutsWorkOnTopInTheFile() throws {
        let model = try model(seed())
        XCTAssertEqual(model.sectionRows.filter(\.isHeader).map(\.area), [.personal, .work])
        XCTAssertTrue(model.isOnTop(.personal))
        XCTAssertEqual(model.destination, .personal, "notes go to the list on top")

        XCTAssertTrue(model.dropSection(.work, on: .personal))
        XCTAssertEqual(model.state.areaOrder, [.work, .personal])
        XCTAssertEqual(model.store.load().areaOrder, [.work, .personal], "written, so the widget and Shortcuts follow")
        XCTAssertEqual(model.sectionRows.filter(\.isHeader).map(\.area), [.work, .personal])
        XCTAssertEqual(model.sectionRows.first?.id, .header(.work))
        XCTAssertTrue(model.isOnTop(.work))
        XCTAssertEqual(model.destination, .work, "and the next note goes to Work")
        XCTAssertEqual(model.store.load().lastArea, .personal, "the old list in view is left as it was")
        XCTAssertEqual(Set(model.store.load().tasks.map(\.area)), [.personal, .work], "no task changes list")

        XCTAssertTrue(model.dropSection(.personal, on: .work), "and back")
        XCTAssertEqual(model.store.load().areaOrder, [.personal, .work])
    }

    @MainActor
    func testADropOnItsOwnListWritesNothing() throws {
        let model = try model(seed())
        let before = try Data(contentsOf: model.store.fileURL)
        XCTAssertFalse(model.dropSection(.personal, on: .personal), "it goes back where it came from")
        XCTAssertFalse(model.dropSection(.work, on: .work))
        XCTAssertFalse(model.moveSection(.personal, toTop: true), "already on top")
        XCTAssertEqual(try Data(contentsOf: model.store.fileURL), before, "the file byte for byte")
    }

    @MainActor
    func testTheMenuAndVoiceOverMoveAListToTheTopOrTheBottom() throws {
        let model = try model(seed())
        XCTAssertTrue(model.moveSection(.work, toTop: true))
        XCTAssertEqual(model.store.load().areaOrder, [.work, .personal])
        XCTAssertTrue(model.moveSection(.work, toTop: false))
        XCTAssertEqual(model.store.load().areaOrder, [.personal, .work])
        XCTAssertTrue(model.moveSection(.personal, toTop: false))
        XCTAssertEqual(model.store.load().areaOrder, [.work, .personal])
    }

    @MainActor
    func testTheLineUnderTheTitleCountsBothLists() throws {
        let model = try model(seed())
        XCTAssertEqual(model.listSummary, "3 open, 1 done today")
        XCTAssertTrue(model.hasListedTasks)
        XCTAssertEqual(model.openCount(in: .personal), 2)
        XCTAssertEqual(model.openCount(in: .work), 1)
        _ = model.dropSection(.work, on: .personal)
        XCTAssertEqual(model.listSummary, "3 open, 1 done today", "the order changes no count")

        let empty = try self.model(TodoState())
        XCTAssertNil(empty.listSummary)
        XCTAssertFalse(empty.hasListedTasks, "the line that teaches it shows, with no headings")
        XCTAssertTrue(empty.sectionRows.isEmpty)
    }

    @MainActor
    func testEraseAllPutsPersonalBackOnTop() throws {
        let model = try model(seed())
        _ = model.moveSection(.work, toTop: true)
        model.eraseAll()
        XCTAssertEqual(model.store.load().areaOrder, [.personal, .work])
        XCTAssertFalse(model.hasListedTasks)
    }
}
