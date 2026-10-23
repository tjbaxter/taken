import XCTest
@testable import Taken

/// weights.json (SPEC 3.12): the round trip, files from earlier and later builds, an unreadable file set aside, writers in
/// several processes at once, and Erase all data's set-aside copies.
final class WeightStoreTests: XCTestCase {

    private func temporaryWeightStore() -> WeightStore {
        WeightStore(fileURL: temporaryStoreURL().deletingLastPathComponent().appendingPathComponent(WeightStore.fileName),
                    postsChangeNotifications: false)
    }

    func testRoundTrip() throws {
        let store = temporaryWeightStore()
        XCTAssertEqual(store.load(), WeightState(), "a missing file is no weigh-ins and the tab off")
        XCTAssertNil(store.load().showsTab)

        var state = WeightState(showsTab: true, unit: .lb, range: .quarter, offerAnswered: true)
        let first = state.log(kg: 88.35, at: at(2026, 10, 21, 7, 42), timeZone: london)
        state.log(kg: 88.6, at: at(2026, 10, 20, 7, 5), timeZone: london)
        try store.replace(with: state)
        XCTAssertEqual(store.load(), state)
        XCTAssertEqual(WeightStore(fileURL: store.fileURL).load(), state, "a second process reads the same file")
        XCTAssertEqual(store.load().weighIn(first.id)?.utcOffset, 3600, "where it was logged, like a dose")
        XCTAssertEqual(store.load().last?.kg, 88.35)
        XCTAssertEqual(store.load().newestFirst.map(\.kg), [88.35, 88.6])

        let text = String(decoding: try WeightStore.encode(state), as: UTF8.self)
        for key in [#""showsTab":true"#, #""unit":"lb""#, #""range":"90d""#, #""offerAnswered":true"#, #""kg":88.35"#,
                    #""firstWeighInAt":"#] {
            XCTAssertTrue(text.contains(key), "\(key) in \(text)")
        }
        XCTAssertEqual(WeightStore.fileName, "weights.json")
        XCTAssertEqual(WeightStore.shared.fileURL.deletingLastPathComponent(),
                       TakenStore.defaultFileURL().deletingLastPathComponent(), "in the App Group, next to the log")
        XCTAssertEqual(WeightStore.shared.fileURL.lastPathComponent, "weights.json")
    }

    func testUpdateIsCoordinatedAndReturnsItsValue() throws {
        let store = temporaryWeightStore()
        let result = try store.update { $0.log(kg: 90, at: at(2026, 10, 22, 7), timeZone: london) }
        XCTAssertEqual(result.value.kg, 90)
        XCTAssertEqual(store.load().weighIns.count, 1)
        XCTAssertEqual(store.load().firstWeighInAt, at(2026, 10, 22, 7))
    }

    /// Missing fields (an earlier build), unknown ones and an unknown unit (a later one) never cost the file; one
    /// unreadable weigh-in never costs the others.
    func testDecodesOlderAndNewerFiles() throws {
        let json = """
            {"weighIns":[
              {"id":"6F1C2D3E-4A5B-4C6D-8E9F-0A1B2C3D4E5F","kg":88.35,"weighedAt":1792000000,"utcOffset":3600},
              {"kg":88.6,"weighedAt":1791900000},
              {"id":"7A1C2D3E-4A5B-4C6D-8E9F-0A1B2C3D4E5F","weighedAt":1791800000},
              {"kg":"heavy","weighedAt":1791700000},
              {"kg":-3,"weighedAt":1791600000}
            ],"unit":"st","range":"decade","showsTab":false,"futureKey":[1,2,3]}
            """
        let state = try WeightStore.decode(Data(json.utf8))
        XCTAssertEqual(state.weighIns.map(\.kg), [88.35, 88.6])
        XCTAssertEqual(state.weighIns.first?.utcOffset, 3600)
        XCTAssertNil(state.weighIns.last?.utcOffset)
        XCTAssertNil(state.unit, "stones are not a unit this build knows: the locale's")
        XCTAssertNil(state.range, "an unknown range reads as All")
        XCTAssertEqual(state.showsTab, false, "an explicit choice is kept")
        XCTAssertFalse(state.offerAnswered)
        XCTAssertNil(state.firstWeighInAt)
        XCTAssertEqual(state.schemaVersion, 1)
        XCTAssertEqual(try WeightStore.decode(Data("{}".utf8)), WeightState())
    }

    func testAnUnreadableFileIsKeptAsideNotOverwritten() throws {
        let store = temporaryWeightStore()
        let folder = store.fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: store.fileURL)
        XCTAssertEqual(store.load(), WeightState())
        try store.update { $0.log(kg: 88, at: Date(), timeZone: london) }
        let siblings = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        XCTAssertTrue(siblings.contains { $0.hasPrefix("weights-unreadable-") }, "\(siblings)")
        XCTAssertEqual(store.load().weighIns.count, 1)

        // Erase all data takes the set-aside copy and leaves every other file.
        try Data("x".utf8).write(to: folder.appendingPathComponent("taken.json"))
        store.removeSetAsideCopies()
        let left = try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
        XCTAssertEqual(left, ["taken.json", "weights.json"])
    }

    /// Each writer its own store, as two processes would be: no weigh-in is lost.
    func testConcurrentWritersNeverLoseAWeighIn() throws {
        let setup = temporaryWeightStore()
        try setup.replace(with: WeightState(showsTab: true))
        let url = setup.fileURL
        let writers = 6
        let each = 20
        DispatchQueue.concurrentPerform(iterations: writers) { writer in
            let store = WeightStore(fileURL: url, postsChangeNotifications: false)
            for index in 0..<each {
                let when = Date(timeIntervalSince1970: 1_792_000_000 + Double(writer * 1_000 + index) * 60)
                _ = try? store.update { $0.log(kg: 80 + Double(index) / 10, at: when, timeZone: london) }
            }
        }
        let state = setup.load()
        XCTAssertEqual(state.weighIns.count, writers * each)
        XCTAssertEqual(Set(state.weighIns.map(\.id)).count, writers * each)
        XCTAssertEqual(state.showsTab, true, "a write never drops the settings")
    }

    /// The model reads and writes through the store: the tab, the unit, the range and the offer's answer persist.
    @MainActor
    func testTheModelPersistsEveryChoice() throws {
        let store = temporaryWeightStore()
        let now = at(2026, 10, 22, 9)
        let model = WeightModel(store: store, isDemo: true, clockNow: { now })
        XCTAssertFalse(model.showsTab, "off by default")
        XCTAssertFalse(model.showsDataRows, "nothing in Profile's Data until the tab is on")
        model.setShowsTab(true)
        model.setUnit(.kg)
        model.setRange(.week)
        let saved = try XCTUnwrap(model.log(kg: 88.35, timeZone: london))
        XCTAssertEqual(saved.weighedAt, now)
        let reread = WeightModel(store: WeightStore(fileURL: store.fileURL), isDemo: true, clockNow: { now })
        XCTAssertTrue(reread.showsTab)
        XCTAssertEqual(reread.unit, .kg)
        XCTAssertEqual(reread.range, .week)
        XCTAssertEqual(reread.state.weighIns, [saved])
        XCTAssertTrue(reread.showsDataRows)

        let before = try XCTUnwrap(model.update(saved.id, kg: 88.4, at: at(2026, 10, 21, 7), timeZone: london))
        XCTAssertEqual(before, saved, "UNDO puts this back")
        XCTAssertEqual(model.state.weighIn(saved.id)?.kg, 88.4)
        model.restore(before)
        XCTAssertEqual(model.state.weighIns, [saved])
        XCTAssertEqual(model.delete(saved.id), saved)
        XCTAssertTrue(model.isEmpty)

        let line = model.importCSV("date,kg\n2026-10-20,88.6\n2026-10-21,88.35\n", locale: Locale(identifier: "en_GB"),
                                   timeZone: london)
        XCTAssertEqual(line, "Added 2 weigh-ins, read in kg.")
        XCTAssertEqual(model.importCSV("date,kg\n2026-10-20,88.6\n", timeZone: london),
                       "Nothing new: that weigh-in is already in Taken.")
        XCTAssertEqual(model.importCSV("no weights here", timeZone: london), WeightCopy.notFound)
        XCTAssertEqual(model.csv(timeZone: london).split(separator: "\n").first, "date,time,kg")
    }
}
