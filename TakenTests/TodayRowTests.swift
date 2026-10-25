import XCTest
@testable import Taken

/// Tap the row to log (Tom 2026-10-25; REDESIGN.md, "Tap the row to log"; SPEC 3.1): a tap anywhere on a Today row does
/// what the ring alone did, the logging moment plays on the row that was tapped, and editing lives in the stack's edit
/// mode, out of the tap's way.
final class TodayRowTests: XCTestCase {

    /// The standard demo stack: Vitamin D3 taken at 07:42, Fish Oil 1 of 2, Magnesium pending, and Zinc (every other
    /// day, taken yesterday) under Not today.
    @MainActor
    private func demoModel(_ screen: String = "today") -> AppModel {
        AppModel.fromLaunchArguments(["Taken", "-demo", "-screen", screen])
    }

    @MainActor
    private func row(_ name: String, in model: AppModel) throws -> ItemDay {
        try XCTUnwrap(model.today.items.first { $0.item.name == name })
    }

    // MARK: The tap

    @MainActor
    func testATapOnAPendingRowLogsADoseAndPlaysTheMomentOnThatRowOnly() throws {
        let model = demoModel()
        let fish = try row("Fish Oil", in: model)
        XCTAssertTrue(fish.isPending)
        model.tap(fish)

        XCTAssertEqual(try row("Fish Oil", in: model).takenCount, fish.takenCount + 1)
        XCTAssertEqual(model.toast?.message, "Fish Oil taken at", "the toast with Undo, as the ring had")
        XCTAssertNotNil(model.toast?.undo)
        XCTAssertEqual(model.rowLogs, [fish.item.id: 1], "the ring pops and the row washes here, and nowhere else")

        model.tap(try row("Fish Oil", in: model))
        XCTAssertFalse(try row("Fish Oil", in: model).isPending, "2x daily: the second tap fills the second arc")
        XCTAssertEqual(model.rowLogs[fish.item.id], 2, "and plays the moment again")
    }

    @MainActor
    func testATapOnATakenRowShowsItsTimesAndNeverUntakes() throws {
        let model = demoModel()
        let vd3 = try row("Vitamin D3", in: model)
        XCTAssertFalse(vd3.isPending)
        let doses = model.state.doses
        model.tap(vd3)
        XCTAssertEqual(model.expandedItemID, vd3.id, "the times open")
        XCTAssertEqual(model.state.doses, doses, "never un-takes and never logs a second dose")
        XCTAssertTrue(model.rowLogs.isEmpty, "no logging moment for showing the times")
        model.tap(vd3)
        XCTAssertNil(model.expandedItemID, "a second tap closes them")
    }

    @MainActor
    func testANotTodayRowLogsTheSameWay() throws {
        let model = demoModel()
        let entry = try XCTUnwrap(model.today.notDue.first { $0.item.name == "Zinc" })
        let shown = model.notTodayRow(entry)
        XCTAssertTrue(shown.row.doses.isEmpty, "a quiet ring")
        model.tap(shown.row)
        XCTAssertEqual(model.engine.doses(of: entry.item.id, on: model.today.day).count, 1, "no lockout")
        XCTAssertEqual(model.rowLogs[entry.item.id], 1)
    }

    @MainActor
    func testTakeAllPlaysNoRowMoment() throws {
        let model = demoModel()
        model.takeAll()
        XCTAssertFalse(try row("Magnesium", in: model).isPending)
        XCTAssertTrue(model.rowLogs.isEmpty, "the moment plays where the finger is: Take all has its own toast")
    }

    @MainActor
    func testALockedRowOpensThePaywallInsteadOfLogging() throws {
        let model = demoModel("locked")
        XCTAssertTrue(model.isLocked)
        let magnesium = try row("Magnesium", in: model)
        let doses = model.state.doses
        model.tap(magnesium)
        XCTAssertNotNil(model.paywall, "as the ring did")
        XCTAssertEqual(model.state.doses, doses)
        XCTAssertTrue(model.rowLogs.isEmpty)

        model.closePaywall()
        model.setEditingStack(true)
        model.tap(magnesium)
        XCTAssertEqual(model.sheet, .editItem(magnesium.item.id), "the item sheet always opens, Pro or not")
        XCTAssertNil(model.paywall)
    }

    // MARK: Edit mode

    @MainActor
    func testEditModeOpensTheItemSheetAndNeverLogs() throws {
        let model = demoModel()
        XCTAssertFalse(model.editingStack, "Today opens logging")
        let vd3 = try row("Vitamin D3", in: model)
        model.tap(vd3)
        model.setEditingStack(true)
        XCTAssertTrue(model.editingStack)
        XCTAssertNil(model.expandedItemID, "editing closes the times, so every row shows its chevron")

        let fish = try row("Fish Oil", in: model)
        let doses = model.state.doses
        model.tap(fish)
        XCTAssertEqual(model.sheet, .editItem(fish.item.id))
        XCTAssertEqual(model.state.doses, doses, "nothing logs while editing")
        XCTAssertNil(model.toast)
        XCTAssertTrue(model.rowLogs.isEmpty)

        model.sheet = nil
        XCTAssertTrue(model.editingStack, "closing the sheet keeps edit mode, so the next item is one tap away")
        model.setEditingStack(false)
        model.tap(fish)
        XCTAssertEqual(try row("Fish Oil", in: model).takenCount, fish.takenCount + 1, "Done: a tap logs again")
    }

    @MainActor
    func testEditModeEndsOnLeavingTodayInTheBackgroundAndWhenTheStackEmpties() throws {
        let model = demoModel()
        model.setEditingStack(true)
        model.tab = .today
        XCTAssertTrue(model.editingStack, "Today's own tab keeps it")
        model.tab = .history
        XCTAssertFalse(model.editingStack)
        model.tab = .today
        XCTAssertFalse(model.editingStack, "coming back finds the rows logging")

        model.setEditingStack(true)
        model.openTodoTab()
        XCTAssertFalse(model.editingStack, "a voice to-do request leaves Today")

        model.tab = .today
        model.setEditingStack(true)
        model.didEnterBackground()
        XCTAssertFalse(model.editingStack, "the next open is a tap that logs")

        model.setEditingStack(true)
        for item in model.activeItems { model.deleteItem(id: item.id) }
        XCTAssertFalse(model.hasStack)
        XCTAssertFalse(model.editingStack, "first run has nothing to edit")
    }

    @MainActor
    func testTheTodayEditScreenOpensTodayInEditMode() {
        let model = demoModel("today-edit")
        XCTAssertEqual(model.tab, .today)
        XCTAssertTrue(model.editingStack)
        XCTAssertFalse(demoModel("today").editingStack, "every other capture shows Today logging")
    }

    // MARK: VoiceOver

    @MainActor
    func testVoiceOverHintsSayWhatADoubleTapDoes() throws {
        let model = demoModel()
        let fish = try row("Fish Oil", in: model)
        let vd3 = try row("Vitamin D3", in: model)
        let hints = [
            ItemRowView.accessibilityHint(row: fish, quiet: false, locked: false),
            ItemRowView.accessibilityHint(row: vd3, quiet: false, locked: false),
            ItemRowView.accessibilityHint(row: fish, quiet: false, locked: true),
            ItemRowView.accessibilityHint(row: fish, quiet: false, locked: false, editing: true),
            ItemRowView.accessibilityHint(row: vd3, quiet: false, locked: true, editing: true),
        ]
        XCTAssertEqual(hints, [
            "Double tap to mark taken.",
            "Double tap for the times. Actions has Edit item.",
            "Logging needs Taken Pro. Double tap to see plans.",
            "Double tap to edit.",
            "Double tap to edit.",
        ])
        for hint in hints {
            XCTAssertFalse(hint.contains("\u{2014}") || hint.contains("\u{2013}"), hint)
            XCTAssertNil(hint.range(of: "name", options: .caseInsensitive), "nothing points at the name: \(hint)")
        }
    }
}
