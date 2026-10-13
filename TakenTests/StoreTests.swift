import XCTest
@testable import Taken

final class StoreTests: XCTestCase {

    func testRoundTrip() throws {
        let store = TakenStore(fileURL: temporaryStoreURL(), postsChangeNotifications: false)
        XCTAssertEqual(store.load(), StackState(), "missing file reads as an empty stack")

        let created = at(2026, 10, 1, 8)
        var state = StackState(items: [
            makeItem("Vitamin D3", "VD3", created: created, sortIndex: 0),
            makeItem("Fish Oil", "FSH", .daily(times: 2), created: created, sortIndex: 1),
            makeItem("Zinc", "ZNC", .alternateDays, created: created, sortIndex: 2),
            makeItem("Minoxidil", "MIN", .weekdays([2, 4, 6]), created: created, sortIndex: 3),
        ])
        state.logDose(itemId: state.items[0].id, at: Date(timeIntervalSince1970: 1_791_000_000.123), timeZone: london)
        state.updateItem(id: state.items[2].id, name: "Zinc", code: "ZNC", frequency: .onceDaily, now: at(2026, 10, 5, 9))
        state.setArchived(id: state.items[3].id, archived: true, now: at(2026, 10, 6, 9))
        state.setArchived(id: state.items[3].id, archived: false, now: at(2026, 10, 9, 9))
        state.settings = StackSettings(dayStartHour: 3, reminderEnabled: true, reminderMinutes: 20 * 60 + 30, hapticsEnabled: false)
        XCTAssertEqual(state.doses.first?.utcOffset, 3600, "BST")
        XCTAssertEqual(state.items[2].pastFrequencies, [FrequencyEra(until: at(2026, 10, 5, 9), frequency: .alternateDays)])
        XCTAssertEqual(state.items[3].pauses, [Pause(from: at(2026, 10, 6, 9), until: at(2026, 10, 9, 9))])

        try store.replace(with: state)
        XCTAssertEqual(store.load(), state)

        let reopened = TakenStore(fileURL: store.fileURL, postsChangeNotifications: false)
        XCTAssertEqual(reopened.load(), state, "a second process sees the same data")
    }

    func testUpdateReturnsValueAndPersists() throws {
        let store = TakenStore(fileURL: temporaryStoreURL(), postsChangeNotifications: false)
        let result = try store.update { state in
            state.addItems([ItemDraft(name: "Creatine")], now: at(2026, 10, 12, 9))
        }
        XCTAssertEqual(result.value.first?.code, "CRE")
        XCTAssertEqual(store.load().items.count, 1)
    }

    func testDecodesOlderFilesWithMissingKeys() throws {
        let json = #"{"items":[{"id":"6F1C2D3E-4A5B-4C6D-8E9F-0A1B2C3D4E5F","name":"Zinc","code":"ZNC","frequency":{"kind":"alt"},"createdAt":1791000000,"archived":false,"sortIndex":0}],"doses":[{"id":"7A1C2D3E-4A5B-4C6D-8E9F-0A1B2C3D4E5F","itemId":"6F1C2D3E-4A5B-4C6D-8E9F-0A1B2C3D4E5F","takenAt":1791000000}]}"#
        let state = try TakenStore.decode(Data(json.utf8))
        XCTAssertEqual(state.items.first?.frequency, .alternateDays)
        XCTAssertEqual(state.settings, StackSettings(), "missing settings fall back to defaults")
        XCTAssertNil(state.items.first?.archivedAt)
        XCTAssertNil(state.items.first?.pastFrequencies, "files from before frequency history still load")
        XCTAssertNil(state.items.first?.pauses)
        XCTAssertEqual(state.doses.count, 1)
        XCTAssertNil(state.doses.first?.utcOffset, "doses from before offsets were recorded still load")
    }

    func testCorruptFileIsKeptAsideNotOverwrittenSilently() throws {
        let url = temporaryStoreURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: url)
        let store = TakenStore(fileURL: url, postsChangeNotifications: false)
        XCTAssertEqual(store.load(), StackState())
        try store.update { $0.addItems([ItemDraft(name: "Zinc")], now: Date()) }
        let siblings = try FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path)
        XCTAssertTrue(siblings.contains { $0.hasPrefix("taken-unreadable-") }, "\(siblings)")
        XCTAssertEqual(store.load().items.count, 1)
    }

    func testConcurrentWritersNeverLoseADose() throws {
        let url = temporaryStoreURL()
        let setup = TakenStore(fileURL: url, postsChangeNotifications: false)
        let item = try setup.update { state in
            state.addItems([ItemDraft(name: "Vitamin D3")], now: Date())
        }.value[0]

        let writers = 6
        let dosesEach = 20
        let itemID = item.id
        DispatchQueue.concurrentPerform(iterations: writers) { writer in
            // Each writer is its own store instance, as the app, widget and intents are.
            let store = TakenStore(fileURL: url, postsChangeNotifications: false)
            for index in 0..<dosesEach {
                let when = Date(timeIntervalSince1970: 1_791_000_000 + Double(writer * 1_000 + index))
                _ = try? store.update { state in state.logDose(itemId: itemID, at: when, timeZone: london) }
            }
        }
        XCTAssertEqual(setup.load().doses.count, writers * dosesEach)
    }

    func testCSVExport() {
        let created = at(2026, 10, 1, 8)
        let vd3 = makeItem("Vitamin D3", "VD3", created: created, sortIndex: 0)
        let odd = makeItem("Fish Oil, \"Triple\"", "FSH", created: created, sortIndex: 1)
        var state = StackState(items: [vd3, odd])
        state.logDose(itemId: odd.id, at: at(2026, 10, 12, 19, 5), timeZone: london)
        state.logDose(itemId: vd3.id, at: at(2026, 10, 12, 7, 42), timeZone: london)
        state.doses.append(Dose(itemId: UUID(), takenAt: at(2026, 10, 12, 8)))

        let csv = CSVExport.make(state: state, timeZone: london)
        let lines = csv.split(separator: "\n").map(String.init)
        XCTAssertEqual(lines, [
            "date,time,item,code",
            "2026-10-12,07:42,Vitamin D3,VD3",
            "2026-10-12,19:05,\"Fish Oil, \"\"Triple\"\"\",FSH",
        ])
    }
}
