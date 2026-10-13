import XCTest
@testable import Taken

/// Where Pro is needed (PRO.md): the first dose needs none, the log stays readable without it, and every surface
/// (app, widgets, control, Siri, nudge) reads the same cached answer.
final class ProGateTests: XCTestCase {

    private let now = at(2026, 10, 13, 9)

    private var pro: ProStatus { ProStatus(isPro: true, reason: .yearly, checkedAt: now, expiresAt: at(2027, 10, 13, 9), willRenew: true) }
    private var notPro: ProStatus { .notPro(checkedAt: now) }

    private func access(_ status: ProStatus?, settled: Bool = true, legacy: Bool = false, logged: Bool = true) -> ProAccess {
        ProGate.access(status: status, settled: settled, legacyLog: legacy, hasLogged: logged, now: now)
    }

    func testTheFirstDoseNeedsNoPro() {
        XCTAssertEqual(access(nil, logged: false), .firstSession, "first run: add the stack, tap the first dose")
        XCTAssertEqual(access(notPro, logged: false), .firstSession)
        XCTAssertEqual(access(nil, settled: false, logged: false), .firstSession, "never waits on StoreKit for it")
        XCTAssertTrue(ProAccess.firstSession.allowsLogging)
    }

    func testAfterTheFirstDoseLoggingNeedsPro() {
        XCTAssertEqual(access(notPro), .locked)
        XCTAssertFalse(ProAccess.locked.allowsLogging)
        XCTAssertEqual(access(nil), .locked, "a missing cache counts as not Pro")
        XCTAssertEqual(access(pro), .pro)
        XCTAssertTrue(ProAccess.pro.allowsLogging)
    }

    func testCachedProHoldsUntilItExpires() {
        // A renewing plan whose period ended an hour ago: the renewal is on its way, and only the app can see it.
        var renewing = pro
        renewing.expiresAt = at(2026, 10, 13, 8)
        XCTAssertEqual(access(renewing), .pro, "a payer is never locked out at a renewal")
        XCTAssertEqual(ProGate.access(ledger: ProLedger(status: renewing, firstSeenAt: now, legacyLog: false),
                                      state: loggedState, now: now), .pro, "widgets, the control, Siri and the nudge too")
        var lapsed = renewing
        lapsed.expiresAt = now.addingTimeInterval(-ProStatus.renewalMargin - 60)
        XCTAssertEqual(access(lapsed), .locked, "the margin is capped")
        XCTAssertEqual(access(lapsed, settled: false), .checking, "the app asks StoreKit before it shows the lock")

        var cancelled = renewing
        cancelled.willRenew = false
        XCTAssertEqual(access(cancelled), .locked, "a plan set not to renew ends on time")
        var billing = renewing
        billing.billingIssue = true
        XCTAssertEqual(access(billing), .locked, "a billing grace period ends on time")
        XCTAssertEqual(access(ProStatus(isPro: true, reason: .lifetime, checkedAt: at(2020, 1, 1, 0))), .pro,
                       "lifetime and founding never expire")
    }

    private var loggedState: StackState {
        let vd3 = makeItem("Vitamin D3", "VD3", created: at(2026, 10, 1, 8))
        var state = StackState(items: [vd3])
        state.logDose(itemId: vd3.id, at: at(2026, 10, 12, 8), timeZone: london)
        return state
    }

    func testTheFirstSessionEndsWithTheFirstDoseEver() {
        // Erasing the log or deleting items after the first dose never opens logging again without Pro.
        let created = at(2026, 10, 1, 8)
        let erased = StackState(items: [makeItem("Vitamin D3", "VD3", created: created)])
        var ledger = ProLedger(status: notPro, firstSeenAt: created, legacyLog: false)
        XCTAssertEqual(ProGate.access(ledger: ledger, state: erased, now: now), .firstSession, "nothing logged yet")
        ledger.firstDoseAt = at(2026, 10, 2, 8)
        XCTAssertEqual(ProGate.access(ledger: ledger, state: erased, now: now), .locked, "the log was erased afterwards")
        XCTAssertEqual(ProGate.access(ledger: ledger, state: StackState(), now: now), .locked, "every item deleted")
        XCTAssertTrue(ProGate.hasLogged(state: StackState(), ledger: ledger))
        XCTAssertTrue(ProGate.hasLogged(state: loggedState, ledger: nil))
        XCTAssertFalse(ProGate.hasLogged(state: erased, ledger: nil))
        ledger.status = pro
        XCTAssertEqual(ProGate.access(ledger: ledger, state: erased, now: now), .pro)
    }

    func testTheFirstDoseIsRecordedOnceInTheLedger() throws {
        let store = ProLedgerStore(fileURL: temporaryStoreURL().deletingLastPathComponent().appendingPathComponent("pro.json"))
        store.noteFirstDose(at: now)
        XCTAssertNil(store.load(), "never creates the ledger: until the app runs, the log counts as one from 1.0")
        _ = store.loadOrCreate { ProLedger(firstSeenAt: now, legacyLog: false) }
        store.noteFirstDose(at: now)
        XCTAssertEqual(store.load()?.firstDoseAt, now)
        store.noteFirstDose(at: at(2026, 10, 20, 9))
        XCTAssertEqual(store.load()?.firstDoseAt, now, "the first one stays")
        let legacy = ProLedger(firstSeenAt: now, legacyLog: true, firstDoseAt: now)
        XCTAssertEqual(try ProLedgerStore.decode(ProLedgerStore.encode(legacy)), legacy, "round trip")
    }

    func testTheAppWaitsForStoreKitBeforeLocking() {
        XCTAssertEqual(access(nil, settled: false), .checking, "no lock flashes before StoreKit answers")
        XCTAssertEqual(access(notPro, settled: false), .checking, "a stale no may have renewed since")
        XCTAssertFalse(ProAccess.checking.allowsLogging)
        XCTAssertEqual(access(pro, settled: false), .pro)
    }

    func testALogFrom10IsNeverLockedOnAGuess() {
        // Updated from 1.0 and StoreKit has not answered yet: every 1.0 App Store download is a founding member.
        XCTAssertEqual(access(nil, settled: true, legacy: true), .pending)
        XCTAssertTrue(ProAccess.pending.allowsLogging)
        XCTAssertEqual(access(notPro, legacy: true), .locked, "once StoreKit has said no, they are locked")
    }

    func testWidgetsAndIntentsReadTheLedger() {
        let created = at(2026, 10, 1, 8)
        let vd3 = makeItem("Vitamin D3", "VD3", created: created)
        var state = StackState(items: [vd3])
        XCTAssertEqual(ProGate.access(ledger: nil, state: state, now: now), .firstSession)
        let ledger = ProLedger(status: notPro, firstSeenAt: created, legacyLog: false)
        XCTAssertEqual(ProGate.access(ledger: ledger, state: state, now: now), .firstSession)

        state.logDose(itemId: vd3.id, at: at(2026, 10, 12, 8), timeZone: london)
        XCTAssertEqual(ProGate.access(ledger: ledger, state: state, now: now), .locked)
        XCTAssertEqual(ProGate.access(ledger: ProLedger(status: pro, firstSeenAt: created, legacyLog: false),
                                      state: state, now: now), .pro)
        XCTAssertEqual(ProGate.access(ledger: nil, state: state, now: now), .pending,
                       "no ledger yet: the app has not run since the update from 1.0")
        XCTAssertEqual(ProGate.access(ledger: ProLedger(firstSeenAt: created, legacyLog: false), state: state, now: now),
                       .locked, "a new install whose check is still open is not Pro")
    }

    func testNudgesFollowPro() {
        XCTAssertEqual(ProGate.nudgeWindow(access: .locked, status: notPro), .closed)
        XCTAssertEqual(ProGate.nudgeWindow(access: .pro, status: pro), .open, "a renewing plan keeps its nudges")
        XCTAssertEqual(ProGate.nudgeWindow(access: .firstSession, status: nil), .open)
        var cancelled = pro
        cancelled.willRenew = false
        XCTAssertEqual(ProGate.nudgeWindow(access: .pro, status: cancelled), .until(at(2027, 10, 13, 9)))
        XCTAssertEqual(ProGate.nudgeWindow(access: .pro, status: cancelled), .until(cancelled.activeUntil!),
                       "nudges stop when cached Pro does")
        XCTAssertEqual(ProGate.nudgeWindow(access: .pro, status: ProStatus(isPro: true, reason: .lifetime, checkedAt: now)), .open)
    }

    func testNoNudgesWhenLockedAndNoneAfterACancelledPlanEnds() {
        let created = at(2026, 10, 1, 8)
        var state = StackState(items: [makeItem("Vitamin D3", "VD3", created: created)])
        state.settings.reminderEnabled = true
        state.settings.reminderMinutes = 21 * 60
        XCTAssertEqual(Reminders.plan(state: state, now: now, timeZone: london, window: .open).count, 14)
        XCTAssertTrue(Reminders.plan(state: state, now: now, timeZone: london, window: .closed).isEmpty)
        let ends = at(2026, 10, 16, 12)
        let plans = Reminders.plan(state: state, now: now, timeZone: london, window: .until(ends))
        XCTAssertEqual(plans.map(\.day), [13, 14, 15].map { DayKey(year: 2026, month: 10, day: $0) },
                       "nudges up to the day the plan ends")
        XCTAssertTrue(plans.allSatisfy { $0.fireDate < ends })
    }

    func testLockedNoteIsWithdrawnLikeTheStaleOne() {
        let state = StackState()
        let withdrawn = Reminders.staleDelivered(["other", Reminders.lockedIdentifier], state: state, now: now, timeZone: london)
        XCTAssertEqual(withdrawn, [Reminders.lockedIdentifier])
    }

    func testLedgerRoundTripThroughTheAppGroupFile() throws {
        let store = ProLedgerStore(fileURL: temporaryStoreURL().deletingLastPathComponent().appendingPathComponent("pro.json"))
        XCTAssertNil(store.load(), "missing until the app first runs")
        let created = store.loadOrCreate { ProLedger(firstSeenAt: now, legacyLog: true) }
        XCTAssertTrue(created.legacyLog)
        let again = store.loadOrCreate { ProLedger(firstSeenAt: at(2030, 1, 1, 0), legacyLog: false) }
        XCTAssertEqual(again, created, "written once, the first time")

        let status = ProStatus(isPro: true, reason: .trial, checkedAt: now, expiresAt: at(2026, 10, 20, 9), willRenew: true)
        store.update { ledger in ledger?.status = status }
        store.recordPending(.log(UUID(uuidString: "6F1C2D3E-4A5B-4C6D-8E9F-0A1B2C3D4E5F")!), at: now)
        let reread = ProLedgerStore(fileURL: store.fileURL).load()
        XCTAssertEqual(reread?.status, status, "the widget extension reads what the app wrote")
        XCTAssertEqual(reread?.pending?.at, now)
        XCTAssertEqual(reread?.pending?.action, .log(UUID(uuidString: "6F1C2D3E-4A5B-4C6D-8E9F-0A1B2C3D4E5F")!))
    }

    func testLedgerDecodesWithMissingKeys() throws {
        let json = #"{"firstSeenAt":1791000000,"status":{"isPro":true,"reason":"founding","checkedAt":1791000000}}"#
        let ledger = try ProLedgerStore.decode(Data(json.utf8))
        XCTAssertEqual(ledger.status?.reason, .founding)
        XCTAssertNil(ledger.status?.expiresAt)
        XCTAssertEqual(ledger.status?.billingIssue, false)
        XCTAssertFalse(ledger.legacyLog)
        XCTAssertNil(ledger.pending)
        XCTAssertNil(ledger.firstDoseAt, "a ledger from before the first dose was recorded")
        XCTAssertEqual(ledger.status?.renewingSubscription, false)
        let unknown = #"{"firstSeenAt":1791000000,"status":{"isPro":false,"reason":"someday","checkedAt":1791000000}}"#
        XCTAssertEqual(try ProLedgerStore.decode(Data(unknown.utf8)).status?.reason, ProReason.none,
                       "a reason from a later version reads as none")
    }

    func testProRouteURLs() {
        XCTAssertEqual(ProRoute().url.absoluteString, "taken://pro")
        XCTAssertEqual(ProRoute(then: .takeAll).url.absoluteString, "taken://pro?then=take-all")
        let id = UUID(uuidString: "6F1C2D3E-4A5B-4C6D-8E9F-0A1B2C3D4E5F")!
        let log = ProRoute(then: .log(id))
        XCTAssertEqual(log.url.absoluteString, "taken://pro?then=log&item=6F1C2D3E-4A5B-4C6D-8E9F-0A1B2C3D4E5F")
        XCTAssertEqual(ProRoute(url: log.url), log)
        XCTAssertEqual(ProRoute(url: URL(string: "taken://pro?then=take-all")!)?.then, .takeAll)
        XCTAssertEqual(ProRoute(url: URL(string: "taken://pro")!), ProRoute())
        XCTAssertNil(ProRoute(url: URL(string: "taken://pro?then=log&item=nope")!)?.then)
        XCTAssertNil(ProRoute(url: URL(string: "taken://today")!))
        XCTAssertNil(ProRoute(url: URL(string: "https://pro")!))
    }
}
