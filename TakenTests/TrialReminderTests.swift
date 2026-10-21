import XCTest
@testable import Taken

/// The trial promise and its one reminder (SPEC 3.9, PRO.md, 2026-10-21): at least 72 hours before StoreKit's end of
/// the trial, at the nudge time or 10:00, with the end date, the price, what was logged and how to cancel; withdrawn
/// when the trial is cancelled, converts, hits a billing issue or Pro is for good; and one notification ask after a
/// trial starts. London clock.
final class TrialReminderTests: XCTestCase {

    private let yearlyPrice = PlanPrice(displayPrice: "$19.99", period: PlanPeriod(value: 1, unit: .year))

    /// A yearly trial that started Wed 28 Oct and ends Wed 4 Nov 2026 at 09:14 in London (after the clocks went back, so
    /// every hour is a plain hour).
    private func trial(willRenew: Bool? = true, reason: ProReason = .trial, billingIssue: Bool = false,
                       ends: Date? = nil) -> ProStatus {
        ProStatus(isPro: true, reason: reason, checkedAt: at(2026, 10, 28, 9, 14), expiresAt: ends ?? at(2026, 11, 4, 9, 14),
                  willRenew: willRenew, billingIssue: billingIssue, plan: .yearly)
    }

    private func logged(_ count: Int, nudge: Bool = false) -> StackState {
        let vd3 = makeItem("Vitamin D3", "VD3", created: at(2026, 10, 28, 9))
        var state = StackState(items: [vd3])
        for index in 0..<count {
            state.logDose(itemId: vd3.id, at: at(2026, 10, 28, 10).addingTimeInterval(Double(index) * 3600), timeZone: london)
        }
        state.settings.reminderEnabled = nudge
        return state
    }

    private func plan(_ status: ProStatus?, _ state: StackState, now: Date = at(2026, 10, 28, 9, 20),
                      price: PlanPrice? = nil) -> TrialReminder.Plan? {
        TrialReminder.plan(status: status, price: price ?? yearlyPrice, state: state, now: now, timeZone: london)
    }

    // MARK: When

    func testTheReminderComesAtLeast72HoursBeforeTheEndAt10WhileTheNudgeIsOff() throws {
        let reminder = try XCTUnwrap(plan(trial(), logged(12)))
        XCTAssertEqual(reminder.fireDate, at(2026, 10, 31, 10, 0),
                       "Saturday at 10:00: Sunday at 10:00 would be under 72 hours before Wednesday 09:14")
        XCTAssertGreaterThanOrEqual(at(2026, 11, 4, 9, 14).timeIntervalSince(reminder.fireDate), 72 * 3600)
        XCTAssertEqual(reminder.components.day, 31)
        XCTAssertEqual(reminder.components.hour, 10)
        XCTAssertEqual(reminder.components.minute, 0)
        XCTAssertEqual(reminder.components.timeZone, london)

        let afternoon = try XCTUnwrap(plan(trial(ends: at(2026, 11, 4, 15, 30)), logged(12)))
        XCTAssertEqual(afternoon.fireDate, at(2026, 11, 1, 10, 0), "a trial started at 15:30: day 4 at 10:00")
        let exactly = try XCTUnwrap(plan(trial(ends: at(2026, 11, 4, 10, 0)), logged(12)))
        XCTAssertEqual(exactly.fireDate, at(2026, 11, 1, 10, 0), "exactly 72 hours counts as at least 72 hours")
    }

    func testTheReminderComesAtTheNudgeTimeWhileTheNudgeIsOn() throws {
        var nudged = logged(12, nudge: true)
        XCTAssertEqual(nudged.settings.reminderMinutes, 20 * 60)
        XCTAssertEqual(try XCTUnwrap(plan(trial(), nudged)).fireDate, at(2026, 10, 31, 20, 0),
                       "Saturday at 20:00: Sunday at 20:00 is under 72 hours before Wednesday 09:14")
        nudged.settings.reminderMinutes = 7 * 60 + 30
        XCTAssertEqual(try XCTUnwrap(plan(trial(), nudged)).fireDate, at(2026, 11, 1, 7, 30), "a morning nudge: day 4")
        nudged.settings.reminderEnabled = false
        XCTAssertEqual(try XCTUnwrap(plan(trial(), nudged)).fireDate, at(2026, 10, 31, 10, 0),
                       "the nudge turned off: 10:00 again, whatever its time")
    }

    func testTheReminderCountsHoursAcrossAClockChange() throws {
        // Ends Sun 25 Oct 2026 at 09:14 GMT; the clocks go back that night. Thu 22 Oct at 10:00 BST is 09:00 UTC, 72 hours
        // and 14 minutes before the end.
        let status = trial(ends: at(2026, 10, 25, 9, 14))
        let reminder = try XCTUnwrap(plan(status, logged(3), now: at(2026, 10, 18, 9, 20)))
        XCTAssertEqual(reminder.fireDate, at(2026, 10, 22, 10, 0))
        XCTAssertGreaterThanOrEqual(at(2026, 10, 25, 9, 14).timeIntervalSince(reminder.fireDate), 72 * 3600)
    }

    func testATrialShorterThanFourDaysGetsNoReminder() {
        let start = at(2026, 10, 28, 9, 14)
        for days in [1, 2, 3] {
            let short = trial(ends: start.addingTimeInterval(Double(days) * 24 * 3600))
            XCTAssertNil(plan(short, logged(1), now: start), "\(days) days")
            XCTAssertNil(plan(short, logged(1), now: start.addingTimeInterval(60)), "\(days) days")
            XCTAssertNil(plan(short, logged(1, nudge: true), now: start.addingTimeInterval(60)), "\(days) days, nudge on")
        }
        XCTAssertNotNil(plan(trial(ends: start.addingTimeInterval(4 * 24 * 3600 + 3600)), logged(1),
                             now: start.addingTimeInterval(60)), "a little over 4 days: one reminder")
    }

    func testNeverLateAndAtMostOne() {
        let state = logged(12)
        XCTAssertNil(plan(trial(), state, now: at(2026, 10, 31, 10, 1)), "the moment has passed: never late")
        XCTAssertNil(plan(trial(), state, now: at(2026, 11, 3, 10)))
        XCTAssertNil(plan(trial(), state, now: at(2026, 11, 4, 10)), "after the end")
        XCTAssertEqual(TrialReminder.identifier, "taken.pro.trial-end", "one identifier: at most one request")
        XCTAssertFalse(TrialReminder.identifier.hasPrefix(Reminders.requestPrefix))
    }

    // MARK: Withdrawn

    func testTheReminderGoesWhenTheTrialIsCancelledConvertsOrIsForGood() {
        let now = at(2026, 10, 28, 9, 20)
        let state = logged(12)
        XCTAssertNotNil(plan(trial(), state, now: now))
        XCTAssertNil(plan(trial(willRenew: false), state, now: now), "auto-renew off: no reminder")
        XCTAssertNotNil(plan(trial(willRenew: nil), state, now: now), "StoreKit did not say: still a trial set to renew")
        XCTAssertNil(plan(trial(reason: .yearly), state, now: now), "converted: no reminder")
        XCTAssertNil(plan(trial(billingIssue: true), state, now: now), "a billing issue: no reminder")
        XCTAssertNil(plan(ProStatus(isPro: true, reason: .lifetime, checkedAt: now), state, now: now), "lifetime")
        XCTAssertNil(plan(ProStatus(isPro: true, reason: .founding, checkedAt: now), state, now: now), "founding")
        XCTAssertNil(plan(.notPro(checkedAt: now), state, now: now))
        XCTAssertNil(plan(nil, state, now: now))

        XCTAssertTrue(TrialReminder.isRenewingTrial(trial(), now: now))
        for status in [trial(willRenew: false), trial(reason: .yearly), trial(billingIssue: true),
                       ProStatus(isPro: true, reason: .founding, checkedAt: now)] {
            XCTAssertFalse(TrialReminder.isRenewingTrial(status, now: now), "a delivered reminder is withdrawn too")
        }
        XCTAssertFalse(TrialReminder.isRenewingTrial(trial(), now: at(2026, 11, 4, 9, 15)), "the trial is over")
    }

    func testTheEntitlementRuleKeepsThePlanForThePrice() {
        let now = at(2026, 10, 28, 9, 20)
        let fact = PurchaseFact(productID: ProPlan.yearly.productID, expiresAt: at(2026, 11, 4, 9, 14), isIntroOffer: true,
                                willRenew: true)
        let status = Entitlement.evaluate(purchases: [fact], app: nil, now: now)
        XCTAssertEqual(status.reason, .trial)
        XCTAssertEqual(status.plan, .yearly)
        let ledger = ProLedger(status: status, firstSeenAt: now, legacyLog: false,
                               prices: [ProPlan.yearly.productID: yearlyPrice,
                                        ProPlan.monthly.productID: PlanPrice(displayPrice: "$3.99",
                                                                             period: PlanPeriod(value: 1, unit: .month))])
        XCTAssertEqual(ledger.renewalPrice, yearlyPrice, "the trial's own plan's price")
        XCTAssertNil(ProLedger(status: status, firstSeenAt: now, legacyLog: false).renewalPrice,
                     "no price until StoreKit has given one")
        let lifetime = Entitlement.evaluate(purchases: [PurchaseFact(productID: ProPlan.lifetime.productID)], app: nil, now: now)
        XCTAssertNil(lifetime.plan)
    }

    func testTheLedgerKeepsThePricesAndTheAsk() throws {
        let now = at(2026, 10, 28, 9, 20)
        let ledger = ProLedger(status: trial(), firstSeenAt: now, legacyLog: false,
                               prices: [ProPlan.yearly.productID: yearlyPrice], trialAskAt: now)
        let again = try ProLedgerStore.decode(ProLedgerStore.encode(ledger))
        XCTAssertEqual(again, ledger, "round trip")
        XCTAssertEqual(again.status?.plan, .yearly)

        let before = #"{"firstSeenAt":1791000000,"legacyLog":false,"status":{"isPro":true,"reason":"trial","checkedAt":1791000000,"expiresAt":1791600000,"willRenew":true}}"#
        let old = try ProLedgerStore.decode(Data(before.utf8))
        XCTAssertNil(old.status?.plan, "a file from before this build")
        XCTAssertEqual(old.prices, [:])
        XCTAssertNil(old.trialAskAt)
        XCTAssertNil(old.renewalPrice)
        let later = #"{"firstSeenAt":1791000000,"status":{"isPro":true,"reason":"trial","checkedAt":1791000000,"plan":"weekly"}}"#
        XCTAssertNil(try ProLedgerStore.decode(Data(later.utf8)).status?.plan, "a plan from a later version")
        XCTAssertEqual(try ProLedgerStore.decode(Data(later.utf8)).status?.reason, .trial, "and the rest still reads")
    }

    // MARK: What it says

    func testTheReminderSaysTheEndThePriceWhatWasLoggedAndHowToCancel() throws {
        XCTAssertEqual(try XCTUnwrap(plan(trial(), logged(12))).body,
                       "Your Taken trial ends Wednesday 4 Nov. Then $19.99 a year. 12 doses logged so far. Manage in Settings > Subscriptions.")
        XCTAssertEqual(TrialReminder.body(end: at(2026, 11, 1, 9), price: yearlyPrice, doses: 12, timeZone: london),
                       "Your Taken trial ends Sunday 1 Nov. Then $19.99 a year. 12 doses logged so far. Manage in Settings > Subscriptions.",
                       "the brief's example")
        XCTAssertEqual(TrialReminder.body(end: at(2026, 11, 1, 9), price: yearlyPrice, doses: 1, timeZone: london),
                       "Your Taken trial ends Sunday 1 Nov. Then $19.99 a year. 1 dose logged so far. Manage in Settings > Subscriptions.")
        XCTAssertEqual(TrialReminder.body(end: at(2026, 11, 1, 9), price: yearlyPrice, doses: 0, timeZone: london),
                       "Your Taken trial ends Sunday 1 Nov. Then $19.99 a year. Manage in Settings > Subscriptions.")
        XCTAssertEqual(TrialReminder.body(end: at(2026, 11, 1, 9), price: nil, doses: 2, timeZone: london),
                       "Your Taken trial ends Sunday 1 Nov. 2 doses logged so far. Manage in Settings > Subscriptions.",
                       "no price until StoreKit has given one: never made up")
        let pounds = PlanPrice(displayPrice: "£19.99", period: PlanPeriod(value: 1, unit: .year))
        XCTAssertEqual(TrialReminder.body(end: at(2026, 11, 1, 9), price: pounds, doses: 0, timeZone: london),
                       "Your Taken trial ends Sunday 1 Nov. Then £19.99 a year. Manage in Settings > Subscriptions.",
                       "the storefront's own price")
        let tokyo = TimeZone(identifier: "Asia/Tokyo")!
        XCTAssertEqual(TrialReminder.body(end: at(2026, 11, 1, 18), price: yearlyPrice, doses: 0, timeZone: tokyo),
                       "Your Taken trial ends Monday 2 Nov. Then $19.99 a year. Manage in Settings > Subscriptions.",
                       "the day and date where the iPhone is")
    }

    func testTheTrialCopyKeepsTheRules() {
        var lines = TrialAsk.all
        for doses in [0, 1, 12] {
            lines.append(TrialReminder.body(end: at(2026, 11, 1, 9), price: yearlyPrice, doses: doses, timeZone: london))
            lines.append(TrialReminder.body(end: at(2026, 11, 1, 9), price: nil, doses: doses, timeZone: london))
        }
        for text in lines {
            XCTAssertNil(text.range(of: "free", options: .caseInsensitive), text)
            XCTAssertFalse(text.contains("\u{2014}") || text.contains("\u{2013}"), "no em or en dash: \(text)")
            XCTAssertFalse(text.contains("!"), text)
            for sales in ["discount", "% off", "offer", "hurry", "last chance", "don't miss", "save "] {
                XCTAssertNil(text.range(of: sales, options: .caseInsensitive), "no sales copy: \(text)")
            }
        }
        XCTAssertEqual(TrialAsk.allow, "Continue", "a pre-prompt button titled like Continue")
        XCTAssertNotEqual(TrialAsk.allow, "Allow")
        XCTAssertEqual(TrialAsk.notNow, "Not now")
        XCTAssertEqual(TrialAsk.body, "Get the evening nudge and a heads-up 3 days before your trial ends.")
    }

    // MARK: The one ask

    func testTheAskShowsOnlyWhileIOSHasNotAsked() {
        XCTAssertTrue(TrialAsk.shows(trialStarted: true, permission: .notDetermined, alreadyShown: false))
        XCTAssertFalse(TrialAsk.shows(trialStarted: true, permission: .allowed, alreadyShown: false),
                       "already allowed: the reminder is simply scheduled")
        XCTAssertFalse(TrialAsk.shows(trialStarted: true, permission: .denied, alreadyShown: false), "already refused")
        XCTAssertFalse(TrialAsk.shows(trialStarted: true, permission: .notDetermined, alreadyShown: true), "once")
        XCTAssertFalse(TrialAsk.shows(trialStarted: false, permission: .notDetermined, alreadyShown: false),
                       "a plan bought without a trial")

        let now = at(2026, 10, 28, 9, 20)
        XCTAssertTrue(TrialAsk.mentionsReminder(status: trial(), now: now))
        XCTAssertFalse(TrialAsk.mentionsReminder(status: trial(ends: now.addingTimeInterval(3 * 24 * 3600)), now: now),
                       "a 3 day trial gets no reminder, so the ask does not promise one")
        XCTAssertEqual(TrialAsk.body(mentionsReminder: false), "Get the evening nudge if anything's left.")
    }

    @MainActor
    func testTheAskShowsOnceAndAnyAnswerAnswersTheNudgeOffer() async {
        let model = AppModel.fromLaunchArguments(["Taken", "-demo", "-screen", "today"])
        XCTAssertNil(model.trialAsk)
        XCTAssertFalse(model.settings.nudgeOfferDone)
        let nudgeBefore = model.settings.reminderEnabled
        await model.offerTrialAsk(at: .root)
        XCTAssertEqual(model.trialAsk, .root, "a trial just started and iOS has not asked")
        XCTAssertTrue(model.pro.trialAskShown)
        await model.answerTrialAsk(allow: false)
        XCTAssertNil(model.trialAsk, "Not now closes it")
        XCTAssertTrue(model.settings.nudgeOfferDone, "and Today does not ask again")
        XCTAssertEqual(model.settings.reminderEnabled, nudgeBefore, "Not now changes nothing else")
        await model.offerTrialAsk(at: .root)
        XCTAssertNil(model.trialAsk, "it never shows twice")

        let allowed = AppModel.fromLaunchArguments(["Taken", "-demo", "-screen", "today"])
        allowed.notificationPermission = { .allowed }
        await allowed.offerTrialAsk(at: .root)
        XCTAssertNil(allowed.trialAsk, "notifications already allowed: no sheet")
        XCTAssertFalse(allowed.pro.trialAskShown)

        let continuing = AppModel.fromLaunchArguments(["Taken", "-demo", "-screen", "today"])
        await continuing.setReminderEnabled(false)
        XCTAssertFalse(continuing.settings.reminderEnabled, "the demo's nudge starts on; off first")
        await continuing.offerTrialAsk(at: .sheet)
        XCTAssertEqual(continuing.trialAsk, .sheet, "on the level the paywall was on")
        await continuing.answerTrialAsk(allow: true)
        XCTAssertNil(continuing.trialAsk)
        XCTAssertTrue(continuing.settings.reminderEnabled, "allowed: the evening nudge is on at its time")
        XCTAssertEqual(continuing.settings.reminderMinutes, 20 * 60)
        XCTAssertTrue(continuing.settings.nudgeOfferDone)

        let swiped = AppModel.fromLaunchArguments(["Taken", "-demo", "-screen", "today"])
        await swiped.offerTrialAsk(at: .root)
        swiped.trialAskDidDismiss()
        XCTAssertNil(swiped.trialAsk)
        XCTAssertTrue(swiped.settings.nudgeOfferDone, "swiped away counts as Not now")
    }

    @MainActor
    func testATrialBoughtInThePaywallBringsTheAskOnceItHasGone() async throws {
        let model = AppModel.fromLaunchArguments(["Taken", "-demo", "-screen", "locked"])
        model.presentPaywall(anchor: .root, origin: .bar)
        XCTAssertNotNil(model.paywall)
        model.paywallUnlocked(trialStarted: true)
        model.closePaywall()
        model.paywallDidDismiss()
        XCTAssertNil(model.trialAsk, "not while the paywall is going")
        try await Task.sleep(for: .milliseconds(900))
        XCTAssertEqual(model.trialAsk, .root)

        let bought = AppModel.fromLaunchArguments(["Taken", "-demo", "-screen", "locked"])
        bought.presentPaywall(anchor: .root, origin: .bar)
        bought.paywallUnlocked(trialStarted: false)
        bought.closePaywall()
        bought.paywallDidDismiss()
        try await Task.sleep(for: .milliseconds(900))
        XCTAssertNil(bought.trialAsk, "a plan bought without a trial gets no ask")
    }
}
