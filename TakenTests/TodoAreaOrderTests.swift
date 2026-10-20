import XCTest
@testable import Taken

/// The order of the To-do tab's two lists (`TodoState.areaOrder`, SPEC 3.10): every list exactly once, Personal first
/// until it is changed, read lossily so an older, damaged or later file never costs a task or a list, and always
/// written. The schema stays 1.
final class TodoAreaOrderTests: XCTestCase {
    private let tasks = #""tasks":[{"id":"6F1C2D3E-4A5B-4C6D-8E9F-0A1B2C3D4E5F","title":"Call the dentist","createdAt":1791000000,"area":"work"}]"#

    /// A file with one Work task and `areaOrder` set to this JSON value, or without the key.
    private func decoded(_ areaOrder: String?) throws -> TodoState {
        let order = areaOrder.map { #","areaOrder":\#($0)"# } ?? ""
        return try TodoStore.decode(Data("{\(tasks)\(order)}".utf8))
    }

    private func temporaryTodoStore() -> TodoStore {
        TodoStore(fileURL: temporaryStoreURL().deletingLastPathComponent().appendingPathComponent(TodoStore.fileName))
    }

    // MARK: Reading

    func testAFileWithoutTheOrderLoadsPersonalFirst() throws {
        XCTAssertEqual(TodoState.defaultAreaOrder, [.personal, .work])
        XCTAssertEqual(TodoState().areaOrder, [.personal, .work])
        let state = try decoded(nil)
        XCTAssertEqual(state.areaOrder, [.personal, .work], "every file written before the order")
        XCTAssertEqual(state.tasks.map(\.title), ["Call the dentist"])
        XCTAssertEqual(try TodoStore.decode(Data("{}".utf8)).areaOrder, [.personal, .work])
        XCTAssertEqual(try decoded("null").areaOrder, [.personal, .work])
    }

    func testTheOrderKeepsOnlyKnownListsEachOnce() throws {
        XCTAssertEqual(try decoded(#"["work","personal"]"#).areaOrder, [.work, .personal])
        XCTAssertEqual(try decoded(#"["personal","work"]"#).areaOrder, [.personal, .work])
        XCTAssertEqual(try decoded(#"["work","family","work"]"#).areaOrder, [.work, .personal],
                       "a list this build does not know and a second Work are dropped, the missing Personal added")
        XCTAssertEqual(try decoded(#"["work"]"#).areaOrder, [.work, .personal])
        XCTAssertEqual(try decoded(#"["family"]"#).areaOrder, [.personal, .work],
                       "an unknown list is never read as Personal, so Personal is never there twice")
        XCTAssertEqual(try decoded(#"["Work"]"#).areaOrder, [.personal, .work], "stored values only, as written")
        XCTAssertEqual(try decoded("[]").areaOrder, [.personal, .work])
    }

    func testAnUnreadableOrderGivesTheDefaultAndEveryTaskStillLoads() throws {
        for unreadable in [#""work""#, "3", "true", #"{"top":"work"}"#, #"["work",3]"#] {
            let state = try decoded(unreadable)
            XCTAssertEqual(state.areaOrder, [.personal, .work], unreadable)
            XCTAssertEqual(state.tasks.map(\.title), ["Call the dentist"], "the tasks still load: \(unreadable)")
            XCTAssertEqual(state.tasks.first?.area, .work, unreadable)
            XCTAssertEqual(state.schemaVersion, 1, unreadable)
        }
    }

    // MARK: Writing

    func testTheOrderIsAlwaysWrittenAndRoundTrips() throws {
        var state = TodoState()
        state.add([TodoDraft(title: "Send the deck")], area: .work, at: at(2026, 10, 20, 9))
        let plain = String(decoding: try TodoStore.encode(state), as: UTF8.self)
        XCTAssertTrue(plain.contains(#""areaOrder":["personal","work"]"#), "the default is written too: \(plain)")

        let store = temporaryTodoStore()
        state.setAreaOrder([.work, .personal])
        try store.replace(with: state)
        XCTAssertEqual(store.load(), state)
        XCTAssertEqual(store.load().areaOrder, [.work, .personal])
        XCTAssertEqual(TodoStore(fileURL: store.fileURL).load().areaOrder, [.work, .personal],
                       "a second process (the widget, a Shortcut) sees the same order")
        let text = String(decoding: try TodoStore.encode(state), as: UTF8.self)
        XCTAssertTrue(text.contains(#""areaOrder":["work","personal"]"#), text)
        XCTAssertTrue(text.contains(#""schemaVersion":1"#), "an additive change: the schema stays 1: \(text)")
        XCTAssertTrue(text.contains(#""lastArea":"personal""#), "the list in view is its own key, unchanged: \(text)")
    }

    func testSettingTheOrderKeepsEveryListOnce() {
        var state = TodoState()
        state.setAreaOrder([.work])
        XCTAssertEqual(state.areaOrder, [.work, .personal])
        state.setAreaOrder([.personal, .personal, .work, .work])
        XCTAssertEqual(state.areaOrder, [.personal, .work])
        state.setAreaOrder([])
        XCTAssertEqual(state.areaOrder, [.personal, .work])
        XCTAssertEqual(TodoState(areaOrder: [.work, .work]).areaOrder, [.work, .personal])
        XCTAssertEqual(TodoState.normalized([.work, .personal, .work]), [.work, .personal])
    }

    func testEraseAllPutsPersonalBackOnTop() {
        var state = TodoState(lastArea: .work, areaOrder: [.work, .personal])
        state.add([TodoDraft(title: "Send the deck")], area: .work, at: at(2026, 10, 20, 9))
        state.eraseAll()
        XCTAssertTrue(state.tasks.isEmpty)
        XCTAssertEqual(state.areaOrder, [.personal, .work])
        XCTAssertEqual(state.lastArea, .personal)
        XCTAssertEqual(state.firstNoteAt, at(2026, 10, 20, 9), "erasing never opens the first note again")
    }

    // MARK: Reading in order

    func testOpenTasksInListOrderPutTheTopListFirst() {
        let clock = londonClock()
        var state = TodoState()
        state.add([TodoDraft(title: "Buy milk"), TodoDraft(title: "Ring Mum")], at: at(2026, 10, 20, 8))
        let work = state.add([TodoDraft(title: "Send the deck", due: .time(at(2026, 10, 20, 16))),
                              TodoDraft(title: "Book the room")], area: .work, at: at(2026, 10, 20, 9))
        state.complete(work[1].id, at: at(2026, 10, 20, 10))

        XCTAssertEqual(state.openTasksInListOrder(clock: clock).map(\.title), ["Buy milk", "Ring Mum", "Send the deck"])
        state.setAreaOrder([.work, .personal])
        XCTAssertEqual(state.openTasksInListOrder(clock: clock).map(\.title), ["Send the deck", "Buy milk", "Ring Mum"],
                       "the top list first, each list in its own order, done tasks left out")
        XCTAssertEqual(Set(state.openTasksInListOrder(clock: clock).map(\.id)), Set(state.openTasks(clock: clock).map(\.id)))
    }
}
