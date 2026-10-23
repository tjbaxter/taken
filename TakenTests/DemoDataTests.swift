import XCTest
@testable import Taken

/// The App Store sets' demo stacks (`-demo-stack us|neutral`, REDESIGN.md "App Store pack for 1.1"): English (U.S.)
/// names generic medicines and has a weekly Semaglutide row; every other storefront gets the neutral stack, with a
/// "Weekly shot" row and no prescription-only medicine. Every other capture keeps the stack it always had.
final class DemoDataTests: XCTestCase {

    /// Names the neutral set must never show: the prescription-only chips and medicines (Guideline 2.3.7 and the
    /// countries that ban promoting them to the public), and the brand names, which go nowhere in any set.
    private let prescriptionOnly = ["Finasteride", "Metformin", "Semaglutide", "Oral Semaglutide", "Tirzepatide",
                                    "Birth Control", "Minoxidil", "Melatonin"]
    private let brands = ["Ozempic", "Wegovy", "Rybelsus", "Mounjaro", "Zepbound", "Propecia", "Proscar"]

    /// Wednesday 21 October 2026 at 10:00 in London, the day this was written.
    private let real = at(2026, 10, 21, 10)

    private func demo(_ stack: DemoStack, allTaken: Bool = false) -> (StackState, Date) {
        let now = DemoData.referenceNow(from: real, timeZone: london, stack: stack)
        return (DemoData.state(now: now, allTaken: allTaken, timeZone: london, stack: stack), now)
    }

    private func clock(_ state: StackState) -> DayClock {
        DayClock(dayStartHour: state.settings.dayStartHour, timeZone: london)
    }

    func testTheArgumentPicksTheStackAndAnythingElseIsTheStandardOne() {
        XCTAssertEqual(DemoStack(arguments: ["Taken", "-demo", "-demo-stack", "us"]), .us)
        XCTAssertEqual(DemoStack(arguments: ["Taken", "-demo", "-demo-stack", "neutral", "-screen", "today"]), .neutral)
        XCTAssertEqual(DemoStack(arguments: ["Taken", "-demo", "-screen", "today"]), .standard)
        XCTAssertEqual(DemoStack(arguments: ["Taken", "-demo", "-demo-stack", "uk"]), .standard, "an unknown set")
        XCTAssertEqual(DemoStack(arguments: ["Taken", "-demo", "-demo-stack"]), .standard, "no value")
    }

    func testEveryOtherCaptureKeepsItsStackAndItsDay() {
        let (state, now) = demo(.standard)
        XCTAssertEqual(state.items.map(\.name), ["Vitamin D3", "Finasteride", "Fish Oil", "Creatine", "Magnesium", "Zinc"])
        XCTAssertEqual(state.items.map(\.sortIndex), Array(0..<6))
        XCTAssertEqual(now, at(2026, 10, 21, 21, 41), "today at 21:41, as before")
    }

    func testTheStoreSetsLiveOnTheMostRecentThursdayAtTwentyOneFortyOne() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = london
        // Thursday 15 to Wednesday 21 October 2026: each goes back to the Thursday on or before it.
        for day in 15...21 {
            for stack in [DemoStack.us, .neutral] {
                let now = DemoData.referenceNow(from: at(2026, 10, day, 9), timeZone: london, stack: stack)
                XCTAssertEqual(now, at(2026, 10, 15, 21, 41), "\(day) October, \(stack)")
            }
        }
        // Across the clocks going back (Sunday 25 October 2026 in London), the evening stays 21:41.
        let after = DemoData.referenceNow(from: at(2026, 10, 28, 9), timeZone: london, stack: .us)
        XCTAssertEqual(after, at(2026, 10, 22, 21, 41))
        XCTAssertEqual(calendar.component(.weekday, from: after), DemoData.storeWeekday)
    }

    func testTheUSStackIsMixedWithASemaglutideRowWeeklyOnThursday() throws {
        let (state, now) = demo(.us)
        XCTAssertEqual(state.items.map(\.name),
                       ["Vitamin D3", "Finasteride", "Semaglutide", "Fish Oil", "Creatine", "Magnesium", "Zinc"])
        XCTAssertEqual(state.items.map(\.sortIndex), Array(0..<7))
        let sem = try XCTUnwrap(state.items.first { $0.name == "Semaglutide" })
        XCTAssertEqual(sem.code, "SEM", "the catalog's code")
        XCTAssertEqual(Fmt.frequency(sem.frequency), "Weekly \u{00B7} Thu")

        let today = StackEngine(state: state, clock: clock(state)).todaySummary(now: now)
        let row = try XCTUnwrap(today.items.first { $0.item.id == sem.id })
        XCTAssertTrue(row.isDue, "due on its day, in the Stack")
        XCTAssertEqual(row.doses.count, 1, "taken that morning")
        XCTAssertEqual(today.takenDueDoses, 5)
        XCTAssertEqual(today.dueDoses, 7, "Vitamin D3, Finasteride, Semaglutide, Fish Oil twice, Creatine, Magnesium")
    }

    func testTheNeutralStackHasAWeeklyShotAndNoPrescriptionOnlyMedicine() throws {
        let (state, now) = demo(.neutral, allTaken: true)
        XCTAssertEqual(state.items.map(\.name), ["Vitamin D3", "Weekly shot", "Fish Oil", "Creatine", "Magnesium", "Zinc"])
        for name in prescriptionOnly + brands {
            XCTAssertFalse(state.items.contains { $0.name.localizedCaseInsensitiveContains(name) }, name)
        }
        let ids = Set(state.items.map(\.id))
        XCTAssertTrue(state.doses.allSatisfy { ids.contains($0.itemId) }, "no dose of an item it does not have")

        let shot = try XCTUnwrap(state.items.first { $0.name == "Weekly shot" })
        XCTAssertEqual(Fmt.frequency(shot.frequency), "Weekly \u{00B7} Thu")
        let today = StackEngine(state: state, clock: clock(state)).todaySummary(now: now)
        XCTAssertEqual(today.dueDoses, 6)
        XCTAssertTrue(today.allTaken, "today-done: everything taken")
    }

    func testTheWeeklyRowIsLoggedEveryWeekSoTheRecordStaysWhole() throws {
        for stack in [DemoStack.us, .neutral] {
            let (state, now) = demo(stack)
            let weekly = try XCTUnwrap(state.items.first { $0.name == stack.weeklyName })
            let engine = StackEngine(state: state, clock: clock(state))
            let today = engine.todaySummary(now: now).day
            for week in 1...8 {
                let row = try XCTUnwrap(engine.summary(for: today.adding(-7 * week), asOf: today).items
                    .first { $0.item.id == weekly.id })
                XCTAssertTrue(row.isDue, "\(stack) week \(week)")
                XCTAssertEqual(row.doses.count, 1, "\(stack) week \(week)")
            }
            // The weekly row never changes the streak the other rows make.
            let (standard, standardNow) = demo(.standard)
            let standardEngine = StackEngine(state: standard, clock: clock(standard))
            XCTAssertEqual(engine.streak(today: today),
                           standardEngine.streak(today: standardEngine.todaySummary(now: standardNow).day), "\(stack)")
        }
    }

    func testTheOtherRowsKeepTheirHistoryInEveryStack() {
        let now = DemoData.referenceNow(from: real, timeZone: london, stack: .us)
        func times(_ stack: DemoStack) -> [String: [Date]] {
            let state = DemoData.state(now: now, allTaken: false, timeZone: london, stack: stack)
            var byName: [String: [Date]] = [:]
            for dose in state.doses {
                guard let item = state.items.first(where: { $0.id == dose.itemId }) else { continue }
                byName[item.name, default: []].append(dose.takenAt)
            }
            return byName
        }
        let standard = times(.standard)
        for stack in [DemoStack.us, .neutral] {
            let other = times(stack)
            for name in ["Vitamin D3", "Fish Oil", "Creatine", "Magnesium", "Zinc"] {
                XCTAssertEqual(other[name], standard[name], "\(stack): \(name)")
            }
        }
    }

    func testTheNeutralTypeAheadFillsTheRoomWithSupplementsOnly() {
        XCTAssertEqual(DemoStack.standard.typedQuery, "tum")
        XCTAssertEqual(DemoStack.us.typedQuery, "tum")
        XCTAssertEqual(DemoStack.neutral.typedQuery, "mag")

        let matches = Suggest.rank("mag")
        XCTAssertEqual(matches.map(\.entry.name),
                       ["Magnesium", "Magnesium Glycinate", "Magnesium Citrate", "Magnesium L-Threonate"])
        XCTAssertTrue(matches.allSatisfy { $0.alias == nil }, "no other name, so no brand, shows")
        let rows = Suggest.rows(matches, literal: Suggest.literal(for: "mag"), capacity: 6)
        XCTAssertEqual(rows.count, 5, "four names and the typed row: the most the card shows")
    }
}
