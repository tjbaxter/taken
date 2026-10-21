import XCTest
@testable import Taken

/// The one reminder before an introductory trial ends (SPEC 3.9, PRO.md): two days before, at the nudge time or 10:00,
/// with when it ends and what was logged; withdrawn when the trial is cancelled or converts. London clock.
final class TrialReminderTests: XCTestCase {

    /// A yearly trial that started Sun 18 Oct and ends Sun 25 Oct 2026 at 09:14 in London.
    private func trial(willRenew: Bool? = true, reason: ProReason = .trial, billingIssue: Bool = false) -> ProStatus {
        ProStatus(isPro: true, reason: reason, checkedAt: at(2026, 10, 18, 9, 14), expiresAt: at(2026, 10, 25, 9, 14),
                  willRenew: willRenew, billingIssue: billingIssue)
    }

    private func logged(_ count: Int) -> StackState {
        let vd3 = makeItem("Vitamin D3", "VD3", created: at(2026, 10, 18, 9))
        var state = StackState(items: [vd3])
        for index in 0..<count {
            state.logDose(itemId: vd3.id, at: at(2026, 10, 18, 10).addingTimeInterval(Double(index) * 3600), timeZone: london)
        }
        return state
    }

    func testTheTrialReminderComesTwoDaysBeforeTheEndWithTheRecap() throws {
        let now = at(2026, 10, 19, 10)
        let plan = try XCTUnwrap(TrialReminder.plan(status: trial(), state: logged(12), now: now, timeZone: london))
        XCTAssertEqual(plan.fireDate, at(2026, 10, 23, 10, 0), "Friday at 10:00 while the nudge is off")
        XCTAssertEqual(plan.body, "Your Taken trial ends Sunday. 12 doses logged so far.")
        XCTAssertEqual(plan.components.hour, 10)
        XCTAssertEqual(plan.components.day, 23)
        XCTAssertEqual(plan.components.timeZone, london)

        var nudged = logged(12)
        nudged.settings.reminderEnabled = true
        XCTAssertEqual(TrialReminder.plan(status: trial(), state: nudged, now: now, timeZone: london)?.fireDate,
                       at(2026, 10, 23, 20, 0), "at the nudge time when the nudge is on")

        XCTAssertEqual(TrialReminder.plan(status: trial(), state: logged(1), now: now, timeZone: london)?.body,
                       "Your Taken trial ends Sunday. 1 dose logged so far.")
        XCTAssertEqual(TrialReminder.plan(status: trial(), state: logged(0), now: now, timeZone: london)?.body,
                       "Your Taken trial ends Sunday.")
        XCTAssertEqual(TrialReminder.identifier, "taken.pro.trial-end")
    }

    func testTheTrialReminderGoesWhenTheTrialIsCancelledOrConverts() {
        let now = at(2026, 10, 19, 10)
        let state = logged(12)
        XCTAssertNil(TrialReminder.plan(status: trial(willRenew: false), state: state, now: now, timeZone: london),
                     "cancelled: no reminder")
        XCTAssertNotNil(TrialReminder.plan(status: trial(willRenew: nil), state: state, now: now, timeZone: london),
                        "StoreKit did not say: still a trial set to renew")
        XCTAssertNil(TrialReminder.plan(status: trial(reason: .yearly), state: state, now: now, timeZone: london),
                     "converted: no reminder")
        XCTAssertNil(TrialReminder.plan(status: trial(billingIssue: true), state: state, now: now, timeZone: london))
        XCTAssertNil(TrialReminder.plan(status: .notPro(checkedAt: now), state: state, now: now, timeZone: london))
        XCTAssertNil(TrialReminder.plan(status: nil, state: state, now: now, timeZone: london))
        XCTAssertNil(TrialReminder.plan(status: trial(), state: state, now: at(2026, 10, 23, 10, 1), timeZone: london),
                     "never late: the moment has passed")
        XCTAssertNil(TrialReminder.plan(status: trial(), state: state, now: at(2026, 10, 25, 10), timeZone: london))
    }

    func testTheTrialReminderCopyKeepsTheRules() {
        let end = at(2026, 10, 25, 9, 14)
        for doses in [0, 1, 12] {
            let text = TrialReminder.body(end: end, doses: doses, timeZone: london)
            XCTAssertNil(text.range(of: "free", options: .caseInsensitive), text)
            XCTAssertFalse(text.contains("\u{2014}") || text.contains("\u{2013}") || text.contains("!"), text)
        }
        XCTAssertEqual(TrialReminder.body(end: at(2026, 10, 22, 23, 30), doses: 3, timeZone: london),
                       "Your Taken trial ends Thursday. 3 doses logged so far.", "the weekday where the iPhone is")
    }
}
