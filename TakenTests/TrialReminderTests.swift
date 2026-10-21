import XCTest
@testable import Taken

/// The trial promise and its one reminder (SPEC 3.9, PRO.md, 2026-10-21): on the day the paywall promised, at least
/// 72 hours before StoreKit's end of the trial, at the nudge time or 10:00, with the end date, the price, what was
/// logged and how to cancel; never twice; withdrawn when the trial is cancelled, converts, hits a billing issue, Pro is
/// for good or Profile's Trial reminder is off; and one notification ask after a trial starts, with one button, that
/// waits until nothing else holds the screen. London clock.
final class TrialReminderTests: XCTestCase {

    private let yearlyPrice = PlanPrice(displayPrice: "$19.99", period: PlanPeriod(value: 1, unit: .year))
    private let monthlyPrice = PlanPrice(displayPrice: "$3.99", period: PlanPeriod(value: 1, unit: .month))

    /// A yearly trial that started Wed 28 Oct and ends Wed 4 Nov 2026 at 09:14 in London (after the clocks went back, so
    /// every hour is a plain hour).
    private func trial(willRenew: Bool? = true, reason: ProReason = .trial, billingIssue: Bool = false,
                       ends: Date? = nil, renewsTo: ProPlan? = nil) -> ProStatus {
        ProStatus(isPro: true, reason: reason, checkedAt: at(2026, 10, 28, 9, 14), expiresAt: ends ?? at(2026, 11, 4, 9, 14),
                  willRenew: willRenew, billingIssue: billingIssue, plan: .yearly, renewsTo: renewsTo)
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
                      price: PlanPrice? = nil, sent: TrialReminderMark? = nil) -> TrialReminder.Plan? {
        TrialReminder.plan(status: status, price: price ?? yearlyPrice, state: state, now: now, timeZone: london,
                           sent: sent)
    }

    private func londonDay(_ date: Date) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = london
        return calendar.startOfDay(for: date)
    }

    private func daysBetween(_ start: Date, _ end: Date) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = london
        return calendar.dateComponents([.day], from: londonDay(start), to: londonDay(end)).day ?? -1
    }

    // MARK: When

    func testTheReminderComesOnDayFourAtLeast72HoursBeforeTheEndWhileTheNudgeIsOff() throws {
        let reminder = try XCTUnwrap(plan(trial(), logged(12)))
        XCTAssertEqual(reminder.fireDate, at(2026, 11, 1, 9, 14),
                       "Sunday, day 4: 10:00 would be under 72 hours before Wednesday 09:14, so 09:14, when the trial began")
        XCTAssertGreaterThanOrEqual(at(2026, 11, 4, 9, 14).timeIntervalSince(reminder.fireDate), 72 * 3600)
        XCTAssertEqual(reminder.components.day, 1)
        XCTAssertEqual(reminder.components.hour, 9)
        XCTAssertEqual(reminder.components.minute, 14)
        XCTAssertEqual(reminder.components.timeZone, london)

        let afternoon = try XCTUnwrap(plan(trial(ends: at(2026, 11, 4, 15, 30)), logged(12)))
        XCTAssertEqual(afternoon.fireDate, at(2026, 11, 1, 10, 0), "a trial started at 15:30: day 4 at 10:00")
        let exactly = try XCTUnwrap(plan(trial(ends: at(2026, 11, 4, 10, 0)), logged(12)))
        XCTAssertEqual(exactly.fireDate, at(2026, 11, 1, 10, 0), "exactly 72 hours counts as at least 72 hours")
        let seconds = try XCTUnwrap(plan(trial(ends: at(2026, 11, 4, 9, 14).addingTimeInterval(42)), logged(12)))
        XCTAssertEqual(seconds.fireDate, at(2026, 11, 1, 9, 14), "down to the minute, never under 72 hours")
    }

    func testTheReminderComesAtTheNudgeTimeWhileTheNudgeIsOn() throws {
        var nudged = logged(12, nudge: true)
        XCTAssertEqual(nudged.settings.reminderMinutes, 20 * 60)
        XCTAssertEqual(try XCTUnwrap(plan(trial(), nudged)).fireDate, at(2026, 11, 1, 9, 14),
                       "day 4 still: Sunday at 20:00 is under 72 hours, so 09:14 that day, not Saturday")
        XCTAssertEqual(try XCTUnwrap(plan(trial(ends: at(2026, 11, 4, 21, 0)), nudged)).fireDate, at(2026, 11, 1, 20, 0),
                       "a trial started at 21:00: day 4 at the nudge time")
        nudged.settings.reminderMinutes = 7 * 60 + 30
        XCTAssertEqual(try XCTUnwrap(plan(trial(), nudged)).fireDate, at(2026, 11, 1, 7, 30), "a morning nudge: day 4")
        nudged.settings.reminderEnabled = false
        XCTAssertEqual(try XCTUnwrap(plan(trial(ends: at(2026, 11, 4, 21, 0)), nudged)).fireDate, at(2026, 11, 1, 10, 0),
                       "the nudge turned off: 10:00 again, whatever its time")
    }

    func testTheReminderKeepsTheDayThePaywallPromised() throws {
        let week = IntroTerms(mode: .onUs, period: PlanPeriod(value: 1, unit: .week), periodCount: 1, displayPrice: "$0.00")
        let offer = PlanOffer(plan: .yearly, displayPrice: "$19.99", price: Decimal(string: "19.99")!, currencyCode: "USD",
                              locale: Locale(identifier: "en_US"), period: PlanPeriod(value: 1, unit: .year), intro: week)
        // (start hour, start minute, nudge on)
        let starts: [(Int, Int, Bool)] = [(9, 14, true), (9, 14, false), (8, 30, false), (8, 30, true), (15, 30, false),
                                          (15, 30, true), (21, 0, true), (23, 40, false), (7, 5, true)]
        for (hour, minute, nudge) in starts {
            let start = at(2026, 10, 28, hour, minute)
            let promised = try XCTUnwrap(ProCopy.trialTimeline(offer, eligible: true, now: start, timeZone: london)
                .first(where: { $0.text == "we remind you" })?.day)
            let end = start.addingTimeInterval(7 * 24 * 3600)
            let reminder = try XCTUnwrap(plan(trial(ends: end), logged(1, nudge: nudge), now: start.addingTimeInterval(60)))
            XCTAssertEqual("Day \(daysBetween(start, reminder.fireDate))", promised,
                           "started \(hour):\(minute), nudge \(nudge ? "on" : "off")")
            XCTAssertGreaterThanOrEqual(end.timeIntervalSince(reminder.fireDate), 72 * 3600)
        }

        // A 4-day trial started at 09:14: day 1 at 09:14, as its timeline says, not 46 minutes after it started.
        let start = at(2026, 10, 28, 9, 14)
        let four = try XCTUnwrap(plan(trial(ends: start.addingTimeInterval(4 * 24 * 3600)), logged(1),
                                      now: start.addingTimeInterval(60)))
        XCTAssertEqual(four.fireDate, at(2026, 10, 29, 9, 14))
    }

    func testANightTimeStartMovesTheReminderToTheEveningBeforeNeverIntoTheNight() throws {
        // A trial started at 02:30: 72 hours before its end is 02:30 on day 4, before the 07:00 wake-up time.
        let start = at(2026, 10, 28, 2, 30)
        let end = start.addingTimeInterval(7 * 24 * 3600)
        let off = try XCTUnwrap(plan(trial(ends: end), logged(1), now: start.addingTimeInterval(60)))
        XCTAssertEqual(off.fireDate, at(2026, 10, 31, 10, 0), "day 3 at 10:00: earlier than the promise, never later")
        let on = try XCTUnwrap(plan(trial(ends: end), logged(1, nudge: true), now: start.addingTimeInterval(60)))
        XCTAssertEqual(on.fireDate, at(2026, 10, 31, 20, 0), "day 3 at the nudge time")
        var early = logged(1)
        early.settings.wakeMinutes = 2 * 60
        XCTAssertEqual(try XCTUnwrap(plan(trial(ends: end), early, now: start.addingTimeInterval(60))).fireDate,
                       at(2026, 11, 1, 2, 30), "someone up at 02:00: day 4 at 02:30 is their morning")
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
        XCTAssertNil(plan(trial(), state, now: at(2026, 11, 1, 9, 15)), "the moment has passed: never late")
        XCTAssertNil(plan(trial(), state, now: at(2026, 11, 3, 10)))
        XCTAssertNil(plan(trial(), state, now: at(2026, 11, 4, 10)), "after the end")
        XCTAssertEqual(TrialReminder.identifier, "taken.pro.trial-end", "one identifier: at most one request")
        XCTAssertFalse(TrialReminder.identifier.hasPrefix(Reminders.requestPrefix))
    }

    func testOnceItHasGoneOutItNeverComesAgain() throws {
        // Nudge off, a trial started Wed 21:00: the reminder goes out Sun 1 Nov at 10:00.
        let end = at(2026, 11, 4, 21, 0)
        let first = try XCTUnwrap(plan(trial(ends: end), logged(2), now: at(2026, 10, 29, 9)))
        XCTAssertEqual(first.fireDate, at(2026, 11, 1, 10, 0))
        let sent = try XCTUnwrap(TrialReminder.nextMark(trial: first, end: end, previous: nil, now: at(2026, 10, 29, 9)))
        XCTAssertEqual(sent, TrialReminderMark(trialEnd: end, fireAt: at(2026, 11, 1, 10, 0)))

        // At noon the nudge comes on at 20:00, which would put the moment that evening again.
        let noon = at(2026, 11, 1, 12, 0)
        XCTAssertNotNil(plan(trial(ends: end), logged(2, nudge: true), now: noon), "without the record: a second one")
        XCTAssertNil(plan(trial(ends: end), logged(2, nudge: true), now: noon, sent: sent),
                     "with it: it has gone out, so never again, even cleared from Notification Center")
        XCTAssertEqual(TrialReminder.nextMark(trial: nil, end: end, previous: sent, now: noon), sent, "kept once gone out")

        // Still pending: a new nudge time moves it, and the record follows.
        let before = at(2026, 10, 30, 12, 0)
        let moved = try XCTUnwrap(plan(trial(ends: end), logged(2, nudge: true), now: before, sent: sent))
        XCTAssertEqual(moved.fireDate, at(2026, 11, 1, 20, 0))
        XCTAssertEqual(TrialReminder.nextMark(trial: moved, end: end, previous: sent, now: before),
                       TrialReminderMark(trialEnd: end, fireAt: at(2026, 11, 1, 20, 0)))
        XCTAssertNil(TrialReminder.nextMark(trial: nil, end: end, previous: sent, now: before),
                     "a pending one removed without a replacement (auto-renew off, the switch off) is forgotten")
        XCTAssertNotNil(plan(trial(ends: at(2026, 11, 6, 21, 0)), logged(2), now: noon, sent: sent),
                        "a record for another trial's end blocks nothing")
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

    func testProfilesTrialReminderSwitchTurnsItOff() throws {
        var state = logged(12, nudge: true)
        XCTAssertTrue(state.settings.trialReminderEnabled, "on unless turned off")
        XCTAssertNotNil(plan(trial(), state))
        state.settings.trialReminderEnabled = false
        XCTAssertNil(plan(trial(), state), "the switch off: no reminder")
        XCTAssertNil(TrialReminder.notice(status: trial(), price: yearlyPrice, state: state, now: at(2026, 11, 2, 9),
                                          timeZone: london), "and no line on Today")
        state.settings.reminderEnabled = false
        XCTAssertNil(plan(trial(), state), "whatever the nudge")

        // Old files read as on; it is written only once turned off.
        let old = try JSONDecoder().decode(StackSettings.self, from: Data(#"{"reminderEnabled":true}"#.utf8))
        XCTAssertTrue(old.trialReminderEnabled)
        let defaults = try JSONEncoder().encode(StackSettings())
        XCTAssertNil(String(decoding: defaults, as: UTF8.self).range(of: "trialReminderEnabled"))
        var off = StackSettings()
        off.trialReminderEnabled = false
        XCTAssertFalse(try JSONDecoder().decode(StackSettings.self, from: JSONEncoder().encode(off)).trialReminderEnabled)
        var erased = StackState(settings: off)
        erased.eraseAll()
        XCTAssertTrue(erased.settings.trialReminderEnabled, "Erase all data puts it back to on with the other settings")
    }

    func testTheEntitlementRuleKeepsThePlanForThePrice() {
        let now = at(2026, 10, 28, 9, 20)
        let fact = PurchaseFact(productID: ProPlan.yearly.productID, expiresAt: at(2026, 11, 4, 9, 14), isIntroOffer: true,
                                willRenew: true)
        let status = Entitlement.evaluate(purchases: [fact], app: nil, now: now)
        XCTAssertEqual(status.reason, .trial)
        XCTAssertEqual(status.plan, .yearly)
        let prices = [ProPlan.yearly.productID: yearlyPrice, ProPlan.monthly.productID: monthlyPrice]
        let ledger = ProLedger(status: status, firstSeenAt: now, legacyLog: false, prices: prices)
        XCTAssertEqual(ledger.renewalPrice, yearlyPrice, "the trial's own plan's price")
        XCTAssertNil(ProLedger(status: status, firstSeenAt: now, legacyLog: false).renewalPrice,
                     "no price until StoreKit has given one")
        let lifetime = Entitlement.evaluate(purchases: [PurchaseFact(productID: ProPlan.lifetime.productID)], app: nil, now: now)
        XCTAssertNil(lifetime.plan)
    }

    func testATrialSwitchedToMonthlyNamesTheMonthlyPrice() throws {
        // Yearly and monthly sit at the same level of one group: a switch during the trial takes effect at its end, and
        // StoreKit's autoRenewPreference names the plan that renews.
        let now = at(2026, 10, 28, 9, 20)
        let fact = PurchaseFact(productID: ProPlan.yearly.productID, expiresAt: at(2026, 11, 4, 9, 14), isIntroOffer: true,
                                willRenew: true, renewsTo: ProPlan.monthly.productID)
        let status = Entitlement.evaluate(purchases: [fact], app: nil, now: now)
        XCTAssertEqual(status.plan, .yearly)
        XCTAssertEqual(status.renewsTo, .monthly)
        let prices = [ProPlan.yearly.productID: yearlyPrice, ProPlan.monthly.productID: monthlyPrice]
        let ledger = ProLedger(status: status, firstSeenAt: now, legacyLog: false, prices: prices)
        XCTAssertEqual(ledger.renewalPrice, monthlyPrice)
        let reminder = try XCTUnwrap(TrialReminder.plan(status: status, price: ledger.renewalPrice, state: logged(0), now: now,
                                                        timeZone: london))
        XCTAssertEqual(reminder.body, "Your Taken trial ends Wednesday 4 Nov. Unless cancelled, it then renews at $3.99 a month. Cancel at least 24 hours before in Settings > your name > Subscriptions.")

        let same = PurchaseFact(productID: ProPlan.yearly.productID, expiresAt: at(2026, 11, 4, 9, 14), isIntroOffer: true,
                                willRenew: true, renewsTo: ProPlan.yearly.productID)
        XCTAssertEqual(ProLedger(status: Entitlement.evaluate(purchases: [same], app: nil, now: now), firstSeenAt: now,
                                 legacyLog: false, prices: prices).renewalPrice, yearlyPrice)
        let odd = PurchaseFact(productID: ProPlan.yearly.productID, expiresAt: at(2026, 11, 4, 9, 14), isIntroOffer: true,
                               willRenew: true, renewsTo: ProPlan.lifetime.productID)
        XCTAssertNil(Entitlement.evaluate(purchases: [odd], app: nil, now: now).renewsTo, "only a subscription renews")
        XCTAssertFalse(status.sameEntitlement(as: Entitlement.evaluate(
            purchases: [PurchaseFact(productID: ProPlan.yearly.productID, expiresAt: at(2026, 11, 4, 9, 14),
                                     isIntroOffer: true, willRenew: true)], app: nil, now: now)),
                       "a switch counts as a change, so the reminder is rebuilt with the new price")
    }

    func testTheLedgerKeepsThePricesTheAskAndTheReminder() throws {
        let now = at(2026, 10, 28, 9, 20)
        let mark = TrialReminderMark(trialEnd: at(2026, 11, 4, 9, 14), fireAt: at(2026, 11, 1, 9, 14))
        let ledger = ProLedger(status: trial(renewsTo: .monthly), firstSeenAt: now, legacyLog: false,
                               prices: [ProPlan.yearly.productID: yearlyPrice], trialAskAt: now, trialReminder: mark)
        let again = try ProLedgerStore.decode(ProLedgerStore.encode(ledger))
        XCTAssertEqual(again, ledger, "round trip")
        XCTAssertEqual(again.status?.plan, .yearly)
        XCTAssertEqual(again.status?.renewsTo, .monthly)
        XCTAssertEqual(again.trialReminder, mark)

        let before = #"{"firstSeenAt":1791000000,"legacyLog":false,"status":{"isPro":true,"reason":"trial","checkedAt":1791000000,"expiresAt":1791600000,"willRenew":true}}"#
        let old = try ProLedgerStore.decode(Data(before.utf8))
        XCTAssertNil(old.status?.plan, "a file from before this build")
        XCTAssertNil(old.status?.renewsTo)
        XCTAssertEqual(old.prices, [:])
        XCTAssertNil(old.trialAskAt)
        XCTAssertNil(old.trialReminder)
        XCTAssertNil(old.renewalPrice)
        let later = #"{"firstSeenAt":1791000000,"status":{"isPro":true,"reason":"trial","checkedAt":1791000000,"plan":"weekly","renewsTo":"weekly"}}"#
        XCTAssertNil(try ProLedgerStore.decode(Data(later.utf8)).status?.plan, "a plan from a later version")
        XCTAssertNil(try ProLedgerStore.decode(Data(later.utf8)).status?.renewsTo)
        XCTAssertEqual(try ProLedgerStore.decode(Data(later.utf8)).status?.reason, .trial, "and the rest still reads")
    }

    // MARK: What it says

    func testTheReminderSaysTheEndThePriceWhatWasLoggedAndHowToCancel() throws {
        XCTAssertEqual(try XCTUnwrap(plan(trial(), logged(12))).body,
                       "Your Taken trial ends Wednesday 4 Nov. Unless cancelled, it then renews at $19.99 a year. 12 doses logged so far. Cancel at least 24 hours before in Settings > your name > Subscriptions.")
        XCTAssertEqual(TrialReminder.body(end: at(2026, 11, 1, 9), price: yearlyPrice, doses: 12, timeZone: london),
                       "Your Taken trial ends Sunday 1 Nov. Unless cancelled, it then renews at $19.99 a year. 12 doses logged so far. Cancel at least 24 hours before in Settings > your name > Subscriptions.",
                       "the brief's example, with Apple's steps and its 24 hours")
        XCTAssertEqual(TrialReminder.body(end: at(2026, 11, 1, 9), price: yearlyPrice, doses: 1, timeZone: london),
                       "Your Taken trial ends Sunday 1 Nov. Unless cancelled, it then renews at $19.99 a year. 1 dose logged so far. Cancel at least 24 hours before in Settings > your name > Subscriptions.")
        XCTAssertEqual(TrialReminder.body(end: at(2026, 11, 1, 9), price: yearlyPrice, doses: 0, timeZone: london),
                       "Your Taken trial ends Sunday 1 Nov. Unless cancelled, it then renews at $19.99 a year. Cancel at least 24 hours before in Settings > your name > Subscriptions.")
        XCTAssertEqual(TrialReminder.body(end: at(2026, 11, 1, 9), price: nil, doses: 2, timeZone: london),
                       "Your Taken trial ends Sunday 1 Nov. Unless cancelled, it then renews. 2 doses logged so far. Cancel at least 24 hours before in Settings > your name > Subscriptions.",
                       "no price until StoreKit has given one: never made up")
        let pounds = PlanPrice(displayPrice: "£19.99", period: PlanPeriod(value: 1, unit: .year))
        XCTAssertEqual(TrialReminder.body(end: at(2026, 11, 1, 9), price: pounds, doses: 0, timeZone: london),
                       "Your Taken trial ends Sunday 1 Nov. Unless cancelled, it then renews at £19.99 a year. Cancel at least 24 hours before in Settings > your name > Subscriptions.",
                       "the storefront's own price")
        let tokyo = TimeZone(identifier: "Asia/Tokyo")!
        XCTAssertEqual(TrialReminder.body(end: at(2026, 11, 1, 18), price: yearlyPrice, doses: 0, timeZone: tokyo),
                       "Your Taken trial ends Monday 2 Nov. Unless cancelled, it then renews at $19.99 a year. Cancel at least 24 hours before in Settings > your name > Subscriptions.",
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
        XCTAssertEqual(TrialAsk.body, "Get the evening nudge and a heads-up 3 days before your trial ends.")
        XCTAssertEqual(TrialReminder.howToCancel, "Cancel at least 24 hours before in Settings > your name > Subscriptions.",
                       "Apple's steps (Settings, your name, Subscriptions) and its 24 hours")
    }

    // MARK: Today's line while notifications cannot carry it

    func testTodayCarriesTheReminderWhileNotificationsCannot() throws {
        let state = logged(12)
        func notice(_ status: ProStatus?, _ now: Date, _ state: StackState) -> String? {
            TrialReminder.notice(status: status, price: yearlyPrice, state: state, now: now, timeZone: london)
        }
        XCTAssertNil(notice(trial(), at(2026, 11, 1, 9, 13), state), "not before the reminder's own moment")
        XCTAssertEqual(notice(trial(), at(2026, 11, 1, 9, 14), state),
                       "Your Taken trial ends Wednesday 4 Nov. Unless cancelled, it then renews at $19.99 a year. 12 doses logged so far. Cancel at least 24 hours before in Settings > your name > Subscriptions.",
                       "the reminder's own words")
        XCTAssertNotNil(notice(trial(), at(2026, 11, 4, 9, 13), state), "until the trial ends")
        XCTAssertNil(notice(trial(), at(2026, 11, 4, 9, 14), state))
        XCTAssertNil(notice(trial(willRenew: false), at(2026, 11, 2, 9), state), "cancelled: gone")
        XCTAssertNil(notice(trial(reason: .yearly), at(2026, 11, 2, 9), state), "converted: gone")

        let today = StackEngine(state: state, clock: londonClock()).todaySummary(now: at(2026, 11, 2, 9))
        let line = try XCTUnwrap(notice(trial(), at(2026, 11, 2, 9), state))
        XCTAssertEqual(TodayPrompts.pick(settings: state.settings, hasStack: true, today: today, repairDay: nil,
                                         locked: false, trialNotice: line),
                       .trialEnds(line), "it comes before the other rows")
        XCTAssertEqual(TodayPrompts.pick(settings: state.settings, hasStack: true, today: today, repairDay: nil,
                                         locked: false),
                       .nudgeOffer(minutes: 20 * 60), "without it, the rows as before")
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
    private func demoModel(_ screen: String = "today") -> AppModel {
        let model = AppModel.fromLaunchArguments(["Taken", "-demo", "-screen", screen])
        model.captureBusy = { false }
        return model
    }

    @MainActor
    func testTheAskShowsOnceOnScreenAndContinueTurnsTheNudgeOn() async {
        let model = demoModel()
        XCTAssertNil(model.trialAsk)
        XCTAssertFalse(model.settings.nudgeOfferDone)
        await model.offerTrialAsk(over: nil)
        XCTAssertEqual(model.trialAsk, .root, "a trial just started and iOS has not asked")
        XCTAssertFalse(model.pro.trialAskShown, "not used up until it is on screen")
        model.trialAskDidAppear()
        XCTAssertTrue(model.pro.trialAskShown)
        model.tab = .todo
        XCTAssertFalse(model.showsTodoTabUncovered, "the mic never opens under it")
        await model.setReminderEnabled(false)
        await model.answerTrialAsk()
        XCTAssertNil(model.trialAsk, "Continue closes it once iOS has answered")
        XCTAssertTrue(model.settings.reminderEnabled, "allowed: the evening nudge is on at its time")
        XCTAssertEqual(model.settings.reminderMinutes, 20 * 60)
        XCTAssertTrue(model.settings.nudgeOfferDone, "and Today does not ask again")
        model.trialAskDidDismiss()
        XCTAssertNil(model.presentTrialAskIfClear(), "answered: it never comes back")
        await model.offerTrialAsk(over: nil)
        XCTAssertNil(model.trialAsk, "it never shows twice")

        let allowed = demoModel()
        allowed.notificationPermission = { .allowed }
        await allowed.offerTrialAsk(over: nil)
        XCTAssertNil(allowed.trialAsk, "notifications already allowed: no sheet")
        XCTAssertFalse(allowed.pro.trialAskShown)
        let denied = demoModel()
        denied.notificationPermission = { .denied }
        await denied.offerTrialAsk(over: nil)
        XCTAssertNil(denied.trialAsk, "already refused: no sheet")
    }

    @MainActor
    func testATrialBoughtInThePaywallBringsTheAskOnceItHasGone() async throws {
        let model = demoModel("locked")
        model.presentPaywall(anchor: .root, origin: .bar)
        XCTAssertNotNil(model.paywall)
        model.paywallUnlocked(trialStarted: true)
        model.closePaywall()
        model.paywallDidDismiss()
        XCTAssertNil(model.trialAsk, "not while the paywall is going")
        try await Task.sleep(for: .milliseconds(900))
        XCTAssertEqual(model.trialAsk, .root)

        let bought = demoModel("locked")
        bought.presentPaywall(anchor: .root, origin: .bar)
        bought.paywallUnlocked(trialStarted: false)
        bought.closePaywall()
        bought.paywallDidDismiss()
        try await Task.sleep(for: .milliseconds(900))
        XCTAssertNil(bought.trialAsk, "a plan bought without a trial gets no ask")
    }

    @MainActor
    func testAnAddFromALockedTodayGetsItsSheetAndTheAskAfterIt() async throws {
        // "+" on Today while locked: the paywall, a trial, then the Add sheet the tap asked for.
        let model = demoModel()
        model.presentPaywall(anchor: .root, origin: .action, pending: { [weak model] in model?.sheet = .add })
        model.paywallUnlocked(trialStarted: true)
        model.closePaywall()
        model.paywallDidDismiss()
        XCTAssertEqual(model.sheet, .add, "the tap that opened the paywall ran")
        model.levelDidAppear(.sheet)
        try await Task.sleep(for: .milliseconds(900))
        XCTAssertNil(model.trialAsk, "never over the Add sheet the person asked for, and never lost either")
        XCTAssertFalse(model.pro.trialAskShown, "nothing is used up while it waits")
        model.sheet = nil
        XCTAssertNil(model.presentTrialAskIfClear(), "not while the sheet is still closing")
        model.levelDidDisappear(.sheet)
        model.rootSheetDidDismiss()
        XCTAssertEqual(model.presentTrialAskIfClear(), .root, "once it has gone, on Today")
        XCTAssertEqual(model.trialAsk, .root)
    }

    @MainActor
    func testATrialStartedOverASheetThatClosesComesOnToday() async {
        // The Add sheet's own Add while locked: the paywall over the sheet, a trial, then the items are added and the
        // sheet closes. Set time works the same way.
        let model = demoModel()
        model.sheet = .add
        model.levelDidAppear(.sheet)
        model.sheet = nil
        await model.offerTrialAsk(over: .add)
        XCTAssertNil(model.trialAsk, "never on a sheet that is closing")
        model.levelDidDisappear(.sheet)
        XCTAssertEqual(model.presentTrialAskIfClear(), .root, "on Today instead")

        // A sheet that stays up (a backfill on the day sheet): over it.
        let staying = demoModel()
        let day = staying.today.day.adding(-1)
        staying.sheet = .day(day)
        staying.levelDidAppear(.sheet)
        await staying.offerTrialAsk(over: .day(day))
        XCTAssertEqual(staying.trialAsk, .sheet, "over the sheet the paywall was over")

        // Profile's Add, which opens a sheet inside Profile: after that one has closed, over Profile.
        let nested = demoModel()
        nested.sheet = .settings
        nested.levelDidAppear(.sheet)
        nested.levelDidAppear(.nested)
        await nested.offerTrialAsk(over: .settings)
        XCTAssertNil(nested.trialAsk, "never over the sheet inside the sheet")
        nested.levelDidDisappear(.nested)
        XCTAssertEqual(nested.presentTrialAskIfClear(), .sheet)
    }

    @MainActor
    func testTheAskWaitsForAVoiceNoteAndStepsAsideForOne() async throws {
        let model = demoModel()
        model.captureBusy = { true }
        await model.offerTrialAsk(over: nil)
        XCTAssertNil(model.trialAsk, "never over a voice note being heard")
        model.captureBusy = { false }
        model.captureDidSettle()
        XCTAssertEqual(model.presentTrialAskIfClear(), .root, "once it is done")

        // A voice to-do request while it is up: it steps aside, held back until the recording has started, and comes
        // back once the recording is done.
        model.trialAskVoiceHold = 0.3
        model.openTodoTab()
        XCTAssertNil(model.trialAsk)
        XCTAssertTrue(model.showsTodoTabUncovered, "the mic may open")
        XCTAssertNil(model.presentTrialAskIfClear(), "held while the recording it asked for starts")
        model.captureBusy = { true }
        try await Task.sleep(for: .milliseconds(800))
        XCTAssertNil(model.trialAsk, "never over the recording")
        model.captureBusy = { false }
        model.captureDidSettle()
        XCTAssertEqual(model.presentTrialAskIfClear(), .root, "once it is done")

        // iOS's prompt answered meanwhile (the nudge's Turn on): the ask is dropped.
        let prompted = demoModel()
        prompted.captureBusy = { true }
        await prompted.offerTrialAsk(over: nil)
        prompted.notificationPermission = { .denied }
        prompted.captureBusy = { false }
        prompted.captureDidSettle()
        try await Task.sleep(for: .milliseconds(700))
        XCTAssertNil(prompted.trialAsk, "iOS has its answer: no ask")
        XCTAssertNil(prompted.presentTrialAskIfClear(), "and none waits")
    }
}
