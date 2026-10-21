import XCTest
@testable import Taken

/// The 1.1 retention build (SPEC 3.1): Today's one-time rows, the evening nudge offered once, the honest repair and the
/// widget invite, each shown once and never again. London clock, the day starting at 04:00.
final class RetentionTests: XCTestCase {

    private let monday = DayKey(year: 2026, month: 10, day: 19)

    private func summary(_ state: StackState, now: Date) -> DaySummary {
        StackEngine(state: state, clock: londonClock()).todaySummary(now: now)
    }

    // MARK: The evening nudge, offered once

    func testTheNudgeOfferShowsRightAfterTheStackIsAddedUntilItIsAnswered() {
        let empty = StackState()
        XCTAssertNil(TodayPrompts.pick(settings: empty.settings, hasStack: false, today: summary(empty, now: at(2026, 10, 19, 9)),
                                       repairDay: nil, locked: false), "nothing before there is a stack")

        let vd3 = makeItem("Vitamin D3", "VD3", created: at(2026, 10, 19, 9))
        var state = StackState(items: [vd3])
        let today = summary(state, now: at(2026, 10, 19, 9))
        XCTAssertFalse(state.settings.reminderEnabled, "the nudge stays off by default")
        XCTAssertEqual(TodayPrompts.pick(settings: state.settings, hasStack: true, today: today, repairDay: nil, locked: false),
                       .nudgeOffer(minutes: 20 * 60), "07:00 wake: the nudge at 20:00")
        XCTAssertEqual(RetentionCopy.nudgeOffer(minutes: state.settings.reminderMinutes), "Nudge me at 20:00 if anything's left")
        state.settings.reminderMinutes = 21 * 60 + 30
        XCTAssertEqual(TodayPrompts.pick(settings: state.settings, hasStack: true, today: today, repairDay: nil, locked: false),
                       .nudgeOffer(minutes: 21 * 60 + 30), "the person's own nudge time")
        XCTAssertNil(TodayPrompts.pick(settings: state.settings, hasStack: true, today: today, repairDay: nil, locked: true),
                     "never while locked")

        var answered = state.settings
        answered.nudgeOfferDone = true
        XCTAssertNil(TodayPrompts.pick(settings: answered, hasStack: true, today: today, repairDay: nil, locked: false),
                     "Turn on or Not now: it never comes back")
        var on = state.settings
        on.reminderEnabled = true
        XCTAssertNil(TodayPrompts.pick(settings: on, hasStack: true, today: today, repairDay: nil, locked: false),
                     "not when the nudge is already on")
    }

    func testOneTimeAnswersAreKeptInTheFileAndThroughErase() throws {
        let plain = String(decoding: try TakenStore.encode(StackState()), as: UTF8.self)
        XCTAssertFalse(plain.contains("nudgeOfferDone") || plain.contains("widgetInvite"), "a file with none looks as before")
        let legacy = try TakenStore.decode(Data(#"{"settings":{"wakeMinutes":420}}"#.utf8)).settings
        XCTAssertFalse(legacy.nudgeOfferDone)
        XCTAssertNil(legacy.widgetInviteDay)
        XCTAssertFalse(legacy.widgetInviteDone)

        var state = StackState(items: [makeItem("Zinc", "ZNC", created: at(2026, 10, 1, 8))])
        state.settings.nudgeOfferDone = true
        state.settings.widgetInviteDay = monday.ordinal
        state.settings.widgetInviteDone = true
        state.settings.reminderEnabled = true
        let text = String(decoding: try TakenStore.encode(state), as: UTF8.self)
        XCTAssertTrue(text.contains(#""nudgeOfferDone":true"#), text)
        XCTAssertTrue(text.contains(#""widgetInviteDay":\#(monday.ordinal)"#), text)
        XCTAssertEqual(try TakenStore.decode(Data(text.utf8)).settings, state.settings)

        state.eraseAll()
        XCTAssertTrue(state.items.isEmpty)
        XCTAssertFalse(state.settings.reminderEnabled, "settings reset")
        XCTAssertTrue(state.settings.nudgeOfferDone, "an answered row never comes back, even after Erase all data")
        XCTAssertTrue(state.settings.widgetInviteDone)
        XCTAssertEqual(state.settings.widgetInviteDay, monday.ordinal)
    }

    // MARK: The widget invite

    func testTheWidgetInviteShowsOnTheFirstAllTakenDayOnly() {
        let vd3 = makeItem("Vitamin D3", "VD3", created: at(2026, 10, 12, 9))
        var state = StackState(items: [vd3])
        state.settings.nudgeOfferDone = true
        let pending = summary(state, now: at(2026, 10, 19, 9))
        XCTAssertNil(TodayPrompts.pick(settings: state.settings, hasStack: true, today: pending, repairDay: nil, locked: false))

        state.logDose(itemId: vd3.id, at: at(2026, 10, 19, 8), timeZone: london)
        let done = summary(state, now: at(2026, 10, 19, 9))
        XCTAssertTrue(done.allTaken)
        XCTAssertEqual(TodayPrompts.pick(settings: state.settings, hasStack: true, today: done, repairDay: nil, locked: false),
                       .widgetInvite, "the first All taken")
        var shown = state.settings
        shown.widgetInviteDay = monday.ordinal
        XCTAssertEqual(TodayPrompts.pick(settings: shown, hasStack: true, today: done, repairDay: nil, locked: false),
                       .widgetInvite, "all that day")
        shown.widgetInviteDay = monday.ordinal - 1
        XCTAssertNil(TodayPrompts.pick(settings: shown, hasStack: true, today: done, repairDay: nil, locked: false),
                     "and never again")
        var closed = state.settings
        closed.widgetInviteDone = true
        XCTAssertNil(TodayPrompts.pick(settings: closed, hasStack: true, today: done, repairDay: nil, locked: false),
                     "gone for good once tapped or closed")
        var unanswered = state.settings
        unanswered.nudgeOfferDone = false
        XCTAssertEqual(TodayPrompts.pick(settings: unanswered, hasStack: true, today: done, repairDay: nil, locked: false),
                       .nudgeOffer(minutes: 20 * 60), "one row at a time, the nudge offer first")
        XCTAssertEqual(RetentionCopy.widgetInvite, "Log from your Lock Screen: add the Taken widget")
    }

    // MARK: The honest repair

    func testTheRepairLineOffersYesterdayAfterAPartOrMissedDay() {
        let created = at(2026, 10, 1, 8)
        let vd3 = makeItem("Vitamin D3", "VD3", created: created, sortIndex: 0)
        let mag = makeItem("Magnesium", "MAG", created: created, sortIndex: 1)
        let sunday = monday.adding(-1)
        var state = StackState(items: [vd3, mag])
        state.settings.nudgeOfferDone = true
        for day in 1...17 {
            state.logDose(itemId: vd3.id, at: at(2026, 10, day, 8), timeZone: london)
            state.logDose(itemId: mag.id, at: at(2026, 10, day, 21), timeZone: london)
        }
        func repair(_ state: StackState) -> DayKey? {
            TodayPrompts.repairDay(engine: StackEngine(state: state, clock: londonClock()), today: monday)
        }
        XCTAssertEqual(repair(state), sunday, "yesterday was missed after a week of logging")

        var partial = state
        partial.logDose(itemId: vd3.id, at: at(2026, 10, 18, 8), timeZone: london)
        XCTAssertEqual(repair(partial), sunday, "yesterday was partial")
        XCTAssertEqual(TodayPrompts.pick(settings: partial.settings, hasStack: true, today: summary(partial, now: at(2026, 10, 19, 9)),
                                         repairDay: repair(partial), locked: false),
                       .repair(sunday))
        XCTAssertNil(TodayPrompts.pick(settings: partial.settings, hasStack: true,
                                       today: summary(partial, now: at(2026, 10, 19, 9)), repairDay: repair(partial),
                                       locked: true), "never while locked")

        partial.logDose(itemId: mag.id, at: at(2026, 10, 18, 21), timeZone: london)
        XCTAssertNil(repair(partial), "gone once yesterday is complete")
        XCTAssertEqual(TodayPrompts.repairDay(engine: StackEngine(state: state, clock: londonClock()), today: monday.adding(1)),
                       monday, "once today ends the line is about Monday, never Sunday again")

        var lapsed = StackState(items: [vd3, mag])
        for day in 1...9 { lapsed.logDose(itemId: vd3.id, at: at(2026, 10, day, 8), timeZone: london) }
        XCTAssertNil(repair(lapsed), "nothing logged in the 7 days before yesterday: no line")

        let fresh = StackState(items: [makeItem("Zinc", "ZNC", created: at(2026, 10, 19, 9))])
        XCTAssertNil(repair(fresh), "the first day has no yesterday to fill in")

        // A weekly shot due yesterday and not logged yet: its week is open, so yesterday is not partial.
        let sem = makeItem("Semaglutide", "SEM", .weekdays([1]), created: created, sortIndex: 2)
        var weekly = StackState(items: [vd3, sem])
        for day in 1...18 { weekly.logDose(itemId: vd3.id, at: at(2026, 10, day, 8), timeZone: london) }
        for day in [4, 11] { weekly.logDose(itemId: sem.id, at: at(2026, 10, day, 8), timeZone: london) }
        XCTAssertNil(repair(weekly), "an open week is not a missed day")
        XCTAssertEqual(RetentionCopy.repair, "Forgot to log yesterday? Fill it in")
    }

    // MARK: Copy

    func testTheRetentionCopyKeepsTheRules() {
        for text in RetentionCopy.all {
            XCTAssertNil(text.range(of: "free", options: .caseInsensitive), text)
            XCTAssertFalse(text.contains("\u{2014}") || text.contains("\u{2013}"), "no em or en dash: \(text)")
            XCTAssertFalse(text.contains("!"), text)
            XCTAssertNil(text.range(of: "streak broken", options: .caseInsensitive), text)
        }
        XCTAssertEqual(RetentionCopy.turnOn, "Turn on")
        XCTAssertEqual(RetentionCopy.notNow, "Not now")
        XCTAssertEqual(RetentionCopy.widgetSteps.count, 3)
    }

    // MARK: -demo

    @MainActor
    func testDemoShowsAOneTimeRowOnlyWhenItsScreenAsks() {
        for screen in ["today", "today-done", "locked"] {
            XCTAssertNil(AppModel.fromLaunchArguments(["Taken", "-demo", "-screen", screen]).todayPrompt,
                         "no one-time row in the \(screen) screenshot")
        }
        let offer = AppModel.fromLaunchArguments(["Taken", "-demo", "-screen", "today-nudge-offer"])
        XCTAssertEqual(offer.todayPrompt, .nudgeOffer(minutes: 20 * 60))
        offer.answerNudgeOffer(turnOn: false)
        XCTAssertNil(offer.todayPrompt, "Not now hides it")
        XCTAssertTrue(offer.settings.nudgeOfferDone)

        let repair = AppModel.fromLaunchArguments(["Taken", "-demo", "-screen", "today-repair"])
        XCTAssertEqual(repair.todayPrompt, .repair(repair.today.day.adding(-1)))
        XCTAssertEqual(repair.repairDay, repair.today.day.adding(-1), "the demo's yesterday is partial")

        let invite = AppModel.fromLaunchArguments(["Taken", "-demo", "-screen", "today-widget-invite"])
        XCTAssertEqual(invite.todayPrompt, .widgetInvite)
        XCTAssertTrue(invite.today.allTaken)
        invite.closeWidgetInvite(openHelp: true)
        XCTAssertNil(invite.todayPrompt)
        XCTAssertEqual(invite.sheet, .widgetHelp)
    }
}
