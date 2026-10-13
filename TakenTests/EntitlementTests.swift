import XCTest
@testable import Taken

/// The money rule (PRO.md): Pro when a live subscription, the lifetime purchase, or founding membership says so.
final class EntitlementTests: XCTestCase {

    private let now = at(2026, 10, 13, 9)
    private let yearly = ProPlan.yearly.productID
    private let monthly = ProPlan.monthly.productID
    private let lifetime = ProPlan.lifetime.productID

    private func production(_ version: String, verified: Bool = true) -> AppTransactionFact {
        AppTransactionFact(verified: verified, environment: .production, originalAppVersion: version)
    }

    func testNothingBoughtIsNotPro() {
        let status = Entitlement.evaluate(purchases: [], app: production("8"), now: now)
        XCTAssertFalse(status.isPro)
        XCTAssertEqual(status.reason, ProReason.none)
        XCTAssertNil(status.expiresAt)
        XCTAssertFalse(status.isActive(at: now))
        XCTAssertFalse(Entitlement.evaluate(purchases: [], app: nil, now: now).isPro, "no app transaction, no purchases")
    }

    func testLiveYearlySubscription() {
        let renews = at(2027, 10, 12, 9)
        let status = Entitlement.evaluate(purchases: [PurchaseFact(productID: yearly, expiresAt: renews, willRenew: true)],
                                          app: production("12"), now: now)
        XCTAssertTrue(status.isPro)
        XCTAssertEqual(status.reason, .yearly)
        XCTAssertEqual(status.expiresAt, renews)
        XCTAssertEqual(status.willRenew, true)
        XCTAssertFalse(status.billingIssue)
        XCTAssertTrue(status.isActive(at: now))
        XCTAssertTrue(status.isActive(at: renews.addingTimeInterval(-1)))
        XCTAssertEqual(status.activeUntil, renews.addingTimeInterval(ProStatus.renewalMargin))
    }

    func testARenewingPlanStaysOnPastItsPeriodEnd() {
        // The widgets, the control, Siri and the nudge read the cache: a renewal Apple has charged must never lock
        // them because Taken was not opened that day.
        let renews = at(2027, 10, 12, 9)
        let status = Entitlement.evaluate(purchases: [PurchaseFact(productID: yearly, expiresAt: renews, willRenew: true)],
                                          app: production("12"), now: now)
        XCTAssertTrue(status.isActive(at: renews), "the renewal moment itself")
        XCTAssertTrue(status.isActive(at: renews.addingTimeInterval(3600)), "an hour after the period end")
        XCTAssertTrue(status.isActive(at: renews.addingTimeInterval(ProStatus.renewalMargin - 1)))
        XCTAssertFalse(status.isActive(at: renews.addingTimeInterval(ProStatus.renewalMargin)), "the margin is capped")
        XCTAssertTrue(status.awaitingRenewal(at: renews.addingTimeInterval(3600)))
        XCTAssertFalse(status.awaitingRenewal(at: now), "not before the period ends")
        XCTAssertTrue(status.lapsedRenewal(at: renews.addingTimeInterval(ProStatus.renewalMargin + 1)),
                      "past the margin the app asks the App Store before locking")

        let unknown = ProStatus(isPro: true, reason: .monthly, checkedAt: now, expiresAt: renews)
        XCTAssertTrue(unknown.isActive(at: renews.addingTimeInterval(3600)), "StoreKit did not say: treated as renewing")
    }

    func testAPlanSetNotToRenewEndsOnTime() {
        let ends = at(2027, 10, 12, 9)
        let status = Entitlement.evaluate(purchases: [PurchaseFact(productID: yearly, expiresAt: ends, willRenew: false)],
                                          app: production("12"), now: now)
        XCTAssertTrue(status.isActive(at: ends.addingTimeInterval(-1)))
        XCTAssertFalse(status.isActive(at: ends), "a cancelled plan is locked at its end")
        XCTAssertEqual(status.activeUntil, ends)
        XCTAssertFalse(status.awaitingRenewal(at: ends))
        XCTAssertFalse(status.lapsedRenewal(at: ends.addingTimeInterval(ProStatus.renewalMargin + 1)))
    }

    func testTheTrialConvertingKeepsPro() {
        // The introductory week ends and Apple charges for the year. Until the new transaction reaches this iPhone,
        // StoreKit still lists the trial as subscribed: Pro stays on (in the sandbox the week lasts about 3 minutes).
        let trialEnds = at(2026, 10, 20, 9)
        let trial = PurchaseFact(productID: yearly, expiresAt: trialEnds, isIntroOffer: true, willRenew: true)
        let justAfter = trialEnds.addingTimeInterval(60)
        let status = Entitlement.evaluate(purchases: [trial], app: production("12"), now: justAfter)
        XCTAssertTrue(status.isPro)
        XCTAssertEqual(status.reason, .trial)
        XCTAssertEqual(status.expiresAt, trialEnds, "the cache keeps the period end")
        XCTAssertTrue(status.awaitingRenewal(at: justAfter))
        let converted = PurchaseFact(productID: yearly, expiresAt: at(2027, 10, 20, 9), willRenew: true)
        XCTAssertEqual(Entitlement.evaluate(purchases: [trial, converted], app: production("12"), now: justAfter).reason,
                       .yearly, "the paid year wins once it arrives")
        XCTAssertFalse(Entitlement.evaluate(purchases: [trial], app: production("12"),
                                            now: trialEnds.addingTimeInterval(ProStatus.renewalMargin + 1)).isPro)
    }

    func testAFailedRenewalGetsNoMargin() {
        let ended = at(2026, 10, 12, 9)
        let retrying = PurchaseFact(productID: monthly, expiresAt: ended, willRenew: true, inBillingRetry: true)
        XCTAssertFalse(Entitlement.evaluate(purchases: [retrying], app: nil, now: now).isPro,
                       "billing retry without a grace period grants nothing")
        let live = PurchaseFact(productID: monthly, expiresAt: at(2026, 11, 12, 9), willRenew: true, inBillingRetry: true)
        let status = Entitlement.evaluate(purchases: [live], app: nil, now: now)
        XCTAssertTrue(status.billingIssue)
        XCTAssertEqual(status.activeUntil, at(2026, 11, 12, 9), "a billing issue ends on time")
    }

    func testLiveMonthlySubscription() {
        let status = Entitlement.evaluate(purchases: [PurchaseFact(productID: monthly, expiresAt: at(2026, 11, 13, 9))],
                                          app: nil, now: now)
        XCTAssertTrue(status.isPro)
        XCTAssertEqual(status.reason, .monthly)
    }

    func testIntroductoryWeekIsTheTrial() {
        let ends = at(2026, 10, 20, 9)
        let status = Entitlement.evaluate(
            purchases: [PurchaseFact(productID: yearly, expiresAt: ends, isIntroOffer: true, willRenew: true)],
            app: production("12"), now: now)
        XCTAssertTrue(status.isPro)
        XCTAssertEqual(status.reason, .trial)
        XCTAssertEqual(status.expiresAt, ends)
    }

    func testExpiredSubscriptionIsNotPro() {
        let lapsed = PurchaseFact(productID: yearly, expiresAt: at(2026, 10, 12, 9), willRenew: false)
        XCTAssertFalse(Entitlement.evaluate(purchases: [lapsed], app: production("12"), now: now).isPro)
        let endsNow = PurchaseFact(productID: monthly, expiresAt: now, willRenew: false)
        XCTAssertFalse(Entitlement.evaluate(purchases: [endsNow], app: nil, now: now).isPro, "the end moment is already out")
        let renewedLongAgo = PurchaseFact(productID: monthly, expiresAt: now.addingTimeInterval(-ProStatus.renewalMargin),
                                          willRenew: true)
        XCTAssertFalse(Entitlement.evaluate(purchases: [renewedLongAgo], app: nil, now: now).isPro,
                       "a renewal that never came is over once the margin is")
        let noDate = PurchaseFact(productID: monthly)
        XCTAssertFalse(Entitlement.evaluate(purchases: [noDate], app: nil, now: now).isPro,
                       "a subscription with no period end grants nothing")
    }

    func testBillingGracePeriodKeepsPro() {
        let grace = at(2026, 10, 25, 9)
        let fact = PurchaseFact(productID: monthly, expiresAt: at(2026, 10, 12, 9), graceUntil: grace, willRenew: true)
        let status = Entitlement.evaluate(purchases: [fact], app: nil, now: now)
        XCTAssertTrue(status.isPro)
        XCTAssertEqual(status.reason, .monthly)
        XCTAssertTrue(status.billingIssue)
        XCTAssertEqual(status.expiresAt, grace, "the cache holds through the grace period")
        XCTAssertEqual(status.activeUntil, grace, "and not past it")
        XCTAssertFalse(status.isActive(at: grace))
        XCTAssertFalse(Entitlement.evaluate(purchases: [fact], app: nil, now: at(2026, 10, 25, 10)).isPro, "and no longer")
    }

    func testRevokedTransactionsNeverCount() {
        let refunded = PurchaseFact(productID: yearly, revokedAt: at(2026, 10, 10, 9), expiresAt: at(2027, 10, 1, 9))
        XCTAssertFalse(Entitlement.evaluate(purchases: [refunded], app: nil, now: now).isPro)
        let refundedLifetime = PurchaseFact(productID: lifetime, revokedAt: at(2026, 10, 10, 9))
        XCTAssertFalse(Entitlement.evaluate(purchases: [refundedLifetime], app: nil, now: now).isPro)
    }

    func testUnverifiedTransactionsNeverCount() {
        let forged = [PurchaseFact(productID: lifetime, verified: false),
                      PurchaseFact(productID: yearly, verified: false, expiresAt: at(2027, 10, 1, 9))]
        XCTAssertFalse(Entitlement.evaluate(purchases: forged, app: nil, now: now).isPro)
    }

    func testLifetimeIsForGood() {
        let status = Entitlement.evaluate(purchases: [PurchaseFact(productID: lifetime)], app: production("40"), now: now)
        XCTAssertTrue(status.isPro)
        XCTAssertEqual(status.reason, .lifetime)
        XCTAssertNil(status.expiresAt)
        XCTAssertTrue(status.isActive(at: at(2040, 1, 1, 0)), "lifetime never expires in the cache")
    }

    func testLifetimeWinsOverASubscription() {
        let status = Entitlement.evaluate(
            purchases: [PurchaseFact(productID: monthly, expiresAt: at(2026, 11, 1, 9)), PurchaseFact(productID: lifetime)],
            app: nil, now: now)
        XCTAssertEqual(status.reason, .lifetime)
        XCTAssertNil(status.expiresAt)
    }

    func testFoundingMembers() {
        XCTAssertTrue(FoundingMember.qualifies(production("7"), maxBuild: 7), "the build in App Review")
        XCTAssertTrue(FoundingMember.qualifies(production("1"), maxBuild: 7))
        XCTAssertTrue(FoundingMember.qualifies(production(" 5 "), maxBuild: 7))
        XCTAssertFalse(FoundingMember.qualifies(production("8"), maxBuild: 7), "the first 1.1 build is past the cutoff")
        XCTAssertFalse(FoundingMember.qualifies(production("0"), maxBuild: 7))
        XCTAssertFalse(FoundingMember.qualifies(production("7.1"), maxBuild: 7))
        XCTAssertFalse(FoundingMember.qualifies(production(""), maxBuild: 7))
        XCTAssertFalse(FoundingMember.qualifies(production("5", verified: false), maxBuild: 7), "unverified")
        XCTAssertFalse(FoundingMember.qualifies(nil, maxBuild: 7))
        XCTAssertTrue(FoundingMember.qualifies(production("9"), maxBuild: 9), "the release engineer can raise the cutoff")
        XCTAssertEqual(FoundingMember.maxBuild, 7)
    }

    func testSandboxAndTestFlightAreNeverFoundingMembers() {
        // In the sandbox (TestFlight, App Review) originalAppVersion is always "1.0".
        let sandbox = AppTransactionFact(verified: true, environment: .sandbox, originalAppVersion: "1.0")
        XCTAssertFalse(FoundingMember.qualifies(sandbox))
        XCTAssertFalse(Entitlement.evaluate(purchases: [], app: sandbox, now: now).isPro, "App Review sees the paywall")
        let sandboxBuild = AppTransactionFact(verified: true, environment: .sandbox, originalAppVersion: "3")
        XCTAssertFalse(FoundingMember.qualifies(sandboxBuild), "only production counts")
        let xcode = AppTransactionFact(verified: true, environment: .xcode, originalAppVersion: "1")
        XCTAssertFalse(FoundingMember.qualifies(xcode))
        XCTAssertFalse(FoundingMember.qualifies(production("1.0")), "1.0 is not a build number")
    }

    func testFoundingMemberIsProForLife() {
        let status = Entitlement.evaluate(purchases: [], app: production("6"), now: now)
        XCTAssertTrue(status.isPro)
        XCTAssertEqual(status.reason, .founding)
        XCTAssertNil(status.expiresAt)
        XCTAssertTrue(status.isActive(at: at(2050, 1, 1, 0)))
        let alsoSubscribed = Entitlement.evaluate(
            purchases: [PurchaseFact(productID: yearly, expiresAt: at(2027, 10, 1, 9))], app: production("6"), now: now)
        XCTAssertEqual(alsoSubscribed.reason, .founding, "for good beats for now")
        XCTAssertFalse(alsoSubscribed.renewingSubscription, "StoreKit did not say it renews")
    }

    func testProForGoodNotesASubscriptionThatStillRenews() {
        // Settings offers MANAGE SUBSCRIPTION to a lifetime or founding member who is still paying for a plan.
        let renewing = PurchaseFact(productID: monthly, expiresAt: at(2026, 11, 1, 9), willRenew: true)
        let lifetimeToo = Entitlement.evaluate(purchases: [renewing, PurchaseFact(productID: lifetime)], app: nil, now: now)
        XCTAssertEqual(lifetimeToo.reason, .lifetime)
        XCTAssertTrue(lifetimeToo.renewingSubscription)
        XCTAssertNil(lifetimeToo.activeUntil, "still Pro for good")
        let founding = Entitlement.evaluate(purchases: [renewing], app: production("6"), now: now)
        XCTAssertEqual(founding.reason, .founding)
        XCTAssertTrue(founding.renewingSubscription)
        var cancelled = renewing
        cancelled.willRenew = false
        XCTAssertFalse(Entitlement.evaluate(purchases: [cancelled, PurchaseFact(productID: lifetime)], app: nil, now: now)
            .renewingSubscription, "a cancelled plan needs nothing more")
        XCTAssertFalse(Entitlement.evaluate(purchases: [PurchaseFact(productID: lifetime)], app: nil, now: now).renewingSubscription)
    }

    // MARK: What a check keeps

    private var founding: ProStatus { ProStatus(isPro: true, reason: .founding, checkedAt: at(2026, 10, 1, 9)) }

    func testAVerifiedAnswerIsConclusive() {
        let fresh = ProStatus.notPro(checkedAt: now)
        XCTAssertEqual(Entitlement.next(previous: founding, fresh: fresh, app: production("12")), fresh)
        XCTAssertEqual(Entitlement.next(previous: nil, fresh: fresh, app: production("12")), fresh)
    }

    func testAnUnverifiedAppTransactionNeverTakesFoundingAway() {
        let unverified = production("7", verified: false)
        let fresh = Entitlement.evaluate(purchases: [], app: unverified, now: now)
        XCTAssertFalse(fresh.isPro, "an unverified app transaction proves nothing")
        let kept = Entitlement.next(previous: founding, fresh: fresh, app: unverified)
        XCTAssertEqual(kept?.reason, .founding, "Pro for life stays")
        XCTAssertEqual(kept?.checkedAt, now)
        XCTAssertNil(Entitlement.next(previous: nil, fresh: fresh, app: unverified),
                     "a log never checked stays unchecked, so a 1.0 log stays pending")
        let renewing = Entitlement.evaluate(purchases: [PurchaseFact(productID: monthly, expiresAt: at(2026, 11, 1, 9),
                                                                     willRenew: true)], app: unverified, now: now)
        XCTAssertEqual(Entitlement.next(previous: founding, fresh: renewing, app: unverified)?.renewingSubscription, true,
                       "a subscription still renewing next to it is noted")
    }

    func testAnUnverifiedAppTransactionStillReadsPurchases() {
        let unverified = production("40", verified: false)
        let refunded = Entitlement.evaluate(purchases: [PurchaseFact(productID: lifetime, revokedAt: at(2026, 10, 10, 9))],
                                            app: unverified, now: now)
        let lifetimeBefore = ProStatus(isPro: true, reason: .lifetime, checkedAt: at(2026, 10, 1, 9))
        XCTAssertEqual(Entitlement.next(previous: lifetimeBefore, fresh: refunded, app: unverified)?.isPro, false,
                       "a refunded lifetime purchase is not kept")
        let bought = Entitlement.evaluate(purchases: [PurchaseFact(productID: yearly, expiresAt: at(2027, 10, 1, 9))],
                                          app: unverified, now: now)
        XCTAssertEqual(Entitlement.next(previous: nil, fresh: bought, app: unverified)?.reason, .yearly)
    }

    func testNoAppTransactionKeepsWhatWasKnown() {
        // Offline or signed out: finding no purchase proves nothing.
        let yearlyBefore = ProStatus(isPro: true, reason: .yearly, checkedAt: at(2026, 10, 1, 9),
                                     expiresAt: at(2027, 10, 1, 9), willRenew: true)
        let fresh = ProStatus.notPro(checkedAt: now)
        XCTAssertEqual(Entitlement.next(previous: yearlyBefore, fresh: fresh, app: nil), yearlyBefore)
        XCTAssertEqual(Entitlement.next(previous: founding, fresh: fresh, app: nil)?.reason, .founding)
        XCTAssertNil(Entitlement.next(previous: nil, fresh: fresh, app: nil))
        let bought = ProStatus(isPro: true, reason: .lifetime, checkedAt: now)
        XCTAssertEqual(Entitlement.next(previous: nil, fresh: bought, app: nil), bought, "a purchase found still counts")
    }

    func testUpgradedAndUnknownTransactionsAreIgnored() {
        let upgradedAway = PurchaseFact(productID: monthly, expiresAt: at(2026, 11, 1, 9), isUpgraded: true)
        XCTAssertFalse(Entitlement.evaluate(purchases: [upgradedAway], app: nil, now: now).isPro)
        let stranger = PurchaseFact(productID: "com.example.other", expiresAt: at(2027, 1, 1, 9))
        XCTAssertFalse(Entitlement.evaluate(purchases: [stranger], app: nil, now: now).isPro)
    }

    func testTheLaterOfTwoLiveSubscriptionsWins() {
        let status = Entitlement.evaluate(purchases: [
            PurchaseFact(productID: monthly, expiresAt: at(2026, 11, 1, 9)),
            PurchaseFact(productID: yearly, expiresAt: at(2027, 10, 1, 9), willRenew: false),
        ], app: nil, now: now)
        XCTAssertEqual(status.reason, .yearly)
        XCTAssertEqual(status.expiresAt, at(2027, 10, 1, 9))
        XCTAssertEqual(status.willRenew, false)
    }

    func testSameEntitlementIgnoresTheCheckTime() {
        let first = ProStatus(isPro: true, reason: .lifetime, checkedAt: now)
        var later = first
        later.checkedAt = now.addingTimeInterval(3600)
        XCTAssertTrue(later.sameEntitlement(as: first))
        XCTAssertFalse(later.sameEntitlement(as: nil))
        later.reason = .founding
        XCTAssertFalse(later.sameEntitlement(as: first))
    }

    func testProductIDsAreFixed() {
        XCTAssertEqual(ProPlan.allCases.map(\.productID), [
            "com.tombaxter.taken.pro.yearly",
            "com.tombaxter.taken.pro.monthly",
            "com.tombaxter.taken.pro.lifetime",
        ])
        XCTAssertEqual(ProPlan(productID: "com.tombaxter.taken.pro.lifetime"), .lifetime)
        XCTAssertNil(ProPlan(productID: "com.tombaxter.taken.pro"))
    }
}
