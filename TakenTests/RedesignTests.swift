import XCTest
@testable import Taken

/// Taken 1.1's redesign (REDESIGN.md): the wake-up time and the day it rolls over, a frequency per item in the Add
/// sheet, the profile, the tabs a voice to-do request opens, and what Erase all data takes.
final class RedesignTests: XCTestCase {

    // MARK: Wake-up time

    func testTheDayRollsOverFourHoursBeforeWakingUpBetweenMidnightAndNoon() {
        XCTAssertEqual(StackSettings.dayStartHour(forWake: 8 * 60), 4)
        XCTAssertEqual(StackSettings.dayStartHour(forWake: 5 * 60), 1)
        XCTAssertEqual(StackSettings.dayStartHour(forWake: 14 * 60), 10)
        XCTAssertEqual(StackSettings.dayStartHour(forWake: 2 * 60), 0, "never before midnight")
        XCTAssertEqual(StackSettings.dayStartHour(forWake: 4 * 60), 0)
        XCTAssertEqual(StackSettings.dayStartHour(forWake: 23 * 60), 12, "never after noon")
        XCTAssertEqual(StackSettings.dayStartHour(forWake: 7 * 60 + 30), 3, "a half hour rolls over on the hour before")
        XCTAssertEqual(StackSettings().wakeMinutes, 7 * 60, "07:00 unless chosen")
        XCTAssertEqual(StackSettings().dayStartHour, 3)
    }

    func testADayStartFromBeforeBecomesTheWakeUpTimeAndNoHistoryMoves() throws {
        for hour in 0...12 {
            let json = #"{"settings":{"dayStartHour":\#(hour)}}"#
            let settings = try TakenStore.decode(Data(json.utf8)).settings
            XCTAssertEqual(settings.wakeMinutes, (hour + 4) * 60)
            XCTAssertEqual(settings.dayStartHour, hour, "the day still rolls over at \(hour):00")
        }
        let legacy = try TakenStore.decode(Data(#"{"settings":{"dayStartHour":4,"reminderMinutes":1260}}"#.utf8)).settings
        XCTAssertEqual(legacy.wakeMinutes, 8 * 60, "1.0's default 04:00 is waking at 08:00")
        XCTAssertEqual(legacy.reminderMinutes, 21 * 60, "a nudge time already set stays")

        // A history logged with the 04:00 rollover reads the same after the move to the wake-up time.
        let vd3 = makeItem("Vitamin D3", "VD3", created: at(2026, 10, 1, 8))
        var before = StackState(items: [vd3], settings: StackSettings(dayStartHour: 4))
        before.logDose(itemId: vd3.id, at: at(2026, 10, 13, 1, 30), timeZone: london)
        let after = try TakenStore.decode(try TakenStore.encode(before))
        let clock = DayClock(dayStartHour: after.settings.dayStartHour, timeZone: london)
        XCTAssertEqual(StackEngine(state: after, clock: clock).summary(for: DayKey(year: 2026, month: 10, day: 12)).status,
                       .complete, "01:30 still counts for the night before")
    }

    func testTheWakeUpTimeIsStoredWithItsRolloverAndReadBack() throws {
        var settings = StackSettings(wakeMinutes: 6 * 60 + 15)
        settings.reminderEnabled = true
        let text = String(decoding: try TakenStore.encode(StackState(settings: settings)), as: UTF8.self)
        XCTAssertTrue(text.contains(#""wakeMinutes":375"#), text)
        XCTAssertTrue(text.contains(#""dayStartHour":2"#), "an earlier build reading this file rolls over at the same hour")
        XCTAssertFalse(text.contains("reminderMinutes"), "no nudge time chosen, none stored")
        XCTAssertEqual(try TakenStore.decode(Data(text.utf8)).settings, settings)
    }

    func testTheNudgeAndBackfillFollowTheWakeUpTimeUntilChosen() {
        var settings = StackSettings(wakeMinutes: 6 * 60)
        XCTAssertEqual(settings.reminderMinutes, 19 * 60, "13 hours after waking")
        XCTAssertEqual(settings.backfillMinutes, 7 * 60, "an hour after waking")
        settings.wakeMinutes = 12 * 60
        XCTAssertEqual(settings.reminderMinutes, 1 * 60, "past midnight wraps")
        settings.reminderMinutes = 21 * 60 + 30
        XCTAssertEqual(settings.chosenReminderMinutes, 21 * 60 + 30)
        settings.wakeMinutes = 5 * 60
        XCTAssertEqual(settings.reminderMinutes, 21 * 60 + 30, "a chosen time stays put")
        XCTAssertEqual(StackSettings(wakeMinutes: -40).wakeMinutes, 0)
        XCTAssertEqual(StackSettings(wakeMinutes: 9000).wakeMinutes, 24 * 60 - 1)

        // The nudge plan reads the derived time.
        let vd3 = makeItem("Vitamin D3", "VD3", created: at(2026, 10, 1, 8))
        let state = StackState(items: [vd3], settings: StackSettings(wakeMinutes: 7 * 60, reminderEnabled: true))
        let plans = Reminders.plan(state: state, now: at(2026, 10, 12, 9), timeZone: london)
        XCTAssertEqual(plans.first?.fireDate, at(2026, 10, 12, 20), "07:00 wake: the nudge at 20:00")
    }

    // MARK: Adding

    func testEachPickedItemKeepsItsOwnFrequency() {
        let drafts = AddPlan.drafts(selected: ["Vitamin D3", "Fish Oil", "Finasteride"], custom: "  Lion's Mane ",
                                    choices: ["Finasteride": .alternate, "Fish Oil": .twice, AddPlan.customKey: .days],
                                    days: [AddPlan.customKey: [2, 4, 6]])
        XCTAssertEqual(drafts.map(\.name), ["Vitamin D3", "Fish Oil", "Finasteride", "Lion's Mane"])
        XCTAssertEqual(drafts.map(\.frequency), [.daily(times: 1), .daily(times: 2), .alternateDays, .weekdays([2, 4, 6])],
                       "Finasteride every other day while D3 is daily, in one go")
        XCTAssertEqual(drafts[0].code, "VD3", "the chip's code")
        XCTAssertNil(drafts[3].code, "a typed name gets one when it is added")

        let noDays = AddPlan.drafts(selected: ["Zinc"], custom: nil, choices: ["Zinc": .days], days: ["Zinc": []])
        XCTAssertEqual(noDays.map(\.frequency), [.daily(times: 1)], "Days with none picked is never an item never due")
        XCTAssertEqual(AddPlan.drafts(selected: ["Zinc"], custom: nil, choices: ["Zinc": .days], days: [:]).map(\.frequency),
                       [.weekdays(FrequencyChoice.defaultDays)])
        XCTAssertTrue(AddPlan.drafts(selected: [], custom: "   ", choices: [:], days: [:]).isEmpty)

        var state = StackState()
        let added = state.addItems(drafts, now: at(2026, 10, 13, 9))
        let engine = StackEngine(state: state, clock: londonClock())
        state.logDose(itemId: added[2].id, at: at(2026, 10, 13, 9), timeZone: london)
        let tomorrow = StackEngine(state: state, clock: londonClock()).todaySummary(now: at(2026, 10, 14, 9))
        XCTAssertEqual(tomorrow.notDue.map(\.item.name), ["Finasteride"], "taken today, so not due tomorrow")
        XCTAssertEqual(engine.todaySummary(now: at(2026, 10, 13, 9)).due.count, 3)
        XCTAssertEqual(FrequencyChoice.allCases.map(\.title), ["Daily", "Every other day", "2x daily", "3x daily", "Days"])
    }

    // MARK: Profile

    func testTheProfileIsOptionalAndLocal() throws {
        XCTAssertNil(Profile().initials, "no name, the person glyph")
        XCTAssertEqual(Profile(name: "Thomas Baxter").initials, "TB")
        XCTAssertEqual(Profile(name: "tom").initials, "T")
        XCTAssertEqual(Profile(name: "Mary Ann de la Cruz").initials, "MC")
        XCTAssertEqual(Profile.clean("  Thomas \n  Baxter  "), "Thomas Baxter")
        XCTAssertEqual(Profile.clean(String(repeating: "a", count: 90)).count, Profile.maxNameLength)

        let folder = temporaryStoreURL().deletingLastPathComponent()
        let store = ProfileStore(directory: folder)
        XCTAssertEqual(store.load(), Profile(), "nothing is asked at first launch")
        try store.save(Profile(name: "Thomas Baxter"))
        try store.savePhoto(Data([0xFF, 0xD8, 0xFF]))
        XCTAssertEqual(ProfileStore(directory: folder).load().name, "Thomas Baxter")
        XCTAssertNotNil(store.loadPhoto())
        store.erase()
        XCTAssertEqual(store.load(), Profile())
        XCTAssertNil(store.loadPhoto())
    }

    // MARK: Tabs

    @MainActor
    func testAVoiceToDoRequestBringsTheToDoTabToTheFrontOverAnySheet() {
        let model = AppModel.fromLaunchArguments(["Taken", "-demo", "-screen", "today"])
        XCTAssertEqual(model.tab, .today)
        model.sheet = .settings
        XCTAssertFalse(model.showsTodoTabUncovered)
        model.openTodoTab()
        XCTAssertEqual(model.tab, .todo)
        XCTAssertNil(model.sheet, "Profile closes so Listening and the stop button are on screen")
        XCTAssertTrue(model.showsTodoTabUncovered)

        XCTAssertEqual(AppModel.tab(forScreen: "todo"), .todo)
        XCTAssertEqual(AppModel.tab(forScreen: "todo-recording"), .todo)
        XCTAssertEqual(AppModel.tab(forScreen: "log"), .history, "the calendar lives on History")
        XCTAssertEqual(AppModel.tab(forScreen: "day"), .history)
        XCTAssertEqual(AppModel.tab(forScreen: nil), .today, "a real launch opens on Today")
        XCTAssertEqual(WidgetGallery.Mode(screen: "widgets-todo"), .todo)
        XCTAssertNil(WidgetGallery.Mode(screen: "today"))
    }

    @MainActor
    func testAnEarlierDaysNudgeOpensThatDayOverHistory() {
        let model = AppModel.fromLaunchArguments(["Taken", "-demo", "-screen", "today"])
        let yesterday = model.today.day.adding(-1)
        model.openDay(fromNudge: yesterday)
        XCTAssertEqual(model.tab, .history)
        XCTAssertEqual(model.sheet, .day(yesterday))
        model.openDay(fromNudge: model.today.day)
        XCTAssertEqual(model.tab, .today)
        XCTAssertNil(model.sheet)
    }

    // MARK: Erase all data

    @MainActor
    func testEraseSaysWhatItTakesAndLeavesNoSetAsideCopies() throws {
        XCTAssertTrue(ProfileView.eraseMessage.contains("to-dos"), "the to-dos go too, so the dialog says so")
        XCTAssertTrue(ProfileView.eraseMessage.contains("profile"))

        let url = temporaryStoreURL()
        let folder = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for name in ["taken-unreadable-1.json", "todos-unreadable-2.json", "pro.json"] {
            try Data("x".utf8).write(to: folder.appendingPathComponent(name))
        }
        TakenStore(fileURL: url, postsChangeNotifications: false).removeSetAsideCopies()
        TodoStore(fileURL: folder.appendingPathComponent(TodoStore.fileName)).removeSetAsideCopies()
        let left = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        XCTAssertEqual(left, ["pro.json"], "the Taken Pro status file stays")
    }
}
